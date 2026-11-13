//
//  FilterDataProvider.swift
//  SieveExtension
//
//  Created by Mahir on 11.11.26.
//

import Network
import NetworkExtension
import os

// Shared state lives in `Store` and behind `ask`'s lock. `listener` and `saving` change only in start and stop.
final class FilterDataProvider: NEFilterDataProvider, @unchecked Sendable {
    private struct Ask {
        // The Sieve app, while it runs. Ask mode needs it.
        var client: NSXPCConnection?
        // Flows waiting for the user's answer, by app key.
        var waiting: [String: [NEFilterFlow]] = [:]
    }

    private let logger = Logger(subsystem: "me.pilinux.Sieve.SieveExtension", category: "filter")
    private let apps = AppKeys()
    private let store = Store()
    private var listener: NSXPCListener?
    private var saving: Task<Void, Never>?
    private var networks: Networks?
    private let ask = OSAllocatedUnfairLock(uncheckedState: Ask())

    override func startFilter() async throws {
        store.load()
        // `stopFilter` keeps both. A restart in the same process must not add a second set.
        if listener == nil { startListener() }
        if networks == nil { networks = Networks { [store] in store.setNetworks($0) } }
        saving = Task { [store] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                store.saveStats()
            }
        }

        // No endpoints: match every outgoing flow except loopback.
        let outbound = NENetworkRule(
            remoteNetworkEndpoint: nil, remotePrefix: 0,
            localNetworkEndpoint: nil, localPrefix: 0,
            protocol: .any, direction: .outbound
        )
        let settings = NEFilterSettings(
            rules: [NEFilterRule(networkRule: outbound, action: .filterData)],
            defaultAction: .allow
        )
        try await apply(settings)
    }

    override func stopFilter(with reason: NEProviderStopReason) async {
        saving?.cancel()
        store.saveStats()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        let app = app(of: flow)
        let host = flow.hostname
        let action = store.verdict(app: app, host: host, address: flow.address)
        // App and host stay private: the log ends up in sysdiagnose reports.
        logger.log("\(action?.rawValue ?? "ask", privacy: .public) \(app.key, privacy: .private) to \(host ?? "?", privacy: .private)")
        switch action {
        case .allow: return counted(.allow())
        case .block: return .drop()
        case nil:
            if waitForAnswer(app: app, host: host, flow: flow) { return .pause() }
            store.countBlocked()
            return .drop()
        }
    }

    // Queues a paused flow for the user's answer. False if the Sieve app is not running:
    // killing the app must not open the filter.
    private func waitForAnswer(app: App, host: String?, flow: NEFilterFlow) -> Bool {
        let key = app.key
        let host = host ?? ""
        guard let client = ask.withLockUnchecked({ $0.client }),
            let prompt = client.remoteObjectProxyWithErrorHandler({ [self] _ in resumeFlows(of: app, host: host, answer: nil) })
                as? PromptXPC
        else { return false }

        let first = ask.withLockUnchecked {
            defer { $0.waiting[key, default: []].append(flow) }
            return $0.waiting[key] == nil
        }
        // Later flows of the same app wait for the same answer.
        if first {
            prompt.prompt(app: key, path: app.path, signer: app.signer, host: host, address: flow.address ?? "") {
                [self] allow, hostOnly in
                resumeFlows(of: app, host: host, answer: (allow ? .allow : .block, hostOnly))
            }
        }
        return true
    }

    // Resumes the app's waiting flows as new flows. The Sieve app saved the answer as a rule before it replied,
    // so lists, limits, and profiles still beat it. The answer itself covers a flow whose rule could not be saved.
    // A flow to a host the answer does not cover waits for a new prompt. With no answer, it is dropped.
    private func resumeFlows(of app: App, host: String, answer: (action: Action, hostOnly: Bool)?) {
        // `NEFilterFlow` is not `Sendable`. Once out of `waiting`, only the block below uses these.
        nonisolated(unsafe) let flows = ask.withLockUnchecked { $0.waiting.removeValue(forKey: app.key) ?? [] }
        // Only a paused flow resumes. A flow joins `waiting` before `handleNewFlow` returns `.pause()`,
        // and a failed send can land here before that, even on the same stack.
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) { [self] in
            for flow in flows {
                let flowHost = flow.hostname
                var action = store.verdict(app: app, host: flowHost, address: flow.address)
                if action == nil, let answer, !answer.hostOnly || flowHost == host {
                    action = answer.action
                    if action == .block { store.countBlocked() }
                }
                switch action {
                case .allow: resumeFlow(flow, with: counted(.allow()))
                case .block: resumeFlow(flow, with: NEFilterNewFlowVerdict.drop())
                case nil:
                    if answer != nil, waitForAnswer(app: app, host: flowHost, flow: flow) { continue }
                    store.countBlocked()
                    resumeFlow(flow, with: NEFilterNewFlowVerdict.drop())
                }
            }
        }
    }

    private func app(of flow: NEFilterFlow) -> App {
        // Some flows carry only the process token.
        let token = flow.sourceAppAuditToken ?? flow.sourceProcessAuditToken
        return token.flatMap(apps.app) ?? App(Config.unknownApp)
    }

    // Asks for the flow's byte counts about once a second, and when it closes.
    private func counted(_ verdict: NEFilterNewFlowVerdict) -> NEFilterNewFlowVerdict {
        verdict.shouldReport = true
        verdict.statisticsReportFrequency = .medium
        return verdict
    }

    override func handle(_ report: NEFilterReport) {
        guard report.event == .statistics || report.event == .flowClosed, let flow = report.flow else { return }
        store.count(
            flow: flow.identifier,
            app: app(of: flow).key,
            total: report.bytesInboundCount + report.bytesOutboundCount,
            closed: report.event == .flowClosed
        )
    }

    private func startListener() {
        guard let name = Bundle.main.machServiceName else {
            logger.error("No NEMachServiceName in Info.plist")
            return
        }
        // The service name starts with the team ID. Accept only the Sieve app, signed by that team.
        let team = name.prefix { $0 != "." }
        var requirement =
            "anchor apple generic and identifier \"me.pilinux.Sieve\" and certificate leaf[subject.OU] = \"\(team)\""
        #if !DEBUG
            // A debugger can inject code into an app with `get-task-allow`. Only Debug builds have it.
            requirement += " and !(entitlement[\"com.apple.security.get-task-allow\"] exists)"
        #endif
        let listener = NSXPCListener(machServiceName: name)
        listener.setConnectionCodeSigningRequirement(requirement)
        listener.delegate = self
        listener.resume()
        self.listener = listener
    }
}

private extension NEFilterFlow {
    var hostname: String? { (url?.host ?? (self as? NEFilterSocketFlow)?.remoteHostname).flatMap(DomainList.normalize) }

    // The endpoint can still be unset when the flow is new, or be a name.
    var address: String? {
        guard case .some(.hostPort(let host, _)) = (self as? NEFilterSocketFlow)?.remoteFlowEndpoint else { return nil }
        return Address.normalize("\(host)")
    }
}

extension FilterDataProvider: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FilterXPC.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: PromptXPC.self)
        connection.invalidationHandler = { [self, weak connection] in
            ask.withLockUnchecked { if $0.client === connection { $0.client = nil } }
        }
        ask.withLockUnchecked { $0.client = connection }
        connection.resume()
        return true
    }
}

extension FilterDataProvider: FilterXPC {
    func config(reply: @escaping @Sendable (Data) -> Void) {
        reply((try? JSONEncoder().encode(store.config)) ?? Data())
    }

    func setConfig(_ config: Data, reply: @escaping @Sendable (Data) -> Void) {
        if let config = try? JSONDecoder().decode(Config.self, from: config) {
            store.setConfig(config)
        }
        reply((try? JSONEncoder().encode(store.config)) ?? Data())
    }

    func stats(reply: @escaping @Sendable (Data) -> Void) {
        reply((try? JSONEncoder().encode(store.statsForApp)) ?? Data())
    }

    func usage(reply: @escaping @Sendable (Data) -> Void) {
        reply((try? JSONEncoder().encode(store.usage)) ?? Data())
    }

    func setList(_ id: String, domains: Data, reply: @escaping @Sendable (Data) -> Void) {
        // The app caps lists too. Check again: this process runs as root.
        if domains.count <= DomainList.maxBytes {
            store.setList(id, text: String(decoding: domains, as: UTF8.self))
        }
        reply(Data())
    }

    func forget(_ app: String, reply: @escaping @Sendable (Data) -> Void) {
        store.forget(app)
        reply(Data())
    }

    func brokenConfig(reply: @escaping @Sendable (Data) -> Void) {
        reply(store.brokenConfig ?? Data())
    }

    func discardBrokenConfig(reply: @escaping @Sendable (Data) -> Void) {
        store.discardBrokenConfig()
        reply(Data())
    }
}

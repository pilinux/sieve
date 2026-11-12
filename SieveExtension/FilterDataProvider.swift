//
//  FilterDataProvider.swift
//  SieveExtension
//
//  Created by Mahir on 11.11.26.
//

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
        startListener()
        networks = Networks { [store] in store.setNetworks($0) }
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
        let action = store.verdict(app: app, host: host)
        // App and host stay private: the log ends up in sysdiagnose reports.
        logger.log("\(action?.rawValue ?? "ask", privacy: .public) \(app.key, privacy: .private) to \(host ?? "?", privacy: .private)")
        switch action {
        case .allow: return counted(.allow())
        case .block: return .drop()
        case nil: return pauseAndAsk(app: app, host: host, flow: flow)
        }
    }

    // Pauses the flow until the user answers. Allows it if the Sieve app is not running.
    private func pauseAndAsk(app: App, host: String?, flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        let key = app.key
        guard let client = ask.withLockUnchecked({ $0.client }),
            let prompt = client.remoteObjectProxyWithErrorHandler({ [self] _ in resumeFlows(of: key) }) as? PromptXPC
        else { return .allow() }

        let first = ask.withLockUnchecked {
            defer { $0.waiting[key, default: []].append(flow) }
            return $0.waiting[key] == nil
        }
        // Later flows of the same app wait for the same answer.
        if first {
            // A key that is the path names no verified signer.
            let signer = app.isApple ? "Apple" : app.key == app.path || app.path.isEmpty ? "" : String(app.key.prefix { $0 != "." })
            prompt.prompt(app: key, path: app.path, signer: signer, host: host ?? "") { [self] in resumeFlows(of: key) }
        }
        return .pause()
    }

    // Resumes the app's waiting flows by the rules. The Sieve app saved the answer as a rule before it replied.
    // Flows the rules leave undecided are allowed once.
    private func resumeFlows(of app: String) {
        let flows = ask.withLockUnchecked { $0.waiting.removeValue(forKey: app) ?? [] }
        let config = store.config
        for flow in flows {
            let verdict = config.verdict(app: app, host: flow.hostname, isApple: false)
            resumeFlow(flow, with: verdict == .block ? NEFilterNewFlowVerdict.drop() : counted(.allow()))
        }
    }

    private func app(of flow: NEFilterFlow) -> App {
        // Some flows carry only the process token.
        let token = flow.sourceAppAuditToken ?? flow.sourceProcessAuditToken
        return token.flatMap(apps.app) ?? App("unknown")
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
    var hostname: String? { url?.host ?? (self as? NEFilterSocketFlow)?.remoteHostname }
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
        // The app caps lists too. Check again: this process runs as root, with no sandbox.
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

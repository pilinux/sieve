//
//  FilterDataProvider.swift
//  SieveExtension
//
//  Created by Mahir on 11.11.26.
//

import NetworkExtension
import os

final class FilterDataProvider: NEFilterDataProvider {
    private let logger = Logger(subsystem: "me.pilinux.Sieve.SieveExtension", category: "filter")
    private let apps = AppKeys()
    private let store = Store()
    private var listener: NSXPCListener?
    private var saving: Task<Void, Never>?

    override func startFilter() async throws {
        store.load()
        startListener()
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
        // Some flows carry only the process token.
        let token = flow.sourceAppAuditToken ?? flow.sourceProcessAuditToken
        let app = token.flatMap(apps.key) ?? "unknown"
        let host = flow.url?.host ?? (flow as? NEFilterSocketFlow)?.remoteHostname
        let action = store.verdict(app: app, host: host)
        logger.log("\(action.rawValue, privacy: .public) \(app, privacy: .public) to \(host ?? "?", privacy: .public)")
        return action == .block ? .drop() : .allow()
    }

    private func startListener() {
        guard let name = Bundle.main.machServiceName else {
            logger.error("No NEMachServiceName in Info.plist")
            return
        }
        // The service name starts with the team ID. Accept only apps signed by that team.
        let team = name.prefix { $0 != "." }
        let listener = NSXPCListener(machServiceName: name)
        listener.setConnectionCodeSigningRequirement(
            "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        )
        listener.delegate = self
        listener.resume()
        self.listener = listener
    }
}

extension FilterDataProvider: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FilterXPC.self)
        connection.exportedObject = self
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
        reply((try? JSONEncoder().encode(store.stats)) ?? Data())
    }
}

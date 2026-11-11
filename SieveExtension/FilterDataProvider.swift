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

    override func startFilter() async throws {
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

    override func stopFilter(with reason: NEProviderStopReason) async {}

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        let remote = (flow as? NEFilterSocketFlow)?.remoteFlowEndpoint.map { "\($0)" } ?? "unknown"
        // Some flows carry only the process token.
        let token = flow.sourceAppAuditToken ?? flow.sourceProcessAuditToken
        let app = token.flatMap(apps.key) ?? "unknown"
        logger.log("flow from \(app, privacy: .public) to \(remote, privacy: .public)")
        return .allow()
    }
}

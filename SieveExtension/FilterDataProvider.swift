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
    private let configURL = URL.applicationSupportDirectory.appending(path: "me.pilinux.Sieve/config.json")
    private var config = Config()

    override func startFilter() async throws {
        config = loadConfig()
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
        let action = config.verdict(app: app)
        logger.log("\(action.rawValue, privacy: .public) \(app, privacy: .public) to \(remote, privacy: .public)")
        return action == .block ? .drop() : .allow()
    }

    private func loadConfig() -> Config {
        do {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            save(Config())
        } catch {
            // Keep the broken file for the user to inspect.
            logger.error("Cannot read config.json, using defaults: \(error, privacy: .public)")
        }
        return Config()
    }

    private func save(_ config: Config) {
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(config).write(to: configURL, options: .atomic)
        } catch {
            logger.error("Cannot write config.json: \(error, privacy: .public)")
        }
    }
}

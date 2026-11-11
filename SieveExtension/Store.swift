import Foundation
import os
import Synchronization

/// Config and stats, shared by the filter and XPC, saved as JSON files.
final class Store: Sendable {
    private struct State {
        var config = Config()
        var stats = Stats()
        var statsChanged = false
        /// The hosts of each list, by list ID.
        var domains: [String: Set<String>] = [:]
        /// Bytes counted so far for each open flow.
        var flowBytes: [UUID: Int] = [:]
    }

    private let state = Mutex(State())
    private let folder = URL.applicationSupportDirectory.appending(path: "me.pilinux.Sieve")
    private let logger = Logger(subsystem: "me.pilinux.Sieve.SieveExtension", category: "store")

    var config: Config { state.withLock { $0.config } }
    var stats: Stats { state.withLock { $0.stats } }

    func load() {
        let config = read(Config.self, "config.json")
        let stats = read(Stats.self, "stats.json")
        var domains: [String: Set<String>] = [:]
        for list in (config ?? Config()).lists {
            let cached = folder.appending(path: "lists/\(list.id).txt")
            // Tracker Shield works before its first refresh.
            let bundled = list.id == DomainList.trackerShield.id
                ? Bundle.main.url(forResource: "trackers", withExtension: "txt") : nil
            if let text = (try? String(contentsOf: cached, encoding: .utf8))
                ?? bundled.flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) {
                domains[list.id] = DomainList.parse(text)
            }
        }
        state.withLock {
            $0.config = config ?? Config()
            $0.stats = stats ?? Stats()
            $0.domains = domains
        }
        if config == nil { write(Config(), "config.json") }
    }

    /// Saves a downloaded list and uses it at once.
    func setList(_ id: String, text: String) {
        // The ID names a file. Keep it inside the lists folder.
        guard !id.contains("/") else { return }
        let hosts = DomainList.parse(text)
        state.withLock { $0.domains[id] = hosts }
        do {
            try FileManager.default.createDirectory(at: folder.appending(path: "lists"), withIntermediateDirectories: true)
            try text.write(to: folder.appending(path: "lists/\(id).txt"), atomically: true, encoding: .utf8)
        } catch {
            logger.error("Cannot save list \(id, privacy: .public): \(error, privacy: .public)")
        }
    }

    func setConfig(_ config: Config) {
        state.withLock { $0.config = config }
        write(config, "config.json")
    }

    func setAction(_ action: Action, for app: String, host: String?) {
        let config = state.withLock {
            $0.config.setAction(action, for: app, host: host)
            return $0.config
        }
        write(config, "config.json")
    }

    /// Decides one flow and records the app and host. Nil means: ask the user.
    func verdict(app: App, host: String?) -> Action? {
        state.withLock {
            var hosts = $0.stats.apps[app.key] ?? []
            if let host { hosts.insert(host) }
            if $0.stats.apps[app.key] != hosts {
                $0.stats.apps[app.key] = hosts
                $0.statsChanged = true
            }
            let action = $0.config.verdict(app: app.key, host: host, isApple: app.isApple, domains: $0.domains)
            if action == .block {
                $0.stats.blocked[Stats.day(.now), default: 0] += 1
                $0.statsChanged = true
            }
            return action
        }
    }

    /// Adds a flow's new bytes to its app. `total` is the flow's count so far.
    func count(flow: UUID, app: String, total: Int, closed: Bool) {
        state.withLock {
            let new = total - ($0.flowBytes[flow] ?? 0)
            $0.flowBytes[flow] = closed ? nil : total
            $0.stats.bytes[app, default: 0] += max(new, 0)
            $0.statsChanged = true
        }
    }

    func saveStats() {
        let stats: Stats? = state.withLock {
            defer { $0.statsChanged = false }
            return $0.statsChanged ? $0.stats : nil
        }
        if let stats { write(stats, "stats.json") }
    }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: folder.appending(path: name)))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            // Keep the broken file for the user to inspect.
            logger.error("Cannot read \(name, privacy: .public), using defaults: \(error, privacy: .public)")
            return nil
        }
    }

    private func write(_ value: some Encodable, _ name: String) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: folder.appending(path: name), options: .atomic)
        } catch {
            logger.error("Cannot write \(name, privacy: .public): \(error, privacy: .public)")
        }
    }
}

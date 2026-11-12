import Foundation
import Synchronization
import os

/// Config and stats, shared by the filter and XPC, saved as JSON files.
final class Store: Sendable {
    private struct State {
        var config = Config()
        var stats = Stats()
        var statsChanged = false
        // The hosts of each list, by list ID.
        var domains: [String: Set<String>] = [:]
        // Bytes counted so far for each open flow.
        var flowBytes: [UUID: Int] = [:]
        // The `NetworkSignature` of each network the Mac is on.
        var networks: Set<String> = []
    }

    private let state = Mutex(State())
    private let folder = URL.applicationSupportDirectory.appending(path: "me.pilinux.Sieve")
    private let logger = Logger(subsystem: "me.pilinux.Sieve.SieveExtension", category: "store")

    var config: Config { state.withLock { $0.config } }
    var stats: Stats { state.withLock { $0.stats } }

    /// The stats, plus what only the app needs: rule flags, networks, the active profile, and list sizes.
    var statsForApp: Stats {
        let (config, stats, domains, networks) = state.withLock { ($0.config, $0.stats, $0.domains, $0.networks) }
        let gone = Set(stats.paths.filter { !FileManager.default.fileExists(atPath: $0.value) }.keys)
        var result = stats
        for rule in config.rules {
            result.flags[rule.id] = config.flag(rule, gone: gone, domains: domains)
        }
        result.networks = networks
        result.profile = Self.activeProfile(config, networks)
        result.listSizes = domains.mapValues(\.count)
        return result
    }

    func setNetworks(_ networks: Set<String>) {
        state.withLock { $0.networks = networks }
    }

    private static func activeProfile(_ config: Config, _ networks: Set<String>) -> UUID? {
        let now = Calendar.current.dateComponents([.weekday, .hour, .minute], from: .now)
        return config.activeProfile(
            networks: networks, weekday: now.weekday ?? 0, minute: (now.hour ?? 0) * 60 + (now.minute ?? 0)
        )
    }

    func load() {
        let config = read(Config.self, "config.json")
        let stats = read(Stats.self, "stats.json")
        var domains: [String: Set<String>] = [:]
        for list in (config ?? Config()).lists {
            let cached = folder.appending(path: "lists/\(list.id).txt")
            // Tracker Shield works before its first refresh.
            let bundled =
                list.id == DomainList.trackerShield.id
                ? Bundle.main.url(forResource: "trackers", withExtension: "txt") : nil
            if let text = (try? String(contentsOf: cached, encoding: .utf8))
                ?? bundled.flatMap({ try? String(contentsOf: $0, encoding: .utf8) })
            {
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
    /// Clears the app's history and saves it at once. Keeps its config.
    func forget(_ app: String) {
        state.withLock {
            $0.stats.forget(app, rules: $0.config.rules.filter { $0.app == app }.map(\.id))
            $0.statsChanged = true
        }
        saveStats()
    }

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
        let today = Stats.day(.now)
        return state.withLock {
            var hosts = $0.stats.apps[app.key] ?? []
            if let host { hosts.insert(host) }
            if $0.stats.apps[app.key] != hosts {
                $0.stats.apps[app.key] = hosts
                $0.statsChanged = true
            }
            if app.isApple, $0.stats.apple.insert(app.key).inserted { $0.statsChanged = true }
            if let host, $0.config.isTracker(host, domains: $0.domains), $0.stats.trackers.insert(host).inserted {
                $0.statsChanged = true
            }
            if !app.path.isEmpty, $0.stats.paths.updateValue(app.path, forKey: app.key) != app.path {
                $0.statsChanged = true
            }
            let overLimit = $0.config.isOverLimit(app.key, daily: $0.stats.daily, today: today)
            let (action, rule) = $0.config.decide(
                app: app.key, host: host, isApple: app.isApple, domains: $0.domains, overLimit: overLimit,
                profile: Self.activeProfile($0.config, $0.networks)
            )
            if let rule {
                $0.stats.hits[rule.id, default: Hit()].count += 1
                $0.stats.hits[rule.id]?.last = .now
                $0.statsChanged = true
            }
            if action == .block {
                $0.stats.blocked[today, default: 0] += 1
                $0.statsChanged = true
            }
            return action
        }
    }

    /// Adds a flow's new bytes to its app. `total` is the flow's count so far.
    func count(flow: UUID, app: String, total: Int, closed: Bool) {
        let today = Stats.day(.now)
        let cutoff = Stats.day(.now.addingTimeInterval(-31 * 24 * 60 * 60))
        state.withLock {
            let new = max(total - ($0.flowBytes[flow] ?? 0), 0)
            $0.flowBytes[flow] = closed ? nil : total
            $0.stats.bytes[app, default: 0] += new
            if $0.stats.daily[today] == nil {
                $0.stats.daily = $0.stats.daily.filter { $0.key > cutoff }
            }
            $0.stats.daily[today, default: [:]][app, default: 0] += new
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

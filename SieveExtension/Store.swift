import Foundation
import Synchronization

/// The extension's error log, next to its config.
let errorLog = ErrorLog(
    folder: URL.applicationSupportDirectory.appending(path: "me.pilinux.Sieve"), source: "extension",
    subsystem: "me.pilinux.Sieve.SieveExtension")

/// Holds the config and stats for the filter and XPC, and saves them as JSON files.
final class Store: Sendable {
    private struct State {
        var config = Config()
        var stats = Stats()
        var statsChanged = false
        // The `Stats.day(_:)` of the last prune.
        var pruned = ""
        // The hosts of each list, by list ID.
        var domains: [String: Set<String>] = [:]
        // Bytes counted so far for each open flow.
        var flowBytes: [UUID: Int] = [:]
        // The `NetworkSignature` of each network the Mac is on.
        var networks: Set<String> = []
        // The code pin of each path key's last flow.
        var codes: [String: String] = [:]
    }

    private let state = Mutex(State())
    private let folder = URL.applicationSupportDirectory.appending(path: "me.pilinux.Sieve")

    var config: Config { state.withLock { $0.config } }
    /// Only the bytes and blocked counts, for the app's live view.
    var usage: Stats {
        state.withLock { Stats(bytes: $0.stats.bytes, blocked: $0.stats.blocked, blockedByList: $0.stats.blockedByList) }
    }
    /// The config file that could not be read, or nil.
    var brokenConfig: Data? { try? Data(contentsOf: brokenConfigFile) }
    // Where `read` moves a config it cannot decode.
    private var brokenConfigFile: URL { folder.appending(path: "config.json.broken") }

    /// The stats, plus what only the app needs: rule flags, networks, the active profile, list sizes, and blocked trackers.
    var statsForApp: Stats {
        let (config, stats, domains, networks, codes) = state.withLock {
            ($0.config, $0.stats, $0.domains, $0.networks, $0.codes)
        }
        let gone = Set(stats.paths.filter { !FileManager.default.fileExists(atPath: $0.value) }.keys)
        var result = stats
        for rule in config.rules {
            result.flags[rule.id] = config.flag(rule, gone: gone, domains: domains)
        }
        result.networks = networks
        result.codes = codes
        result.profile = Self.activeProfile(config, networks)
        result.listSizes = domains.mapValues(\.count)
        result.blockedDomains = config.blockedDomainCount(domains)
        result.brokenConfig = FileManager.default.fileExists(atPath: brokenConfigFile.path)
        for (app, hosts) in stats.apps {
            let blocked = hosts.keys.filter { host in
                stats.trackers.contains(host)
                    && config.verdict(app: app, host: host, isApple: false, domains: domains, profile: result.profile) == .block
            }
            if !blocked.isEmpty { result.blockedTrackers[app] = Set(blocked) }
        }
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
            // The bundled copy lets Tracker Shield work before its first refresh.
            let bundled =
                list.id == DomainList.trackerShield.id
                ? Bundle.main.url(forResource: "trackers", withExtension: "txt") : nil
            if let text = listFile(list.id).flatMap({ try? String(contentsOf: $0, encoding: .utf8) })
                ?? bundled.flatMap({ try? String(contentsOf: $0, encoding: .utf8) })
            {
                domains[list.id] = DomainList.parse(text)
            }
        }
        state.withLock {
            $0.config = config ?? Config()
            $0.stats = stats ?? Stats()
            $0.domains = domains
            Self.prune(&$0)
        }
        if config == nil { write(Config(), "config.json") }
    }

    /// Clears the app's history and saves right away. The app's config stays.
    func forget(_ app: String) {
        state.withLock {
            $0.stats.forget(app, rules: $0.config.rules.filter { $0.app == app }.map(\.id))
            $0.statsChanged = true
        }
        saveStats()
    }

    /// Empties the stats and saves right away. The config stays.
    func clearHistory() {
        state.withLock {
            $0.stats = Stats()
            $0.codes = [:]
            $0.statsChanged = true
        }
        saveStats()
    }

    /// The entry of each list that covers the host, by list ID.
    func listEntries(for host: String) -> [String: String] {
        // Copy out of the lock, so a lookup never holds up a flow.
        let (config, domains) = state.withLock { ($0.config, $0.domains) }
        return config.listEntries(for: host, domains: domains)
    }

    func discardBrokenConfig() {
        try? FileManager.default.removeItem(at: brokenConfigFile)
    }

    /// Saves a downloaded list and starts using it right away.
    func setList(_ id: String, text: String) {
        guard let file = listFile(id) else { return }
        let hosts = DomainList.parse(text)
        state.withLock { $0.domains[id] = hosts }
        do {
            try FileManager.default.createDirectory(at: folder.appending(path: "lists"), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            errorLog.error("store", "Cannot save list \(id)", error)
        }
    }

    // The ID becomes a file name, so make sure it stays inside the lists folder.
    private func listFile(_ id: String) -> URL? {
        id.contains("/") ? nil : folder.appending(path: "lists/\(id).txt")
    }

    /// Replaces the config. Drops the domains and the cached file of each list it no longer has.
    func setConfig(_ config: Config) {
        let gone = state.withLock {
            $0.config = config
            Self.prune(&$0)
            let gone = Set($0.domains.keys).subtracting(config.lists.map(\.id))
            for id in gone { $0.domains[id] = nil }
            return gone
        }
        write(config, "config.json")
        for file in gone.compactMap(listFile) { try? FileManager.default.removeItem(at: file) }
    }

    private static func prune(_ state: inout State) {
        state.stats.prune(state.config, cutoff: Stats.cutoff(.now))
        state.codes = state.codes.filter { state.stats.apps[$0.key] != nil }
        state.pruned = Stats.day(.now)
        state.statsChanged = true
    }

    /// Decides one flow and records the app, host, and address. Returns nil when Sieve should ask the user.
    /// - Parameter dns: whether the flow is DNS, so its address gets marked.
    func verdict(app: App, host: String?, address: String?, dns: Bool) -> Action? {
        let today = Stats.day(.now)
        return state.withLock {
            if $0.pruned != today { Self.prune(&$0) }
            if $0.stats.see(app.key, host: host, address: address, dns: dns, day: today) { $0.statsChanged = true }
            if host != nil || address != nil {
                $0.stats.countFlow(app.key, host: host, address: address, time: .now)
                $0.statsChanged = true
            }
            // An earlier build may have marked a user tool as Apple.
            if app.isApple ? $0.stats.apple.insert(app.key).inserted : $0.stats.apple.remove(app.key) != nil {
                $0.statsChanged = true
            }
            if let host, $0.config.isTracker(host, domains: $0.domains) {
                $0.stats.trackers.insert(host)
                $0.stats.countTrackerFlow(app.key, host: host)
                $0.statsChanged = true
            }
            if app.isVPN, $0.stats.vpns?.contains(app.key) != true {
                $0.stats.vpns = ($0.stats.vpns ?? []).union([app.key])
                $0.statsChanged = true
            }
            if !app.path.isEmpty, $0.stats.paths.updateValue(app.path, forKey: app.key) != app.path {
                $0.statsChanged = true
            }
            if app.signer.isEmpty { $0.codes[app.key] = app.code }
            let overLimit = $0.config.isOverLimit(app.key, daily: $0.stats.daily, today: today)
            let (action, rule) = $0.config.decide(
                app: app.key, host: host, address: address, isApple: app.isApple, domains: $0.domains,
                overLimit: overLimit,
                profile: Self.activeProfile($0.config, $0.networks),
                trusted: $0.config.trusts(app.key, signer: app.signer, code: app.code)
            )
            if let rule {
                $0.stats.hits[rule.id, default: Hit()].count += 1
                $0.stats.hits[rule.id]?.last = .now
                $0.statsChanged = true
            }
            if action == .block {
                // With no rule and no limit, a listed host can only have been dropped by a block list.
                let byList = if rule == nil, !overLimit, let host { $0.config.isListBlocked(host, domains: $0.domains) } else { false }
                $0.stats.countBlocked(day: today, byList: byList)
                $0.statsChanged = true
            }
            return action
        }
    }

    /// Counts a flow dropped outside `verdict(app:host:address:dns:)`, such as when the Sieve app cannot be asked.
    func countBlocked() {
        state.withLock {
            $0.stats.countBlocked(day: Stats.day(.now), byList: false)
            $0.statsChanged = true
        }
    }

    /// Adds a flow's new bytes to its app. `total` is the flow's count so far.
    func count(flow: UUID, app: String, total: Int, closed: Bool) {
        let today = Stats.day(.now)
        state.withLock {
            let new = max(total - ($0.flowBytes[flow] ?? 0), 0)
            $0.flowBytes[flow] = closed ? nil : total
            // A flow can stay open into a day on which its app opened no new flow.
            _ = $0.stats.see(app, host: nil, day: today)
            $0.stats.bytes[app, default: 0] += new
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
            // Keep the broken file for the user to inspect. The next save would replace it.
            let broken = folder.appending(path: name + ".broken")
            try? FileManager.default.removeItem(at: broken)
            try? FileManager.default.moveItem(at: folder.appending(path: name), to: broken)
            errorLog.error("store", "Cannot read \(name). Moved it aside", error)
            return nil
        }
    }

    private func write(_ value: some Encodable, _ name: String) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: folder.appending(path: name), options: .atomic)
        } catch {
            errorLog.error("store", "Cannot write \(name)", error)
        }
    }
}

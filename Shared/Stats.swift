import Foundation

/// What the filter has seen. Stored as `stats.json` by the extension.
struct Stats: Codable, Equatable {
    /// Hosts each app contacted, by app key, each with the `day(_:)` it was last seen.
    var apps: [String: [String: String]] = [:]
    /// The `day(_:)` each app was last seen, by app key. A flow may have no host.
    var seen: [String: String] = [:]
    /// Bytes in and out, by app key.
    var bytes: [String: Int] = [:]
    /// Blocked flows, by `day(_:)`. Keeps 31 days.
    var blocked: [String: Int] = [:]
    /// Keys of apps that are Apple platform binaries.
    var apple: Set<String> = []
    /// The app bundle or executable on disk, by app key.
    var paths: [String: String] = [:]
    /// Flows each rule decided, by rule ID.
    var hits: [UUID: Hit] = [:]
    /// Rules that are not needed, by rule ID. Filled in for the app only, never saved.
    var flags: [UUID: Flag] = [:]
    /// The `NetworkSignature` of each network the Mac is on. Filled in for the app only.
    var networks: Set<String> = []
    /// The active profile. Filled in for the app only.
    var profile: UUID?
    /// Hosts on any block list, enabled or not.
    var trackers: Set<String> = []
    /// Bytes in and out by `day(_:)`, then by app key. Keeps 31 days.
    var daily: [String: [String: Int]] = [:]
    /// Domains in each list, by list ID. Filled in for the app only.
    var listSizes: [String: Int] = [:]
    /// Whether the extension holds a config file it could not read. Filled in for the app only.
    var brokenConfig = false
    /// Tracker hosts that the current rules and lists block, by app key. Filled in for the app only.
    var blockedTrackers: [String: Set<String>] = [:]
    /// The code directory hash of each path key's last flow. Filled in for the app only.
    /// Optional, so a saved file without it still loads.
    var codes: [String: String]?
    /// `Config.blockedDomainCount(_:)`. Filled in for the app only. Optional, so a saved file without it still loads.
    var blockedDomains: Int?

    /// The most hosts kept for one app.
    static let maxHosts = 1_000

    /// The hosts one app contacted.
    func hosts(_ app: String) -> Set<String> {
        Set(apps[app, default: [:]].keys)
    }

    /// Tracker hosts the app contacted that the current rules and lists let through.
    func openTrackers(_ app: String) -> Int {
        apps[app, default: [:]].keys.filter { trackers.contains($0) && blockedTrackers[app]?.contains($0) != true }.count
    }

    /// A to F, from `openTrackers(_:)`. `–` when the app gave no host names, so its trackers are unknown.
    func grade(_ app: String) -> String {
        apps[app, default: [:]].isEmpty ? "–" : Self.grade(trackers: openTrackers(app))
    }

    /// Each grade, with the open tracker counts it covers.
    static let grades: [(letter: String, trackers: ClosedRange<Int>)] = [
        ("A", 0...0), ("B", 1...2), ("C", 3...5), ("D", 6...10), ("F", 11...Int.max),
    ]

    static func grade(trackers: Int) -> String {
        grades.first { $0.trackers.contains(trackers) }?.letter ?? "F"
    }

    /// Non-Apple apps without an app rule in any column, sorted. Never `Config.unknownApp`, which takes no rule.
    func undecided(_ config: Config) -> [String] {
        apps.keys.filter { $0 != Config.unknownApp && !apple.contains($0) && !config.hasAppRule($0) }.sorted()
    }

    /// Records that the app made a flow on `day`, to `host` if known. Returns whether anything changed.
    /// Past `maxHosts`, a new host replaces the one seen longest ago.
    mutating func see(_ app: String, host: String?, day: String) -> Bool {
        var changed = seen.updateValue(day, forKey: app) != day
        if apps[app] == nil {
            apps[app] = [:]
            changed = true
        }
        guard let host, let hosts = apps[app], hosts[host] != day else { return changed }
        if hosts[host] == nil, hosts.count >= Self.maxHosts,
            let oldest = hosts.min(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key
        {
            apps[app]?[oldest] = nil
        }
        apps[app]?[host] = day
        return true
    }

    /// Drops what was last seen on or before `cutoff`: hosts, days, and apps with no rule and no data limit.
    /// Also drops the hits of rules not in `config`, and trackers no app still has.
    mutating func prune(_ config: Config, cutoff: String) {
        let kept = Set(config.rules.map(\.app) + config.limits.map(\.app))
        for (app, day) in seen where day <= cutoff && !kept.contains(app) {
            apps[app] = nil
            seen[app] = nil
            bytes[app] = nil
            paths[app] = nil
            apple.remove(app)
        }
        apps = apps.mapValues { $0.filter { $0.value > cutoff } }
        blocked = blocked.filter { $0.key > cutoff }
        daily = daily.filter { $0.key > cutoff }
        let rules = Set(config.rules.map(\.id))
        hits = hits.filter { rules.contains($0.key) }
        trackers = trackers.filter { host in apps.values.contains { $0[host] != nil } }
    }

    /// Clears what the app did: its hosts, bytes, and rule hits. Keeps the app in the list, with its path.
    /// - Parameter rules: the IDs of the app's rules.
    mutating func forget(_ app: String, rules: [UUID]) {
        apps[app] = [:]
        bytes[app] = nil
        for day in daily.keys { daily[day]?[app] = nil }
        for rule in rules { hits[rule] = nil }
        // A tracker that no other app reached was this app's history too.
        trackers = trackers.filter { host in apps.values.contains { $0[host] != nil } }
    }

    /// The `day(_:)` 31 days before `date`. Stats keep only the days after it.
    static func cutoff(_ date: Date) -> String {
        day(date.addingTimeInterval(-31 * 24 * 60 * 60))
    }

    /// The local date, such as `2026-11-11`.
    static func day(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}

struct Hit: Codable, Equatable {
    var count = 0
    var last = Date.now
}

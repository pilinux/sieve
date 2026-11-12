import Foundation

/// What the filter has seen. Stored as `stats.json` by the extension.
struct Stats: Codable, Equatable {
    /// Hosts each app contacted, by app key.
    var apps: [String: Set<String>] = [:]
    /// Bytes in and out, by app key.
    var bytes: [String: Int] = [:]
    /// Blocked flows, by `day(_:)`.
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

    /// A to F, from the number of tracker hosts the app contacted.
    func grade(_ app: String) -> String {
        Self.grade(trackers: apps[app, default: []].intersection(trackers).count)
    }

    static func grade(trackers: Int) -> String {
        switch trackers {
        case 0: "A"
        case 1...2: "B"
        case 3...5: "C"
        case 6...10: "D"
        default: "F"
        }
    }

    /// Non-Apple apps without an app rule, sorted.
    func undecided(_ config: Config) -> [String] {
        apps.keys.filter { !apple.contains($0) && config.action(for: $0) == nil }.sorted()
    }

    /// Clears what the app did: its hosts, bytes, and rule hits. Keeps the app in the list, with its path.
    /// - Parameter rules: the IDs of the app's rules.
    mutating func forget(_ app: String, rules: [UUID]) {
        apps[app] = []
        bytes[app] = nil
        for day in daily.keys { daily[day]?[app] = nil }
        for rule in rules { hits[rule] = nil }
        // A tracker that no other app reached was this app's history too.
        trackers = trackers.filter { host in apps.values.contains { $0.contains(host) } }
    }

    /// The local date, such as `2026-11-11`.
    static func day(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}

extension Stats {
    // Missing keys get defaults, so stats from an older build still load.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        apps = try values.decodeIfPresent([String: Set<String>].self, forKey: .apps) ?? [:]
        bytes = try values.decodeIfPresent([String: Int].self, forKey: .bytes) ?? [:]
        blocked = try values.decodeIfPresent([String: Int].self, forKey: .blocked) ?? [:]
        apple = try values.decodeIfPresent(Set<String>.self, forKey: .apple) ?? []
        paths = try values.decodeIfPresent([String: String].self, forKey: .paths) ?? [:]
        hits = try values.decodeIfPresent([UUID: Hit].self, forKey: .hits) ?? [:]
        flags = try values.decodeIfPresent([UUID: Flag].self, forKey: .flags) ?? [:]
        networks = try values.decodeIfPresent(Set<String>.self, forKey: .networks) ?? []
        profile = try values.decodeIfPresent(UUID.self, forKey: .profile)
        trackers = try values.decodeIfPresent(Set<String>.self, forKey: .trackers) ?? []
        daily = try values.decodeIfPresent([String: [String: Int]].self, forKey: .daily) ?? [:]
        listSizes = try values.decodeIfPresent([String: Int].self, forKey: .listSizes) ?? [:]
        brokenConfig = try values.decodeIfPresent(Bool.self, forKey: .brokenConfig) ?? false
    }
}

struct Hit: Codable, Equatable {
    var count = 0
    var last = Date.now
}

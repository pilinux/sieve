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

    /// Non-Apple apps without an app rule, sorted.
    func undecided(_ config: Config) -> [String] {
        apps.keys.filter { !apple.contains($0) && config.action(for: $0) == nil }.sorted()
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
    }
}

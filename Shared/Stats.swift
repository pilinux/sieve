import Foundation
import Network

/// What the filter has seen. The extension saves it as `stats.json`.
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
    /// The code pin of each path key's last flow. Filled in for the app only.
    /// It is optional, so an older file without it still loads.
    var codes: [String: String]?
    /// `Config.blockedDomainCount(_:)`. Filled in for the app only. It is optional, so an older file without it still loads.
    var blockedDomains: Int?
    /// IP addresses each app connected to, by app key, then by address. It is optional, so an older file without it still loads.
    var addresses: [String: [String: Address]]?
    /// How many of the `blocked` flows a block list dropped, by `day(_:)`. A day with no entry was counted before this split.
    /// It is optional, so an older file without it still loads.
    var blockedByList: [String: Int]?
    /// Flows to each tracker host, allowed or blocked, by app key, then host. It is optional, so an older file without it still loads.
    var trackerFlows: [String: [String: Int]]?
    /// Keys of VPN and proxy apps. Their flows carry other apps' traffic again. It is optional, so an older file without it still loads.
    var vpns: Set<String>?
    /// Flows to each host, allowed or blocked, and the last one, by app key, then host.
    /// It is optional, so an older file without it still loads.
    var hostHits: [String: [String: Hit]]?
    /// Keys of apps whose path is no longer on disk. Filled in for the app only.
    var gone: Set<String>?

    /// The most hosts, and the most IP addresses, that Sieve keeps for one app.
    static let maxHosts = 1_000

    /// The hosts one app contacted.
    func hosts(_ app: String) -> Set<String> {
        Set(apps[app, default: [:]].keys)
    }

    /// Tracker hosts the app contacted that the current rules and lists let through.
    func openTrackers(_ app: String) -> Int {
        apps[app, default: [:]].keys.filter { trackers.contains($0) && blockedTrackers[app]?.contains($0) != true }.count
    }

    /// A grade from A to F, based on `openTrackers(_:)`. `–` when the app sent no host names, so its trackers are unknown.
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

    /// Non-Apple apps with no app rule in any column, sorted. Leaves out `Config.unknownApp`, which cannot have a rule.
    func undecided(_ config: Config) -> [String] {
        apps.keys.filter { $0 != Config.unknownApp && !apple.contains($0) && !config.hasAppRule($0) }.sorted()
    }

    /// Records that the app made a flow on `day`, to `host` and `address` if known. Returns whether anything changed.
    /// Once the app has `maxHosts`, a new host or address replaces the one seen longest ago.
    /// An address keeps its last host name when a later flow to it has none, unless that flow is DNS, whose host name
    /// replaces it even when it is none. An address stays marked once a flow to it was DNS.
    mutating func see(_ app: String, host: String?, address: String? = nil, dns: Bool = false, day: String) -> Bool {
        var changed = seen.updateValue(day, forKey: app) != day
        if apps[app] == nil {
            apps[app] = [:]
            changed = true
        }
        if let host, apps[app]?[host] != day {
            if let gone = Self.makeRoom(for: host, in: &apps[app, default: [:]], day: { $0 }) { hostHits?[app]?[gone] = nil }
            apps[app, default: [:]][host] = day
            changed = true
        }
        if let address {
            let old = addresses?[app]?[address]
            let new = Address(
                day: day, host: dns ? host : host ?? old?.host, hits: old?.hits, dns: dns || old?.dns == true ? true : nil)
            if addresses?[app]?[address] != new {
                // Take the map out first. With one owner, Swift changes it in place instead of copying it.
                var all = addresses.take() ?? [:]
                Self.makeRoom(for: address, in: &all[app, default: [:]]) { $0.day }
                all[app, default: [:]][address] = new
                addresses = all
                changed = true
            }
        }
        return changed
    }

    /// Counts one blocked flow on `day`.
    mutating func countBlocked(day: String, byList: Bool) {
        blocked[day, default: 0] += 1
        // Create the day's entry on its first blocked flow. A day that began on an older build has no entry, so it stays unsplit.
        if blocked[day] == 1 {
            var all = blockedByList.take() ?? [:]
            all[day] = 0
            blockedByList = all
        }
        if byList { blockedByList?[day]? += 1 }
    }

    /// The day's blocked flows, split into those a block list dropped and those dropped by rules, limits, or Ask mode.
    /// Nil for a day counted before the split.
    func blockedSplit(_ day: String) -> (lists: Int, rules: Int)? {
        guard let lists = blockedByList?[day] else { return nil }
        return (lists, blocked[day, default: 0] - lists)
    }

    /// Bytes of all apps together. VPN apps are left out, so traffic through a VPN counts once.
    var totalBytes: Int {
        bytes.filter { vpns?.contains($0.key) != true }.values.reduce(0, +)
    }

    /// `totalBytes` for one day.
    func totalBytes(day: String) -> Int {
        (daily[day] ?? [:]).filter { vpns?.contains($0.key) != true }.values.reduce(0, +)
    }

    /// Counts one flow from the app to `host` and `address`. Call it after `see(_:host:address:day:)`, which adds them.
    mutating func countFlow(_ app: String, host: String?, address: String?, time: Date) {
        if let host {
            // Take the map out first. With one owner, Swift changes it in place instead of copying it.
            var all = hostHits.take() ?? [:]
            all[app, default: [:]][host, default: Hit()].count += 1
            all[app]?[host]?.last = time
            hostHits = all
        }
        if let address, let old = addresses?[app]?[address] {
            addresses?[app]?[address]?.hits = Hit(count: (old.hits?.count ?? 0) + 1, last: time)
        }
    }

    /// Counts one flow from the app to a tracker host.
    mutating func countTrackerFlow(_ app: String, host: String) {
        // Take the map out first. With one owner, Swift changes it in place instead of copying it.
        var all = trackerFlows.take() ?? [:]
        all[app, default: [:]][host, default: 0] += 1
        trackerFlows = all
    }

    /// Flows from the app to all its tracker hosts.
    func trackerCalls(_ app: String) -> Int {
        trackerFlows?[app]?.values.reduce(0, +) ?? 0
    }

    /// Flows from all apps to the tracker host.
    func trackerCalls(host: String) -> Int {
        trackerFlows?.values.reduce(0) { $0 + ($1[host] ?? 0) } ?? 0
    }

    // Drops the entry seen longest ago when a new key would pass `maxHosts`, and returns its key.
    @discardableResult
    private static func makeRoom<Value>(for key: String, in map: inout [String: Value], day: (Value) -> String) -> String? {
        guard map[key] == nil, map.count >= maxHosts,
            let oldest = map.min(by: { (day($0.value), $0.key) < (day($1.value), $1.key) })?.key
        else { return nil }
        map[oldest] = nil
        return oldest
    }

    /// Removes what was last seen on or before `cutoff`: hosts, addresses, days, and apps with no rule and no data limit.
    /// Also removes the hits of rules not in `config`, trackers no app still has, and tracker flows and host hits of hosts an app dropped.
    mutating func prune(_ config: Config, cutoff: String) {
        let kept = Set(config.rules.map(\.app) + config.limits.map(\.app))
        for (app, day) in seen where day <= cutoff && !kept.contains(app) {
            apps[app] = nil
            seen[app] = nil
            bytes[app] = nil
            paths[app] = nil
            apple.remove(app)
            vpns?.remove(app)
            addresses?[app] = nil
        }
        apps = apps.mapValues { $0.filter { $0.value > cutoff } }
        addresses = addresses?.mapValues { $0.filter { $0.value.day > cutoff } }
        blocked = blocked.filter { $0.key > cutoff }
        blockedByList = blockedByList?.filter { $0.key > cutoff }
        trackerFlows = trackerFlows.map { seenHostsOnly($0) }
        hostHits = hostHits.map { seenHostsOnly($0) }
        daily = daily.filter { $0.key > cutoff }
        let rules = Set(config.rules.map(\.id))
        hits = hits.filter { rules.contains($0.key) }
        dropUnreachedTrackers()
    }

    // Keeps the hosts each app still has, and drops apps with none left.
    private func seenHostsOnly<Value>(_ map: [String: [String: Value]]) -> [String: [String: Value]] {
        map.reduce(into: [:]) { kept, entry in
            let hosts = entry.value.filter { apps[entry.key]?[$0.key] != nil }
            if !hosts.isEmpty { kept[entry.key] = hosts }
        }
    }

    private mutating func dropUnreachedTrackers() {
        trackers = trackers.filter { host in apps.values.contains { $0[host] != nil } }
    }

    /// Clears the app's history: its hosts, addresses, tracker flows, host hits, bytes, and rule hits. Unless `entirely` is set, the app stays in the list, with its path.
    /// - Parameter rules: the IDs of the app's rules.
    /// - Parameter entirely: whether the app leaves the list too, with its path and every other fact about it.
    mutating func forget(_ app: String, rules: [UUID], entirely: Bool = false) {
        apps[app] = entirely ? nil : [:]
        if entirely {
            seen[app] = nil
            paths[app] = nil
            apple.remove(app)
            vpns?.remove(app)
        }
        addresses?[app] = nil
        trackerFlows?[app] = nil
        hostHits?[app] = nil
        bytes[app] = nil
        for day in daily.keys { daily[day]?[app] = nil }
        for rule in rules { hits[rule] = nil }
        // Also remove trackers that no other app reached, since they were part of this app's history.
        dropUnreachedTrackers()
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

/// One IP address an app connected to. It is a struct so that new facts can be added later as optional fields.
struct Address: Codable, Equatable {
    /// The `Stats.day(_:)` it was last seen.
    var day: String
    /// The last host name seen with it, or nil if no flow to it had one.
    var host: String?
    /// Flows to it, allowed or blocked, and the last one. Nil for an address seen before Sieve counted them.
    var hits: Hit?
    /// True once a flow to it was DNS: port 53, or 853 for DNS over TLS. Nil otherwise.
    var dns: Bool?

    /// Whether the address is in a range for local networks: RFC 1918, RFC 6598 shared space, link-local, or RFC 4193.
    static func isLocal(_ address: String) -> Bool {
        guard let bytes = AddressTable.bytes(address) else { return false }
        return localRanges.contains { $0.contains(bytes) }
    }

    private static let localRanges = [
        "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "169.254.0.0/16", "fc00::/7", "fe80::/10",
    ].compactMap { AddressRange($0) }

    /// The address in the form rules and stats use, or nil if `text` is not an IP address.
    /// Drops the `%` zone from IPv6, and turns an IPv4-mapped IPv6 address into IPv4.
    nonisolated static func normalize(_ text: String) -> String? {
        if let ipv4 = IPv4Address(text) { return "\(ipv4)" }
        guard let ipv6 = IPv6Address(text) else { return nil }
        if ipv6.isIPv4Mapped, let ipv4 = ipv6.asIPv4 { return "\(ipv4)" }
        // Rebuilding the address from its bytes leaves out the interface, so the zone goes too.
        return IPv6Address(ipv6.rawValue).map { "\($0)" }
    }
}

/// The IP addresses that share their first bits, written as `prefix/length`, such as `10.0.0.0/8`.
struct AddressRange {
    private let prefix: [UInt8]
    private let length: Int

    init?(_ text: String) {
        let parts = text.split(separator: "/")
        // Normalizing first makes an IPv4-mapped IPv6 address compare as IPv4.
        guard parts.count == 2, let length = Int(parts[1]), let prefix = AddressTable.bytes(String(parts[0])),
            (0...prefix.count * 8).contains(length)
        else { return nil }
        self.prefix = prefix
        self.length = length
    }

    func contains(_ address: String) -> Bool {
        AddressTable.bytes(address).map(contains) ?? false
    }

    /// Takes the bytes that `AddressTable.bytes(_:)` gives, so a caller that checks many ranges parses the address once.
    func contains(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == prefix.count else { return false }
        return (0..<length).allSatisfy { bit in (bytes[bit / 8] ^ prefix[bit / 8]) & (0x80 >> (bit % 8)) == 0 }
    }
}

nonisolated struct Hit: Codable, Equatable, Sendable {
    var count = 0
    var last = Date.now
}

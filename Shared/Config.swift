import Foundation

/// Everything the user sets. Stored as `config.json` by the extension.
struct Config: Codable, Equatable {
    var mode = Mode.quiet
    var rules: [Rule] = []
    var lists: [DomainList] = [.trackerShield]
    var limits: [Limit] = []
    var profiles: [Profile] = []
    /// The code directory hash the user allowed, by path key. Optional, so a config without it still loads.
    var codes: [String: String]?

    /// The key of a process that exited before its lookup. Many processes share it, so no rule covers it.
    static let unknownApp = "unknown"

    /// Decides one flow. Nil means: ask the user.
    /// - Parameters:
    ///   - address: the remote IP address, as `Address.normalize(_:)` gives it.
    ///   - domains: the hosts of each list, by list ID.
    func verdict(
        app: String, host: String?, address: String? = nil, isApple: Bool, domains: [String: Set<String>] = [:],
        overLimit: Bool = false, profile: UUID? = nil
    ) -> Action? {
        decide(
            app: app, host: host, address: address, isApple: isApple, domains: domains, overLimit: overLimit,
            profile: profile
        ).action
    }

    /// The verdict, and the rule that gave it.
    /// - Parameters:
    ///   - profile: the active profile. Rules of other profiles do not count.
    ///   - trusted: false drops the app's Allow rules. Its Block rules still count.
    func decide(
        app: String, host: String?, address: String? = nil, isApple: Bool, domains: [String: Set<String>],
        overLimit: Bool = false, profile: UUID? = nil, trusted: Bool = true
    ) -> (action: Action?, rule: Rule?) {
        if mode == .off { return (.allow, nil) }
        let appRule = rule(for: app, profile: profile, trusted: trusted)
        if appRule?.action == .block { return (.block, appRule) }
        if overLimit { return (.block, nil) }
        if let host, let rule = hostRule(for: app, host: host, profile: profile, trusted: trusted) {
            return (rule.action, rule)
        }
        // An IP rule names one address: no parent to check.
        if let address, let rule = rule(for: app, host: address, profile: profile, trusted: trusted) {
            return (rule.action, rule)
        }
        if let host {
            if isListed(host, .allow, domains) { return (.allow, nil) }
            if isListed(host, .block, domains) { return (.block, nil) }
        }
        if let appRule { return (appRule.action, appRule) }
        if isApple { return (.allow, nil) }
        // Ask mode cannot ask about a process that is gone.
        if mode == .ask, app == Self.unknownApp { return (.block, nil) }
        return (mode == .ask ? nil : .allow, nil)
    }

    /// Why a rule is not needed, or nil.
    /// - Parameter gone: keys of apps no longer on disk.
    func flag(_ rule: Rule, gone: Set<String>, domains: [String: Set<String>]) -> Flag? {
        if gone.contains(rule.app) { return .appGone }
        guard let host = rule.host else { return nil }
        if isAppBlocked(rule.app, profile: rule.profile) { return .appBlocked }
        // An allow list beats a block list, so a Block rule for a host on both still decides it.
        if rule.action == .block, isListed(host, .block, domains), !isListed(host, .allow, domains) { return .blockList }
        // Where the rule counts: its own profile, or with no profile, wherever no profile has its own rule for the host.
        let counts: [UUID?] =
            if let profile = rule.profile { [profile] } else {
                [nil] + profiles.map(\.id).filter { self.rule(for: rule.app, host: host, profile: $0)?.profile == nil }
            }
        // The nearest parent domain rule decides the host when this rule is gone, wherever this rule counts.
        var without = self
        without.rules.removeAll { $0.id == rule.id }
        let parents = counts.map { without.hostRule(for: rule.app, host: host, profile: $0) }
        return parents.allSatisfy { $0?.action == rule.action && $0?.host != host } ? .parentRule : nil
    }

    // Whether the app is blocked wherever a rule of `profile` counts: in that profile,
    // or with no profile, in every profile, since a profile without its own app rule falls back to Always.
    private func isAppBlocked(_ app: String, profile: UUID?) -> Bool {
        if let profile { return rule(for: app, profile: profile)?.action == .block }
        return rule(for: app)?.action == .block && !rules.contains { $0.app == app && $0.host == nil && $0.action == .allow }
    }

    /// Whether the app has an app rule in any column: Always or a profile.
    func hasAppRule(_ app: String) -> Bool {
        rules.contains { $0.app == app && $0.host == nil }
    }

    /// The app's rule for exactly this host. A nil host means the app rule.
    func action(for app: String, host: String? = nil) -> Action? {
        rule(for: app, host: host)?.action
    }

    // A rule of the active profile beats one without a profile.
    private func rule(for app: String, host: String? = nil, profile: UUID? = nil, trusted: Bool = true) -> Rule? {
        guard app != Self.unknownApp else { return nil }
        let matches = rules.filter { $0.app == app && $0.host == host && (trusted || $0.action == .block) }
        return matches.first { profile != nil && $0.profile == profile } ?? matches.first { $0.profile == nil }
    }

    /// Whether the app's Allow rules count. A verified signer names the app wherever it is.
    /// A path key names a file that other code can replace, so only the code the user allowed counts.
    /// - Parameter code: the code directory hash of the running code, if it has one.
    func trusts(_ app: String, signer: String, code: String?) -> Bool {
        !signer.isEmpty || (code != nil && codes?[app] == code)
    }

    /// Allows the code each app runs now, for each Allow rule that `old` does not have.
    /// Keeps the allowed hash while the running code is not known. Drops the hash of an app with no rule left.
    /// - Parameter running: the code directory hash of each path key, as in `Stats.codes`.
    mutating func approveCode(since old: Config, running: [String: String]) {
        let allowed = Set(old.rules.filter { $0.action == .allow }.map(\.id))
        var codes = self.codes ?? [:]
        for rule in rules where rule.action == .allow && !allowed.contains(rule.id) {
            if let code = running[rule.app] { codes[rule.app] = code }
        }
        self.codes = codes.filter { app, _ in rules.contains { $0.app == app } }
    }

    /// The first profile whose network or any time block matches.
    /// - Parameters:
    ///   - networks: the `NetworkSignature` of each network the Mac is on.
    ///   - weekday: 1 is Sunday, as in `Calendar`.
    ///   - minute: minutes after midnight.
    func activeProfile(networks: Set<String>, weekday: Int, minute: Int) -> UUID? {
        profiles.first { profile in
            if let network = profile.network, networks.contains(network) { return true }
            return profile.schedules.contains { $0.covers(weekday: weekday, minute: minute) }
        }?.id
    }

    /// Whether the app has used up its data limit.
    /// - Parameters:
    ///   - daily: bytes by day, then by app key.
    ///   - today: `Stats.day(_:)` of now.
    func isOverLimit(_ app: String, daily: [String: [String: Int]], today: String) -> Bool {
        guard let limit = limits.first(where: { $0.app == app }) else { return false }
        return usage(app, period: limit.period, daily: daily, today: today) >= limit.bytes
    }

    /// Bytes the app used today, or this month so far.
    func usage(_ app: String, period: Period, daily: [String: [String: Int]], today: String) -> Int {
        let days = period == .day ? [today] : daily.keys.filter { $0.hasPrefix(today.prefix(7)) }
        return days.reduce(0) { $0 + (daily[$1]?[app] ?? 0) }
    }

    /// Replaces the app's limit. Nil bytes removes it.
    mutating func setLimit(_ bytes: Int?, period: Period, for app: String) {
        limits.removeAll { $0.app == app }
        if let bytes { limits.append(Limit(app: app, bytes: bytes, period: period)) }
    }

    /// Replaces the app's rule for this host. Leaves rules of profiles alone.
    mutating func setAction(_ action: Action, for app: String, host: String? = nil) {
        guard app != Self.unknownApp else { return }
        // A new rule even for the same action: a new Allow rule is what allows a path key's changed code.
        rules.removeAll { $0.app == app && $0.host == host && $0.profile == nil }
        rules.append(Rule(app: app, host: host, action: action))
    }

    /// Sets the rule for this app, host, and profile. Picking the rule's own action again removes it.
    mutating func pick(_ action: Action, for app: String, host: String?, profile: UUID?) {
        guard app != Self.unknownApp else { return }
        if let index = rules.firstIndex(where: { $0.app == app && $0.host == host && $0.profile == profile }) {
            if rules[index].action == action { rules.remove(at: index) } else { rules[index].action = action }
        } else {
            rules.append(Rule(app: app, host: host, action: action, profile: profile))
        }
    }

    // Checks the host, then each parent domain, so the most specific rule wins.
    /// The app's rule for the host or its nearest parent domain.
    func hostRule(for app: String, host: String, profile: UUID? = nil, trusted: Bool = true) -> Rule? {
        var domain = Substring(host)
        while true {
            if let rule = rule(for: app, host: String(domain), profile: profile, trusted: trusted) { return rule }
            guard let dot = domain.firstIndex(of: ".") else { return nil }
            domain = domain[domain.index(after: dot)...]
        }
    }

    /// The hosts on the enabled block lists that no enabled allow list covers. A host on several lists counts once.
    func blockedDomainCount(_ domains: [String: Set<String>]) -> Int {
        lists.filter { $0.enabled && $0.action == .block }
            .reduce(into: Set<String>()) { $0.formUnion(domains[$1.id] ?? []) }
            .count(where: { !isListed($0, .allow, domains) })
    }

    /// Whether any block list covers the host, enabled or not.
    func isTracker(_ host: String, domains: [String: Set<String>]) -> Bool {
        lists.contains { $0.action == .block && Self.covers(domains[$0.id] ?? [], host) }
    }

    private func isListed(_ host: String, _ action: Action, _ domains: [String: Set<String>]) -> Bool {
        lists.contains { $0.enabled && $0.action == action && Self.covers(domains[$0.id] ?? [], host) }
    }

    // An entry covers its own host and every subdomain: check the host, then each parent domain.
    private static func covers(_ entries: Set<String>, _ host: String) -> Bool {
        var domain = Substring(host)
        while true {
            if entries.contains(String(domain)) { return true }
            guard let dot = domain.firstIndex(of: ".") else { return false }
            domain = domain[domain.index(after: dot)...]
        }
    }
}

enum Mode: String, Codable {
    case off, ask, quiet
}

enum Action: String, Codable {
    case allow, block
}

/// Bytes in and out an app may use per period. Over it, new flows are dropped.
struct Limit: Codable, Equatable {
    var app: String
    var bytes: Int
    var period: Period
}

enum Period: String, Codable {
    case day, month
}

/// Why a rule is not needed. The raw value is the text the app shows.
enum Flag: String, Codable {
    case appGone = "App is gone"
    case appBlocked = "App is blocked"
    case blockList = "On a block list"
    case parentRule = "Parent domain rule"
}

struct Rule: Codable, Equatable, Identifiable {
    var id = UUID()
    var app: String
    /// Nil: the rule covers the whole app. Else this domain and its subdomains, or this one IP address.
    var host: String?
    var action: Action
    /// Nil: the rule always counts. Else only while this profile is active.
    var profile: UUID?
}

/// A set of rules that counts only on a network or during one of its time blocks.
struct Profile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    /// A `NetworkSignature`, such as `IPv4.Router=172.20.10.1;IPv4.RouterHardwareAddress=…`.
    var network: String?
    /// Time blocks, each with its own weekdays and times.
    var schedules: [Schedule] = []
    /// The user's colour, such as `#4fb3c9`. Nil: a default by position.
    var color: String?
}

struct Schedule: Codable, Equatable {
    /// 1 is Sunday, as in `Calendar`.
    var weekdays: Set<Int>
    /// Minutes after midnight.
    var start: Int
    var end: Int

    /// Whether the block covers this weekday and minute. The end is not included.
    func covers(weekday: Int, minute: Int) -> Bool {
        weekdays.contains(weekday) && minute >= start && minute < end
    }
}

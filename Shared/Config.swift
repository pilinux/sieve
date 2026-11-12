import Foundation

/// Everything the user sets. Stored as `config.json` by the extension.
struct Config: Codable, Equatable {
    var mode = Mode.quiet
    var rules: [Rule] = []
    var lists: [DomainList] = [.trackerShield]
    var limits: [Limit] = []
    var profiles: [Profile] = []

    /// Decides one flow. Nil means: ask the user.
    /// - Parameter domains: the hosts of each list, by list ID.
    func verdict(
        app: String, host: String?, isApple: Bool, domains: [String: Set<String>] = [:], overLimit: Bool = false,
        profile: UUID? = nil
    ) -> Action? {
        decide(app: app, host: host, isApple: isApple, domains: domains, overLimit: overLimit, profile: profile).action
    }

    /// The verdict, and the rule that gave it.
    /// - Parameter profile: the active profile. Rules of other profiles do not count.
    func decide(
        app: String, host: String?, isApple: Bool, domains: [String: Set<String>], overLimit: Bool = false,
        profile: UUID? = nil
    ) -> (action: Action?, rule: Rule?) {
        if mode == .off { return (.allow, nil) }
        let appRule = rule(for: app, profile: profile)
        if appRule?.action == .block { return (.block, appRule) }
        if overLimit { return (.block, nil) }
        if let host {
            if let rule = hostRule(for: app, host: host, profile: profile) { return (rule.action, rule) }
            if isListed(host, .allow, domains) { return (.allow, nil) }
            if isListed(host, .block, domains) { return (.block, nil) }
        }
        if let appRule { return (appRule.action, appRule) }
        if isApple { return (.allow, nil) }
        return (mode == .ask ? nil : .allow, nil)
    }

    /// Why a rule is not needed, or nil.
    /// - Parameter gone: keys of apps no longer on disk.
    func flag(_ rule: Rule, gone: Set<String>, domains: [String: Set<String>]) -> Flag? {
        if gone.contains(rule.app) { return .appGone }
        guard let host = rule.host else { return nil }
        if action(for: rule.app) == .block { return .appBlocked }
        if rule.action == .block, isListed(host, .block, domains) { return .blockList }
        // The nearest parent domain rule decides the host when this rule is gone.
        if let dot = host.firstIndex(of: "."),
            hostRule(for: rule.app, host: String(host[host.index(after: dot)...]))?.action == rule.action
        {
            return .parentRule
        }
        return nil
    }

    /// The app's rule for exactly this host. A nil host means the app rule.
    func action(for app: String, host: String? = nil) -> Action? {
        rule(for: app, host: host)?.action
    }

    // A rule of the active profile beats one without a profile.
    private func rule(for app: String, host: String? = nil, profile: UUID? = nil) -> Rule? {
        let matches = rules.filter { $0.app == app && $0.host == host }
        return matches.first { profile != nil && $0.profile == profile } ?? matches.first { $0.profile == nil }
    }

    /// The first profile whose network or schedule matches.
    /// - Parameters:
    ///   - networks: the `NetworkSignature` of each network the Mac is on.
    ///   - weekday: 1 is Sunday, as in `Calendar`.
    ///   - minute: minutes after midnight.
    func activeProfile(networks: Set<String>, weekday: Int, minute: Int) -> UUID? {
        profiles.first { profile in
            if let network = profile.network, networks.contains(network) { return true }
            guard let schedule = profile.schedule, schedule.weekdays.contains(weekday) else { return false }
            // An end before the start runs past midnight.
            return schedule.start <= schedule.end
                ? (schedule.start..<schedule.end).contains(minute)
                : minute >= schedule.start || minute < schedule.end
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
        rules.removeAll { $0.app == app && $0.host == host && $0.profile == nil }
        rules.append(Rule(app: app, host: host, action: action))
    }

    // Checks the host, then each parent domain, so the most specific rule wins.
    private func hostRule(for app: String, host: String, profile: UUID? = nil) -> Rule? {
        var domain = Substring(host)
        while true {
            if let rule = rule(for: app, host: String(domain), profile: profile) { return rule }
            guard let dot = domain.firstIndex(of: ".") else { return nil }
            domain = domain[domain.index(after: dot)...]
        }
    }

    /// Whether any block list has the host, enabled or not.
    func isTracker(_ host: String, domains: [String: Set<String>]) -> Bool {
        lists.contains { $0.action == .block && domains[$0.id]?.contains(host) == true }
    }

    // List entries match the exact host only.
    private func isListed(_ host: String, _ action: Action, _ domains: [String: Set<String>]) -> Bool {
        lists.contains { $0.enabled && $0.action == action && domains[$0.id]?.contains(host) == true }
    }
}

extension Config {
    // Missing keys get defaults, so a config from an older build still loads.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config()
        mode = try values.decodeIfPresent(Mode.self, forKey: .mode) ?? defaults.mode
        rules = try values.decodeIfPresent([Rule].self, forKey: .rules) ?? defaults.rules
        lists = try values.decodeIfPresent([DomainList].self, forKey: .lists) ?? defaults.lists
        limits = try values.decodeIfPresent([Limit].self, forKey: .limits) ?? defaults.limits
        profiles = try values.decodeIfPresent([Profile].self, forKey: .profiles) ?? defaults.profiles
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
    /// Nil: the rule covers the whole app. Else this domain and its subdomains.
    var host: String?
    var action: Action
    /// Nil: the rule always counts. Else only while this profile is active.
    var profile: UUID?
}

/// A set of rules that counts only on a network or during a schedule.
struct Profile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    /// A `NetworkSignature`, such as `IPv4.Router=172.20.10.1;IPv4.RouterHardwareAddress=…`.
    var network: String?
    var schedule: Schedule?
}

struct Schedule: Codable, Equatable {
    /// 1 is Sunday, as in `Calendar`.
    var weekdays: Set<Int>
    /// Minutes after midnight.
    var start: Int
    var end: Int
}

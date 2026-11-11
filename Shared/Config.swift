import Foundation

/// Everything the user sets. Stored as `config.json` by the extension.
struct Config: Codable, Equatable {
    var mode = Mode.quiet
    var rules: [Rule] = []
    var lists: [DomainList] = [.trackerShield]
    var limits: [Limit] = []

    /// Decides one flow. Nil means: ask the user.
    /// - Parameter domains: the hosts of each list, by list ID.
    func verdict(
        app: String, host: String?, isApple: Bool, domains: [String: Set<String>] = [:], overLimit: Bool = false
    ) -> Action? {
        decide(app: app, host: host, isApple: isApple, domains: domains, overLimit: overLimit).action
    }

    /// The verdict, and the rule that gave it.
    func decide(
        app: String, host: String?, isApple: Bool, domains: [String: Set<String>], overLimit: Bool = false
    ) -> (action: Action?, rule: Rule?) {
        if mode == .off { return (.allow, nil) }
        let appRule = rule(for: app)
        if appRule?.action == .block { return (.block, appRule) }
        if overLimit { return (.block, nil) }
        if let host {
            if let rule = hostRule(for: app, host: host) { return (rule.action, rule) }
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
           hostRule(for: rule.app, host: String(host[host.index(after: dot)...]))?.action == rule.action {
            return .parentRule
        }
        return nil
    }

    /// The app's rule for exactly this host. A nil host means the app rule.
    func action(for app: String, host: String? = nil) -> Action? {
        rule(for: app, host: host)?.action
    }

    private func rule(for app: String, host: String? = nil) -> Rule? {
        rules.first { $0.app == app && $0.host == host }
    }

    /// Whether the app has used up its data limit.
    /// - Parameters:
    ///   - daily: bytes by day, then by app key.
    ///   - today: `Stats.day(_:)` of now.
    func isOverLimit(_ app: String, daily: [String: [String: Int]], today: String) -> Bool {
        guard let limit = limits.first(where: { $0.app == app }) else { return false }
        let days = limit.period == .day ? [today] : daily.keys.filter { $0.hasPrefix(today.prefix(7)) }
        return days.reduce(0) { $0 + (daily[$1]?[app] ?? 0) } >= limit.bytes
    }

    /// Replaces the app's limit. Nil bytes removes it.
    mutating func setLimit(_ bytes: Int?, period: Period, for app: String) {
        limits.removeAll { $0.app == app }
        if let bytes { limits.append(Limit(app: app, bytes: bytes, period: period)) }
    }

    /// Replaces the app's rule for this host.
    mutating func setAction(_ action: Action, for app: String, host: String? = nil) {
        rules.removeAll { $0.app == app && $0.host == host }
        rules.append(Rule(app: app, host: host, action: action))
    }

    /// Checks the host, then each parent domain, so the most specific rule wins.
    private func hostRule(for app: String, host: String) -> Rule? {
        var domain = Substring(host)
        while true {
            if let rule = rule(for: app, host: String(domain)) { return rule }
            guard let dot = domain.firstIndex(of: ".") else { return nil }
            domain = domain[domain.index(after: dot)...]
        }
    }

    /// Whether any block list has the host, enabled or not.
    func isTracker(_ host: String, domains: [String: Set<String>]) -> Bool {
        lists.contains { $0.action == .block && domains[$0.id]?.contains(host) == true }
    }

    /// List entries match the exact host only.
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
}

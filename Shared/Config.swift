import Foundation

/// Everything the user sets. Stored as `config.json` by the extension.
struct Config: Codable, Equatable {
    var mode = Mode.quiet
    var rules: [Rule] = []
    var lists: [DomainList] = [.trackerShield]

    /// Decides one flow. Nil means: ask the user.
    /// - Parameter domains: the hosts of each list, by list ID.
    func verdict(app: String, host: String?, isApple: Bool, domains: [String: Set<String>] = [:]) -> Action? {
        if mode == .off { return .allow }
        let appAction = action(for: app)
        if appAction == .block { return .block }
        if let host {
            if let action = hostAction(for: app, host: host) { return action }
            if isListed(host, .allow, domains) { return .allow }
            if isListed(host, .block, domains) { return .block }
        }
        if appAction == .allow { return .allow }
        if isApple { return .allow }
        return mode == .ask ? nil : .allow
    }

    /// The app's rule for exactly this host. A nil host means the app rule.
    func action(for app: String, host: String? = nil) -> Action? {
        rules.first { $0.app == app && $0.host == host }?.action
    }

    /// Replaces the app's rule for this host.
    mutating func setAction(_ action: Action, for app: String, host: String? = nil) {
        rules.removeAll { $0.app == app && $0.host == host }
        rules.append(Rule(app: app, host: host, action: action))
    }

    /// Checks the host, then each parent domain, so the most specific rule wins.
    private func hostAction(for app: String, host: String) -> Action? {
        var domain = Substring(host)
        while true {
            if let action = action(for: app, host: String(domain)) { return action }
            guard let dot = domain.firstIndex(of: ".") else { return nil }
            domain = domain[domain.index(after: dot)...]
        }
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
    }
}

enum Mode: String, Codable {
    case off, ask, quiet
}

enum Action: String, Codable {
    case allow, block
}

struct Rule: Codable, Equatable, Identifiable {
    var id = UUID()
    var app: String
    /// Nil: the rule covers the whole app. Else this domain and its subdomains.
    var host: String?
    var action: Action
}

import Foundation

/// Everything the user sets. Stored as `config.json` by the extension.
struct Config: Codable, Equatable {
    var mode = Mode.quiet
    var rules: [Rule] = []

    /// Decides one flow. Nil means: ask the user.
    func verdict(app: String, host: String?, isApple: Bool) -> Action? {
        if mode == .off { return .allow }
        let appAction = action(for: app)
        if appAction == .block { return .block }
        if let host, let action = hostAction(for: app, host: host) { return action }
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

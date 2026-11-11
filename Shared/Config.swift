import Foundation

/// Everything the user sets. Stored as `config.json` by the extension.
struct Config: Codable, Equatable {
    var mode = Mode.quiet
    var rules: [Rule] = []

    /// Decides one flow. Nil means: ask the user.
    func verdict(app: String, isApple: Bool) -> Action? {
        if mode == .off { return .allow }
        if let action = action(for: app) { return action }
        if isApple { return .allow }
        return mode == .ask ? nil : .allow
    }

    func action(for app: String) -> Action? {
        rules.first { $0.app == app }?.action
    }

    /// Replaces the app's rule.
    mutating func setAction(_ action: Action, for app: String) {
        rules.removeAll { $0.app == app }
        rules.append(Rule(app: app, action: action))
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
    var action: Action
}

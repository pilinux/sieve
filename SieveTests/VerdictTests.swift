import Foundation
import Testing

struct VerdictTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"

    @Test func offAllowsEvenBlockedApps() {
        let config = Config(mode: .off, rules: [Rule(app: app, action: .block)])
        #expect(config.verdict(app: app, host: nil, isApple: false) == .allow)
    }

    @Test func blockRuleDrops() {
        let config = Config(rules: [Rule(app: app, action: .block)])
        #expect(config.verdict(app: app, host: nil, isApple: false) == .block)
    }

    @Test func blockRuleBeatsApple() {
        let config = Config(mode: .ask, rules: [Rule(app: "com.apple.Safari", action: .block)])
        #expect(config.verdict(app: "com.apple.Safari", host: nil, isApple: true) == .block)
    }

    @Test func allowRuleAllows() {
        let config = Config(mode: .ask, rules: [Rule(app: app, action: .allow)])
        #expect(config.verdict(app: app, host: nil, isApple: false) == .allow)
    }

    @Test func askAllowsAppleWithoutAsking() {
        let config = Config(mode: .ask)
        #expect(config.verdict(app: "com.apple.Safari", host: nil, isApple: true) == .allow)
    }

    @Test func askAsksForUnknownApp() {
        let config = Config(mode: .ask)
        #expect(config.verdict(app: app, host: nil, isApple: false) == nil)
    }

    @Test func quietAllowsUnknownApp() {
        let config = Config(rules: [Rule(app: "other", action: .block)])
        #expect(config.verdict(app: app, host: nil, isApple: false) == .allow)
    }

    @Test func setActionReplacesTheAppsRule() {
        var config = Config()
        config.setAction(.block, for: app)
        config.setAction(.allow, for: app)
        #expect(config.rules.count == 1)
        #expect(config.action(for: app) == .allow)
    }

    @Test func configSurvivesJSON() throws {
        let config = Config(rules: [Rule(app: app, host: "example.com", action: .block)])
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }

    @Test func hostRuleMatchesSubdomains() {
        let config = Config(rules: [Rule(app: app, host: "example.com", action: .block)])
        #expect(config.verdict(app: app, host: "example.com", isApple: false) == .block)
        #expect(config.verdict(app: app, host: "a.b.example.com", isApple: false) == .block)
        #expect(config.verdict(app: app, host: "notexample.com", isApple: false) == .allow)
        #expect(config.verdict(app: app, host: "example.com.evil.net", isApple: false) == .allow)
    }

    @Test func hostRuleIsPerApp() {
        let config = Config(rules: [Rule(app: "other", host: "example.com", action: .block)])
        #expect(config.verdict(app: app, host: "example.com", isApple: false) == .allow)
    }

    @Test func mostSpecificHostRuleWins() {
        let config = Config(rules: [
            Rule(app: app, host: "example.com", action: .block),
            Rule(app: app, host: "api.example.com", action: .allow),
        ])
        #expect(config.verdict(app: app, host: "v1.api.example.com", isApple: false) == .allow)
        #expect(config.verdict(app: app, host: "www.example.com", isApple: false) == .block)
    }

    @Test func hostBlockBeatsAppAllowAndApple() {
        let config = Config(rules: [
            Rule(app: app, action: .allow),
            Rule(app: app, host: "example.com", action: .block),
        ])
        #expect(config.verdict(app: app, host: "example.com", isApple: true) == .block)
    }

    @Test func appBlockBeatsHostAllow() {
        let config = Config(rules: [
            Rule(app: app, action: .block),
            Rule(app: app, host: "example.com", action: .allow),
        ])
        #expect(config.verdict(app: app, host: "example.com", isApple: false) == .block)
    }

    @Test func hostAllowSkipsTheAsk() {
        let config = Config(mode: .ask, rules: [Rule(app: app, host: "example.com", action: .allow)])
        #expect(config.verdict(app: app, host: "example.com", isApple: false) == .allow)
        #expect(config.verdict(app: app, host: "other.com", isApple: false) == nil)
    }

    @Test func undecidedSkipsAppleAndAppsWithRules() {
        let stats = Stats(apps: [app: [], "com.apple.Safari": [], "decided": [], "host-only": []], apple: ["com.apple.Safari"])
        let config = Config(rules: [
            Rule(app: "decided", action: .block),
            Rule(app: "host-only", host: "example.com", action: .block),
        ])
        #expect(stats.undecided(config) == [app, "host-only"])
    }

    @Test func setActionKeepsAppAndHostRulesApart() {
        var config = Config()
        config.setAction(.allow, for: app)
        config.setAction(.block, for: app, host: "example.com")
        #expect(config.rules.count == 2)
        #expect(config.action(for: app) == .allow)
        #expect(config.action(for: app, host: "example.com") == .block)
    }
}

import Foundation
import Testing

struct VerdictTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"

    @Test func offAllowsEvenBlockedApps() {
        let config = Config(mode: .off, rules: [Rule(app: app, action: .block)])
        #expect(config.verdict(app: app, isApple: false) == .allow)
    }

    @Test func blockRuleDrops() {
        let config = Config(rules: [Rule(app: app, action: .block)])
        #expect(config.verdict(app: app, isApple: false) == .block)
    }

    @Test func blockRuleBeatsApple() {
        let config = Config(mode: .ask, rules: [Rule(app: "com.apple.Safari", action: .block)])
        #expect(config.verdict(app: "com.apple.Safari", isApple: true) == .block)
    }

    @Test func allowRuleAllows() {
        let config = Config(mode: .ask, rules: [Rule(app: app, action: .allow)])
        #expect(config.verdict(app: app, isApple: false) == .allow)
    }

    @Test func askAllowsAppleWithoutAsking() {
        let config = Config(mode: .ask)
        #expect(config.verdict(app: "com.apple.Safari", isApple: true) == .allow)
    }

    @Test func askAsksForUnknownApp() {
        let config = Config(mode: .ask)
        #expect(config.verdict(app: app, isApple: false) == nil)
    }

    @Test func quietAllowsUnknownApp() {
        let config = Config(rules: [Rule(app: "other", action: .block)])
        #expect(config.verdict(app: app, isApple: false) == .allow)
    }

    @Test func setActionReplacesTheAppsRule() {
        var config = Config()
        config.setAction(.block, for: app)
        config.setAction(.allow, for: app)
        #expect(config.rules.count == 1)
        #expect(config.action(for: app) == .allow)
    }

    @Test func configSurvivesJSON() throws {
        let config = Config(rules: [Rule(app: app, action: .block)])
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }
}

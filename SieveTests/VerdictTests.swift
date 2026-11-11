import Foundation
import Testing

struct VerdictTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"

    @Test func offAllowsEvenBlockedApps() {
        let config = Config(mode: .off, rules: [Rule(app: app, action: .block)])
        #expect(config.verdict(app: app) == .allow)
    }

    @Test func blockRuleDrops() {
        let config = Config(rules: [Rule(app: app, action: .block)])
        #expect(config.verdict(app: app) == .block)
    }

    @Test func allowRuleAllows() {
        let config = Config(rules: [Rule(app: app, action: .allow)])
        #expect(config.verdict(app: app) == .allow)
    }

    @Test func unknownAppIsAllowed() {
        let config = Config(rules: [Rule(app: "other", action: .block)])
        #expect(config.verdict(app: app) == .allow)
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

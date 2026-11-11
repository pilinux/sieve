import Testing

struct FlagTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"
    let blockList = DomainList(id: "b", name: "B", url: "https://b.example", action: .block)

    @Test func goneAppIsFlagged() {
        let rule = Rule(app: app, action: .allow)
        #expect(Config(rules: [rule]).flag(rule, gone: [app], domains: [:]) == .appGone)
    }

    @Test func neededRuleIsNotFlagged() {
        let rule = Rule(app: app, host: "example.com", action: .block)
        #expect(Config(rules: [rule]).flag(rule, gone: [], domains: [:]) == nil)
    }

    @Test func hostRuleUnderAppBlockIsFlagged() {
        let rule = Rule(app: app, host: "example.com", action: .allow)
        let config = Config(rules: [Rule(app: app, action: .block), rule])
        #expect(config.flag(rule, gone: [], domains: [:]) == .appBlocked)
    }

    @Test func blockRuleOnBlockListIsFlagged() {
        let rule = Rule(app: app, host: "ads.example.com", action: .block)
        let config = Config(rules: [rule], lists: [blockList])
        #expect(config.flag(rule, gone: [], domains: ["b": ["ads.example.com"]]) == .blockList)
    }

    @Test func parentRuleWithSameActionFlags() {
        let rule = Rule(app: app, host: "api.example.com", action: .block)
        let config = Config(rules: [Rule(app: app, host: "example.com", action: .block), rule])
        #expect(config.flag(rule, gone: [], domains: [:]) == .parentRule)
    }

    @Test func exceptionToParentRuleIsNotFlagged() {
        let rule = Rule(app: app, host: "api.example.com", action: .allow)
        let config = Config(rules: [Rule(app: app, host: "example.com", action: .block), rule])
        #expect(config.flag(rule, gone: [], domains: [:]) == nil)
    }

    @Test func nearestParentDecides() {
        let rule = Rule(app: app, host: "v1.api.example.com", action: .block)
        let config = Config(rules: [
            Rule(app: app, host: "example.com", action: .block),
            Rule(app: app, host: "api.example.com", action: .allow),
            rule,
        ])
        #expect(config.flag(rule, gone: [], domains: [:]) == nil)
    }

    @Test func decideNamesTheRule() {
        let rule = Rule(app: app, host: "example.com", action: .block)
        let config = Config(rules: [Rule(app: app, action: .allow), rule])
        #expect(config.decide(app: app, host: "www.example.com", isApple: false, domains: [:]).rule == rule)
    }
}

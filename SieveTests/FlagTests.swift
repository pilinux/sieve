import Foundation
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

    @Test func appBlockFlagsOnlyWhereItCounts() {
        let profile = UUID()
        let always = Rule(app: app, host: "example.com", action: .allow)
        let inProfile = Rule(app: app, host: "example.com", action: .allow, profile: profile)
        // Blocked only in the profile, so the Always host rule still applies elsewhere.
        var config = Config(rules: [Rule(app: app, action: .block, profile: profile), always, inProfile])
        #expect(config.flag(always, gone: [], domains: [:]) == nil)
        #expect(config.flag(inProfile, gone: [], domains: [:]) == .appBlocked)
        // Blocked always but allowed in a profile, so the Always host rule applies in that profile.
        config.rules = [Rule(app: app, action: .block), Rule(app: app, action: .allow, profile: profile), always]
        #expect(config.flag(always, gone: [], domains: [:]) == nil)
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

    @Test func parentRuleMustDecideInEveryProfile() {
        let profile = UUID()
        let rule = Rule(app: app, host: "api.example.com", action: .allow)
        let config = Config(
            rules: [
                Rule(app: app, host: "example.com", action: .allow),
                Rule(app: app, host: "example.com", action: .block, profile: profile), rule,
            ],
            profiles: [Profile(id: profile, name: "Work")])
        #expect(config.flag(rule, gone: [], domains: [:]) == nil)
    }

    @Test func profileParentRuleFlags() {
        let profile = UUID()
        let rule = Rule(app: app, host: "api.example.com", action: .block, profile: profile)
        let config = Config(
            rules: [Rule(app: app, host: "example.com", action: .block, profile: profile), rule],
            profiles: [Profile(id: profile, name: "Work")])
        #expect(config.flag(rule, gone: [], domains: [:]) == .parentRule)
    }

    @Test func blockRuleOnAllowListIsNotFlagged() {
        let rule = Rule(app: app, host: "ads.example.com", action: .block)
        let allowList = DomainList(id: "a", name: "A", url: "https://a.example", action: .allow)
        let config = Config(rules: [rule], lists: [blockList, allowList])
        #expect(config.flag(rule, gone: [], domains: ["b": ["ads.example.com"], "a": ["example.com"]]) == nil)
    }
}

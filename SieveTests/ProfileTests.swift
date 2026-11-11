import Foundation
import Testing

struct ProfileTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"
    let hotspot = Profile(name: "Hotspot", network: "IPv4.Router=172.20.10.1")
    // Monday to Friday, 9:00 to 17:00.
    let work = Profile(name: "Work", schedule: Schedule(weekdays: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60))
    let night = Profile(name: "Night", schedule: Schedule(weekdays: [1, 2, 3, 4, 5, 6, 7], start: 22 * 60, end: 7 * 60))

    @Test func networkActivatesProfile() {
        let config = Config(profiles: [work, hotspot])
        #expect(config.activeProfile(networks: ["IPv4.Router=172.20.10.1"], weekday: 1, minute: 0) == hotspot.id)
        #expect(config.activeProfile(networks: ["IPv4.Router=10.1.0.1"], weekday: 1, minute: 0) == nil)
    }

    @Test func scheduleActivatesProfile() {
        let config = Config(profiles: [work])
        #expect(config.activeProfile(networks: [], weekday: 2, minute: 9 * 60) == work.id)
        #expect(config.activeProfile(networks: [], weekday: 2, minute: 17 * 60) == nil)
        #expect(config.activeProfile(networks: [], weekday: 1, minute: 12 * 60) == nil)
    }

    @Test func scheduleRunsPastMidnight() {
        let config = Config(profiles: [night])
        #expect(config.activeProfile(networks: [], weekday: 3, minute: 23 * 60) == night.id)
        #expect(config.activeProfile(networks: [], weekday: 3, minute: 6 * 60) == night.id)
        #expect(config.activeProfile(networks: [], weekday: 3, minute: 12 * 60) == nil)
    }

    @Test func firstMatchingProfileWins() {
        let config = Config(profiles: [work, hotspot])
        #expect(config.activeProfile(networks: ["IPv4.Router=172.20.10.1"], weekday: 2, minute: 10 * 60) == work.id)
    }

    @Test func profileRuleCountsOnlyWhileActive() {
        let config = Config(rules: [Rule(app: app, action: .block, profile: hotspot.id)], profiles: [hotspot])
        #expect(config.verdict(app: app, host: nil, isApple: false, profile: hotspot.id) == .block)
        #expect(config.verdict(app: app, host: nil, isApple: false) == .allow)
        #expect(config.verdict(app: app, host: nil, isApple: false, profile: work.id) == .allow)
    }

    @Test func activeProfileRuleBeatsRuleWithoutProfile() {
        let config = Config(rules: [
            Rule(app: app, host: "example.com", action: .allow),
            Rule(app: app, host: "example.com", action: .block, profile: hotspot.id),
        ])
        #expect(config.verdict(app: app, host: "example.com", isApple: false, profile: hotspot.id) == .block)
        #expect(config.verdict(app: app, host: "example.com", isApple: false) == .allow)
    }

    @Test func setActionKeepsProfileRules() {
        var config = Config(rules: [Rule(app: app, action: .block, profile: hotspot.id)])
        config.setAction(.allow, for: app)
        #expect(config.rules.count == 2)
    }
}

import Foundation
import Testing

struct ProfileTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"
    let hotspot = Profile(name: "Hotspot", network: "IPv4.Router=172.20.10.1")
    // Monday to Friday, 9:00 to 17:00.
    let work = Profile(name: "Work", schedules: [Schedule(weekdays: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60)])

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

    @Test func blockStaysInOneDay() {
        // Monday 22:00 to 23:59.
        let late = Profile(name: "Late", schedules: [Schedule(weekdays: [2], start: 22 * 60, end: 23 * 60 + 59)])
        let config = Config(profiles: [late])
        #expect(config.activeProfile(networks: [], weekday: 2, minute: 23 * 60) == late.id)
        #expect(config.activeProfile(networks: [], weekday: 2, minute: 6 * 60) == nil)
        #expect(config.activeProfile(networks: [], weekday: 3, minute: 0) == nil)
    }

    @Test func blockEndingAt24CoversTheLastMinute() {
        let night = Schedule(weekdays: [2], start: 22 * 60, end: 24 * 60)
        #expect(night.covers(weekday: 2, minute: 23 * 60 + 59))
        #expect(!night.covers(weekday: 3, minute: 0))
    }

    @Test func anyBlockActivatesProfile() {
        // Weekdays 9:00 to 17:00, and Saturday 10:00 to 14:00.
        var work = work
        work.schedules.append(Schedule(weekdays: [7], start: 10 * 60, end: 14 * 60))
        let config = Config(profiles: [work])
        #expect(config.activeProfile(networks: [], weekday: 7, minute: 11 * 60) == work.id)
        #expect(config.activeProfile(networks: [], weekday: 7, minute: 15 * 60) == nil)
        #expect(config.activeProfile(networks: [], weekday: 2, minute: 15 * 60) == work.id)
    }

    @Test func profileWithoutBlocksNeedsItsNetwork() {
        let config = Config(profiles: [Profile(name: "Empty")])
        #expect(config.activeProfile(networks: [], weekday: 2, minute: 10 * 60) == nil)
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

    // The first match wins, so moving the hotspot up makes it active on its network during work hours.
    @Test func moveProfileChangesTheOrderAndKeepsColours() {
        let home = Profile(name: "Home", color: "#4fb3c9")
        let night = Profile(name: "Night")
        let travel = Profile(name: "Travel")
        var config = Config(profiles: [work, hotspot, home, night, travel])
        config.moveProfile(travel.id, to: work.id)
        #expect(config.profiles.map(\.name) == ["Travel", "Work", "Hotspot", "Home", "Night"])
        #expect(config.profiles.map(\.color) == ["#8a8983", "#199e70", "#c98500", "#4fb3c9", "#9085e9"])
        config.moveProfile(travel.id, to: night.id)
        #expect(config.profiles.map(\.name) == ["Work", "Hotspot", "Home", "Night", "Travel"])
        #expect(config.activeProfile(networks: ["IPv4.Router=172.20.10.1"], weekday: 2, minute: 600) == work.id)
        config.moveProfile(hotspot.id, to: work.id)
        #expect(config.activeProfile(networks: ["IPv4.Router=172.20.10.1"], weekday: 2, minute: 600) == hotspot.id)
    }
}

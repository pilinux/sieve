import Foundation
import Testing

struct TrafficTests {
    @Test func countBytesSplitsDownAndUp() {
        var stats = Stats()
        stats.countBytes("app", down: 70, up: 30, day: "2026-11-23")
        stats.countBytes("app", down: 5, up: 0, day: "2026-11-24")
        #expect(stats.bytes["app"] == 105)
        #expect(stats.daily["2026-11-24"]?["app"] == 5)
        #expect(stats.dailyTraffic?["2026-11-23"]?["app"] == Transfer(down: 70, up: 30))
        #expect(stats.traffic?["app"] == Transfer(down: 75, up: 30))
        #expect(stats.since?["app"] == "2026-11-23")
    }

    @Test func bytesOfAnOlderBuildStayUnsplit() {
        var stats = Stats(bytes: ["app": 500], daily: ["2026-11-24": ["app": 500]])
        stats.countBytes("app", down: 60, up: 40, day: "2026-11-24")
        #expect(stats.daily["2026-11-24"]?["app"] == 600)
        #expect(stats.totalTraffic(day: "2026-11-24") == Transfer(down: 60, up: 40))
    }

    @Test func startSinceCountsAnOlderAppFromThatDay() {
        var stats = Stats(bytes: ["old": 900, "idle": 50], daily: ["2026-11-24": ["old": 200]], since: ["new": "2026-11-20"])
        stats.bytes["new"] = 30
        stats.startSince(day: "2026-11-24")
        #expect(stats.bytes == ["old": 200, "idle": 0, "new": 30])
        #expect(stats.since == ["old": "2026-11-24", "idle": "2026-11-24", "new": "2026-11-20"])
        #expect(stats.totalSince == "2026-11-20")
    }

    // The browser's bytes run through the VPN, which carries them again.
    @Test func totalsLeaveOutVPNApps() {
        var stats = Stats(vpns: ["vpn"])
        stats.countBytes("browser", down: 80, up: 20, day: "2026-11-24")
        stats.countBytes("vpn", down: 90, up: 30, day: "2026-11-23")
        #expect(stats.totalTraffic == Transfer(down: 80, up: 20))
        #expect(stats.totalTraffic(day: "2026-11-24") == Transfer(down: 80, up: 20))
        #expect(stats.totalTraffic(day: "2026-11-23") == Transfer())
        #expect(stats.totalSince == "2026-11-24")
    }

    @Test func totalSinceNeedsADayForEveryCountedApp() {
        var stats = Stats(bytes: ["old": 10])
        stats.countBytes("new", down: 1, up: 1, day: "2026-11-24")
        #expect(stats.totalSince == nil)
        stats.forget("old", rules: [], entirely: true)
        #expect(stats.totalSince == "2026-11-24")
    }

    @Test func pruneDropsOldDaysAndDroppedApps() {
        var stats = Stats()
        stats.countBytes("gone", down: 1, up: 1, day: "2026-10-01")
        stats.countBytes("kept", down: 1, up: 1, day: "2026-11-24")
        _ = stats.see("gone", host: nil, day: "2026-10-01")
        _ = stats.see("kept", host: nil, day: "2026-11-24")
        stats.prune(Config(), cutoff: "2026-10-24")
        #expect(stats.dailyTraffic?.keys.sorted() == ["2026-11-24"])
        #expect(stats.traffic?.keys.sorted() == ["kept"])
        #expect(stats.since?.keys.sorted() == ["kept"])
    }

    @Test func forgetStartsTheCountAgain() {
        var stats = Stats()
        stats.countBytes("app", down: 1, up: 1, day: "2026-11-20")
        stats.forget("app", rules: [])
        #expect(stats.traffic?["app"] == nil)
        #expect(stats.dailyTraffic?["2026-11-20"]?["app"] == nil)
        stats.countBytes("app", down: 1, up: 1, day: "2026-11-24")
        #expect(stats.since?["app"] == "2026-11-24")
    }

    // The VPN carries the browser's bytes again, so only the browser's count for the profile.
    @Test func countBytesAddsToTheActiveProfileButNotForVPNApps() {
        let work = UUID()
        var stats = Stats(vpns: ["vpn"])
        stats.countBytes("browser", down: 80, up: 20, day: "2026-11-23", profile: work)
        stats.countBytes("browser", down: 10, up: 5, day: "2026-11-24", profile: work)
        stats.countBytes("vpn", down: 90, up: 30, day: "2026-11-24", profile: work)
        stats.countBytes("browser", down: 7, up: 3, day: "2026-11-24")
        #expect(stats.profileTraffic == [work: Transfer(down: 90, up: 25)])
        #expect(stats.profileDaily?["2026-11-24"] == [work: Transfer(down: 10, up: 5)])
        #expect(stats.profileSince == [work: "2026-11-23"])
    }

    @Test func pruneDropsOldProfileDaysAndDeletedProfiles() {
        let kept = Profile(name: "Work")
        let deleted = UUID()
        var stats = Stats()
        stats.countBytes("app", down: 1, up: 1, day: "2026-10-01", profile: kept.id)
        stats.countBytes("app", down: 2, up: 2, day: "2026-11-24", profile: kept.id)
        stats.countBytes("app", down: 3, up: 3, day: "2026-11-24", profile: deleted)
        stats.prune(Config(profiles: [kept]), cutoff: "2026-10-24")
        #expect(stats.profileDaily == ["2026-11-24": [kept.id: Transfer(down: 2, up: 2)]])
        #expect(stats.profileTraffic == [kept.id: Transfer(down: 3, up: 3)])
        #expect(stats.profileSince == [kept.id: "2026-10-01"])
    }
}

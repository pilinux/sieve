import Foundation
import Testing

struct BlockedTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"
    let day = "2026-11-15"

    @Test func blockedSplitsIntoListsAndRules() {
        var stats = Stats()
        stats.countBlocked(day: day, byList: false)
        stats.countBlocked(day: day, byList: true)
        stats.countBlocked(day: day, byList: true)
        #expect(stats.blocked[day] == 3)
        #expect(stats.blockedSplit(day)! == (2, 1))
    }

    @Test func dayOnlyRulesBlockedStillSplits() {
        var stats = Stats()
        stats.countBlocked(day: day, byList: false)
        #expect(stats.blockedSplit(day)! == (0, 1))
    }

    @Test func dayCountedBeforeTheSplitStaysUnsplit() {
        var stats = Stats(blocked: [day: 4, "2026-11-14": 7])
        stats.countBlocked(day: day, byList: true)
        #expect(stats.blocked[day] == 5)
        #expect(stats.blockedSplit(day) == nil)
        #expect(stats.blockedSplit("2026-11-14") == nil)
        stats.countBlocked(day: "2026-11-16", byList: true)
        #expect(stats.blockedSplit("2026-11-16")! == (1, 0))
    }

    @Test func trackerCallsAddUpByAppAndHost() {
        var stats = Stats()
        stats.countTrackerFlow(app, host: "ads.example.com")
        stats.countTrackerFlow(app, host: "ads.example.com")
        stats.countTrackerFlow(app, host: "pixel.example.net")
        stats.countTrackerFlow("other", host: "ads.example.com")
        #expect(stats.trackerCalls(app) == 3)
        #expect(stats.trackerCalls(host: "ads.example.com") == 3)
        #expect(stats.trackerCalls("none") == 0)
    }

    @Test func pruneAndForgetDropSplitAndTrackerFlows() {
        var stats = Stats(
            apps: [app: ["ads.example.com": day, "old.example.com": "2026-10-01"]], seen: [app: day],
            blocked: ["2026-10-01": 2, day: 1], blockedByList: ["2026-10-01": 1, day: 1],
            trackerFlows: [app: ["ads.example.com": 4, "old.example.com": 9]]
        )
        stats.prune(Config(), cutoff: "2026-10-12")
        #expect(stats.blockedByList == [day: 1])
        #expect(stats.trackerFlows == [app: ["ads.example.com": 4]])
        stats.forget(app, rules: [])
        #expect(stats.trackerFlows == [:])
    }
}

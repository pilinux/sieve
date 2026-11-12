import Foundation
import Testing

struct PruneTests {
    let rule = Rule(app: "ruled", action: .allow)
    let deleted = Rule(app: "ruled", host: "gone.example", action: .block)
    let cutoff = "2026-10-12"
    let old = "2026-10-12"
    let new = "2026-10-13"

    var stats: Stats {
        Stats(
            apps: [
                "ruled": ["old.example": old, "new.example": new],
                "limited": ["old.example": old],
                "idle": ["idle.example": old],
                "active": ["new.example": new],
            ],
            seen: ["ruled": old, "limited": old, "idle": old, "active": new],
            bytes: ["ruled": 1, "limited": 2, "idle": 3, "active": 4],
            blocked: [old: 5, new: 6],
            apple: ["idle"],
            paths: ["idle": "/Applications/Idle.app", "active": "/Applications/Active.app"],
            hits: [rule.id: Hit(), deleted.id: Hit()],
            trackers: ["old.example", "idle.example", "new.example"],
            daily: [old: ["idle": 3], new: ["active": 4]]
        )
    }

    var config: Config {
        Config(rules: [rule], limits: [Limit(app: "limited", bytes: 1, period: .day)])
    }

    @Test func pruneDropsOldHostsAndDays() {
        var stats = stats
        stats.prune(config, cutoff: cutoff)
        #expect(stats.apps["ruled"] == ["new.example": new])
        #expect(stats.blocked == [new: 6])
        #expect(stats.daily == [new: ["active": 4]])
        #expect(stats.trackers == ["new.example"])
    }

    @Test func pruneDropsIdleAppsWithoutRuleOrLimit() {
        var stats = stats
        stats.prune(config, cutoff: cutoff)
        #expect(Set(stats.apps.keys) == ["ruled", "limited", "active"])
        #expect(stats.apps["limited"] == [:])
        #expect(stats.seen["idle"] == nil)
        #expect(stats.bytes == ["ruled": 1, "limited": 2, "active": 4])
        #expect(stats.paths == ["active": "/Applications/Active.app"])
        #expect(stats.apple.isEmpty)
    }

    @Test func pruneDropsHitsOfDeletedRules() {
        var stats = stats
        stats.prune(config, cutoff: cutoff)
        #expect(Set(stats.hits.keys) == [rule.id])
    }

    @Test func seeAddsAppWithoutHost() {
        var stats = Stats()
        let first = stats.see("app", host: nil, day: new)
        let again = stats.see("app", host: nil, day: new)
        #expect(first && !again)
        #expect(stats.apps == ["app": [:]])
        #expect(stats.seen == ["app": new])
    }

    @Test func seeKeepsTheNewestHostsAtTheCap() {
        var stats = Stats()
        for index in 0..<Stats.maxHosts {
            _ = stats.see("app", host: "h\(index).example", day: index == 7 ? old : new)
        }
        _ = stats.see("app", host: "next.example", day: new)
        #expect(stats.apps["app"]?.count == Stats.maxHosts)
        #expect(stats.apps["app"]?["h7.example"] == nil)
        #expect(stats.apps["app"]?["next.example"] == new)
        // A known host only moves its day.
        _ = stats.see("app", host: "h8.example", day: "2026-10-14")
        #expect(stats.apps["app"]?.count == Stats.maxHosts)
    }
}

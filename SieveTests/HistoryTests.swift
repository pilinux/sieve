import Foundation
import Testing

struct HistoryTests {
    let rule = Rule(app: "app", host: "ads.example.com", action: .block)
    let other = Rule(app: "other", action: .allow)

    var stats: Stats {
        Stats(
            apps: ["app": ["ads.example.com": "2026-11-12", "shared.example": "2026-11-12"], "other": ["shared.example": "2026-11-12"]],
            bytes: ["app": 100, "other": 50],
            paths: ["app": "/Applications/App.app"],
            hits: [rule.id: Hit(), other.id: Hit()],
            trackers: ["ads.example.com", "shared.example"],
            daily: ["2026-11-11": ["app": 60, "other": 20], "2026-11-12": ["app": 40, "other": 30]]
        )
    }

    @Test func forgetClearsOnlyTheAppsHistory() {
        var stats = stats
        stats.forget("app", rules: [rule.id])
        #expect(stats.apps == ["app": [:], "other": ["shared.example": "2026-11-12"]])
        #expect(stats.bytes == ["other": 50])
        #expect(stats.daily == ["2026-11-11": ["other": 20], "2026-11-12": ["other": 30]])
        #expect(Set(stats.hits.keys) == [other.id])
        #expect(stats.paths == ["app": "/Applications/App.app"])
        #expect(stats.trackers == ["shared.example"])
    }
}

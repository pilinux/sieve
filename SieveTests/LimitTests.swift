import Testing

struct LimitTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"
    let daily = [
        "2026-10-31": ["EQHXZ8M8AV.com.google.Chrome": 500],
        "2026-11-01": ["EQHXZ8M8AV.com.google.Chrome": 300],
        "2026-11-11": ["EQHXZ8M8AV.com.google.Chrome": 200, "other": 900],
    ]

    @Test func noLimitIsNeverOver() {
        #expect(!Config().isOverLimit(app, daily: daily, today: "2026-11-11"))
    }

    @Test func dayLimitCountsTodayOnly() {
        let config = Config(limits: [Limit(app: app, bytes: 200, period: .day)])
        #expect(config.isOverLimit(app, daily: daily, today: "2026-11-11"))
        #expect(!config.isOverLimit(app, daily: daily, today: "2026-11-12"))
    }

    @Test func monthLimitCountsThisMonthOnly() {
        // November: 300 + 200. October's 500 does not count.
        #expect(
            Config(limits: [Limit(app: app, bytes: 500, period: .month)])
                .isOverLimit(app, daily: daily, today: "2026-11-11"))
        #expect(
            !Config(limits: [Limit(app: app, bytes: 501, period: .month)])
                .isOverLimit(app, daily: daily, today: "2026-11-11"))
    }

    @Test func overLimitBeatsAllowRules() {
        let config = Config(rules: [
            Rule(app: app, action: .allow),
            Rule(app: app, host: "example.com", action: .allow),
        ])
        #expect(config.verdict(app: app, host: "example.com", isApple: true, overLimit: true) == .block)
    }

    @Test func setLimitReplacesAndRemoves() {
        var config = Config()
        config.setLimit(100, period: .day, for: app)
        config.setLimit(200, period: .month, for: app)
        #expect(config.limits == [Limit(app: app, bytes: 200, period: .month)])
        config.setLimit(nil, period: .month, for: app)
        #expect(config.limits.isEmpty)
    }
}

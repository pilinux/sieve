import Testing

struct GradeTests {
    @Test(arguments: [(0, "A"), (1, "B"), (2, "B"), (3, "C"), (5, "C"), (6, "D"), (10, "D"), (11, "F")])
    func gradeFromTrackerCount(count: Int, grade: String) {
        #expect(Stats.grade(trackers: count) == grade)
    }

    @Test func gradeCountsOnlyTheAppsTrackers() {
        let stats = Stats(
            apps: ["app": ["ads.example.com", "example.com"], "other": ["t1.example", "t2.example", "t3.example"]],
            trackers: ["ads.example.com", "t1.example", "t2.example", "t3.example"]
        )
        #expect(stats.grade("app") == "B")
    }

    @Test func disabledBlockListStillMarksTrackers() {
        var list = DomainList.trackerShield
        list.enabled = false
        let config = Config(lists: [list])
        #expect(config.isTracker("ads.example.com", domains: [list.id: ["ads.example.com"]]))
        #expect(!config.isTracker("example.com", domains: [list.id: ["ads.example.com"]]))
    }
}

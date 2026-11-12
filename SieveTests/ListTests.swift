import Foundation
import Testing

struct ListTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"
    let blocked = DomainList(id: "b", name: "B", url: "https://b.example", action: .block)
    let allowed = DomainList(id: "a", name: "A", url: "https://a.example", action: .allow)

    @Test func parsesPlainAndHostsFileLines() {
        let text = """
            # comment
            ads.example.com
            0.0.0.0 Tracker.example.net # inline comment
            127.0.0.1 localhost
            0.0.0.0 one.example two.example

            """
        #expect(DomainList.parse(text) == ["ads.example.com", "tracker.example.net", "one.example", "two.example"])
    }

    @Test func blockListDrops() {
        let config = Config(lists: [blocked])
        let domains = ["b": Set(["ads.example.com"])]
        #expect(config.verdict(app: app, host: "ads.example.com", isApple: true, domains: domains) == .block)
    }

    @Test func listEntryCoversSubdomains() {
        let config = Config(lists: [blocked])
        let domains = ["b": Set(["example.com"])]
        #expect(config.verdict(app: app, host: "www.example.com", isApple: false, domains: domains) == .block)
        #expect(config.verdict(app: app, host: "a.b.example.com", isApple: false, domains: domains) == .block)
        #expect(config.verdict(app: app, host: "notexample.com", isApple: false, domains: domains) == .allow)
    }

    @Test func subdomainEntryLeavesParentAlone() {
        let config = Config(lists: [blocked])
        let domains = ["b": Set(["ads.example.com"])]
        #expect(config.verdict(app: app, host: "example.com", isApple: false, domains: domains) == .allow)
        #expect(config.verdict(app: app, host: "www.example.com", isApple: false, domains: domains) == .allow)
        #expect(config.verdict(app: app, host: "x.ads.example.com", isApple: false, domains: domains) == .block)
    }

    @Test func allowListCoversSubdomains() {
        let config = Config(lists: [blocked, allowed])
        let domains = ["a": Set(["example.com"]), "b": Set(["ads.example.com"])]
        #expect(config.verdict(app: app, host: "ads.example.com", isApple: false, domains: domains) == .allow)
    }

    @Test func disabledListIsIgnored() {
        var list = blocked
        list.enabled = false
        let config = Config(lists: [list])
        let domains = ["b": Set(["ads.example.com"])]
        #expect(config.verdict(app: app, host: "ads.example.com", isApple: false, domains: domains) == .allow)
    }

    @Test func allowListBeatsBlockList() {
        let config = Config(lists: [blocked, allowed])
        let domains = ["a": Set(["ads.example.com"]), "b": Set(["ads.example.com"])]
        #expect(config.verdict(app: app, host: "ads.example.com", isApple: false, domains: domains) == .allow)
    }

    @Test func hostRuleBeatsList() {
        let config = Config(rules: [Rule(app: app, host: "ads.example.com", action: .allow)], lists: [blocked])
        let domains = ["b": Set(["ads.example.com"])]
        #expect(config.verdict(app: app, host: "ads.example.com", isApple: false, domains: domains) == .allow)
    }

    @Test func oldConfigGetsTrackerShield() throws {
        let data = Data(#"{"mode":"ask","rules":[]}"#.utf8)
        let config = try JSONDecoder().decode(Config.self, from: data)
        #expect(config.mode == .ask)
        #expect(config.lists == [.trackerShield])
    }
}

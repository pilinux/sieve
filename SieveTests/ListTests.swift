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

    @Test func normalizesEntriesAndSkipsAdblockLines() {
        let text = """
            Trailing.Example.com.
            ||adblock.example.com^
            *.wild.example.com
            example.
            under_score.example.com

            """
        #expect(DomainList.parse(text) == ["trailing.example.com", "under_score.example.com"])
    }

    @Test func skipsIPAddresses() {
        #expect(DomainList.parse("1.2.3.4\n0.0.0.0 5.6.7.8 ads.example.com\n") == ["ads.example.com"])
    }

    @Test(arguments: [("Ads.Example.COM", "ads.example.com"), ("ads.example.com.", "ads.example.com"), (".", nil)])
    func normalizesHost(host: String, normalized: String?) {
        #expect(DomainList.normalize(host) == normalized)
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

    @Test func blockedDomainsCountEachHostOnceAndSkipAllowed() {
        var off = blocked
        off.id = "off"
        off.enabled = false
        var allowOff = allowed
        allowOff.id = "allow-off"
        allowOff.enabled = false
        let second = DomainList(id: "c", name: "C", url: "https://c.example", action: .block)
        let config = Config(lists: [blocked, second, off, allowed, allowOff])
        let domains = [
            "b": Set(["ads.example.com", "x.example.com"]),
            "c": Set(["ads.example.com", "y.example.com", "t.cdn.example"]),
            "off": Set(["z.example.com"]),
            // An exact entry and a parent domain each take a host out. A disabled allow list takes none.
            "a": Set(["x.example.com", "cdn.example"]),
            "allow-off": Set(["y.example.com"]),
        ]
        #expect(config.blockedDomainCount(domains) == 2)
    }

    @Test func newConfigIsQuietWithTrackerShieldOn() {
        let config = Config()
        #expect(config.mode == .quiet)
        #expect(config.lists == [.trackerShield])
        #expect(DomainList.trackerShield.enabled)
    }

    @Test func hostRuleBeatsList() {
        let config = Config(rules: [Rule(app: app, host: "ads.example.com", action: .allow)], lists: [blocked])
        let domains = ["b": Set(["ads.example.com"])]
        #expect(config.verdict(app: app, host: "ads.example.com", isApple: false, domains: domains) == .allow)
    }

    @Test func listEntriesNameTheMatchingEntryOfEachList() {
        var off = blocked
        off.id = "off"
        off.enabled = false
        let config = Config(lists: [blocked, allowed, off])
        let domains = ["b": Set(["example.com"]), "a": ["ads.example.com"], "off": ["example.com"]]
        #expect(
            config.listEntries(for: "ads.example.com", domains: domains) == [
                "b": "example.com", "a": "ads.example.com", "off": "example.com",
            ])
        #expect(config.listEntries(for: "cdn.example.com", domains: domains) == ["b": "example.com", "off": "example.com"])
        #expect(config.listEntries(for: "example.org", domains: domains) == [:])
    }
}

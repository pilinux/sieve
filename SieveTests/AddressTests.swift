import Foundation
import Testing

struct AddressTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"
    let day = "2026-11-13"

    @Test func normalizeGivesOneFormPerAddress() {
        #expect(Address.normalize("192.0.2.1") == "192.0.2.1")
        #expect(Address.normalize("2001:DB8:0:0::1") == "2001:db8::1")
        #expect(Address.normalize("fe80::1%en0") == "fe80::1")
        #expect(Address.normalize("::ffff:192.0.2.1") == "192.0.2.1")
        #expect(Address.normalize("example.com") == nil)
        #expect(Address.normalize("") == nil)
    }

    @Test func hostRuleBeatsIPRule() {
        let config = Config(rules: [
            Rule(app: app, host: "example.com", action: .allow),
            Rule(app: app, host: "192.0.2.1", action: .block),
        ])
        #expect(config.verdict(app: app, host: "example.com", address: "192.0.2.1", isApple: false) == .allow)
        #expect(config.verdict(app: app, host: "other.com", address: "192.0.2.1", isApple: false) == .block)
        #expect(config.verdict(app: app, host: nil, address: "192.0.2.1", isApple: false) == .block)
        #expect(config.verdict(app: app, host: nil, address: "192.0.2.2", isApple: false) == .allow)
    }

    @Test func ipRuleBeatsListsAndAppAllow() {
        let domains = ["b": Set(["example.com"])]
        let config = Config(
            rules: [Rule(app: app, action: .allow), Rule(app: app, host: "192.0.2.1", action: .block)],
            lists: [DomainList(id: "b", name: "B", url: "https://b.example", action: .block)]
        )
        #expect(config.verdict(app: app, host: nil, address: "192.0.2.1", isApple: false) == .block)
        let allowed = Config(rules: [Rule(app: app, host: "192.0.2.1", action: .allow)], lists: config.lists)
        #expect(allowed.verdict(app: app, host: "example.com", address: "192.0.2.1", isApple: false, domains: domains) == .allow)
    }

    @Test func appBlockBeatsIPAllow() {
        let config = Config(rules: [Rule(app: app, action: .block), Rule(app: app, host: "192.0.2.1", action: .allow)])
        #expect(config.verdict(app: app, host: nil, address: "192.0.2.1", isApple: false) == .block)
    }

    @Test func ipRuleIsPerApp() {
        let config = Config(mode: .ask, rules: [Rule(app: "other", host: "192.0.2.1", action: .allow)])
        #expect(config.verdict(app: app, host: nil, address: "192.0.2.1", isApple: false) == nil)
    }

    @Test func seeKeepsTheLastHostName() {
        var stats = Stats()
        let first = stats.see(app, host: "example.com", address: "192.0.2.1", day: day)
        let again = stats.see(app, host: nil, address: "192.0.2.1", day: day)
        #expect(first && !again)
        #expect(stats.addresses?[app]?["192.0.2.1"] == Address(day: day, host: "example.com"))
        _ = stats.see(app, host: "cdn.example", address: "192.0.2.1", day: day)
        #expect(stats.addresses?[app]?["192.0.2.1"]?.host == "cdn.example")
        _ = stats.see(app, host: nil, address: "192.0.2.2", day: day)
        #expect(stats.addresses?[app]?["192.0.2.2"] == Address(day: day, host: nil))
    }

    @Test func seeKeepsTheNewestAddressesAtTheCap() {
        var stats = Stats()
        for index in 0..<Stats.maxHosts {
            _ = stats.see(app, host: nil, address: "10.0.\(index / 256).\(index % 256)", day: index == 7 ? "2026-11-12" : day)
        }
        _ = stats.see(app, host: nil, address: "192.0.2.1", day: day)
        #expect(stats.addresses?[app]?.count == Stats.maxHosts)
        #expect(stats.addresses?[app]?["10.0.0.7"] == nil)
        #expect(stats.addresses?[app]?["192.0.2.1"] != nil)
    }

    @Test func pruneAndForgetDropAddresses() {
        var stats = Stats(
            apps: [app: [:], "idle": [:]], seen: [app: day, "idle": "2026-10-01"],
            addresses: [
                app: ["192.0.2.1": Address(day: "2026-10-01"), "192.0.2.2": Address(day: day)],
                "idle": ["192.0.2.3": Address(day: "2026-10-01")],
            ]
        )
        stats.prune(Config(), cutoff: "2026-10-12")
        #expect(stats.addresses == [app: ["192.0.2.2": Address(day: day)]])
        stats.forget(app, rules: [])
        #expect(stats.addresses == [:])
    }
}

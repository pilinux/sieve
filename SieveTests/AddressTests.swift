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

    @Test func countFlowCountsHostsAndAddresses() {
        var stats = Stats()
        let first = Date(timeIntervalSince1970: 1_000)
        let last = Date(timeIntervalSince1970: 2_000)
        _ = stats.see(app, host: "example.com", address: "192.0.2.1", day: day)
        stats.countFlow(app, host: "example.com", address: "192.0.2.1", time: first)
        _ = stats.see(app, host: nil, address: "192.0.2.1", day: "2026-11-14")
        stats.countFlow(app, host: nil, address: "192.0.2.1", time: last)
        #expect(stats.hostHits?[app]?["example.com"] == Hit(count: 1, last: first))
        // A new day for the address keeps its count.
        #expect(stats.addresses?[app]?["192.0.2.1"] == Address(day: "2026-11-14", host: "example.com", hits: Hit(count: 2, last: last)))
    }

    @Test func hostHitsGoWithTheirHost() {
        var stats = Stats()
        for index in 0..<Stats.maxHosts {
            let host = "h\(index).example"
            _ = stats.see(app, host: host, day: index == 7 ? "2026-11-12" : day)
            stats.countFlow(app, host: host, address: nil, time: .now)
        }
        _ = stats.see(app, host: "next.example", day: day)
        #expect(stats.hostHits?[app]?["h7.example"] == nil)
        #expect(stats.hostHits?[app]?.count == Stats.maxHosts - 1)
        stats.apps[app]?["h8.example"] = "2026-10-01"
        stats.prune(Config(), cutoff: "2026-10-12")
        #expect(stats.hostHits?[app]?["h8.example"] == nil)
        stats.forget(app, rules: [])
        #expect(stats.hostHits?[app] == nil)
    }

    @Test func isLocalCoversOnlyLocalRanges() {
        for address in ["10.1.0.1", "172.31.255.255", "192.168.1.1", "100.100.100.100", "169.254.1.1", "fd00::1", "fe80::1"] {
            #expect(Address.isLocal(address), "\(address)")
        }
        for address in ["172.32.0.1", "100.128.0.1", "1.1.1.3", "2606:4700:4700::1113", "example.com"] {
            #expect(!Address.isLocal(address), "\(address)")
        }
    }

    @Test func seeKeepsTheDNSMark() {
        var stats = Stats()
        _ = stats.see(app, host: nil, address: "192.168.1.1", dns: true, day: day)
        _ = stats.see(app, host: "router.example", address: "192.168.1.1", day: "2026-11-14")
        #expect(stats.addresses?[app]?["192.168.1.1"] == Address(day: "2026-11-14", host: "router.example", dns: true))
        _ = stats.see(app, host: nil, address: "192.168.1.2", day: day)
        #expect(stats.addresses?[app]?["192.168.1.2"]?.dns == nil)
    }

    @Test func dnsFlowReplacesTheHostName() {
        var stats = Stats()
        _ = stats.see(app, host: "api.github.com", address: "10.1.0.1", day: day)
        _ = stats.see(app, host: nil, address: "10.1.0.1", dns: true, day: day)
        #expect(stats.addresses?[app]?["10.1.0.1"] == Address(day: day, host: nil, dns: true))
        _ = stats.see(app, host: "api.github.com", address: "1.1.1.3", day: day)
        _ = stats.see(app, host: "family.cloudflare-dns.com", address: "1.1.1.3", dns: true, day: day)
        #expect(stats.addresses?[app]?["1.1.1.3"]?.host == "family.cloudflare-dns.com")
    }
}

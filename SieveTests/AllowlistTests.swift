import Foundation
import Testing

struct AllowlistTests {
    @Test func readsEachLineForm() {
        let (list, tally) = Allowlist.parse(
            """
            # comment
            Example.COM.
            "api.test.org",note
            203.0.113.24  # a server

            2001:DB8::1%en0
            ::ffff:198.51.100.7
            10.0.0.0/8
            """)
        #expect(
            list.entries == [
                "api.test.org", "example.com", "10.0.0.0/8", "198.51.100.7", "203.0.113.24", "2001:db8::1",
            ])
        #expect(tally == Allowlist.Tally(kept: 6))
    }

    @Test func dropsDuplicatesAndCoveredEntries() {
        let (list, tally) = Allowlist.parse(
            "example.com\nexample.com\nwww.example.com\n1.1.1.0/24\n1.1.1.1\n1.1.1.1/32\n1.1.0.0/16\nlocalhost\n")
        #expect(list.entries == ["example.com", "1.1.0.0/16"])
        #expect(tally.kept == 2)
        // `1.1.1.1/32` equals `1.1.1.1` once normalized.
        #expect(tally.duplicates == 2)
        #expect(tally.covered == 3)
        #expect(tally.invalid == 1)
    }

    @Test func clearsHostBitsAndShortensFullLengths() {
        let (list, _) = Allowlist.parse("10.1.2.3/8\n192.0.2.9/32\n2001:db8::7/128\n2001:db8:aa::1/32")
        // `2001:db8::7` falls inside `2001:db8::/32`, so it is covered.
        #expect(list.entries == ["10.0.0.0/8", "192.0.2.9", "2001:db8::/32"])
    }

    @Test func countsInvalidLinesWithTheFirstThreeNumbers() {
        let (_, tally) = Allowlist.parse("https://example.com/a\nok.example\nlocalhost\n10.0.0.0/33\n::/129\nbad host\n")
        #expect(tally.invalid == 5)
        #expect(tally.invalidLines == [1, 3, 4])
    }

    @Test func matchesHostsAddressesAndRanges() {
        let list = Allowlist.parse("example.com\n203.0.113.24\n10.0.0.0/8\n2001:db8::/32").list
        #expect(list.allows(host: "www.example.com", address: nil))
        #expect(!list.allows(host: "example.org", address: nil))
        #expect(list.allows(host: nil, address: "203.0.113.24"))
        #expect(!list.allows(host: nil, address: "203.0.113.25"))
        #expect(list.allows(host: nil, address: "10.255.255.255"))
        #expect(!list.allows(host: nil, address: "11.0.0.0"))
        #expect(list.allows(host: nil, address: "2001:db8:ffff::1"))
        #expect(!list.allows(host: nil, address: "2001:db9::"))
        #expect(!list.allows(host: nil, address: nil))
    }
}

struct AllowOnlyTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"
    let list = Allowlist.parse("example.com\n203.0.113.24\n10.0.0.0/8").list

    @Test func dropsWhatTheListDoesNotHave() {
        let config = Config(allowOnly: true)
        #expect(config.verdict(app: app, host: "example.org", isApple: false, allowlist: list) == .block)
        #expect(config.verdict(app: app, host: "www.example.com", isApple: false, allowlist: list) == .allow)
        #expect(config.verdict(app: app, host: nil, address: "203.0.113.24", isApple: false, allowlist: list) == .allow)
        #expect(config.verdict(app: app, host: nil, address: "10.1.2.3", isApple: false, allowlist: list) == .allow)
        #expect(config.verdict(app: app, host: nil, address: "11.1.2.3", isApple: false, allowlist: list) == .block)
    }

    @Test func coreServicesPassButOtherAppleAppsDoNot() {
        let config = Config(allowOnly: true)
        #expect(config.verdict(app: "com.apple.mDNSResponder", host: nil, isApple: true, allowlist: list) == .allow)
        #expect(config.verdict(app: "com.apple.nsurlsessiond", host: nil, isApple: true, allowlist: list) == .block)
        // Only Apple code can be a core service.
        #expect(config.verdict(app: "com.apple.mDNSResponder", host: nil, isApple: false, allowlist: list) == .block)
    }

    @Test func rulesStillApplyToListedHosts() {
        let config = Config(rules: [Rule(app: app, host: "example.com", action: .block)], allowOnly: true)
        #expect(config.verdict(app: app, host: "example.com", isApple: false, allowlist: list) == .block)
    }

    @Test func offAndModeOffIgnoreTheList() {
        #expect(Config().verdict(app: app, host: "example.org", isApple: false, allowlist: list) == .allow)
        let off = Config(mode: .off, allowOnly: true)
        #expect(off.verdict(app: app, host: "example.org", isApple: false, allowlist: list) == .allow)
    }
}

import Testing

struct PublicDNSTests {
    let dns = PublicDNS(
        text: """
            # A comment, then records.
            1.1.1.1,Cloudflare,One.One.One.One
            2606:4700:4700:0:0:0:0:1111,Cloudflare,one.one.one.one
            dns.nextdns.io,NextDNS
            4.2.2.1,Level3,
            45.90.28.0/24,NextDNS,dns.nextdns.io
            2a07:a8c0::/96,NextDNS,dns.nextdns.io
            10.0.0.0/33,Bad

            no-provider.example
            1.1.1.1,Other
            """)

    @Test func addressGetsItsResolverHost() {
        #expect(dns.entry(for: "1.1.1.1") == .init(provider: "Cloudflare", host: "one.one.one.one"))
        #expect(dns.entry(for: "4.2.2.1") == .init(provider: "Level3", host: nil))
    }

    @Test func addressMatchesInAnyForm() {
        #expect(dns.entry(for: "2606:4700:4700::1111")?.provider == "Cloudflare")
        #expect(dns.entry(for: "::ffff:1.1.1.1")?.provider == "Cloudflare")
    }

    @Test func hostMatchesItselfAndSubdomains() {
        #expect(dns.entry(for: "dns.nextdns.io") == .init(provider: "NextDNS", host: nil))
        #expect(dns.entry(for: "abc123.dns.nextdns.io")?.provider == "NextDNS")
        #expect(dns.entry(for: "nextdns.io") == nil)
    }

    @Test func rangeMatchesOnlyItsAddresses() {
        #expect(dns.entry(for: "45.90.28.123") == .init(provider: "NextDNS", host: "dns.nextdns.io"))
        #expect(dns.entry(for: "45.90.29.1") == nil)
        #expect(dns.entry(for: "2a07:a8c0::55:dbcf")?.provider == "NextDNS")
        #expect(dns.entry(for: "2a07:a8c0::1:0:0") == nil)
        #expect(dns.entry(for: "10.0.0.1") == nil)
    }

    @Test func badAndUnknownLinesMatchNothing() {
        #expect(dns.entry(for: "no-provider.example") == nil)
        #expect(dns.entry(for: "8.8.8.8") == nil)
        #expect(dns.entry(for: "example.com") == nil)
    }
}

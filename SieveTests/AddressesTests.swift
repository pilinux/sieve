import Foundation
import Testing

struct AddressesTests {
    let early = Date(timeIntervalSince1970: 1_000)
    let late = Date(timeIntervalSince1970: 2_000)

    @Test func rowsMergeEveryAppsRecord() {
        let stats = Stats(addresses: [
            "b": ["192.0.2.1": Address(day: "2026-11-16", host: "old.example", hits: Hit(count: 3, last: early))],
            "a": [
                "192.0.2.1": Address(day: "2026-11-17", host: "new.example", hits: Hit(count: 4, last: late)),
                "192.0.2.2": Address(day: "2026-11-17", dns: true),
            ],
        ])
        let rows = Dictionary(uniqueKeysWithValues: stats.addressRows().map { ($0.address, $0) })
        #expect(
            rows["192.0.2.1"]
                == AddressRow(
                    address: "192.0.2.1", host: "new.example", apps: ["a", "b"], flows: 7, last: late,
                    appHits: ["a": Hit(count: 4, last: late), "b": Hit(count: 3, last: early)]))
        // A record with no count yet leaves the flows unknown.
        #expect(rows["192.0.2.2"] == AddressRow(address: "192.0.2.2", apps: ["a"], dns: true))
    }

    @Test @MainActor func labelTakesTheFirstThatFits() {
        var builder = AddressTable.Builder(fieldCount: 4)
        builder.add("203.0.113.0/24", row: ["DE", "AS3320", "Deutsche Telekom AG", "telekom.de"])
        builder.add("104.16.0.0/13", row: ["US", "AS13335", "Cloudflare, Inc.", "cloudflare.com"])
        let ipInfo = builder.finish()
        let publicDNS = PublicDNS(text: "1.1.1.3,Cloudflare,family.cloudflare-dns.com")
        let cdn = AddressTable.cdn(text: "104.16.0.0/13,Cloudflare,edge").table
        let label = { (value: String, dns: Bool) in AddressLabel(value, dns: dns, ipInfo: ipInfo, publicDNS: publicDNS, cdn: cdn) }
        #expect(label("1.1.1.3", true) == .publicDNS(provider: "Cloudflare"))
        #expect(label("10.1.0.1", true) == .dns(local: true))
        #expect(label("203.0.113.9", true) == .dns(local: false))
        #expect(label("10.1.0.20", false) == .local)
        #expect(label("104.16.132.229", false) == .cdn(provider: "Cloudflare"))
        #expect(label("203.0.113.9", false) == .country(code: "DE", asn: "AS3320", owner: "Deutsche Telekom AG", domain: "telekom.de"))
        #expect(label("198.51.100.1", false) == nil)
        #expect(label("example.com", false) == nil)
    }

    @Test func flowsGoToCountriesOrOffTheMap() {
        let rows = [
            AddressRow(address: "203.0.113.1", apps: ["a", "b"], flows: 10),
            AddressRow(address: "203.0.113.2", apps: ["a"], flows: 5),
            AddressRow(address: "104.16.0.1", apps: ["a"], flows: 7),
            AddressRow(address: "198.51.100.1", apps: ["a"]),
        ]
        let places = FlowsByPlace(rows) { row in
            switch row.address {
            case "104.16.0.1": .cdn(provider: "Cloudflare")
            case "198.51.100.1": nil
            default: .country(code: "DE", asn: "", owner: "", domain: "")
            }
        }
        #expect(places.countries == ["DE": FlowsByPlace.Country(flows: 15, addresses: 2, apps: ["a": 15, "b": 10])])
        #expect(places.offMap == [.cdn: 7, FlowsByPlace.OffMap.none: 0])
    }

    @Test func equalEarthKeepsTheCentreAndMirrors() {
        let centre = EqualEarth.project(longitude: 0, latitude: 0)
        #expect(centre.x == 0 && centre.y == 0)
        let east = EqualEarth.project(longitude: 180, latitude: 0)
        #expect(abs(east.x - 2.7066) < 0.001)
        let north = EqualEarth.project(longitude: 90, latitude: 45)
        let south = EqualEarth.project(longitude: -90, latitude: -45)
        #expect(north.x == -south.x && north.y == -south.y && north.y > 0)
    }

    @Test func shapesReadRingsAndSkipComments() {
        let shapes = CountryShape.parse("# A comment\nDE|0,0 10,0 10,10|20,20 21,20 21,21\nbad line\n")
        #expect(shapes.map(\.code) == ["DE"])
        #expect(shapes.first?.rings.map(\.count) == [3, 3])
        #expect(shapes.first?.rings.first?.first?.x == 0)
    }
}

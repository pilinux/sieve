import Foundation
import Testing

struct AddressTableTests {
    private func table(_ ranges: [(String, String)]) -> AddressTable {
        var builder = AddressTable.Builder(fieldCount: 1)
        for (network, value) in ranges { builder.add(network, row: [value]) }
        return builder.finish()
    }

    @Test func findsTheRangeOfAnAddress() {
        let table = table([("10.0.0.0/8", "a"), ("192.0.2.0/24", "b"), ("198.51.100.7", "c"), ("2001:db8::/32", "d")])
        #expect(table.row(for: "10.20.30.40") == ["a"])
        #expect(table.row(for: "192.0.2.255") == ["b"])
        #expect(table.row(for: "198.51.100.7") == ["c"])
        #expect(table.row(for: "2001:db8:1::5") == ["d"])
        #expect(table.row(for: "::ffff:10.1.1.1") == ["a"])
    }

    @Test func gapsAndOtherFamiliesMatchNothing() {
        let table = table([("10.0.0.0/8", "a"), ("2001:db8::/32", "d")])
        #expect(table.row(for: "9.255.255.255") == nil)
        #expect(table.row(for: "11.0.0.0") == nil)
        #expect(table.row(for: "2001:db9::1") == nil)
        #expect(table.row(for: "example.com") == nil)
    }

    @Test func neighborsWithTheSameRowMergeAndOverlapsDrop() {
        var builder = AddressTable.Builder(fieldCount: 1)
        builder.add("10.0.0.0/25", row: ["a"])
        builder.add("10.0.0.128/25", row: ["a"])
        builder.add("10.0.0.64/26", row: ["b"])
        let added = builder.add("not an address", row: ["x"])
        #expect(!added)
        let table = builder.finish()
        #expect(builder.dropped == 1)
        #expect(table.sourceCount == 3)
        #expect(table.row(for: "10.0.0.70") == ["a"])
        #expect(table.row(for: "10.0.0.200") == ["a"])
    }

    @Test func dataReadsBackAsTheSameTable() throws {
        let built = table([("0.0.0.0/0", "all"), ("::/0", "every")])
        let read = try #require(AddressTable(data: built.data))
        #expect(read.row(for: "255.255.255.255") == ["all"])
        #expect(read.row(for: "ffff::1") == ["every"])
        #expect(AddressTable(data: Data("not a table".utf8)) == nil)
    }

    @Test func csvFieldsKeepQuotedCommas() {
        let line = Data(#"1.0.0.0/24,Australia,AU,Oceania,OC,AS13335,"Cloudflare, Inc.",cloudflare.com"#.utf8)
        #expect(IPInfoLite.fields(line)[6] == "Cloudflare, Inc.")
        #expect(IPInfoLite.fields(Data(#""say ""hi""",b"#.utf8)) == [#"say "hi""#, "b"])
    }

    private let sample = """
        network,country,country_code,continent,continent_code,asn,as_name,as_domain
        1.0.0.0/24,Australia,AU,Oceania,OC,AS13335,"Cloudflare, Inc.",cloudflare.com
        1.0.1.0/24,China,CN,Asia,AS,,,
        1.6.2.1,South Africa,ZA,Africa,AF,AS9583,Sify Limited,sifycorp.com
        2a00:1450::/32,Ireland,IE,Europe,EU,AS15169,Google LLC,google.com

        """

    private func file(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try data.write(to: url)
        return url
    }

    @Test func readsAPlainFile() throws {
        let table = try IPInfoLite.table(from: file(Data(sample.utf8)))
        #expect(table.sourceCount == 4)
        #expect(table.row(for: "1.0.0.1") == ["AU", "AS13335", "Cloudflare, Inc.", "cloudflare.com"])
        #expect(table.row(for: "1.0.1.9") == ["CN", "", "", ""])
        #expect(table.row(for: "1.6.2.1") == ["ZA", "AS9583", "Sify Limited", "sifycorp.com"])
        #expect(table.row(for: "1.6.2.2") == nil)
        #expect(table.row(for: "2a00:1450:4001::1")?.first == "IE")
    }

    @Test func readsAGzipFile() throws {
        // A gzip file is a 10-byte header, raw DEFLATE data, and an 8-byte trailer that the reader skips.
        let deflated = try (Data(sample.utf8) as NSData).compressed(using: .zlib) as Data
        let gzip = Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3]) + deflated + Data(count: 8)
        let table = try IPInfoLite.table(from: file(gzip))
        #expect(table.row(for: "1.0.0.1")?.first == "AU")
    }

    @Test func refusesAnotherFile() throws {
        let other = try file(Data("start_ip,end_ip,country\n1.0.0.0,1.0.0.255,AU\n".utf8))
        #expect(throws: IPInfoLite.Failure.self) { try IPInfoLite.table(from: other) }
    }

    @Test func bundledCDNListHasNoOverlap() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Shared/cdn.csv")
        let (table, dropped) = AddressTable.cdn(text: try String(contentsOf: url, encoding: .utf8))
        #expect(dropped == 0)
        #expect(table.row(for: "104.16.132.229") == ["Cloudflare", "edge"])
        #expect(table.row(for: "151.101.65.140") == ["Fastly", "edge"])
        #expect(table.row(for: "192.0.2.1") == nil)
    }
}

import Foundation
import Testing

struct DNSQueryTests {
    // A query for each name, type A, with no records unless `extra` adds them.
    func query(_ names: [String], records: Int = 0, extra: [UInt8] = []) -> [UInt8] {
        var bytes: [UInt8] = [0x12, 0x34, 0x01, 0x00, 0, UInt8(names.count), 0, 0, 0, 0, 0, UInt8(records)]
        for name in names {
            for label in name.split(separator: ".") { bytes += [UInt8(label.utf8.count)] + Array(label.utf8) }
            bytes += [0, 0, 1, 0, 1]
        }
        return bytes + extra
    }

    // The EDNS record that most resolvers add: the root name, type OPT, and no data.
    let edns: [UInt8] = [0, 0, 41, 0x10, 0, 0, 0, 0, 0, 0, 0]

    func tcp(_ message: [UInt8]) -> [UInt8] { [UInt8(message.count >> 8), UInt8(message.count & 0xFF)] + message }

    @Test func readsTheNameOfAQuery() throws {
        let bytes = query(["ads.google.com"], records: 1, extra: edns)
        let result = try #require(DNSQuery.names(in: Data(bytes), tcp: false))
        #expect(result.names == ["ads.google.com"])
        #expect(result.used == bytes.count)
    }

    @Test func readsQueriesThatFollowEachOther() throws {
        let bytes = query(["a.example"]) + query(["b.example"])
        #expect(try #require(DNSQuery.names(in: Data(bytes), tcp: false)).names == ["a.example", "b.example"])
    }

    @Test func readsEachTCPQuery() throws {
        let first = tcp(query(["a.example"], records: 1, extra: edns))
        let result = try #require(DNSQuery.names(in: Data(first + tcp(query(["b.example"]))), tcp: true))
        #expect(result.names == ["a.example", "b.example"])
    }

    @Test func leavesAPartTCPQueryForLater() throws {
        let first = tcp(query(["a.example"]))
        let result = try #require(DNSQuery.names(in: Data(first + tcp(query(["b.example"])).prefix(9)), tcp: true))
        #expect(result.names == ["a.example"])
        #expect(result.used == first.count)
    }

    @Test func followsACompressedName() throws {
        // The second question is `www.` and then a pointer to the first name, at byte 12.
        let bytes = query(["a.example"], extra: [3] + Array("www".utf8) + [0xC0, 12, 0, 1, 0, 1])
        var header = bytes
        header[5] = 2
        #expect(try #require(DNSQuery.names(in: Data(header), tcp: false)).names == ["a.example", "www.a.example"])
    }

    @Test func rejectsWhatIsNotAQuery() {
        var reply = query(["a.example"])
        reply[2] |= 0x80
        #expect(DNSQuery.names(in: Data(reply), tcp: false) == nil)
        #expect(DNSQuery.names(in: Data([1, 2, 3]), tcp: false) == nil)
        #expect(DNSQuery.names(in: Data(query(["a.example"]).dropLast(2)), tcp: false) == nil)
    }

    @Test func rejectsAPointerLoop() {
        var bytes = query([])
        bytes[5] = 1
        bytes += [0xC0, 12, 0, 1, 0, 1]
        #expect(DNSQuery.names(in: Data(bytes), tcp: false) == nil)
    }
}

import Foundation
import Network

/// IP ranges, each with a row of text fields, such as a CDN provider, or a country and a network owner.
/// A lookup reads the data in place, so it can be a large file mapped into memory.
nonisolated struct AddressTable: Sendable {
    // The file starts with this, then six counts: source ranges, fields per row, IPv4 entries, IPv6 entries, rows, strings.
    private static let magic = Data("SIEVEAT1".utf8)
    private static let headerSize = 32
    // An entry with this row marks a gap with no range.
    private static let gap = UInt32.max

    let data: Data
    /// The number of ranges in the source, before neighbors with the same row merged.
    let sourceCount: Int
    private let fieldCount: Int
    private let v4Count: Int
    private let v6Count: Int
    private let rowCount: Int
    private let stringCount: Int

    /// Reads a table that `Builder` made. Nil if the data is not one.
    init?(data: Data) {
        guard data.count >= Self.headerSize, data.prefix(8) == Self.magic else { return nil }
        self.init(trusted: data)
        guard fieldCount > 0, blobStart <= data.count else { return nil }
    }

    private init(trusted data: Data) {
        let counts = (0..<6).map { Int(data.word(at: 8 + $0 * 4)) }
        (sourceCount, fieldCount, v4Count, v6Count, rowCount, stringCount) = (
            counts[0], counts[1], counts[2], counts[3], counts[4], counts[5]
        )
        self.data = data
    }

    // Each section follows the one before it.
    private var v6Start: Int { Self.headerSize + v4Count * 8 }
    private var rowsStart: Int { v6Start + v6Count * 20 }
    private var stringsStart: Int { rowsStart + rowCount * fieldCount * 4 }
    private var blobStart: Int { stringsStart + stringCount * 8 }

    /// The row of the range that holds the address, or nil if no range does.
    func row(for address: String) -> [String]? {
        guard let bytes = Self.bytes(address) else { return nil }
        let row =
            bytes.count == 4
            ? lastEntry(count: v4Count, start: Self.headerSize, size: 8, key: UInt128(Self.number(bytes))) {
                UInt128(data.word(at: $0))
            }
            : lastEntry(count: v6Count, start: v6Start, size: 20, key: Self.number(bytes)) {
                UInt128(data.double(at: $0)) << 64 | UInt128(data.double(at: $0 + 8))
            }
        guard let row, row != Self.gap, Int(row) < rowCount else { return nil }
        return (0..<fieldCount).map { string(Int(data.word(at: rowsStart + (Int(row) * fieldCount + $0) * 4))) }
    }

    // Finds the entry with the highest start at or below `key`, and returns its row. Its row is the last 4 bytes.
    private func lastEntry(count: Int, start: Int, size: Int, key: UInt128, first: (Int) -> UInt128) -> UInt32? {
        var low = 0
        var high = count
        while low < high {
            let middle = (low + high) / 2
            if first(start + middle * size) <= key { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : data.word(at: start + (low - 1) * size + size - 4)
    }

    private func string(_ index: Int) -> String {
        guard index < stringCount else { return "" }
        let offset = blobStart + Int(data.word(at: stringsStart + index * 8))
        let end = offset + Int(data.word(at: stringsStart + index * 8 + 4))
        guard end <= data.count else { return "" }
        return String(decoding: data[data.startIndex + offset..<data.startIndex + end], as: UTF8.self)
    }

    /// The address bytes in network order, after `Address.normalize(_:)`. Nil if `text` is not an IP address.
    static func bytes(_ text: String) -> [UInt8]? {
        guard let address = Address.normalize(text) else { return nil }
        return (IPv4Address(address)?.rawValue ?? IPv6Address(address)?.rawValue).map(Array.init)
    }

    private static func number(_ bytes: [UInt8]) -> UInt128 {
        bytes.reduce(0) { $0 << 8 | UInt128($1) }
    }

    /// Collects ranges, then writes the table. Of two ranges that overlap, the first one added wins.
    struct Builder {
        let fieldCount: Int
        private(set) var sourceCount = 0
        /// Ranges left out because an earlier one already covered part of them.
        private(set) var dropped = 0
        private var v4: [(first: UInt128, last: UInt128, row: UInt32)] = []
        private var v6: [(first: UInt128, last: UInt128, row: UInt32)] = []
        private var rows: [[UInt32]: UInt32] = [:]
        private var strings: [String: UInt32] = [:]
        // Neighbors in a source file often share a row, so the last one skips the lookups.
        private var previous: (row: [String], index: UInt32)?

        init(fieldCount: Int) {
            self.fieldCount = fieldCount
        }

        /// Adds a range written as `prefix/length`, or one address. Returns false if `network` is not one.
        @discardableResult
        mutating func add(_ network: some StringProtocol, row: [String]) -> Bool {
            let parts = network.split(separator: "/")
            guard parts.count <= 2, let bytes = Self.parse(String(parts[0])) else { return false }
            let bits = bytes.count * 8
            guard let length = parts.count == 2 ? Int(parts[1]) : bits, (0...bits).contains(length) else { return false }
            // The bits after the prefix. A shift by the full 128 bits would overflow, so length 0 is its own case.
            let host = length == 0 ? UInt128.max >> (128 - bits) : (1 << (bits - length)) - 1
            let first = AddressTable.number(bytes) & ~host
            let last = first | host
            let index: UInt32
            if let previous, previous.row == row {
                index = previous.index
            } else {
                let fields = (0..<fieldCount).map { $0 < row.count ? intern(row[$0]) : intern("") }
                index = rows[fields] ?? UInt32(rows.count)
                rows[fields] = index
                previous = (row, index)
            }
            sourceCount += 1
            if bits == 32 { v4.append((first, last, index)) } else { v6.append((first, last, index)) }
            return true
        }

        // Source files write addresses in one form already, so this skips `Address.normalize(_:)`.
        // `inet_pton` is also much faster than `IPv4Address(_:)` over millions of lines.
        private static func parse(_ text: String) -> [UInt8]? {
            var v4 = in_addr()
            if text.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 { return withUnsafeBytes(of: v4) { Array($0) } }
            var v6 = in6_addr()
            if text.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 { return withUnsafeBytes(of: v6) { Array($0) } }
            return nil
        }

        private mutating func intern(_ text: String) -> UInt32 {
            if let index = strings[text] { return index }
            let index = UInt32(strings.count)
            strings[text] = index
            return index
        }

        /// The table. Its `data` can be saved and read back with `AddressTable(data:)`.
        mutating func finish() -> AddressTable {
            let v4Entries = entries(v4, max: UInt128(UInt32.max))
            let v6Entries = entries(v6, max: .max)
            var data = AddressTable.magic
            for count in [sourceCount, fieldCount, v4Entries.count, v6Entries.count, rows.count, strings.count] {
                data.append(word: UInt32(count))
            }
            for entry in v4Entries {
                data.append(word: UInt32(entry.first))
                data.append(word: entry.row)
            }
            for entry in v6Entries {
                data.append(double: UInt64(entry.first >> 64))
                data.append(double: UInt64(truncatingIfNeeded: entry.first))
                data.append(word: entry.row)
            }
            for fields in rows.sorted(by: { $0.value < $1.value }).map(\.key) {
                for field in fields { data.append(word: field) }
            }
            let ordered = strings.sorted { $0.value < $1.value }.map { Data($0.key.utf8) }
            var offset = 0
            for text in ordered {
                data.append(word: UInt32(offset))
                data.append(word: UInt32(text.count))
                offset += text.count
            }
            for text in ordered { data.append(text) }
            return AddressTable(trusted: data)
        }

        // Sorts the ranges and turns them into starts. A gap entry ends each range that the next one does not follow.
        // Neighbors with the same row merge into one entry.
        private mutating func entries(_ ranges: [(first: UInt128, last: UInt128, row: UInt32)], max: UInt128)
            -> [(first: UInt128, row: UInt32)]
        {
            var result: [(first: UInt128, row: UInt32)] = []
            var end: UInt128?
            for range in ranges.enumerated().sorted(by: { ($0.element.first, $0.offset) < ($1.element.first, $1.offset) })
                .map(\.element)
            {
                if let end, range.first <= end {
                    dropped += 1
                    continue
                }
                let follows = end.map { $0 + 1 == range.first } ?? false
                if !follows, let end { result.append((end + 1, AddressTable.gap)) }
                if !(follows && result.last?.row == range.row) { result.append((range.first, range.row)) }
                end = range.last
            }
            if let end, end < max { result.append((end + 1, AddressTable.gap)) }
            return result
        }
    }
}

nonisolated extension AddressTable {
    /// `cdn.csv`, which ships in the bundle. Each row holds the provider and the kind.
    static let cdn = cdn(
        text: Bundle.main.url(forResource: "cdn", withExtension: "csv").flatMap {
            try? String(contentsOf: $0, encoding: .utf8)
        } ?? ""
    ).table

    /// Reads one `value,provider,kind` record per line. Lines that start with `#` are comments.
    static func cdn(text: String) -> (table: AddressTable, dropped: Int) {
        var builder = Builder(fieldCount: 2)
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { continue }
            builder.add(fields[0], row: fields.dropFirst().map(String.init))
        }
        let table = builder.finish()
        return (table, builder.dropped)
    }
}

// Little-endian integers in a byte buffer. The table packs them with no padding.
private extension Data {
    nonisolated func word(at offset: Int) -> UInt32 {
        withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }

    nonisolated func double(at offset: Int) -> UInt64 {
        withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
    }

    nonisolated mutating func append(word: UInt32) {
        Swift.withUnsafeBytes(of: word.littleEndian) { append(contentsOf: $0) }
    }

    nonisolated mutating func append(double: UInt64) {
        Swift.withUnsafeBytes(of: double.littleEndian) { append(contentsOf: $0) }
    }
}

import Compression
import Foundation

/// Reads an IPinfo Lite CSV file, plain or gzip, into an `AddressTable`.
/// Each row holds the country code, AS number, AS name, and AS domain. Any of them can be empty.
nonisolated enum IPInfoLite {
    static let header = "network,country,country_code,continent,continent_code,asn,as_name,as_domain"

    enum Failure: LocalizedError {
        case notIPInfo

        var errorDescription: String? { "It is not an IPinfo Lite file." }
    }

    /// Reads the file in chunks, so the whole text never sits in memory.
    /// - Parameter progress: the share of the file read so far, from 0 to 1.
    static func table(from file: URL, progress: @escaping (Double) -> Void = { _ in }) throws -> AddressTable {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let size = Double(max(try handle.seekToEnd(), 1))
        try handle.seek(toOffset: 0)
        var pending = try handle.read(upToCount: 1 << 20) ?? Data()
        var offset = 0
        var read = Double(pending.count)
        let gzip = pending.starts(with: [0x1f, 0x8b])
        if gzip {
            guard let length = gzipHeaderLength(pending) else { throw Failure.notIPInfo }
            offset = length
        }
        // The file's bytes after any gzip header, at most `length` at a time.
        let next = { (length: Int) throws -> Data? in
            if offset == pending.count {
                guard let more = try handle.read(upToCount: 1 << 20), !more.isEmpty else { return nil }
                read += Double(more.count)
                progress(read / size)
                pending = more
                offset = 0
            }
            let end = min(offset + length, pending.count)
            defer { offset = end }
            return pending.subdata(in: offset..<end)
        }
        let filter = gzip ? try InputFilter(.decompress, using: .zlib, readingFrom: next) : nil
        let text = { () throws -> Data? in try filter.map { try $0.readData(ofLength: 1 << 20) } ?? next(1 << 20) }

        var builder = AddressTable.Builder(fieldCount: 4)
        var first = true
        func line(_ bytes: UnsafeBufferPointer<UInt8>) throws {
            let bytes = bytes.last == 0x0D ? UnsafeBufferPointer(rebasing: bytes.dropLast()) : bytes
            if first {
                first = false
                let head = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
                guard head == header else { throw Failure.notIPInfo }
                return
            }
            let fields = Self.fields(bytes)
            guard fields.count >= 8 else { return }
            builder.add(fields[0], row: [fields[2], fields[5], fields[6], fields[7]])
        }
        // Raw byte buffers, since stepping through `Data` one byte at a time is slow over 4 million lines.
        var carry: [UInt8] = []
        while let chunk = try text() {
            carry.append(contentsOf: chunk)
            let used = try carry.withUnsafeBufferPointer { buffer in
                var start = 0
                while let newline = buffer[start...].firstIndex(of: 0x0A) {
                    try line(UnsafeBufferPointer(rebasing: buffer[start..<newline]))
                    start = newline + 1
                }
                return start
            }
            carry.removeFirst(used)
        }
        if !carry.isEmpty { try carry.withUnsafeBufferPointer { try line($0) } }
        guard !first, builder.sourceCount > 0 else { throw Failure.notIPInfo }
        return builder.finish()
    }

    /// Splits one CSV line. A quoted field may hold commas, and two quotes inside it stand for one.
    static func fields(_ line: some Collection<UInt8>) -> [String] {
        // Most lines have no quotes, and a plain split is much faster.
        guard line.contains(0x22) else {
            return line.split(separator: 0x2C, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        }
        var fields: [String] = []
        var field: [UInt8] = []
        var quoted = false
        var closed = false
        for byte in line {
            if quoted {
                if byte == 0x22 {
                    quoted = false
                    closed = true
                } else {
                    field.append(byte)
                }
                continue
            }
            if byte == 0x22 {
                // A quote right after a closing quote is a quote in the text.
                if closed { field.append(byte) }
                quoted = true
                closed = false
                continue
            }
            closed = false
            if byte == 0x2C {
                fields.append(String(decoding: field, as: UTF8.self))
                field.removeAll(keepingCapacity: true)
            } else {
                field.append(byte)
            }
        }
        fields.append(String(decoding: field, as: UTF8.self))
        return fields
    }

    // The size of the gzip header that `data` starts with, as RFC 1952 lays it out. Nil if it is cut short.
    private static func gzipHeaderLength(_ data: Data) -> Int? {
        let bytes = [UInt8](data.prefix(4096))
        guard bytes.count >= 10, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var at = 10
        if flags & 4 != 0 {
            guard at + 2 <= bytes.count else { return nil }
            at += 2 + (Int(bytes[at]) | Int(bytes[at + 1]) << 8)
        }
        // The file name, then the comment, each ending in a zero byte.
        for flag: UInt8 in [8, 16] where flags & flag != 0 {
            guard at < bytes.count, let end = bytes[at...].firstIndex(of: 0) else { return nil }
            at = end + 1
        }
        if flags & 2 != 0 { at += 2 }
        return at <= bytes.count ? at : nil
    }
}

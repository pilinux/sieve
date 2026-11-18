import Foundation

/// Reads the names that DNS queries ask, from the data an app sends to port 53.
enum DNSQuery {
    /// How many bytes the filter asks to see at a time: the largest DNS message over TCP, with its length.
    static let peek = 65_537

    /// The names that the whole queries at the start of `data` ask, and how many bytes those queries take.
    /// Over TCP, two bytes of length come before each query, and a query can end in later data.
    /// Returns nil when the data is not a DNS query.
    static func names(in data: Data, tcp: Bool) -> (names: [String], used: Int)? {
        var reader = Reader(bytes: [UInt8](data))
        var names: [String] = []
        var used = 0
        while used < reader.bytes.count {
            reader.at = used
            if tcp {
                guard let length = reader.short(), reader.at + length <= reader.bytes.count else { break }
                reader.start = reader.at
                guard let asked = reader.query() else { return nil }
                names += asked
                used = reader.start + length
            } else {
                reader.start = used
                guard let asked = reader.query() else { return nil }
                names += asked
                used = reader.at
            }
        }
        return (names, used)
    }
}

private struct Reader {
    let bytes: [UInt8]
    // Where the current message starts. Compressed names point from there.
    var start = 0
    var at = 0

    mutating func short() -> Int? {
        guard at + 2 <= bytes.count else { return nil }
        defer { at += 2 }
        return Int(bytes[at]) << 8 | Int(bytes[at + 1])
    }

    // A whole query: the header, the questions, and the records. A query may carry records, such as the EDNS one.
    mutating func query() -> [String]? {
        guard at + 12 <= bytes.count, bytes[at + 2] & 0x80 == 0 else { return nil }
        at += 4
        guard let questions = short(), let answers = short(), let authority = short(), let additional = short() else {
            return nil
        }
        var names: [String] = []
        for _ in 0..<questions {
            // A question ends with its type and class.
            guard let name = name(), skip(4) else { return nil }
            names.append(name)
        }
        for _ in 0..<(answers + authority + additional) {
            // A record has a type, class, and time to live, then its data after the data's length.
            guard name() != nil, skip(8), let length = short(), skip(length) else { return nil }
        }
        return names
    }

    mutating func skip(_ count: Int) -> Bool {
        at += count
        return at <= bytes.count
    }

    // Labels end with a zero length, or with a pointer to the rest of the name earlier in the message.
    mutating func name() -> String? {
        var labels: [String] = []
        var next = at
        var end: Int?
        // A pointer must lead back, so a loop of pointers cannot run forever.
        var limit = next
        while next < bytes.count {
            let length = Int(bytes[next])
            if length == 0 {
                at = end ?? next + 1
                return labels.joined(separator: ".")
            }
            if length >= 0xC0 {
                guard next + 1 < bytes.count else { return nil }
                end = end ?? next + 2
                next = start + ((length & 0x3F) << 8 | Int(bytes[next + 1]))
                guard next < limit else { return nil }
                limit = next
                continue
            }
            guard length < 64, next + 1 + length <= bytes.count else { return nil }
            labels.append(String(decoding: bytes[(next + 1)...(next + length)], as: UTF8.self))
            next += 1 + length
        }
        return nil
    }
}

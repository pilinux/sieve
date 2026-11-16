import Foundation

/// Public DNS resolvers, by IP address and by host name.
struct PublicDNS {
    struct Entry: Equatable {
        var provider: String
        /// The resolver's host name, for an address. Nil for a host name, or an address with none.
        var host: String?
    }

    /// The list that ships in the bundle.
    static let bundled = PublicDNS(
        text: Bundle.main.url(forResource: "public-dns", withExtension: "csv").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? "")

    private var entries: [String: Entry] = [:]
    private var ranges: [(range: AddressRange, entry: Entry)] = []

    /// Reads one `value,provider,host` record per line. A value is an IP address, a range as `prefix/length`, or a host name.
    /// `host` may be left out. Lines that start with `#` are comments.
    /// A line with no value or no provider is skipped. Of two lines with the same value, the first wins.
    init(text: String) {
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, !fields[0].isEmpty, !fields[1].isEmpty else { continue }
            let value = Address.normalize(fields[0]) ?? fields[0].lowercased()
            let host = fields.count > 2 && !fields[2].isEmpty ? fields[2].lowercased() : nil
            let entry = Entry(provider: fields[1], host: host)
            if fields[0].contains("/") {
                if let range = AddressRange(fields[0]) { ranges.append((range, entry)) }
            } else if entries[value] == nil {
                entries[value] = entry
            }
        }
    }

    /// The entry of an IP address, or of a host name or one of its parent domains. An exact address wins over a range.
    func entry(for value: String) -> Entry? {
        if let address = Address.normalize(value) {
            return entries[address] ?? ranges.first { $0.range.contains(address) }?.entry
        }
        var domain = Substring(value)
        while true {
            if let entry = entries[String(domain)] { return entry }
            guard let dot = domain.firstIndex(of: ".") else { return nil }
            domain = domain[domain.index(after: dot)...]
        }
    }
}

import Foundation

/// A list of hosts to allow or block, downloaded or uploaded.
struct DomainList: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    /// An `https` URL, or nil for an uploaded file. An uploaded file cannot be refreshed.
    var url: String?
    var action: Action
    var enabled = true

    /// The largest list Sieve accepts, in bytes.
    static let maxBytes = 16_000_000

    /// Steven Black's unified hosts list, under the MIT licence. A copy ships with the extension, so it works before its first download.
    static let trackerShield = DomainList(
        id: "tracker-shield",
        name: "Tracker Shield",
        url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
        action: .block
    )

    /// Returns the host the way lists store it: lowercase, with no dot at the start or end. Returns nil if nothing is left.
    /// This way `Example.COM.` and `example.com` match the same entry.
    static func normalize(_ host: String) -> String? {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host.isEmpty ? nil : host
    }

    /// Reads one host per line. Hosts-file lines such as `0.0.0.0 example.com` work too. Each host goes through `normalize(_:)`.
    /// It skips `#` comments, names without a dot such as `localhost`, text that cannot be a host name such as
    /// the adblock line `||example.com^`, and IP addresses, because lists match host names only.
    static func parse(_ text: String) -> Set<String> {
        var hosts = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let words = line.prefix { $0 != "#" }.split(whereSeparator: \.isWhitespace)
            for word in words.dropFirst(words.count == 1 ? 0 : 1) {
                if let host = host(String(word)) { hosts.insert(host) }
            }
        }
        return hosts
    }

    /// The first non-nil `match` of the host, then of each parent domain, nearest first.
    nonisolated static func nearest<T>(_ host: String, _ match: (String) -> T?) -> T? {
        var domain = Substring(host)
        while true {
            if let found = match(String(domain)) { return found }
            guard let dot = domain.firstIndex(of: ".") else { return nil }
            domain = domain[domain.index(after: dot)...]
        }
    }

    /// The word as a host name, after `normalize(_:)`. Nil for a name without a dot, text that cannot be a host name,
    /// and an IP address.
    static func host(_ word: String) -> String? {
        guard let host = normalize(word), host.contains("."),
            host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }),
            Address.normalize(host) == nil
        else { return nil }
        return host
    }
}

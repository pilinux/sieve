import Foundation

/// A list of hosts to allow or block, loaded from a URL.
struct DomainList: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    /// An `https` or `file` URL.
    var url: String
    var action: Action
    var enabled = true

    /// The largest list Sieve takes, in bytes.
    static let maxBytes = 16_000_000

    /// Steven Black's unified hosts, MIT licence. Its first copy ships with the extension.
    static let trackerShield = DomainList(
        id: "tracker-shield",
        name: "Tracker Shield",
        url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
        action: .block,
        enabled: false
    )

    /// The host as lists hold it: lowercase, with no dot at either end. Nil if nothing is left.
    /// `Example.COM.` and `example.com` name the same host, so both must match the same entry.
    static func normalize(_ host: String) -> String? {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host.isEmpty ? nil : host
    }

    /// Reads one host per line, or hosts-file lines such as `0.0.0.0 example.com`.
    /// Skips `#` comments and names without a dot, such as `localhost`.
    static func parse(_ text: String) -> Set<String> {
        var hosts = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let words = line.prefix { $0 != "#" }.split(whereSeparator: \.isWhitespace)
            for word in words.dropFirst(words.count == 1 ? 0 : 1) where word.contains(".") {
                hosts.insert(word.lowercased())
            }
        }
        return hosts
    }
}

import Foundation

/// A list of hosts to allow or block, downloaded or uploaded.
struct DomainList: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    /// An `https` URL. Nil for an uploaded file, which has no refresh.
    var url: String?
    var action: Action
    var enabled = true

    /// The largest list Sieve takes, in bytes.
    static let maxBytes = 16_000_000

    /// Steven Black's unified hosts, MIT licence. Its first copy ships with the extension, so it is on from the start.
    static let trackerShield = DomainList(
        id: "tracker-shield",
        name: "Tracker Shield",
        url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
        action: .block
    )

    /// The host as lists hold it: lowercase, with no dot at either end. Nil if nothing is left.
    /// `Example.COM.` and `example.com` name the same host, so both must match the same entry.
    static func normalize(_ host: String) -> String? {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host.isEmpty ? nil : host
    }

    /// Reads one host per line, or hosts-file lines such as `0.0.0.0 example.com`, each as `normalize(_:)` gives it.
    /// Skips `#` comments, names without a dot, such as `localhost`, words no host name can be,
    /// such as the adblock line `||example.com^`, and IP addresses, since lists match host names.
    static func parse(_ text: String) -> Set<String> {
        var hosts = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let words = line.prefix { $0 != "#" }.split(whereSeparator: \.isWhitespace)
            for word in words.dropFirst(words.count == 1 ? 0 : 1) {
                guard let host = normalize(String(word)), host.contains("."),
                    host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }),
                    Address.normalize(host) == nil
                else { continue }
                hosts.insert(host)
            }
        }
        return hosts
    }
}

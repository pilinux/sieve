import Foundation

/// A list of hosts to allow or block, loaded from a URL.
struct DomainList: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    /// An `https` or `file` URL.
    var url: String
    var action: Action
    var enabled = true

    /// Steven Black's unified hosts, MIT licence. Its first copy ships with the extension.
    static let trackerShield = DomainList(
        id: "tracker-shield",
        name: "Tracker Shield",
        url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
        action: .block,
        enabled: false
    )

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

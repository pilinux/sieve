import Foundation
import Network

/// The hosts, IP addresses, and IP ranges that may connect while Allowlist only is on.
struct Allowlist: Sendable {
    /// The list ID the app and the extension use for the allowlist.
    static let id = "allowlist"

    /// App keys of the macOS services that stay allowed, so the Mac keeps working: DNS, time, certificate checks,
    /// DHCP, and the captive portal check.
    static let services: Set<String> = [
        "com.apple.mDNSResponder", "com.apple.timed", "com.apple.trustd", "com.apple.configd", "com.apple.captiveagent",
    ]

    /// What an upload held. Kept, duplicates, covered, and invalid add up to the lines that held an entry.
    struct Tally: Codable, Equatable {
        var kept = 0
        /// Lines equal to an earlier one after normalizing.
        var duplicates = 0
        /// Entries that a listed parent domain or range already covers.
        var covered = 0
        var invalid = 0
        /// The numbers of the first three invalid lines, counting from 1.
        var invalidLines: [Int] = []
    }

    /// Sorted hosts, then addresses and ranges as `prefix/length`, sorted by address.
    let entries: [String]
    private let hosts: Set<String>
    private let addresses: AddressTable

    /// Reads one entry per line: a host, an IP address, or a range as `prefix/length`. Text after `#` is a comment.
    /// Only the first comma field counts, without spaces and quotes around it. Drops duplicates and covered entries.
    static func parse(_ text: String) -> (list: Allowlist, tally: Tally) {
        var tally = Tally()
        var hosts = Set<String>()
        var networks: [String: IPRange] = [:]
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let field = line.prefix { $0 != "#" }.split(separator: ",", omittingEmptySubsequences: false).first ?? ""
            let value = field.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            guard !value.isEmpty else { continue }
            if let network = IPRange(value) {
                if networks.updateValue(network, forKey: network.text) != nil { tally.duplicates += 1 }
            } else if let host = DomainList.host(value) {
                if !hosts.insert(host).inserted { tally.duplicates += 1 }
            } else {
                tally.invalid += 1
                if tally.invalidLines.count < 3 { tally.invalidLines.append(index + 1) }
            }
        }
        let keptHosts = hosts.filter { host in
            host.split(separator: ".", maxSplits: 1).dropFirst().first.map { Config.entry(in: hosts, for: String($0)) == nil }
                ?? true
        }
        // Sorted by first address with the widest first, a range comes before the ranges inside it.
        // Two ranges are either nested or apart, so one inside the last kept range is covered.
        var kept: [IPRange] = []
        for network in networks.values.sorted(by: { ($0.bits, $0.first, $0.length) < ($1.bits, $1.first, $1.length) }) {
            if let last = kept.last, last.bits == network.bits, network.first <= last.last { continue }
            kept.append(network)
        }
        tally.covered = hosts.count - keptHosts.count + networks.count - kept.count
        tally.kept = keptHosts.count + kept.count
        var builder = AddressTable.Builder(fieldCount: 1)
        for network in kept { builder.add(network.text, row: [""]) }
        let list = Allowlist(entries: keptHosts.sorted() + kept.map(\.text), hosts: keptHosts, addresses: builder.finish())
        return (list, tally)
    }

    /// An empty list, which allows nothing.
    static let empty = parse("").list

    /// Whether the list covers the host, or holds the address or a range around it.
    func allows(host: String?, address: String?) -> Bool {
        if let host, Config.entry(in: hosts, for: host) != nil { return true }
        if let address, addresses.row(for: address) != nil { return true }
        return false
    }

    // An IP address or range. An address is a range of full length.
    private struct IPRange {
        let bits: Int
        let length: Int
        let first: UInt128
        let last: UInt128
        // The normalized form: the address alone at full length, else `prefix/length` with the host bits cleared.
        let text: String

        init?(_ value: String) {
            let parts = value.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count <= 2, let bytes = AddressTable.bytes(String(parts[0])) else { return nil }
            bits = bytes.count * 8
            guard let length = parts.count == 2 ? Int(parts[1]) : bits, (0...bits).contains(length) else { return nil }
            // A shift by the full 128 bits would overflow, so length 0 is its own case.
            let host = length == 0 ? UInt128.max >> (128 - bits) : (1 << (bits - length)) - 1
            let start = bytes.reduce(UInt128(0)) { $0 << 8 | UInt128($1) } & ~host
            let masked = Data((0..<bytes.count).map { UInt8(truncatingIfNeeded: start >> ((bytes.count - 1 - $0) * 8)) })
            guard let address = bits == 32 ? IPv4Address(masked).map({ "\($0)" }) : IPv6Address(masked).map({ "\($0)" })
            else { return nil }
            self.length = length
            first = start
            last = start | host
            text = length == bits ? address : "\(address)/\(length)"
        }
    }
}

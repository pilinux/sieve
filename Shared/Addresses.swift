import Foundation

/// What an IP address or host name is. The first that fits wins: public DNS, a DNS server a flow used, a local network,
/// a CDN, then the country and network owner from the uploaded IP data. A host name can only be public DNS.
nonisolated enum AddressLabel: Equatable, Sendable {
    case publicDNS(provider: String)
    /// A DNS server that a flow used on port 53 or 853.
    case dns(local: Bool)
    case local
    case cdn(provider: String)
    case country(code: String, asn: String, owner: String, domain: String)

    /// - Parameter dns: whether a flow to the address used port 53 or 853.
    @MainActor init?(
        _ value: String, dns: Bool = false, ipInfo: AddressTable?, publicDNS: PublicDNS = .bundled, cdn: AddressTable = .cdn
    ) {
        if let entry = publicDNS.entry(for: value) {
            self = .publicDNS(provider: entry.provider)
        } else if Address.normalize(value) == nil {
            return nil
        } else if dns {
            self = .dns(local: Address.isLocal(value))
        } else if Address.isLocal(value) {
            self = .local
        } else if let row = cdn.row(for: value) {
            self = .cdn(provider: row[0])
        } else if let row = ipInfo?.row(for: value), row[0].count == 2 {
            self = .country(code: row[0], asn: row[1], owner: row[2], domain: row[3])
        } else {
            return nil
        }
    }
}

/// One IP address, merged over every app that reached it.
nonisolated struct AddressRow: Identifiable, Equatable, Sendable {
    var id: String { address }
    let address: String
    /// The host name from the record seen last.
    var host: String?
    /// App keys, sorted.
    var apps: [String] = []
    /// Flows summed over the apps. Nil until a record has a count.
    var flows: Int?
    var last: Date?
    /// Each app's own flows and last flow, by app key. An app whose record has no count yet is left out.
    var appHits: [String: Hit] = [:]
    /// Whether a flow to it used port 53 or 853.
    var dns = false
}

extension Stats {
    /// Every app's `addresses`, merged into one row per address.
    func addressRows() -> [AddressRow] {
        var rows: [String: AddressRow] = [:]
        // The day and last flow of the record whose host name a row holds.
        var hostSeen: [String: (day: String, last: Date)] = [:]
        for (app, records) in addresses ?? [:] {
            for (address, record) in records {
                var row = rows[address] ?? AddressRow(address: address)
                row.apps.append(app)
                row.dns = row.dns || record.dns == true
                if let hits = record.hits {
                    row.appHits[app] = hits
                    row.flows = (row.flows ?? 0) + hits.count
                    row.last = max(row.last ?? hits.last, hits.last)
                }
                let seen = (day: record.day, last: record.hits?.last ?? .distantPast)
                if let host = record.host, hostSeen[address].map({ ($0.day, $0.last) < (seen.day, seen.last) }) ?? true {
                    row.host = host
                    hostSeen[address] = seen
                }
                rows[address] = row
            }
        }
        return rows.values.map {
            var row = $0
            row.apps.sort()
            return row
        }
    }
}

/// Flows summed by country, and by the kinds of address that have no single place.
struct FlowsByPlace: Equatable {
    struct Country: Equatable {
        var flows = 0
        var addresses = 0
        /// Flows by app key.
        var apps: [String: Int] = [:]
    }

    /// Kinds of address left off the map. A CDN or a DNS server answers from many places, and a local or unknown
    /// address has no country.
    enum OffMap: String, CaseIterable {
        case publicDNS = "Public DNS", dns = "DNS", local = "Local network", cdn = "CDN", none = "No country"
    }

    var countries: [String: Country] = [:]
    var offMap: [OffMap: Int] = [:]

    init(_ rows: [AddressRow], label: (AddressRow) -> AddressLabel?) {
        for row in rows {
            let flows = row.flows ?? 0
            let kind: OffMap
            switch label(row) {
            case .country(let code, _, _, _):
                countries[code, default: Country()].flows += flows
                countries[code, default: Country()].addresses += 1
                // An address's flows are not split by app, so each of its apps gets them all.
                for app in row.apps { countries[code, default: Country()].apps[app, default: 0] += flows }
                continue
            case .publicDNS: kind = .publicDNS
            case .dns: kind = .dns
            case .local: kind = .local
            case .cdn: kind = .cdn
            case nil: kind = .none
            }
            offMap[kind, default: 0] += flows
        }
    }
}

/// The Equal Earth map projection, which keeps areas true.
nonisolated enum EqualEarth {
    /// Takes degrees. Returns x from about -2.71 to 2.71 and y from about -1.32 to 1.32, with y up.
    static func project(longitude: Double, latitude: Double) -> (x: Double, y: Double) {
        let (a1, a2, a3, a4) = (1.340264, -0.081106, 0.000893, 0.003796)
        let theta = asin(3.0.squareRoot() / 2 * sin(latitude * .pi / 180))
        let t2 = theta * theta
        let t6 = t2 * t2 * t2
        let x = 2 * 3.0.squareRoot() * (longitude * .pi / 180) * cos(theta) / (3 * (9 * a4 * t6 * t2 + 7 * a3 * t6 + 3 * a2 * t2 + a1))
        return (x, theta * (a4 * t6 * t2 + a3 * t6 + a2 * t2 + a1))
    }
}

/// A country's outline, in Equal Earth coordinates.
nonisolated struct CountryShape: Sendable {
    /// The ISO 3166 alpha-2 code.
    let code: String
    let rings: [[(x: Double, y: Double)]]

    /// Reads one country per line: its code, then rings of `longitude,latitude` pairs, each ring after a `|`.
    /// Lines that start with `#` are comments. A point that does not parse is skipped.
    static func parse(_ text: String) -> [CountryShape] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let parts = line.split(separator: "|")
            guard parts.count > 1 else { return nil }
            let rings = parts.dropFirst().map { ring in
                ring.split(separator: " ").compactMap { point -> (x: Double, y: Double)? in
                    let values = point.split(separator: ",").compactMap { Double($0) }
                    return values.count == 2 ? EqualEarth.project(longitude: values[0], latitude: values[1]) : nil
                }
            }
            return CountryShape(code: String(parts[0]), rings: rings)
        }
    }
}

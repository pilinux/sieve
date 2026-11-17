import SwiftUI

/// Every IP address any app reached, as a table or as a world map shaded by flows.
struct AddressesView: View {
    let filter: Filter

    var body: some View {
        // The stats change every second as bytes come in. This view redraws only when the addresses or the IP data change.
        AddressesContent(
            addresses: filter.stats.addresses ?? [:], paths: filter.stats.paths, ipInfo: filter.ipInfo?.table,
            ipInfoDate: filter.ipInfo?.date
        )
        .equatable()
    }
}

private struct AddressesContent: View, Equatable {
    let addresses: [String: [String: Address]]
    let paths: [String: String]
    let ipInfo: AddressTable?
    let ipInfoDate: Date?
    @State private var showsMap = false
    @State private var query = ""
    // The country a click on the map narrowed the table to.
    @State private var country: String?
    @State private var order = [KeyPathComparator(\Line.flows, order: .reverse)]
    // Rows opened to one row per app, by address.
    @State private var open: Set<String> = []

    static func == (a: Self, b: Self) -> Bool {
        a.addresses == b.addresses && a.paths == b.paths && a.ipInfoDate == b.ipInfoDate
    }

    var body: some View {
        let names = Stats(paths: paths)
        let rows = Stats(addresses: addresses).addressRows()
        let lines = rows.map { Line(row: $0, label: AddressLabel($0.address, dns: $0.dns, ipInfo: ipInfo)) }
        let labels = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.label) })
        let places = FlowsByPlace(rows) { labels[$0.id] ?? nil }
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Kpi(title: "Addresses", value: rows.count.formatted()) {
                    Text("across \(counted(Set(rows.flatMap(\.apps)).count, "app"))")
                }
                Kpi(title: "Countries", value: places.countries.count.formatted()) {
                    Text(ipInfo == nil ? "needs IP data" : "from IP data")
                }
                Kpi(title: "Flows", value: rows.reduce(0) { $0 + ($1.flows ?? 0) }.formatted()) { Text("allowed or blocked") }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Segments(
                    options: [.init(value: false, label: "Table"), .init(value: true, label: "Map")], selection: showsMap
                ) { showsMap = $0 }
                if !showsMap {
                    SearchField(text: $query, prompt: "Search addresses").frame(width: 240)
                    if let country {
                        HStack(spacing: 4) {
                            Text(countryName(country))
                            IconButton(icon: "xmark", help: "Show every country") { self.country = nil }
                        }
                        .font(.aileron(12, .semibold))
                        .padding(.leading, 10)
                        .background(.s3, in: .capsule)
                    }
                }
                Spacer()
            }
            if showsMap {
                ScrollView { map(places) }
            } else {
                table(lines, names: names)
            }
        }
        .padding(EdgeInsets(top: 20, leading: 24, bottom: 28, trailing: 24))
    }

    private func table(_ lines: [Line], names: Stats) -> some View {
        // Ignore case and accents, as the other searches do.
        let shown = lines.filter { line in
            (country == nil || line.code == country)
                && (query.isEmpty || [line.address, line.host, line.labelName].contains { $0.localizedStandardContains(query) })
        }
        .sorted(using: order)
        let most = Double(max(lines.map(\.flows).max() ?? 1, 1))
        return Table(of: Line.self, sortOrder: $order) {
            TableColumn("Address", value: \.sortAddress) { line in
                if let app = line.app {
                    HStack(spacing: 8) {
                        AppIcon(path: paths[app], size: 20)
                        Text(names.name(app))
                    }
                    .padding(.leading, 18)
                } else {
                    HStack(spacing: 6) {
                        Button {
                            toggle(line.id)
                        } label: {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.ink3)
                                .rotationEffect(.degrees(open.contains(line.id) ? 90 : 0))
                                .frame(width: 12, height: 18)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help("Show each app")
                        Copyable(text: line.address).monospacedDigit()
                    }
                }
            }
            .width(min: 120, ideal: 160)
            TableColumn("Label", value: \.labelKey) { line in
                if line.app == nil { AddressFact(value: line.address, dns: line.row.dns, ipInfo: ipInfo) }
            }
            .width(min: 120, ideal: 240)
            TableColumn("Host", value: \.host) { line in
                if line.app == nil {
                    if line.host.isEmpty {
                        Text("–").foregroundStyle(.ink3)
                    } else {
                        Copyable(text: line.host).foregroundStyle(.ink2).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            TableColumn("Apps", value: \.appCount) { line in
                if line.app == nil {
                    Button {
                        toggle(line.id)
                    } label: {
                        HStack(spacing: -6) {
                            ForEach(line.row.apps.prefix(3), id: \.self) { AppIcon(path: paths[$0], size: 20) }
                            if line.row.apps.count > 3 {
                                Text("+\(line.row.apps.count - 3)").font(.aileron(11)).foregroundStyle(.ink3).padding(.leading, 10)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("\(line.row.apps.map(names.name).sorted().joined(separator: ", ")). Click to show each app's flows.")
                }
            }
            .width(min: 60, ideal: 90)
            TableColumn("Flows", value: \.flows) { line in
                HStack(spacing: 8) {
                    UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4).fill(.allow)
                        .frame(width: line.flows > 0 ? max(2, 64 * Double(line.flows) / most) : 0, height: 8)
                    Text(line.flows < 0 ? "–" : line.flows.formatted()).monospacedDigit()
                }
            }
            .width(min: 90, ideal: 130)
            TableColumn("Last flow", value: \.last) { line in
                Text(line.lastFlow.map { $0.formatted(.relative(presentation: .named)) } ?? "–").foregroundStyle(.ink2)
            }
            .width(min: 80, ideal: 110)
        } rows: {
            ForEach(
                shown.flatMap { line in
                    [line]
                        + (open.contains(line.id)
                            ? line.row.apps.map { line.child($0) }
                                .sorted { ($0.flows, names.name($1.app ?? "")) > ($1.flows, names.name($0.app ?? "")) } : [])
                }
            ) { TableRow($0) }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .card(padding: 8)
        .overlay {
            if shown.isEmpty {
                Text(lines.isEmpty ? "No addresses yet. An address shows up when an app connects to it." : "No addresses match.")
                    .foregroundStyle(.ink3)
            }
        }
    }

    private func toggle(_ id: String) {
        if open.remove(id) == nil { open.insert(id) }
    }

    private func map(_ places: FlowsByPlace) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Caption("Flows by country")
                    Spacer()
                    HStack(spacing: 6) {
                        Text("Fewer")
                        ForEach(WorldMap.shades, id: \.self) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.allow.opacity($0)).frame(width: 10, height: 10)
                        }
                        Text("More")
                    }
                    .font(.aileron(12)).foregroundStyle(.ink2)
                }
                WorldMap(places: places, paths: paths) { code in
                    country = code
                    showsMap = false
                }
                if ipInfo == nil {
                    Label(
                        "Upload an IPinfo Lite file on the Lists screen to place addresses in countries.",
                        systemImage: "square.and.arrow.up"
                    )
                    .font(.aileron(11)).foregroundStyle(.ink3)
                } else {
                    Text("Countries from IP data by [IPinfo](https://ipinfo.io) · Map: Natural Earth").font(.aileron(11)).foregroundStyle(
                        .ink3)
                }
            }
            .card()
            VStack(alignment: .leading, spacing: 10) {
                Caption("Not on the map")
                Text("These have no single place, so the map leaves them out.").font(.aileron(12)).foregroundStyle(.ink3)
                ForEach(FlowsByPlace.OffMap.allCases, id: \.self) { kind in
                    HStack {
                        Text(kind.rawValue)
                        Spacer()
                        Text((places.offMap[kind] ?? 0).formatted()).font(.aileron(13, .semibold)).monospacedDigit()
                    }
                }
                Divider()
                HStack {
                    Text("Total")
                    Spacer()
                    Text(places.offMap.values.reduce(0, +).formatted()).font(.aileron(13, .semibold)).monospacedDigit()
                }
            }
            .frame(width: 260)
            .card()
        }
    }
}

// One table row: an address, or one app's share under an opened address. Each sortable column reads a property here.
private nonisolated struct Line: Identifiable, Sendable {
    let row: AddressRow
    let label: AddressLabel?
    /// The app of a row under an opened address. Nil for the address's own row.
    var app: String?
    var id: String { app.map { "\(row.address)\n\($0)" } ?? row.address }
    var address: String { row.address }
    var host: String { row.host ?? "" }
    var appCount: Int { row.apps.count }
    // A row with no count sorts below one with 0 flows.
    var flows: Int { (app.map { row.appHits[$0]?.count } ?? row.flows) ?? -1 }
    var lastFlow: Date? { app.map { row.appHits[$0]?.last } ?? row.last }
    var last: Date { lastFlow ?? .distantPast }

    func child(_ app: String) -> Line {
        Line(row: row, label: nil, app: app)
    }
    var code: String? {
        if case .country(let code, _, _, _) = label { code } else { nil }
    }

    // Sorts IPv4 before IPv6, each by number rather than by text.
    var sortAddress: String {
        let bytes = AddressTable.bytes(address) ?? []
        return "\(bytes.count)" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    // The words a search can match: the provider, or the country and owner.
    var labelName: String {
        switch label {
        case .publicDNS(let provider), .cdn(let provider): provider
        case .country(let code, _, let owner, _): "\(countryName(code)) \(code) \(owner)"
        default: ""
        }
    }

    // Sorts by kind, then by name.
    var labelKey: String {
        switch label {
        case .publicDNS: "0 \(labelName)"
        case .dns: "1"
        case .local: "2"
        case .cdn: "3 \(labelName)"
        case .country: "4 \(labelName)"
        case nil: "5"
        }
    }
}

/// A world map with each country shaded by the flows to its addresses. It is drawn here, so no map service sees the traffic.
private struct WorldMap: View {
    let places: FlowsByPlace
    let paths: [String: String]
    let select: (String) -> Void
    @State private var hover: (code: String, at: CGPoint)?
    // Zoom from 1 to 8 times, and how far a drag moved the zoomed map, in points.
    @State private var zoom: CGFloat = 1
    @State private var pan = CGSize.zero
    // The zoom and the pan when the current pinch or drag began.
    @State private var pinchStart: CGFloat?
    @State private var dragStart: CGSize?

    /// Five steps of the traffic blue, from the quietest country to the busiest.
    static let shades = [0.22, 0.38, 0.55, 0.75, 1.0]

    // Each country's outline in Equal Earth units, with y down as on screen.
    private static let outlines: [(code: String, path: Path)] = CountryShape.parse(Bundle.main.text("countries", "txt") ?? "")
        .map { shape in
            (
                shape.code,
                Path { path in
                    for ring in shape.rings {
                        path.addLines(ring.map { CGPoint(x: $0.x, y: -$0.y) })
                        path.closeSubpath()
                    }
                }
            )
        }
    private static let bounds = outlines.reduce(CGRect.null) { $0.union($1.path.boundingRect) }

    var body: some View {
        let shade = shades()
        GeometryReader { geometry in
            let size = geometry.size
            let transform = Self.transform(size).concatenating(viewing(size))
            Canvas { context, _ in
                for (code, path) in Self.outlines {
                    let shape = path.applying(transform)
                    context.fill(shape, with: .color(shade[code].map { Color.allow.opacity($0) } ?? .s3))
                    context.stroke(shape, with: .color(code == hover?.code ? .ink : .bg), lineWidth: code == hover?.code ? 1 : 0.5)
                }
            }
            .onContinuousHover { phase in
                if case .active(let point) = phase, let code = Self.country(at: point, transform) {
                    hover = (code, point)
                } else {
                    hover = nil
                }
            }
            .onTapGesture { point in
                if let code = Self.country(at: point, transform), places.countries[code] != nil { select(code) }
            }
            // A drag of 3 points or more pans, so a click still picks a country.
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { drag in
                        let from = dragStart ?? pan
                        dragStart = from
                        pan = clamped(
                            CGSize(width: from.width + drag.translation.width, height: from.height + drag.translation.height), size)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { pinch in
                        let from = pinchStart ?? zoom
                        pinchStart = from
                        setZoom(from * pinch.magnification, size)
                    }
                    .onEnded { _ in pinchStart = nil }
            )
            .clipShape(.rect(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 4) {
                    IconButton(icon: "plus", help: "Zoom in") { setZoom(zoom * 1.5, size) }
                    IconButton(icon: "minus", help: "Zoom out") { setZoom(zoom / 1.5, size) }
                    if zoom > 1 { IconButton(icon: "arrow.counterclockwise", help: "Reset the map") { setZoom(1, size) } }
                }
                .padding(4)
                .background(.s2, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.line2))
                .padding(8)
            }
            .overlay(alignment: .topLeading) {
                if let hover { tip(hover.code).offset(x: hover.at.x + 14, y: hover.at.y + 14).allowsHitTesting(false) }
            }
        }
        .aspectRatio(Self.bounds.width / Self.bounds.height, contentMode: .fit)
    }

    // Zooms around the centre of the view, then moves by the pan.
    private func viewing(_ size: CGSize) -> CGAffineTransform {
        let pan = clamped(pan, size)
        return CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
            .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
            .concatenating(CGAffineTransform(translationX: size.width / 2 + pan.width, y: size.height / 2 + pan.height))
    }

    // A pan can move the map only as far as the zoom pushed it off screen, so no empty edge shows.
    private func clamped(_ pan: CGSize, _ size: CGSize) -> CGSize {
        let x = size.width * (zoom - 1) / 2
        let y = size.height * (zoom - 1) / 2
        return CGSize(width: min(max(pan.width, -x), x), height: min(max(pan.height, -y), y))
    }

    private func setZoom(_ next: CGFloat, _ size: CGSize) {
        zoom = min(max(next, 1), 8)
        pan = clamped(pan, size)
    }

    // Scales the map to fit the view, centred.
    private static func transform(_ size: CGSize) -> CGAffineTransform {
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let x = (size.width - bounds.width * scale) / 2 - bounds.minX * scale
        let y = (size.height - bounds.height * scale) / 2 - bounds.minY * scale
        return CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale)
    }

    private static func country(at point: CGPoint, _ transform: CGAffineTransform) -> String? {
        let point = point.applying(transform.inverted())
        return outlines.first { $0.path.contains(point) }?.code
    }

    // A log scale, so a few busy countries do not leave the rest in the faintest step.
    private func shades() -> [String: Double] {
        let totals = places.countries.mapValues { log10(Double(max($0.flows, 1))) }
        guard let low = totals.values.min(), let high = totals.values.max() else { return [:] }
        let span = high - low > 0 ? high - low : 1
        return totals.mapValues { Self.shades[min(4, Int((($0 - low) / span) * 5))] }
    }

    private func tip(_ code: String) -> some View {
        let place = places.countries[code]
        let names = Stats(paths: paths)
        let busiest = (place?.apps ?? [:]).sorted { $0.value > $1.value }.prefix(3).map { names.name($0.key) }
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(flag(code)) \(countryName(code))").font(.aileron(12, .semibold))
            if let place {
                Text("\(counted(place.addresses, "address")) · \(counted(place.flows, "flow"))").monospacedDigit()
                Text(busiest.joined(separator: ", ")).foregroundStyle(.ink3)
            } else {
                Text("No addresses").foregroundStyle(.ink3)
            }
        }
        .font(.aileron(11))
        .padding(8)
        .background(.s2, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.line2))
        .fixedSize()
    }
}

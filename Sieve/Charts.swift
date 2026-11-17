import Charts
import SwiftUI

// The value comes first, then the label.
private struct Tooltip: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.aileron(12, .semibold)).monospacedDigit().foregroundStyle(.ink)
            Text(label).font(.aileron(12)).foregroundStyle(.ink2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.tip, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.line2))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
        .fixedSize()
    }
}

private extension View {
    func hoverX<X: Plottable>(_ selection: Binding<X?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear.contentShape(.rect).onContinuousHover { phase in
                    guard case .active(let point) = phase, let frame = proxy.plotFrame else {
                        selection.wrappedValue = nil
                        return
                    }
                    selection.wrappedValue = proxy.value(atX: point.x - geometry[frame].minX, as: X.self)
                }
            }
        }
    }
}

private func niceMax(_ value: Double) -> Double {
    guard value > 0 else { return 1 }
    let power = pow(10, floor(log10(value)))
    return [1, 1.5, 2, 3, 4, 5, 6, 8, 10].map { $0 * power }.first { $0 >= value } ?? value
}

/// A live rate line, one point per second. The last point is now.
struct RateLine: View {
    let values: [Double]
    var hover = false
    @State private var selected: Int?

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        let points = Array(values.enumerated())
        // A vectorized plot draws the whole series as one mark. One mark per point costs far more on every update.
        Chart {
            AreaPlot(points, x: .value("Second", \.offset), y: .value("Rate", \.element))
                .foregroundStyle(Color.allow.opacity(0.12))
            LinePlot(points, x: .value("Second", \.offset), y: .value("Rate", \.element))
                .foregroundStyle(Color.allow)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let last = values.indices.last {
                PointMark(x: .value("Second", last), y: .value("Rate", values[last]))
                    .foregroundStyle(Color.allow)
                    .symbolSize(30)
            }
            if hover, let selected, values.indices.contains(selected) {
                RuleMark(x: .value("Second", selected))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        let ago = values.count - 1 - selected
                        Tooltip(value: rate(values[selected]), label: ago == 0 ? "Now" : "\(ago) s ago")
                    }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(values.count - 1, 1))
        .chartYScale(domain: 0...top * 1.05)
        .chartLegend(.hidden)
        .hoverX($selected)
    }
}

/// One bar per day from one baseline, with an optional limit line.
/// A cumulative chart starts each bar where the previous one ended, like a waterfall.
struct DayBars: View, Equatable {
    struct Bar: Identifiable, Equatable {
        let id: String
        /// The tooltip text after the value: the date, and any lines before it.
        let label: String
        let value: Double
        /// The date under the axis. Only some bars have one.
        var tick: String?
        var color: Color?
        /// Parts stacked from the bottom up, instead of one bar.
        var parts: [SegmentBar.Part]?
    }

    let bars: [Bar]
    /// Every day on the axis, when the axis runs past the last bar.
    var domain: [String]?
    var color: Color = .allow
    var limit: Double?
    var cumulative = false
    let format: (Double) -> String
    @State private var hovered: String?

    // A closure cannot be compared. Each caller always passes the same `format`, so the data alone decides a redraw.
    static func == (lhs: DayBars, rhs: DayBars) -> Bool {
        lhs.bars == rhs.bars && lhs.domain == rhs.domain && lhs.color == rhs.color && lhs.limit == rhs.limit
            && lhs.cumulative == rhs.cumulative
    }

    var body: some View {
        let starts = bars.indices.map { cumulative ? bars[..<$0].reduce(0) { $0 + $1.value } : 0 }
        let total = bars.reduce(0) { $0 + $1.value }
        let top = niceMax(max(cumulative ? total : bars.map(\.value).max() ?? 0, (limit ?? 0) * 1.08))
        Chart {
            ForEach(segments(starts)) { segment in
                // Round only the top of a column.
                let top: CGFloat = cumulative ? 2 : segment.top ? 4 : 0
                BarMark(
                    x: .value("Day", segment.bar),
                    yStart: .value("From", segment.from),
                    yEnd: .value("To", segment.to),
                    width: .ratio(0.8)
                )
                .foregroundStyle(segment.color)
                .opacity(hovered == nil || hovered == segment.bar ? 1 : 0.7)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: top, bottomLeadingRadius: cumulative ? 2 : 0,
                        bottomTrailingRadius: cumulative ? 2 : 0, topTrailingRadius: top)
                )
                .annotation(position: .trailing, alignment: .center) {
                    if cumulative, segment.bar == bars.last?.id {
                        Text(format(total)).font(.aileron(11, .semibold)).foregroundStyle(.ink).fixedSize()
                    }
                }
            }
            if let limit {
                RuleMark(y: .value("Limit", limit))
                    .foregroundStyle(Color.ink2)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Limit \(format(limit))").font(.aileron(11, .semibold)).foregroundStyle(.ink)
                    }
            }
            if let hovered, let bar = bars.first(where: { $0.id == hovered }) {
                RuleMark(x: .value("Day", hovered))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Tooltip(value: format(bar.value), label: bar.label)
                    }
            }
        }
        .chartXScale(domain: domain ?? bars.map(\.id))
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks(values: bars.filter { $0.tick != nil }.map(\.id)) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let tick = bars.first(where: { $0.id == id })?.tick {
                        Text(tick).font(.aileron(11)).foregroundStyle(.ink3)
                    }
                }
            }
        }
        .chartYAxis {
            // With no data, show only the baseline. Half and full marks on an empty scale would mean nothing.
            AxisMarks(position: .leading, values: bars.contains { $0.value > 0 } || limit != nil ? [0, top / 2, top] : [0]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.white.opacity(value.index == 0 ? 0.16 : 0.06))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(format(number)).font(.aileron(11)).foregroundStyle(.ink3).monospacedDigit()
                    }
                }
            }
        }
        .hoverX($hovered)
    }

    // One piece of a column: the whole bar, or one of its parts.
    private struct Segment: Identifiable {
        let id: String
        let bar: String
        let from: Double
        let to: Double
        let color: Color
        let top: Bool
    }

    private func segments(_ starts: [Double]) -> [Segment] {
        bars.enumerated().flatMap { index, bar in
            let parts = bar.parts?.filter { $0.value > 0 } ?? []
            var from = starts[index]
            guard !parts.isEmpty else {
                return [Segment(id: bar.id, bar: bar.id, from: from, to: from + bar.value, color: bar.color ?? color, top: true)]
            }
            return parts.enumerated().map { part, piece in
                let segment = Segment(
                    id: "\(bar.id) \(part)", bar: bar.id, from: from, to: from + Double(piece.value), color: piece.color,
                    top: part == parts.count - 1)
                from = segment.to
                return segment
            }
        }
    }
}

/// One row of `RankedBars`.
struct RankedItem: Identifiable {
    // Two apps can have the same name, but never the same key.
    var id: String { key.isEmpty ? name : key }
    /// The app key, when the item is an app.
    var key = ""
    let name: String
    let value: Double
    let text: String
}

/// Ranked horizontal bars in one hue, largest first.
struct RankedBars<Leading: View>: View {
    let items: [RankedItem]
    var color: Color = .allow
    /// Puts the bar under the name, for narrow cards.
    var stacked = false
    var nameWidth: CGFloat = 120
    var valueWidth: CGFloat = 68
    /// Whether the names, or the names in the lines under a row, are hosts that copy themselves on a click.
    var copiesNames = false
    var copiesDetails = false
    /// Lines that a click on a row shows under it. Nil means the rows do not expand.
    var details: ((RankedItem) -> [(name: String, text: String)])?
    @ViewBuilder let leading: (RankedItem) -> Leading
    @State private var expanded: String?

    var body: some View {
        let top = max(items.map(\.value).max() ?? 0, 1)
        VStack(spacing: stacked ? 12 : 9) {
            ForEach(items) { item in
                VStack(spacing: 6) {
                    row(item, top: top)
                        .contentShape(.rect)
                        .onTapGesture {
                            guard details != nil else { return }
                            expanded = expanded == item.id ? nil : item.id
                        }
                    if expanded == item.id, let details {
                        let lines = details(item)
                        // Two apps can have the same name, so the index is the identity.
                        ForEach(lines.indices, id: \.self) { index in
                            HStack {
                                label(lines[index].name, copies: copiesDetails).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(lines[index].text).monospacedDigit()
                            }
                            .font(.aileron(12)).foregroundStyle(.ink2)
                            .padding(.leading, 32)
                        }
                    }
                }
            }
        }
    }

    // A click on a host copies it. A click anywhere else in the row still opens or closes it.
    @ViewBuilder private func label(_ text: String, copies: Bool) -> some View {
        if copies { Copyable(text: text) } else { Text(text) }
    }

    @ViewBuilder private func row(_ item: RankedItem, top: Double) -> some View {
        let bar = GeometryReader { geometry in
            UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                .fill(color)
                .frame(width: max(2, geometry.size.width * item.value / top))
        }
        .frame(height: 8)
        if stacked {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    leading(item)
                    label(item.name, copies: copiesNames).font(.aileron(13, .semibold)).lineLimit(1)
                    Spacer()
                    Text(item.text).foregroundStyle(.ink2).monospacedDigit()
                }
                bar.padding(.leading, 32)
            }
        } else {
            HStack(spacing: 10) {
                leading(item)
                label(item.name, copies: copiesNames).font(.aileron(13, .semibold)).lineLimit(1).truncationMode(.middle)
                    .frame(width: nameWidth, alignment: .leading)
                bar
                Text(item.text).foregroundStyle(.ink2).monospacedDigit().frame(width: valueWidth, alignment: .trailing)
            }
        }
    }
}

/// A bar that splits a whole into parts. A tall bar shows each part's value inside it.
struct SegmentBar: View {
    struct Part: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let value: Int
        let color: Color
        /// Use dark text, because the fill is light.
        var dark = false
    }

    let parts: [Part]
    var tall = false

    var body: some View {
        let shown = parts.filter { $0.value > 0 }
        let total = shown.reduce(0) { $0 + $1.value }
        GeometryReader { geometry in
            let width = geometry.size.width - CGFloat(max(shown.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, part in
                    let first = index == 0 || tall
                    let last = index == shown.count - 1 || tall
                    let share = Double(part.value) / Double(max(total, 1))
                    UnevenRoundedRectangle(
                        topLeadingRadius: first ? 4 : 0, bottomLeadingRadius: first ? 4 : 0,
                        bottomTrailingRadius: last ? 4 : 0, topTrailingRadius: last ? 4 : 0
                    )
                    .fill(part.color)
                    .frame(width: max(3, width * share))
                    .overlay(alignment: .leading) {
                        if tall, share > 0.06 {
                            Text("\(part.value)").font(.aileron(12, .bold))
                                .foregroundStyle(part.dark ? Color(hex: 0x0B0B0B) : .white)
                                .padding(.leading, 8)
                        }
                    }
                    .help("\(part.name): \(part.value), \(Int((share * 100).rounded())) %")
                }
            }
        }
        .frame(height: tall ? 28 : 8)
        .background { if total == 0 { Capsule().fill(.s3) } }
    }
}

/// A colour key for each part, in order.
struct Legend: View {
    let parts: [(name: String, color: Color)]

    var body: some View {
        HStack(spacing: 16) {
            // Identify parts by position, since two profiles can have the same name.
            ForEach(parts.indices, id: \.self) { index in
                let part = parts[index]
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(part.color).frame(width: 10, height: 10)
                    Text(part.name)
                }
            }
        }
        .font(.aileron(12))
        .foregroundStyle(.ink2)
        .lineLimit(1)
    }
}

/// Usage against a limit. It turns to warning at 80 % and critical at 100 %.
struct Meter: View {
    let used: Int
    let limit: Int

    var body: some View {
        let share = Double(used) / Double(max(limit, 1))
        let tone: Color = share >= 1 ? .crit : share >= 0.8 ? .warn : .allow
        GeometryReader { geometry in
            Capsule().fill(tone.opacity(0.18)).overlay(alignment: .leading) {
                Capsule().fill(tone).frame(width: geometry.size.width * min(share, 1))
            }
        }
        .frame(height: 8)
    }
}

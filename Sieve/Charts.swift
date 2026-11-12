import Charts
import SwiftUI

// The value leads, the label follows.
struct Tooltip: View {
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

extension View {
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

func niceMax(_ value: Double) -> Double {
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
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { second, value in
                AreaMark(x: .value("Second", second), y: .value("Rate", value))
                    .foregroundStyle(Color.allow.opacity(0.12))
                LineMark(x: .value("Second", second), y: .value("Rate", value))
                    .foregroundStyle(Color.allow)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
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
/// A cumulative chart floats each bar on the sum before it: a waterfall.
struct DayBars: View {
    struct Bar: Identifiable {
        let id: String
        /// The day in the tooltip.
        let label: String
        let value: Double
        /// The day under the axis, on some bars only.
        var tick: String?
        var color: Color?
    }

    let bars: [Bar]
    /// Every day on the axis, when it runs past the last bar.
    var domain: [String]?
    var color: Color = .allow
    var limit: Double?
    var cumulative = false
    let format: (Double) -> String
    @State private var hovered: String?

    var body: some View {
        let starts = bars.indices.map { cumulative ? bars[..<$0].reduce(0) { $0 + $1.value } : 0 }
        let total = bars.reduce(0) { $0 + $1.value }
        let top = niceMax(max(cumulative ? total : bars.map(\.value).max() ?? 0, (limit ?? 0) * 1.08))
        Chart {
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                BarMark(
                    x: .value("Day", bar.id),
                    yStart: .value("From", starts[index]),
                    yEnd: .value("To", starts[index] + bar.value),
                    width: .ratio(0.8)
                )
                .foregroundStyle(bar.color ?? color)
                .opacity(hovered == nil || hovered == bar.id ? 1 : 0.7)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: cumulative ? 2 : 4, bottomLeadingRadius: cumulative ? 2 : 0,
                                                  bottomTrailingRadius: cumulative ? 2 : 0, topTrailingRadius: cumulative ? 2 : 4))
                .annotation(position: .trailing, alignment: .center) {
                    if cumulative, index == bars.count - 1 {
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
            AxisMarks(position: .leading, values: [0, top / 2, top]) { value in
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
}

/// One row of `RankedBars`.
struct RankedItem: Identifiable {
    var id: String { name }
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
    /// The bar sits under the name, for narrow cards.
    var stacked = false
    var nameWidth: CGFloat = 120
    @ViewBuilder let leading: (RankedItem) -> Leading

    var body: some View {
        let top = max(items.map(\.value).max() ?? 0, 1)
        VStack(spacing: stacked ? 12 : 9) {
            ForEach(items) { item in
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
                            Text(item.name).font(.aileron(13, .semibold)).lineLimit(1)
                            Spacer()
                            Text(item.text).foregroundStyle(.ink2).monospacedDigit()
                        }
                        bar.padding(.leading, 32)
                    }
                } else {
                    HStack(spacing: 10) {
                        leading(item)
                        Text(item.name).font(.aileron(13, .semibold)).lineLimit(1).truncationMode(.middle)
                            .frame(width: nameWidth, alignment: .leading)
                        bar
                        Text(item.text).foregroundStyle(.ink2).monospacedDigit().frame(width: 68, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// One whole split into parts. A tall bar prints each part's value inside it.
struct SegmentBar: View {
    struct Part: Identifiable {
        var id: String { name }
        let name: String
        let value: Int
        let color: Color
        /// Dark text on a light fill.
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
            ForEach(parts, id: \.name) { part in
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

/// Use against a limit. Warns from 80 %, turns critical at 100 %.
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

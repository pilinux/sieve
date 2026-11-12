import SwiftUI

struct MenuView: View {
    let filter: Filter

    var body: some View {
        let blocked = lastDays(7).map { (day: $0, count: filter.stats.blocked[Stats.day($0)] ?? 0) }
        let most = Double(max(blocked.map(\.count).max() ?? 0, 1))
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 17)).foregroundStyle(.allow)
                Text("Sieve").font(.aileron(15, .bold))
                Spacer()
                ModePicker(filter: filter)
            }
            VStack(alignment: .leading, spacing: 6) {
                Caption("Now")
                Text(rate(filter.rates.values.reduce(0, +))).font(.aileron(52, .light)).monospacedDigit()
                RateLine(values: filter.trend(nil), hover: true).frame(height: 64)
            }
            Rectangle().fill(.line).frame(height: 1)
            VStack(spacing: 0) {
                ForEach(filter.rates.sorted { $0.value > $1.value }.prefix(5), id: \.key) { app, _ in
                    AppRow(filter: filter, app: app)
                }
            }
            Rectangle().fill(.line).frame(height: 1)
            HStack(alignment: .bottom) {
                Caption("Blocked today")
                Spacer()
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(blocked, id: \.day) { day in
                        UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                            .fill(Color.block.opacity(day.day == blocked.last?.day ? 1 : 0.45))
                            .frame(width: 8, height: max(2, 24 * Double(day.count) / most))
                            .help("\(day.count) blocked, \(day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    }
                }
                .frame(height: 24, alignment: .bottom)
                Text("\(blocked.last?.count ?? 0)").font(.aileron(20, .light)).monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        .padding(16)
        .frame(width: 400)
        .font(.aileron(13))
        .foregroundStyle(.ink)
        .preferredColorScheme(.dark)
        .task { await filter.poll() }
    }
}

import SwiftUI

struct MenuView: View {
    let filter: Filter

    var body: some View {
        VStack(alignment: .leading) {
            ModePicker(filter: filter)
            Text("Total \(rate(filter.rates.values.reduce(0, +)))")
            ForEach(filter.rates.sorted { $0.value > $1.value }.prefix(5), id: \.key) { app, _ in
                AppSwitch(filter: filter, app: app)
            }
            Text("Blocked today: \(filter.stats.blocked[Stats.day(.now)] ?? 0)")
        }
        .padding()
        .frame(width: 400)
        .task { await filter.poll() }
    }
}

struct ModePicker: View {
    let filter: Filter

    var body: some View {
        Picker("Mode", selection: Binding(get: { filter.config.mode }, set: { mode in filter.update { $0.mode = mode } })) {
            Text("Off").tag(Mode.off)
            Text("Ask").tag(Mode.ask)
            Text("Quiet").tag(Mode.quiet)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

/// An app's allow switch, with its rate and total.
struct AppSwitch: View {
    let filter: Filter
    let app: String

    var body: some View {
        Toggle(isOn: Binding(
            get: { filter.config.action(for: app) != .block },
            set: { on in filter.update { $0.setAction(on ? .allow : .block, for: app) } }
        )) {
            HStack {
                Text(app).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(rate(filter.rates[app] ?? 0)).monospacedDigit()
                Text(Int64(filter.stats.bytes[app] ?? 0).formatted(.byteCount(style: .file))).monospacedDigit()
            }
        }
    }
}

private func rate(_ bytesPerSecond: Double) -> String {
    Int64(bytesPerSecond).formatted(.byteCount(style: .file)) + "/s"
}

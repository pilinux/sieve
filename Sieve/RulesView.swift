import SwiftUI

struct RulesView: View {
    let filter: Filter

    var body: some View {
        List(filter.config.rules) { rule in
            let hit = filter.stats.hits[rule.id]
            HStack {
                VStack(alignment: .leading) {
                    Text(rule.app).lineLimit(1).truncationMode(.middle)
                    Text(rule.host ?? "All hosts").foregroundStyle(.secondary)
                }
                Spacer()
                if let flag = filter.stats.flags[rule.id] {
                    Text(flag.rawValue).foregroundStyle(.orange)
                }
                Text(rule.action == .allow ? "Allow" : "Block")
                Picker("Profile", selection: profile(rule.id)) {
                    Text("Always").tag(nil as UUID?)
                    ForEach(filter.config.profiles) { Text($0.name).tag($0.id as UUID?) }
                }
                .labelsHidden()
                .fixedSize()
                Text("\(hit?.count ?? 0) hits").monospacedDigit()
                Text(hit.map { $0.last.formatted(.relative(presentation: .named)) } ?? "Never")
                    .foregroundStyle(.secondary)
                Button("Delete") { filter.update { $0.rules.removeAll { $0.id == rule.id } } }
            }
        }
    }

    private func profile(_ id: UUID) -> Binding<UUID?> {
        Binding(
            get: { filter.config.rules.first { $0.id == id }?.profile },
            set: { profile in
                filter.update { config in
                    if let index = config.rules.firstIndex(where: { $0.id == id }) { config.rules[index].profile = profile }
                }
            }
        )
    }
}

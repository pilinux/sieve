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
                Text("\(hit?.count ?? 0) hits").monospacedDigit()
                Text(hit.map { $0.last.formatted(.relative(presentation: .named)) } ?? "Never")
                    .foregroundStyle(.secondary)
                Button("Delete") { filter.update { $0.rules.removeAll { $0.id == rule.id } } }
            }
        }
    }
}

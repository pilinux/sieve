import SwiftUI

struct ListsView: View {
    let filter: Filter
    @State private var url = ""
    @State private var action = Action.block

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("https or file URL", text: $url)
                Picker("Action", selection: $action) {
                    Text("Allow").tag(Action.allow)
                    Text("Block").tag(Action.block)
                }
                .fixedSize()
                Button("Add") { add() }
                    .disabled(!["https", "file"].contains(URL(string: url)?.scheme))
            }
            List(filter.config.lists) { list in
                HStack {
                    Toggle(list.name, isOn: enabled(list.id))
                    Spacer()
                    Text(list.action == .allow ? "Allow" : "Block")
                    Button("Refresh") { Task { await filter.load(list) } }
                }
            }
        }
    }

    private func add() {
        guard let parsed = URL(string: url) else { return }
        let list = DomainList(name: parsed.host() ?? parsed.lastPathComponent, url: url, action: action)
        filter.update { $0.lists.append(list) }
        url = ""
        Task { await filter.load(list) }
    }

    private func enabled(_ id: String) -> Binding<Bool> {
        Binding(
            get: { filter.config.lists.first { $0.id == id }?.enabled ?? false },
            set: { on in filter.update { config in
                if let index = config.lists.firstIndex(where: { $0.id == id }) { config.lists[index].enabled = on }
            } }
        )
    }
}

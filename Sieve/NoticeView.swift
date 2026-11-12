import AppKit
import SwiftUI

/// Shows while the extension holds a config file it could not read. `compact` stacks it for the menu.
struct BrokenConfigNotice: View {
    let filter: Filter
    var compact = false
    @State private var discarding = false

    var body: some View {
        let layout = compact ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(alignment: compact ? .top : .center, spacing: 12) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.serious)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sieve could not read its config").font(.aileron(13, .semibold))
                    Text("It started with defaults. Your rules, lists, limits, and profiles are not in use.")
                        .font(.aileron(12)).foregroundStyle(.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button {
                    Task { await save() }
                } label: {
                    Label("Save a copy…", systemImage: "square.and.arrow.down").frame(maxWidth: compact ? .infinity : nil)
                }
                Button {
                    discarding = true
                } label: {
                    Text("Discard").frame(maxWidth: compact ? .infinity : nil)
                }
                .confirmationDialog("Discard the broken config?", isPresented: $discarding) {
                    Button("Discard", role: .destructive) { Task { await filter.discardBrokenConfig() } }
                } message: {
                    Text("Sieve deletes the file. Your old rules cannot be recovered from it.")
                }
            }
        }
        .padding(EdgeInsets(top: compact ? 12 : 10, leading: compact ? 12 : 16, bottom: compact ? 12 : 10, trailing: compact ? 12 : 10))
        .background(Color.crit.opacity(0.16), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.crit.opacity(0.5)))
    }

    private func save() async {
        guard let data = await filter.brokenConfig(), !data.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "config.json.broken"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            NSApp.presentError(error)
        }
    }
}

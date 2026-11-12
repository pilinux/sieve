import SwiftUI

/// What Ask mode shows when an unknown app connects.
struct PromptView: View {
    let filter: Filter
    let app: String
    /// Empty when the flow has no host name.
    let host: String
    let answer: (Action, Bool) -> Void
    @State private var hostOnly = false

    var body: some View {
        VStack(spacing: 14) {
            AppIcon(path: filter.stats.paths[app], size: 56)
            VStack(spacing: 2) {
                Text(filter.stats.name(app)).font(.aileron(15, .bold))
                Text("wants to connect").foregroundStyle(.ink2)
            }
            HStack(spacing: 8) {
                if host.isEmpty {
                    Text("Unknown host").foregroundStyle(.ink3)
                } else {
                    Text(host).font(.aileron(13, .semibold)).lineLimit(1).truncationMode(.middle)
                    if filter.stats.trackers.contains(host) { Chip.tracker }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .padding(.horizontal, 12)
            .background(.bg, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.line))
            if !host.isEmpty {
                HStack(spacing: 10) {
                    Toggle("This host only", isOn: $hostOnly).toggleStyle(.switch).labelsHidden().controlSize(.small).tint(.allow)
                    Text("This host only").foregroundStyle(.ink2)
                }
            }
            HStack(spacing: 8) {
                Button { answer(.block, hostOnly) } label: {
                    Label { Text("Block") } icon: { Image(systemName: "xmark").foregroundStyle(.block) }
                        .frame(maxWidth: .infinity)
                }
                Button { answer(.allow, hostOnly) } label: {
                    Label("Allow", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.allow)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(EdgeInsets(top: 30, leading: 22, bottom: 20, trailing: 22))
        .frame(width: 300)
        .font(.aileron(13))
        .foregroundStyle(.ink)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .preferredColorScheme(.dark)
    }
}

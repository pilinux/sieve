import SwiftUI

/// What Ask mode shows when an unknown app connects.
struct PromptView: View {
    let filter: Filter
    let path: String
    /// A Team ID, `Apple`, or empty if not verified.
    let signer: String
    /// Empty when the flow has no host name.
    let host: String
    let answer: (Action, Bool) -> Void
    @State private var hostOnly = false

    var body: some View {
        VStack(spacing: 14) {
            AppIcon(path: path, size: 56)
            VStack(spacing: 2) {
                Text(FileManager.default.displayName(atPath: path)).font(.aileron(15, .bold))
                Text("wants to connect").foregroundStyle(.ink2)
            }
            // Name and icon come from the file, so anyone can copy them. Path and signer cannot be faked.
            VStack(spacing: 2) {
                Text(path).foregroundStyle(.ink2).lineLimit(2).truncationMode(.middle)
                Text(signer.isEmpty ? "Signer not verified" : signer == "Apple" ? "Signed by Apple" : "Team ID \(signer)")
                    .foregroundStyle(signer.isEmpty ? .block : .ink2)
            }
            .font(.aileron(11))
            .multilineTextAlignment(.center)
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
                Button {
                    answer(.block, hostOnly)
                } label: {
                    Label {
                        Text("Block")
                    } icon: {
                        Image(systemName: "xmark").foregroundStyle(.block)
                    }
                    .frame(maxWidth: .infinity)
                }
                Button {
                    answer(.allow, hostOnly)
                } label: {
                    Label("Allow", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.allow)
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

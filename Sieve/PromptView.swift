import SwiftUI

/// What Ask mode shows when an unknown app connects.
struct PromptView: View {
    let filter: Filter
    let app: String
    /// Empty when the extension could not find the process on disk.
    let path: String
    /// A Team ID, `Apple`, or empty if not verified.
    let signer: String
    /// Empty when the flow has no host name.
    let host: String
    /// The remote IP address, or empty if it is not known.
    let address: String
    let answer: (Action, Bool) -> Void
    @State private var hostOnly = false

    var body: some View {
        VStack(spacing: 14) {
            AppIcon(path: path.isEmpty ? nil : path, size: 56)
            VStack(spacing: 2) {
                Text(path.isEmpty ? app : FileManager.default.displayName(atPath: path)).font(.aileron(15, .bold))
                Text("wants to connect").foregroundStyle(.ink2)
            }
            // Name and icon come from the file, so anyone can copy them. Path and signer cannot be faked.
            VStack(spacing: 2) {
                if !path.isEmpty {
                    Copyable(text: path).foregroundStyle(.ink2).lineLimit(2).truncationMode(.middle)
                }
                Text(signer.isEmpty ? "Signer not verified" : signer == "Apple" ? "Signed by Apple" : "Team ID \(signer)")
                    .foregroundStyle(signer.isEmpty ? .block : .ink2)
                // Different code at an allowed path, for example after an update, or because another app replaced the file.
                if let allowed = filter.config.codes?[app], allowed != filter.stats.codes?[app] {
                    Text("Code changed since you allowed it").foregroundStyle(.block)
                }
            }
            .font(.aileron(11))
            .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                if !host.isEmpty {
                    Copyable(text: host).font(.aileron(13, .semibold)).lineLimit(1).truncationMode(.middle)
                    if filter.stats.trackers.contains(host) { Chip.tracker }
                } else if !address.isEmpty {
                    Copyable(text: address).font(.aileron(13, .semibold)).lineLimit(1).truncationMode(.middle)
                } else {
                    Text("Unknown host").foregroundStyle(.ink3)
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

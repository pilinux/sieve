import SwiftUI

/// The window until the filter is on: three steps, and what to do now.
struct SetupView: View {
    let filter: Filter

    var body: some View {
        let status = filter.status
        let failed = status.hasPrefix("Error")
        let current = status == "Allow Sieve in System Settings" ? 1 : 0
        VStack(spacing: 28) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.ink3)
                .frame(width: 96, height: 96)
                .background(.s1, in: .rect(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.line2))
            Text(failed ? "Error" : status).font(.aileron(26, .light))
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(["Turn on", "Allow", "Filter"].enumerated()), id: \.offset) { index, label in
                    if index > 0 {
                        Rectangle().fill(index <= current ? .allow : .s3).frame(height: 2).padding(.top, 15)
                    }
                    VStack(spacing: 10) {
                        node(index, current: current, failed: failed, busy: status == "Activating")
                        Text(label).font(.aileron(13, .semibold)).foregroundStyle(index == current ? .ink : .ink3)
                    }
                    .frame(width: 80)
                }
            }
            .frame(width: 480)
            VStack(spacing: 14) {
                switch status {
                case "Off":
                    Button("Turn on", systemImage: "power") { filter.turnOn() }
                        .buttonStyle(.borderedProminent).tint(.allow).controlSize(.extraLarge)
                case "Activating":
                    Text("Installing the system extension").foregroundStyle(.ink3)
                case "Allow Sieve in System Settings":
                    settingsHint
                    // Login Items & Extensions, which lists Network Extensions.
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        Link("Open System Settings", destination: url)
                    }
                default:
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.serious)
                        Text(status)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.crit.opacity(0.16), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.crit.opacity(0.5)))
                    Button("Turn on", systemImage: "power") { filter.turnOn() }.controlSize(.extraLarge)
                }
            }
            .frame(minHeight: 96, alignment: .top)
            LaunchAtLogin().frame(width: 160)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func node(_ index: Int, current: Int, failed: Bool, busy: Bool) -> some View {
        ZStack {
            if index < current {
                Circle().fill(.allow)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
            } else if index == current && failed {
                Circle().fill(.crit)
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
            } else if index == current {
                Circle().fill(.bg)
                Circle().strokeBorder(.allow, lineWidth: 2)
                if busy { ProgressView().controlSize(.small) } else { Text("\(index + 1)").font(.aileron(13, .bold)) }
            } else {
                Circle().fill(.s3)
                Text("\(index + 1)").font(.aileron(13, .bold)).foregroundStyle(.ink2)
            }
        }
        .frame(width: 32, height: 32)
    }

    // A picture of the System Settings switch, not a control.
    private var settingsHint: some View {
        HStack(spacing: 12) {
            AppIcon(path: Bundle.main.bundlePath, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sieve").font(.aileron(13, .semibold))
                Text("Network Extensions").foregroundStyle(.ink3)
            }
            Spacer()
            Capsule().fill(.s3).frame(width: 46, height: 26)
                .overlay(alignment: .leading) { Circle().fill(.ink2).frame(width: 22).padding(.leading, 2) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 380)
        .background(.s1, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.line2))
    }
}

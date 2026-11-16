import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A small all-caps label, with wide letter spacing, above a value or a chart.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased()).font(.aileron(11, .semibold)).tracking(1).foregroundStyle(.ink3)
    }
}

/// A big figure with a caption, and a line under it.
struct Kpi<Footer: View>: View {
    let title: String
    let value: String
    var unit: String?
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption(title)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.aileron(26, .light))
                if let unit { Text(unit).font(.aileron(13)).foregroundStyle(.ink3) }
            }
            .lineLimit(1)
            footer.font(.aileron(12)).foregroundStyle(.ink3)
        }
        // Take an equal share of the row's width, and the full height of a fixed-height row.
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}

/// A day's blocked flows as bar parts: block lists first, then rules and limits. A day counted before the split gets one grey part.
func blockedParts(_ stats: Stats, day: String) -> [SegmentBar.Part] {
    guard let split = stats.blockedSplit(day) else {
        return [.init(name: "Not split", value: stats.blocked[day] ?? 0, color: .unsplit)]
    }
    return [
        .init(name: "Block lists", value: split.lists, color: .block),
        .init(name: "Rules and limits", value: split.rules, color: .ruleBlock),
    ]
}

/// Today's blocked flows, with a bar that splits them. If today was counted before the split, there is no bar.
struct BlockedToday: View {
    let stats: Stats

    var body: some View {
        let today = Stats.day(.now)
        Kpi(title: "Blocked today", value: "\(stats.blocked[today] ?? 0)") {
            if stats.blockedSplit(today) != nil { SegmentBar(parts: blockedParts(stats, day: today)) }
        }
    }
}

/// A short label in a capsule.
struct Chip: View {
    let text: String
    var icon: String?
    var iconColor: Color = .ink2
    var fill: Color = .s3

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(iconColor) }
            Text(text)
        }
        .font(.aileron(11, .semibold))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(fill, in: .capsule)
    }
}

extension Chip {
    /// Allow in blue, Block in orange.
    init(action: Action) {
        self.init(
            text: action == .allow ? "Allow" : "Block", icon: action == .allow ? "checkmark" : "xmark",
            iconColor: action == .allow ? .allow : .block
        )
    }

    static let tracker = Chip(text: "Tracker", icon: "exclamationmark.triangle.fill", iconColor: .warn, fill: .warn.opacity(0.14))

    /// The DNS tag of a host or address: "Public DNS" when it is on the list, and hover shows the provider.
    /// Else, for an address that a DNS flow went to, "Local DNS" on a local network, or "DNS".
    @ViewBuilder static func dns(_ value: String, used: Bool = false) -> some View {
        if let entry = PublicDNS.bundled.entry(for: value) {
            Chip(text: "Public DNS", icon: "server.rack").help("\(entry.provider) public DNS resolver")
        } else if used {
            let local = Address.isLocal(value)
            Chip(text: local ? "Local DNS" : "DNS", icon: "server.rack")
                .help(local ? "A DNS server on a local network" : "A DNS server")
        }
    }
}

/// A privacy grade, A to F, on its own colour.
struct GradeBadge: View {
    let grade: String
    var size: CGFloat = 22

    var body: some View {
        let color = Color.grade(grade)
        Text(grade)
            .font(.aileron(size > 40 ? 40 : 12, size > 40 ? .light : .bold))
            .frame(width: size, height: size)
            .background(color.opacity(0.22), in: .rect(cornerRadius: size * 0.26))
            .overlay(RoundedRectangle(cornerRadius: size * 0.26).strokeBorder(color.opacity(0.7)))
            .help("Grade \(grade)")
    }
}

/// The app's Finder icon.
struct AppIcon: View {
    let path: String?
    var size: CGFloat = 28

    var body: some View {
        let icon = path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .unixExecutable)
        Image(nsImage: icon).resizable().frame(width: size, height: size)
    }
}

/// A segmented control. A tinted option shows its colour when chosen.
struct Segments<Value: Hashable>: View {
    struct Option {
        var value: Value
        var label: String
        var icon: String?
        var tint: Color?
    }

    let options: [Option]
    let selection: Value?
    var small = false
    /// A glass capsule, for the toolbar.
    var glass = false
    let choose: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button {
                    choose(option.value)
                } label: {
                    HStack(spacing: 6) {
                        if let icon = option.icon {
                            Image(systemName: icon).font(.system(size: small ? 9 : 10, weight: .bold))
                                .foregroundStyle(on ? option.tint ?? .ink : .ink2)
                        }
                        Text(option.label)
                    }
                    .font(.aileron(small ? 11 : 12, .semibold))
                    .foregroundStyle(on ? .ink : .ink2)
                    .padding(.horizontal, small ? 8 : 12)
                    .frame(height: small ? 22 : 26)
                    .background(on ? option.tint.map { $0.opacity(0.16) } ?? .s3 : .clear, in: .rect(cornerRadius: glass ? 13 : 6))
                    .overlay {
                        if on { RoundedRectangle(cornerRadius: glass ? 13 : 6).strokeBorder(option.tint?.opacity(0.55) ?? .line2) }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(glass ? 3 : 2)
        .background(glass ? .clear : .s1, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(glass ? .clear : .line))
        .glassEffect(glass ? .regular : .identity, in: .capsule)
        .fixedSize()
    }
}

extension Segments where Value == Action {
    /// Allow and Block. Neither is chosen while there is no rule.
    init(verdict: Action?, small: Bool = false, choose: @escaping (Action) -> Void) {
        self.init(
            options: [
                Option(value: .allow, label: "Allow", icon: "checkmark", tint: .allow),
                Option(value: .block, label: "Block", icon: "xmark", tint: .block),
            ],
            selection: verdict, small: small, choose: choose
        )
    }
}

/// A borderless icon button that lights up on hover.
struct IconButton: View {
    let icon: String
    let help: String
    var tint: Color?
    var ring = false
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hover ? tint ?? .ink : .ink2)
                .frame(width: 28, height: 28)
                .background(hover ? tint.map { $0.opacity(0.16) } ?? .s3 : .clear, in: .rect(cornerRadius: 7))
                .overlay { if ring { RoundedRectangle(cornerRadius: 7).strokeBorder(.line2) } }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hover = $0 && isEnabled }
        .help(help)
    }
}

/// Picks the mode: Off, Ask, or Quiet.
struct ModePicker: View {
    let filter: Filter
    var glass = false

    var body: some View {
        Segments(
            options: [.init(value: Mode.off, label: "Off"), .init(value: .ask, label: "Ask"), .init(value: .quiet, label: "Quiet")],
            selection: filter.config.mode, glass: glass
        ) { mode in filter.update { $0.mode = mode } }
    }
}

/// One app row: its allow switch, grade, total, and live rate.
struct AppRow: View {
    let filter: Filter
    let app: String
    var selected = false

    var body: some View {
        let stats = filter.stats
        let on = filter.config.action(for: app) != .block
        let current = filter.rates[app] ?? 0
        let fastest = max(filter.rates.values.max() ?? 0, 1)
        HStack(spacing: 10) {
            Group {
                AppIcon(path: stats.paths[app])
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 7) {
                        Text(stats.name(app)).font(.aileron(13, .semibold)).lineLimit(1).truncationMode(.middle)
                        GradeBadge(grade: stats.grade(app))
                    }
                    Text(
                        "\(bytes(stats.bytes[app] ?? 0)) · \(counted(stats.apps[app]?.count ?? 0, "host")) · \(counted(stats.addresses?[app]?.count ?? 0, "IP"))"
                    )
                    .font(.aileron(11)).foregroundStyle(.ink3).monospacedDigit().lineLimit(1)
                }
            }
            .opacity(on ? 1 : 0.5)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(rate(current)).font(.aileron(12)).foregroundStyle(.ink2).monospacedDigit()
                Capsule().fill(.s3).frame(width: 78, height: 3).overlay(alignment: .leading) {
                    Capsule().fill(.allow).frame(width: 78 * current / fastest)
                }
                .animation(.easeOut(duration: 0.6), value: current)
            }
            // `unknown` cannot have a rule, because many processes share it.
            if app != Config.unknownApp {
                Toggle(
                    "Allow",
                    isOn: Binding(
                        get: { on },
                        set: { allow in filter.update { $0.setAction(allow ? .allow : .block, for: app) } }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.allow)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? .s2 : .clear, in: .rect(cornerRadius: 9))
        .overlay(alignment: .leading) {
            if selected { Capsule().fill(.allow).frame(width: 3).padding(.vertical, 10) }
        }
        .contentShape(.rect)
    }
}

/// A search field with an icon, and a clear button once it holds text. Escape also clears it.
struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.ink3)
            TextField(prompt, text: $text).textFieldStyle(.plain).onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.ink3)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.bg, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.line2))
    }
}

/// A glass capsule button for the toolbar.
struct ToolButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.aileron(12, .semibold))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// An empty screen: an icon, a title, and a line on what will fill it.
struct EmptyState: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(.ink2)
                .frame(width: 72, height: 72)
                .background(.s1, in: .circle)
                .overlay(Circle().strokeBorder(.line2))
            Text(title).font(.aileron(16, .semibold))
            Text(text).foregroundStyle(.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Text that copies itself on a click. A checkmark shows for a moment after.
struct Copyable: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 9, weight: .semibold))
        }
        .contentShape(.rect)
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
        }
        .help("Click to copy")
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

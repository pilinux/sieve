import AppKit
import CoreText
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

extension ShapeStyle where Self == Color {
    static var bg: Color { Color(hex: 0x0E0F12) }
    static var s1: Color { Color(hex: 0x141619) }
    static var s2: Color { Color(hex: 0x1B1E22) }
    static var s3: Color { Color(hex: 0x252A30) }
    static var line: Color { .white.opacity(0.07) }
    static var line2: Color { .white.opacity(0.14) }
    static var ink: Color { Color(hex: 0xF2F1EE) }
    static var ink2: Color { Color(hex: 0xB7B6AF) }
    static var ink3: Color { Color(hex: 0x8A8983) }
    /// Traffic and allow.
    static var allow: Color { Color(hex: 0x3987E5) }
    static var block: Color { Color(hex: 0xD95926) }
    static var good: Color { Color(hex: 0x0CA30C) }
    static var warn: Color { Color(hex: 0xFAB219) }
    static var serious: Color { Color(hex: 0xEC835A) }
    static var crit: Color { Color(hex: 0xD03B3B) }
    static var tip: Color { Color(hex: 0x2A2F36) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A to F, from green to red.
    static func grade(_ letter: String) -> Color {
        switch letter {
        case "A": .good
        case "B": Color(hex: 0x8FB51F)
        case "C": .warn
        case "D": .serious
        default: .crit
        }
    }

    /// The user's colour, else four defaults by position, else gray.
    static func profile(_ index: Int, _ hex: String?) -> Color {
        if let hex, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) { return Color(hex: value) }
        return [Color(hex: 0x199E70), Color(hex: 0xC98500), Color(hex: 0xD55181), Color(hex: 0x9085E9)]
            .dropFirst(index).first ?? .ink3
    }
}

extension Font {
    /// Aileron, bundled with the app. Light, regular, semibold, and bold.
    static func aileron(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        let face =
            switch weight {
            case .light: "UltraLight"
            case .semibold: "SemiBold"
            case .bold: "Bold"
            default: "Regular"
            }
        return .custom("Aileron-\(face)", size: size)
    }

    /// Makes the bundled fonts available to this process.
    static func registerAileron() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "woff2", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

extension Stats {
    /// The app's name from its file on disk, else its key.
    func name(_ app: String) -> String {
        paths[app].map { FileManager.default.displayName(atPath: $0) } ?? app
    }
}

/// Decimal units, as Finder shows them.
func bytes(_ count: Int) -> String {
    count == 0 ? "0 B" : Int64(count).formatted(.byteCount(style: .file))
}

func rate(_ bytesPerSecond: Double) -> String {
    bytes(Int(bytesPerSecond)) + "/s"
}

/// The last `count` days, oldest first, ending today.
func lastDays(_ count: Int) -> [Date] {
    (0..<count).map { Calendar.current.date(byAdding: .day, value: $0 - count + 1, to: .now) ?? .now }
}

extension View {
    /// A rounded panel on the window background.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.s1, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.line))
    }
}

/// A small spaced caps label above a value or a chart.
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
        // Equal shares of the row, equal heights in a fixed-height row.
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
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
}

/// A privacy grade, A to F, on its colour.
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

/// Off, Ask, or Quiet.
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

/// An app's allow switch, with its grade, total, and live rate.
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
                    Text("\(bytes(stats.bytes[app] ?? 0)) · \(stats.apps[app, default: []].count) hosts")
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? .s2 : .clear, in: .rect(cornerRadius: 9))
        .overlay(alignment: .leading) {
            if selected { Capsule().fill(.allow).frame(width: 3).padding(.vertical, 10) }
        }
        .contentShape(.rect)
    }
}

/// The "Launch at login" switch. Shows the real state: if (un)registering fails, the switch stays put.
struct LaunchAtLogin: View {
    @State private var on = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack {
            Text("Launch at login").font(.aileron(12)).foregroundStyle(.ink2)
            Spacer()
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { on },
                    set: { wanted in
                        let service = SMAppService.mainApp
                        try? wanted ? service.register() : service.unregister()
                        on = service.status == .enabled
                    })
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .tint(.allow)
        }
    }
}

/// An empty screen: an icon, a title, and what fills it.
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

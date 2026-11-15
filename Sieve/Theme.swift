import CoreText
import SwiftUI

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
    /// A block by the user's rules, limits, or Ask mode: a choice, not a bad request.
    static var ruleBlock: Color { Color(hex: 0xA46FC2) }
    /// Blocked flows of a day saved before the split.
    static var unsplit: Color { Color(hex: 0x5F636A) }
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
        case "–": .ink3
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

extension View {
    /// A rounded panel on the window background.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.s1, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.line))
    }
}

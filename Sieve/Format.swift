import Foundation

// Display names, cached by path. Each Launch Services lookup takes about a millisecond, and lists sort by name every second.
@MainActor private var displayNames: [String: String] = [:]

extension Stats {
    /// The app's name from its file on disk, or its key if there is no file.
    @MainActor func name(_ app: String) -> String {
        guard let path = paths[app] else { return app }
        if let name = displayNames[path] { return name }
        let name = FileManager.default.displayName(atPath: path)
        displayNames[path] = name
        return name
    }
}

/// Formats a byte count in decimal units, as Finder does.
func bytes(_ count: Int) -> String {
    count == 0 ? "0 B" : Int64(count).formatted(.byteCount(style: .file))
}

func rate(_ bytesPerSecond: Double) -> String {
    bytes(Int(bytesPerSecond)) + "/s"
}

// Counts with their nouns, cached. Grammar agreement is slow, and lists show several counts per row on every redraw.
@MainActor private var countedTexts: [String: String] = [:]

/// A count with its noun in the matching form, such as "1 host" or "2 hosts".
func counted(_ count: Int, _ noun: String) -> String {
    // Automatic grammar agreement leaves "IP" as it is.
    if noun == "IP" { return "\(count.formatted()) \(count == 1 ? "IP" : "IPs")" }
    let key = "\(count) \(noun)"
    if let text = countedTexts[key] { return text }
    // Counts such as flows keep growing, so start over rather than keep every one.
    if countedTexts.count >= 10_000 { countedTexts.removeAll() }
    let text = String(AttributedString(localized: "^[\(count) \(noun)](inflect: true)").characters)
    countedTexts[key] = text
    return text
}

/// The last `count` days, oldest first, ending today.
func lastDays(_ count: Int) -> [Date] {
    (0..<count).map { Calendar.current.date(byAdding: .day, value: $0 - count + 1, to: .now) ?? .now }
}

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

/// The last `count` days, oldest first, ending today.
func lastDays(_ count: Int) -> [Date] {
    (0..<count).map { Calendar.current.date(byAdding: .day, value: $0 - count + 1, to: .now) ?? .now }
}

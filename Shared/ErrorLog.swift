import Foundation
import Network
import Synchronization
import os

/// One line of an error log, after the header. The fields are strings, not enums, so values from a newer build still load.
nonisolated struct LogEntry: Codable, Equatable, Sendable {
    var time: Date
    /// `error` means Sieve could not do what was asked. Anything else is a warning: Sieve recovered or used a fallback.
    var level: String
    /// `app` or `extension`.
    var source: String
    var area: String
    /// Fixed text from the code. It never holds user data.
    var message: String
    var detail: String?
    var build: String?
    /// How many identical entries were skipped before this one.
    var repeats: Int?
    /// The file that logged it, from `#fileID`. Not `#filePath`, because that includes the builder's home folder.
    var file: String?
    var line: Int?
    var function: String?

    var isError: Bool { level == "error" }
}

nonisolated extension LogEntry {
    /// Creates an entry and scrubs personal data from its text.
    /// The detail never uses `String(describing:)`, because that prints `userInfo`, which can hold URLs and paths.
    init(
        level: String, source: String, area: String, message: String, error: (any Error)?, build: String?, time: Date = .now,
        file: String = #fileID, line: Int = #line, function: String = #function
    ) {
        let detail = error.map { error in
            let error = error as NSError
            return Self.scrub("\(error.domain) \(error.code): \(error.localizedDescription)")
        }
        // `#fileID` looks like "Module/File.swift". Keep only the file name, since `source` already names the process.
        self.init(
            time: time, level: level, source: source, area: area, message: Self.scrub(message), detail: detail, build: build,
            file: file.split(separator: "/").last.map(String.init), line: line, function: function)
    }

    /// Replaces the user's folder with `~`, and URLs, email and IP addresses with placeholders.
    static func scrub(_ text: String) -> String {
        var text = text
        text.replace(#/[A-Za-z][A-Za-z0-9+.\-]*:\/\/[^\s"'“”<>]*[^\s"'“”<>.,;:)]/#, with: "<url>")
        text.replace(#/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/#, with: "<email>")
        text.replace(#/\/Users\/[^\/\s"'“”]+/#, with: "~")
        text.replace(#/[0-9A-Za-z:.%]*[:.][0-9A-Za-z:.%]*/#) { match in
            let token = String(match.output)
            let core = token.trimmingCharacters(in: CharacterSet(charactersIn: ".:"))
            // Use a strict check. `IPv4Address` also accepts "640" or "1.2.3", which are error codes and versions here.
            let ipv4 =
                core.wholeMatch(of: #/(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/#).map { parts in
                    [parts.1, parts.2, parts.3, parts.4].allSatisfy { (Int($0) ?? 256) <= 255 }
                } ?? false
            // Require at least two colons, so a time such as 10:32 is kept.
            let ipv6 = core.count { $0 == ":" } >= 2 && IPv6Address(core) != nil
            return ipv4 || ipv6 ? token.replacingOccurrences(of: core, with: "<address>") : token
        }
        return text
    }
}

/// The first line of an error log.
nonisolated struct LogHeader: Codable, Equatable, Sendable {
    var format = 1
    /// When the log was last reset. After a trim, the time of the oldest entry kept.
    var since: Date
}

/// The first line of a saved copy, which holds the entries of both logs.
nonisolated struct LogExport: Codable {
    var format = 1
    var exported: Date
    var macOS: String
    var build: String
    /// The `since` of each log, by source.
    var since: [String: Date]
}

/// An error log in JSON Lines: a header line, then one entry per line, oldest first. New entries are appended.
nonisolated struct LogFile: Equatable, Sendable {
    static let keep = 2_000
    static let trimTo = 1_500

    var header: LogHeader
    var entries: [LogEntry] = []

    init(since: Date) {
        header = LogHeader(since: since)
    }

    /// Skips lines that do not decode, such as a line cut short by a crash.
    init(data: Data, now: Date) {
        let lines = data.split(separator: UInt8(ascii: "\n")).map { Data($0) }
        entries = lines.compactMap { try? Self.decoder.decode(LogEntry.self, from: $0) }
        header = lines.first.flatMap { try? Self.decoder.decode(LogHeader.self, from: $0) } ?? LogHeader(since: entries.first?.time ?? now)
    }

    var data: Data { ([Self.line(header)] + entries.map(Self.line)).reduce(Data(), +) }
    var errors: Int { entries.count(where: \.isError) }
    var warnings: Int { entries.count - errors }

    /// With more than `keep` entries, keeps the newest `trimTo` and sets `since` to the oldest of those.
    mutating func trim() {
        guard entries.count > Self.keep else { return }
        entries.removeFirst(entries.count - Self.trimTo)
        header.since = entries[0].time
    }

    /// A saved copy: an export header, then the entries of every log, oldest first.
    static func export(_ logs: [String: LogFile], macOS: String, build: String, now: Date) -> Data {
        let header = LogExport(exported: now, macOS: macOS, build: build, since: logs.mapValues(\.header.since))
        let entries = logs.values.flatMap(\.entries).sorted { $0.time < $1.time }
        return ([line(header)] + entries.map(line)).reduce(Data(), +)
    }

    /// One JSON object and a newline.
    static func line(_ value: some Encodable) -> Data {
        ((try? encoder.encode(value)) ?? Data()) + Data("\n".utf8)
    }

    // ISO 8601 in UTC, with milliseconds.
    private static let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(style))
        }
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try style.parse(decoder.singleValueContainer().decode(String.self))
        }
        return decoder
    }
}

/// Skips an entry identical to one written in the last 10 minutes, and counts how many it skipped.
nonisolated struct LogThrottle: Sendable {
    private var last: [String: (time: Date, held: Int)] = [:]

    /// Returns the entry to write, with the number skipped before it, or nil to skip it.
    mutating func admit(_ entry: LogEntry) -> LogEntry? {
        let key = [entry.level, entry.area, entry.message, entry.detail ?? "", entry.file ?? "", "\(entry.line ?? 0)"]
            .joined(separator: "\u{1F}")
        if let seen = last[key], entry.time < seen.time.addingTimeInterval(600) {
            last[key]?.held += 1
            return nil
        }
        var entry = entry
        if let held = last[key]?.held, held > 0 { entry.repeats = held }
        last[key] = (entry.time, 0)
        return entry
    }
}

/// Appends this process's errors and warnings to `errors.jsonl` on a background queue. Each one also goes to `Logger`.
nonisolated final class ErrorLog: Sendable {
    private struct State {
        var throttle = LogThrottle()
        // The number of entries in the file. Nil until the first write reads the file.
        var count: Int?
    }

    /// The version and build number, as each entry holds them.
    let build: String
    private let file: URL
    private let source: String
    private let subsystem: String
    private let queue = DispatchQueue(label: "me.pilinux.Sieve.errors")
    private let state = Mutex(State())

    init(folder: URL, source: String, subsystem: String) {
        let info = Bundle.main.infoDictionary ?? [:]
        build = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
        file = folder.appending(path: "errors.jsonl")
        self.source = source
        self.subsystem = subsystem
        // Create the log on first launch, so "Since" has a date.
        queue.async { [self] in
            if !FileManager.default.fileExists(atPath: file.path) { save(LogFile(since: .now)) }
        }
    }

    func error(
        _ area: String, _ message: String, _ error: (any Error)? = nil, file: String = #fileID, line: Int = #line,
        function: String = #function
    ) {
        add("error", area, message, error, file, line, function)
    }

    func warning(
        _ area: String, _ message: String, _ error: (any Error)? = nil, file: String = #fileID, line: Int = #line,
        function: String = #function
    ) {
        add("warning", area, message, error, file, line, function)
    }

    /// The file as stored, once the queued writes are done.
    func contents() -> Data {
        queue.sync { (try? Data(contentsOf: file)) ?? Data() }
    }

    /// Deletes every entry and sets `since` to now.
    func reset() {
        queue.sync {
            save(LogFile(since: .now))
            state.withLock { $0 = State(count: 0) }
        }
    }

    private func add(
        _ level: String, _ area: String, _ message: String, _ error: (any Error)?, _ file: String, _ line: Int, _ function: String
    ) {
        let entry = LogEntry(
            level: level, source: source, area: area, message: message, error: error, build: build, file: file, line: line,
            function: function)
        // The text is already scrubbed, so it can be public.
        Logger(subsystem: subsystem, category: entry.area).log(
            level: entry.isError ? .error : .default, "\(entry.message, privacy: .public) \(entry.detail ?? "", privacy: .public)")
        queue.async { [self] in
            guard let entry = state.withLock({ $0.throttle.admit(entry) }) else { return }
            append(entry)
        }
    }

    // Call only on `queue`.
    private func append(_ entry: LogEntry) {
        do {
            if !FileManager.default.fileExists(atPath: file.path) { save(LogFile(since: entry.time)) }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: LogFile.line(entry))
            var count = state.withLock { $0.count.map { $0 + 1 } } ?? read().entries.count
            if count > LogFile.keep {
                var log = read()
                log.trim()
                save(log)
                count = log.entries.count
            }
            state.withLock { $0.count = count }
        } catch {
            // Report a failed write to `Logger` only, so the log never logs itself.
            Logger(subsystem: subsystem, category: "errors").error("Cannot write errors.jsonl: \(error)")
        }
    }

    private func read() -> LogFile {
        LogFile(data: (try? Data(contentsOf: file)) ?? Data(), now: .now)
    }

    private func save(_ log: LogFile) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try log.data.write(to: file, options: .atomic)
        } catch {
            Logger(subsystem: subsystem, category: "errors").error("Cannot write errors.jsonl: \(error)")
        }
    }
}

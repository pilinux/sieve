import Foundation
import Testing

struct ErrorLogTests {
    let start = Date(timeIntervalSince1970: 1_794_600_000)

    func entry(_ level: String = "warning", at minutes: Double = 0, detail: String? = nil, source: String = "app") -> LogEntry {
        LogEntry(
            time: start.addingTimeInterval(minutes * 60), level: level, source: source, area: "xpc", message: "Cannot reach the filter",
            detail: detail)
    }

    @Test func parserSkipsALineCutShort() {
        var log = LogFile(since: start)
        log.entries = [entry("error"), entry(at: 1)]
        let data = log.data + Data(#"{"area":"store","level":"err"#.utf8)
        #expect(LogFile(data: data, now: .now) == log)
    }

    @Test func noHeaderStartsAtTheFirstEntry() {
        let data = LogFile.line(entry(at: 5)) + LogFile.line(entry(at: 6))
        #expect(LogFile(data: data, now: .now).header.since == start.addingTimeInterval(300))
        #expect(LogFile(data: Data(), now: start).header.since == start)
    }

    @Test func summaryCountsUnknownLevelsAsWarnings() {
        var log = LogFile(since: start)
        log.entries = [entry("error"), entry("warning"), entry("notice")]
        #expect(log.errors == 1 && log.warnings == 2)
    }

    @Test func trimKeepsTheNewestAndMovesSince() {
        var log = LogFile(since: start)
        log.entries = (0...LogFile.keep).map { entry(at: Double($0)) }
        log.trim()
        #expect(log.entries.count == LogFile.trimTo)
        #expect(log.header.since == log.entries[0].time)
        #expect(log.entries.last == entry(at: Double(LogFile.keep)))
    }

    @Test func throttleHoldsBackRepeatsFor10Minutes() {
        var throttle = LogThrottle()
        let first = throttle.admit(entry())
        let held = [throttle.admit(entry(at: 1)), throttle.admit(entry(at: 9))]
        let other = throttle.admit(entry(at: 2, detail: "NSCocoaErrorDomain 4097"))
        let later = throttle.admit(entry(at: 10))
        #expect(first == entry())
        #expect(held == [nil, nil])
        #expect(other != nil)
        #expect(later?.repeats == 2)
    }

    @Test func entryRecordsWhereItWasLogged() {
        let entry = LogEntry(level: "error", source: "app", area: "store", message: "Cannot write stats.json", error: nil, build: nil)
        #expect(entry.file == "ErrorLogTests.swift")
        #expect(entry.line == #line - 2)
        #expect(entry.function == "entryRecordsWhereItWasLogged()")
    }

    @Test func throttleKeepsCallSitesApart() {
        var throttle = LogThrottle()
        var here = entry()
        here.line = 10
        var there = entry()
        there.line = 20
        let first = throttle.admit(here)
        let second = throttle.admit(there)
        #expect(first != nil && second != nil)
    }

    @Test func scrubberRemovesPersonalData() {
        #expect(LogEntry.scrub("Path /Users/jane.doe/Library/x.json.") == "Path ~/Library/x.json.")
        #expect(LogEntry.scrub("At https://lists.example/a?token=s3cret, then") == "At <url>, then")
        #expect(LogEntry.scrub("Mail jane@example.com now") == "Mail <email> now")
        #expect(LogEntry.scrub("From 192.0.2.10.") == "From <address>.")
        #expect(LogEntry.scrub("To 2001:db8::1 and fe80::1%en0") == "To <address> and <address>")
        // Codes, versions, times, and Sieve's own names stay.
        let kept = "NSCocoaErrorDomain 640 at 10:32:05 in 26.6.1 for stats.json and Swift.DecodingError"
        #expect(LogEntry.scrub(kept) == kept)
    }

    @Test func entryHoldsNoPersonalData() {
        let error = NSError(
            domain: NSURLErrorDomain, code: -1003,
            userInfo: [
                NSLocalizedDescriptionKey: "No host at https://jane.example/l.txt from 192.0.2.7 for jane@example.com in /Users/jane/x",
                NSURLErrorFailingURLErrorKey: URL(string: "https://jane.example/l.txt") as Any,
            ])
        let entry = LogEntry(
            level: "warning", source: "app", area: "lists", message: "Cannot load list l-1", error: error, build: "1.0 (1)")
        let line = String(decoding: LogFile.line(entry), as: UTF8.self)
        #expect(LogEntry.scrub(line) == line)
        #expect(entry.detail == "NSURLErrorDomain -1003: No host at <url> from <address> for <email> in ~/x")
    }

    @Test func exportMergesBothLogsOldestFirst() {
        var app = LogFile(since: start)
        app.entries = [entry(at: 1), entry(at: 3)]
        var filter = LogFile(since: start.addingTimeInterval(60))
        filter.entries = [entry(at: 2, source: "extension")]
        let data = LogFile.export(["app": app, "extension": filter], macOS: "26.6", build: "1.0 (1)", now: start)
        let lines = data.split(separator: UInt8(ascii: "\n")).map { Data($0) }
        #expect(lines.count == 4)
        #expect(LogFile(data: data, now: start).entries.map(\.source) == ["app", "extension", "app"])
    }
}

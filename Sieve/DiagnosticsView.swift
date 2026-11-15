import AppKit
import SwiftUI

/// Counts from both error logs, and their newest entries.
struct DiagnosticsView: View {
    let filter: Filter

    var body: some View {
        let entries = filter.logs.values.flatMap(\.entries).sorted { $0.time > $1.time }
        let errors = entries.filter(\.isError)
        let warnings = entries.filter { !$0.isError }
        let since = filter.logs.values.map(\.header.since).min()
        let unread = !filter.logs.isEmpty && filter.logs["extension"] == nil
        ScrollView {
            VStack(spacing: 12) {
                if unread {
                    Label(
                        "The filter cannot be reached, so its log cannot be read or reset. This page and a saved copy hold the app log only.",
                        systemImage: "power"
                    )
                    .foregroundStyle(.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 12)
                }
                HStack(spacing: 12) {
                    Kpi(title: "Errors", value: "\(errors.count)") { Label(split(errors, unread: unread), systemImage: "xmark") }
                    Kpi(title: "Warnings", value: "\(warnings.count)") {
                        Label(split(warnings, unread: unread), systemImage: "exclamationmark.triangle")
                    }
                    Kpi(title: "Since", value: since?.formatted(.dateTime.day().month()) ?? "") {
                        // Relative times go out of date, so redraw them every minute.
                        TimelineView(.everyMinute) { _ in
                            Label(
                                [
                                    since.map { "Reset \($0.formatted(.relative(presentation: .named)))" },
                                    entries.first.map { "last entry \($0.time.formatted(.relative(presentation: .named)))" },
                                ]
                                .compactMap(\.self).joined(separator: " · "),
                                systemImage: "clock")
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Caption("Newest entries")
                        Text(entries.count > 50 ? "50 of \(entries.count)" : "\(entries.count)")
                            .font(.aileron(12)).foregroundStyle(.ink3).monospacedDigit()
                    }
                    .padding(.bottom, 14)
                    if entries.isEmpty {
                        EmptyState(
                            icon: "checkmark", title: "No errors or warnings",
                            text: since.map { "Since \($0.formatted(.dateTime.day().month().hour().minute().second()))." } ?? ""
                        )
                        .frame(height: 220)
                    }
                    ForEach(Array(entries.prefix(50).enumerated()), id: \.offset) { _, entry in row(entry) }
                    Label(
                        "No hosts, IP addresses, URLs, names, or paths with your user name. The file is safe to share.",
                        systemImage: "shield"
                    )
                    .font(.aileron(12)).foregroundStyle(.ink2)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(.line).frame(height: 1) }
                }
                .card()
            }
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 28, trailing: 24))
        }
        .task { await filter.readErrorLogs() }
    }

    private func split(_ entries: [LogEntry], unread: Bool) -> String {
        let app = entries.count { $0.source == "app" }
        return "\(app) in the app · " + (unread ? "filter not read" : "\(entries.count - app) in the filter")
    }

    private func row(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.isError ? "xmark" : "exclamationmark.triangle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(entry.isError ? .serious : .warn)
                .frame(width: 16, height: 18)
                .help(entry.isError ? "Error: Sieve could not do what was asked" : "Warning: Sieve recovered or fell back")
            Text(entry.time.formatted(.dateTime.day().month().hour().minute().second()))
                .font(.aileron(12)).foregroundStyle(.ink2).monospacedDigit()
                .frame(width: 128, height: 18, alignment: .leading)
                .help("\(entry.time.formatted(.iso8601)), UTC, as in the file")
            Chip(text: entry.source == "app" ? "App" : "Filter").frame(width: 52, alignment: .leading)
            Text(entry.area).font(.system(size: 11, design: .monospaced)).foregroundStyle(.ink3)
                .frame(width: 48, height: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.message).font(.aileron(13, .semibold))
                        .help(entry.file.map { "\($0):\(entry.line ?? 0) in \(entry.function ?? "?")" } ?? "")
                    if let repeats = entry.repeats {
                        Chip(text: "×\(repeats + 1)").help("\(repeats) more, held back within 10 minutes")
                    }
                }
                .frame(minHeight: 18)
                if let detail = entry.detail {
                    Text(detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(.ink3)
                        .lineLimit(1).truncationMode(.tail)
                        .help("\(detail)\n\(entry.build ?? "")")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(.line).frame(height: 1) }
    }
}

/// The Save a copy and Reset buttons, for the toolbar.
struct DiagnosticsTools: View {
    let filter: Filter
    @State private var resetting = false

    var body: some View {
        ToolButton(title: "Save a copy…", icon: "square.and.arrow.down") { Task { await save() } }
        ToolButton(title: "Reset…", icon: "trash") { resetting = true }
            .confirmationDialog("Reset the error log?", isPresented: $resetting) {
                Button("Reset", role: .destructive) { Task { await filter.resetErrorLogs() } }
            } message: {
                Text("Sieve deletes every logged error and warning, in the app and the filter.")
            }
    }

    private func save() async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sieve-log-\(Date.now.formatted(.iso8601.year().month().day())).jsonl"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await filter.readErrorLogs()
        let data = LogFile.export(
            filter.logs, macOS: ProcessInfo.processInfo.operatingSystemVersionString, build: errorLog.build, now: .now)
        do {
            try data.write(to: url)
        } catch {
            errorLog.error("store", "Cannot save a copy of the error log", error)
            NSApp.presentError(error)
        }
    }
}

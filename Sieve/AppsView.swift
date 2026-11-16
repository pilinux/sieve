import SwiftUI

struct AppsView: View {
    let filter: Filter
    // Nil means All apps.
    @State private var selected: String?
    @State private var query = ""

    var body: some View {
        if filter.stats.apps.isEmpty {
            EmptyState(icon: "square.grid.2x2", title: "No apps yet", text: "An app shows up on its first connection.")
        } else {
            HStack(spacing: 0) {
                list.frame(width: 380)
                Rectangle().fill(.line).frame(width: 1)
                ScrollView {
                    Group {
                        if let selected, filter.stats.apps[selected] != nil {
                            // A new app gets a fresh view, so a focused limit field does not carry over.
                            XRay(filter: filter, app: selected).id(selected)
                        } else {
                            Overview(filter: filter)
                        }
                    }
                    .padding(EdgeInsets(top: 20, leading: 22, bottom: 28, trailing: 22))
                }
            }
        }
    }

    private var list: some View {
        let stats = filter.stats
        let byName = { (a: String, b: String) in stats.name(a).localizedStandardCompare(stats.name(b)) == .orderedAscending }
        // Ignore case and accents.
        let match = { (app: String) in
            query.isEmpty || stats.name(app).localizedStandardContains(query) || app.localizedStandardContains(query)
        }
        let all = Set(stats.undecided(filter.config))
        let undecided = all.filter(match).sorted(by: byName)
        let decided = stats.apps.keys.filter { !all.contains($0) && match($0) }.sorted(by: byName)
        // All apps and the search field stay in place. Each group header sticks to the top until the next one pushes it out.
        return VStack(spacing: 0) {
            allApps.padding(EdgeInsets(top: 12, leading: 10, bottom: 0, trailing: 10))
            SearchField(text: $query, prompt: "Search apps").padding(EdgeInsets(top: 10, leading: 10, bottom: 0, trailing: 10))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    if !undecided.isEmpty {
                        Section {
                            VStack(spacing: 0) { ForEach(undecided, id: \.self, content: undecidedRow) }
                                .padding(2)
                                .background(.s1, in: .rect(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.line))
                        } header: {
                            group("Undecided", undecided.count)
                        }
                    }
                    Section {
                        ForEach(decided, id: \.self) { app in
                            AppRow(filter: filter, app: app, selected: app == selected).onTapGesture { selected = app }
                        }
                    } header: {
                        group("Apps", decided.count)
                    }
                    if !query.isEmpty, undecided.isEmpty, decided.isEmpty {
                        Text("No apps match “\(query)”.").foregroundStyle(.ink3).padding(.horizontal, 10)
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 10, bottom: 12, trailing: 10))
            }
        }
    }

    private var allApps: some View {
        HStack(spacing: 10) {
            Image(systemName: "sum").font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.s3, in: .rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text("All apps").font(.aileron(13, .semibold))
                Text("\(bytes(filter.stats.totalBytes)) · \(filter.stats.apps.count) apps")
                    .font(.aileron(11)).foregroundStyle(.ink3).monospacedDigit()
            }
            Spacer()
            Text(rate(filter.totalRate)).font(.aileron(12)).foregroundStyle(.ink2).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected == nil ? .s2 : .clear, in: .rect(cornerRadius: 9))
        .overlay(alignment: .leading) {
            if selected == nil { Capsule().fill(.allow).frame(width: 3).padding(.vertical, 10) }
        }
        .contentShape(.rect)
        .onTapGesture { selected = nil }
    }

    private func group(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 8) {
            Caption(title)
            Text("\(count)").font(.aileron(11, .semibold)).foregroundStyle(.ink2)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(.s3, in: .capsule)
        }
        .padding(EdgeInsets(top: 14, leading: 10, bottom: 8, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bg)
    }

    private func undecidedRow(_ app: String) -> some View {
        let stats = filter.stats
        let hosts = stats.hosts(app)
        return HStack(spacing: 10) {
            AppIcon(path: stats.paths[app])
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(stats.name(app)).font(.aileron(13, .semibold)).lineLimit(1).truncationMode(.middle)
                    GradeBadge(grade: stats.grade(app))
                }
                Text("\(hosts.count) hosts · \(hosts.intersection(stats.trackers).count) trackers")
                    .font(.aileron(11)).foregroundStyle(.ink3).monospacedDigit()
            }
            Spacer()
            IconButton(icon: "xmark", help: "Block", tint: .block, ring: true) {
                filter.update { $0.setAction(.block, for: app) }
            }
            IconButton(icon: "checkmark", help: "Allow", tint: .allow, ring: true) {
                filter.update { $0.setAction(.allow, for: app) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected == app ? .s2 : .clear, in: .rect(cornerRadius: 9))
        .contentShape(.rect)
        .onTapGesture { selected = app }
    }
}

private func split(_ text: String) -> (value: String, unit: String?) {
    let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
    return (parts.first ?? text, parts.dropFirst().first)
}

// The tracker counts of one grade, such as `1–2` or `11 or more`.
private func trackerCounts(_ range: ClosedRange<Int>) -> String {
    if range.upperBound == 0 { return "no trackers" }
    if range.upperBound == .max { return "\(range.lowerBound) or more" }
    return "\(range.lowerBound)–\(range.upperBound)"
}

private extension DayBars.Bar {
    // `lines` come before the date in the tooltip.
    init(day: Date, value: Double, tick: String? = nil, color: Color? = nil, parts: [SegmentBar.Part]? = nil, lines: [String] = []) {
        let date = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        self.init(
            id: Stats.day(day), label: (lines + [date]).joined(separator: "\n"),
            value: value, tick: tick, color: color, parts: parts
        )
    }

    // A date label every `step` days, kept away from the right edge. A narrow chart uses a longer step.
    static func weekly(_ index: Int, of count: Int, _ day: Date, step: Int = 7) -> String? {
        (count - 1 - index) % step == 2 ? day.formatted(.dateTime.day().month(.abbreviated)) : nil
    }
}

private struct Overview: View {
    let filter: Filter

    var body: some View {
        let stats = filter.stats
        let days = lastDays(31)
        let today = Stats.day(.now)
        let total = stats.totalBytes(day:)
        let data = days.enumerated().map { index, day in
            DayBars.Bar(day: day, value: Double(total(Stats.day(day))), tick: DayBars.Bar.weekly(index, of: days.count, day))
        }
        let blocked = days.enumerated().map { index, day in
            let parts = blockedParts(stats, day: Stats.day(day))
            let lines = parts.count > 1 ? parts.map { "\($0.name): \($0.value.formatted())" } : parts.map(\.name)
            return DayBars.Bar(
                day: day, value: Double(stats.blocked[Stats.day(day)] ?? 0),
                tick: DayBars.Bar.weekly(index, of: days.count, day, step: 14), parts: parts, lines: lines
            )
        }
        // The legend lists only the kinds the chart draws.
        let kinds = blocked.flatMap { $0.parts ?? [] }.filter { $0.value > 0 }
        let legend = [
            (name: "Block lists", color: Color.block), (name: "Rules and limits", color: .ruleBlock), (name: "Not split", color: .unsplit),
        ]
        .filter { kind in kinds.contains { $0.name == kind.name } }
        let top = stats.bytes.sorted { $0.value > $1.value }.prefix(5)
        let todayBytes = split(bytes(total(today)))
        let withTrackers = stats.apps.values.filter { $0.keys.contains(where: stats.trackers.contains) }.count
        let grades = Stats.grades.map { grade, range in
            SegmentBar.Part(
                name: "\(grade) · \(trackerCounts(range))", value: stats.apps.keys.filter { stats.grade($0) == grade }.count,
                color: .grade(grade), dark: "BCD".contains(grade)
            )
        }
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                let now = split(rate(filter.totalRate))
                Kpi(title: "Now", value: now.value, unit: now.unit) {
                    RateLine(values: filter.trend(nil), hover: true).frame(height: 28)
                }
                Kpi(title: "Today", value: todayBytes.value, unit: todayBytes.unit) {
                    Text("\(bytes(Int(data.reduce(0) { $0 + $1.value }))) in 31 days")
                }
                BlockedToday(stats: stats)
                Kpi(title: "Trackers seen", value: "\(stats.trackers.count)") {
                    Label("in \(withTrackers) apps", systemImage: "exclamationmark.triangle")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                Caption("Data · 31 days")
                DayBars(bars: data, format: { bytes(Int($0)) }).equatable().frame(height: 170)
            }
            .card()
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    Caption("Top apps")
                    RankedBars(
                        items: top.map { .init(key: $0.key, name: stats.name($0.key), value: Double($0.value), text: bytes($0.value)) },
                        stacked: true
                    ) { item in AppIcon(path: stats.paths[item.key], size: 22) }
                }
                .card()
                VStack(alignment: .leading, spacing: 14) {
                    Caption("Blocked flows · 31 days")
                    DayBars(bars: blocked, format: { Int($0).formatted() }).equatable().frame(height: 172)
                    Legend(parts: legend)
                }
                .card()
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Caption("Privacy grades")
                    Spacer()
                    Text("\(stats.apps.count) apps").foregroundStyle(.ink3)
                }
                SegmentBar(parts: grades, tall: true)
                Legend(parts: grades.map { ($0.name, $0.color) })
            }
            .card()
        }
    }
}

private struct XRay: View {
    let filter: Filter
    let app: String
    @FocusState private var editing: Bool
    @State private var clearing = false

    var body: some View {
        let stats = filter.stats
        let config = filter.config
        let hosts = stats.hosts(app)
        let trackers = hosts.intersection(stats.trackers)
        let limit = config.limits.first { $0.app == app }
        let used = limit.map { config.usage(app, period: $0.period, daily: stats.daily, today: Stats.day(.now)) } ?? 0
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                AppIcon(path: stats.paths[app], size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.name(app)).font(.aileron(20, .bold)).lineLimit(1)
                    Text(stats.paths[app] ?? app).font(.aileron(12)).foregroundStyle(.ink3)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if stats.apple.contains(app) { Chip(text: "Apple") }
                if stats.vpns?.contains(app) == true { Chip(text: "VPN") }
                if let limit, used >= limit.bytes {
                    Chip(text: "Over limit", icon: "exclamationmark.triangle.fill", iconColor: .serious, fill: .crit.opacity(0.2))
                }
                // Quiet mode never prompts, so this is the only place a code change shows.
                if let allowed = config.codes?[app], let running = stats.codes?[app], running != allowed {
                    Chip(text: "Code changed", icon: "exclamationmark.triangle.fill", iconColor: .warn)
                        .help("Its Allow rules do not count until you allow it again")
                }
                IconButton(icon: "clock.arrow.circlepath", help: "Clear history", ring: true) { clearing = true }
                    .confirmationDialog("Clear the history of \(stats.name(app))?", isPresented: $clearing) {
                        Button("Clear History", role: .destructive) { Task { await filter.forget(app) } }
                    } message: {
                        Text("Its traffic, hosts, IP addresses, and rule hits go. Its rules and data limit stay.")
                    }
                // `unknown` cannot have a rule, because many processes share it.
                if app != Config.unknownApp {
                    Segments(verdict: config.action(for: app)) { action in filter.update { $0.setAction(action, for: app) } }
                }
            }
            HStack(spacing: 12) {
                let open = stats.openTrackers(app)
                grade(stats.grade(app), trackers: open, blocked: trackers.count - open, hosts: hosts.count).frame(width: 250)
                VStack(alignment: .leading, spacing: 6) {
                    Caption("Now")
                    Text(rate(filter.rates[app] ?? 0)).font(.aileron(26, .light)).monospacedDigit()
                    RateLine(values: filter.trend(app), hover: true).frame(height: 70)
                    HStack {
                        Text("Total \(Text(bytes(stats.bytes[app] ?? 0)).foregroundStyle(.ink))")
                        Spacer()
                        Text("Today \(Text(bytes(stats.daily[Stats.day(.now)]?[app] ?? 0)).foregroundStyle(.ink))")
                    }
                    .font(.aileron(12))
                    .foregroundStyle(.ink3)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .card()
            }
            .fixedSize(horizontal: false, vertical: true)
            data(limit: limit, used: used)
            hostList(hosts.sorted { (trackers.contains($0) ? 0 : 1, $0) < (trackers.contains($1) ? 0 : 1, $1) }, trackers: trackers)
            addressList(stats.addresses?[app] ?? [:])
        }
        // macOS keeps a field focused when the user clicks outside it.
        .contentShape(.rect)
        .onTapGesture { editing = false }
    }

    private func grade(_ grade: String, trackers: Int, blocked: Int, hosts: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Caption("Privacy grade")
            HStack(spacing: 16) {
                GradeBadge(grade: grade, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(trackers)").font(.aileron(26, .light))
                        Text("trackers open").foregroundStyle(.ink3)
                    }
                    Text("\(blocked) blocked · \(hosts) hosts").font(.aileron(12)).foregroundStyle(.ink3)
                }
            }
            HStack(spacing: 2) {
                ForEach(Stats.grades.indices, id: \.self) { index in
                    let (letter, range) = Stats.grades[index]
                    let last = index == Stats.grades.count - 1
                    VStack(spacing: 5) {
                        UnevenRoundedRectangle(
                            topLeadingRadius: index == 0 ? 3 : 0, bottomLeadingRadius: index == 0 ? 3 : 0,
                            bottomTrailingRadius: last ? 3 : 0, topTrailingRadius: last ? 3 : 0
                        )
                        .fill(letter == grade ? Color.grade(letter) : .s3)
                        .frame(height: 6)
                        Text(letter).font(.aileron(10, letter == grade ? .semibold : .regular))
                            .foregroundStyle(letter == grade ? .ink : .ink3)
                    }
                    .help("Grade \(letter) · \(trackerCounts(range))")
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private func data(limit: Limit?, used: Int) -> some View {
        let stats = filter.stats
        let calendar = Calendar.current
        let month = limit?.period == .month
        let start = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let monthDays = (0..<(calendar.range(of: .day, in: .month, for: .now)?.count ?? 31)).map {
            calendar.date(byAdding: .day, value: $0, to: start) ?? start
        }
        let days = month ? Array(monthDays.prefix(calendar.component(.day, from: .now))) : lastDays(31)
        var running = 0
        let bars = days.enumerated().map { index, day in
            let value = stats.daily[Stats.day(day)]?[app] ?? 0
            running += value
            let reached = limit.map { (month ? running : value) >= $0.bytes } ?? false
            return DayBars.Bar(
                day: day, value: Double(value),
                tick: month ? (index % 5 == 0 ? "\(index + 1)" : nil) : DayBars.Bar.weekly(index, of: days.count, day),
                color: reached ? .crit : nil
            )
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Caption(month ? "Data · this month" : "Data · 31 days")
                Spacer()
                Text("Limit").foregroundStyle(.ink3)
                TextField("Data limit", value: megabytes, format: .number, prompt: Text("None"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 76)
                    .focused($editing)
                    // A focused field keeps its caret until something else takes focus.
                    .onSubmit { editing = false }
                    .onExitCommand { editing = false }
                Text("MB").foregroundStyle(.ink3)
                // The period menu needs a limit first.
                if let limit {
                    Segments(
                        options: [.init(value: Period.day, label: "Day"), .init(value: .month, label: "Month")],
                        selection: limit.period
                    ) { period in
                        filter.update { config in
                            if let index = config.limits.firstIndex(where: { $0.app == app }) { config.limits[index].period = period }
                        }
                    }
                }
            }
            if let limit {
                HStack(spacing: 14) {
                    Meter(used: used, limit: limit.bytes)
                    Text(
                        "\(Text(bytes(used)).font(.aileron(13, .semibold)).foregroundStyle(.ink)) of \(bytes(limit.bytes)) · \(used * 100 / max(limit.bytes, 1)) %"
                    )
                    .foregroundStyle(.ink3)
                    .monospacedDigit()
                }
            }
            DayBars(
                bars: bars, domain: month ? monthDays.map { Stats.day($0) } : nil,
                limit: limit.map { Double($0.bytes) }, cumulative: month, format: { bytes(Int($0)) }
            )
            .equatable()
            .frame(height: 170)
        }
        .card()
    }

    private func hostList(_ hosts: [String], trackers: Set<String>) -> some View {
        // A parent domain's rule covers the host too.
        let rows = hosts.map { (host: $0, rule: filter.config.hostRule(for: app, host: $0)) }
        return VStack(alignment: .leading, spacing: 0) {
            listHead("Hosts", actions: rows.map { $0.rule?.action })
            // There can be up to 1,000 hosts, so build only the rows on screen.
            LazyVStack(spacing: 0) {
                ForEach(rows, id: \.host) { host, rule in
                    let tracker = trackers.contains(host)
                    Rectangle().fill(.line).frame(height: 1)
                    HStack(spacing: 10) {
                        Image(systemName: tracker ? "exclamationmark.triangle" : "circle")
                            .font(.system(size: tracker ? 12 : 5, weight: .semibold))
                            .foregroundStyle(tracker ? .warn : .ink3)
                            .frame(width: 16)
                        Text(host).lineLimit(1).truncationMode(.middle)
                        if let parent = rule?.host, parent != host {
                            Text("from \(parent)").font(.aileron(11)).foregroundStyle(.ink3).lineLimit(1)
                        }
                        Spacer()
                        if tracker { Chip.tracker }
                        if app != Config.unknownApp {
                            Segments(verdict: rule?.action, small: true) { action in
                                filter.update { $0.setAction(action, for: app, host: host) }
                            }
                        }
                    }
                    .frame(height: 38)
                }
            }
        }
        .card()
    }

    // Rows with no host name come first, because only an IP rule can catch those flows.
    private func addressList(_ addresses: [String: Address]) -> some View {
        let rows = addresses.map { (address: $0.key, host: $0.value.host, action: filter.config.action(for: app, host: $0.key)) }
            .sorted { ($0.host == nil ? 0 : 1, $0.host ?? "", $0.address) < ($1.host == nil ? 0 : 1, $1.host ?? "", $1.address) }
        return VStack(alignment: .leading, spacing: 0) {
            listHead("IP addresses", actions: rows.map(\.action))
            LazyVStack(spacing: 0) {
                ForEach(rows, id: \.address) { address, host, action in
                    Rectangle().fill(.line).frame(height: 1)
                    HStack(spacing: 10) {
                        Image(systemName: "circle").font(.system(size: 5, weight: .semibold)).foregroundStyle(.ink3)
                            .frame(width: 16)
                        Text(address).monospacedDigit().lineLimit(1)
                        if let host {
                            Text(host).font(.aileron(11)).foregroundStyle(.ink3).lineLimit(1).truncationMode(.middle)
                        } else {
                            Chip(text: "No host name")
                        }
                        Spacer()
                        if app != Config.unknownApp {
                            Segments(verdict: action, small: true) { action in
                                filter.update { $0.setAction(action, for: app, host: address) }
                            }
                        }
                    }
                    .frame(height: 38)
                }
            }
        }
        .card()
    }

    // A list card's title, count, legend, and the bar of allowed, blocked, and no rule.
    @ViewBuilder private func listHead(_ title: String, actions: [Action?]) -> some View {
        let parts = [
            SegmentBar.Part(name: "Allowed", value: actions.count { $0 == .allow }, color: .allow),
            SegmentBar.Part(name: "Blocked", value: actions.count { $0 == .block }, color: .block),
            SegmentBar.Part(name: "No rule", value: actions.count { $0 == nil }, color: .s3),
        ]
        HStack(spacing: 10) {
            Caption(title)
            Text("\(actions.count)").foregroundStyle(.ink3).monospacedDigit()
            Spacer()
            Legend(parts: parts.map { ($0.name, $0.color) })
        }
        SegmentBar(parts: parts).padding(.top, 14).padding(.bottom, 12)
    }

    // In MB. Empty means no limit.
    private var megabytes: Binding<Int?> {
        Binding(
            get: { filter.config.limits.first { $0.app == app }.map { $0.bytes / 1_000_000 } },
            set: { megabytes in
                // Allow up to 1 PB. A larger number overflows `Int` in bytes, and zero or less would block the app right away.
                guard megabytes.map({ (1...1_000_000_000).contains($0) }) ?? true else { return }
                filter.update { config in
                    let period = config.limits.first { $0.app == app }?.period ?? .day
                    config.setLimit(megabytes.map { $0 * 1_000_000 }, period: period, for: app)
                }
            }
        )
    }
}

/// A toolbar button that clears every app's history. It asks first.
struct ClearAllHistory: View {
    let filter: Filter
    @State private var clearing = false

    var body: some View {
        ToolButton(title: "Clear all history…", icon: "clock.arrow.circlepath") { clearing = true }
            .confirmationDialog("Clear all history?", isPresented: $clearing) {
                Button("Clear All History", role: .destructive) { Task { await filter.clearHistory() } }
            } message: {
                Text(
                    "Every app, host, data count, blocked count, tracker, and rule hit goes. "
                        + "Rules, lists, data limits, and profiles stay."
                )
            }
    }
}

import SwiftUI

struct RulesView: View {
    let filter: Filter

    // The order of `Config.decide`, with the verdicts each step can give.
    private static let steps: [(label: String, outs: [Color])] = [
        ("App block", [.block]), ("Data limit", [.block]), ("Host rule", [.allow, .block]), ("Allow list", [.allow]),
        ("Block list", [.block]), ("App allow", [.allow]), ("Apple app", [.allow]), ("Mode", [.allow, .ink2]),
    ]

    var body: some View {
        let rules = filter.config.rules
        let stats = filter.stats
        if rules.isEmpty {
            EmptyState(icon: "checklist", title: "No rules yet", text: "Allow or block an app to make the first one.")
        } else {
            let split = [
                SegmentBar.Part(name: "Allow", value: rules.filter { $0.action == .allow }.count, color: .allow),
                SegmentBar.Part(name: "Block", value: rules.filter { $0.action == .block }.count, color: .block),
            ]
            let flags = Dictionary(grouping: rules.compactMap { stats.flags[$0.id] }, by: \.self).mapValues(\.count)
            let total = VStack(alignment: .leading, spacing: 10) {
                Caption("Rules")
                Text("\(rules.count)").font(.aileron(26, .light))
                Spacer(minLength: 0)
                SegmentBar(parts: split)
                Legend(parts: split.map { ("\($0.name) \($0.value)", $0.color) })
            }
            let unneeded = VStack(alignment: .leading, spacing: 8) {
                Caption("Not needed")
                Text("\(flags.values.reduce(0, +))").font(.aileron(26, .light))
                if flags.isEmpty { Text("Every rule can fire").font(.aileron(12)).foregroundStyle(.ink3) }
                ForEach(flags.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { flag in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 11, weight: .semibold)).foregroundStyle(.warn)
                        Text(flag.rawValue).foregroundStyle(.ink2)
                        Spacer()
                        Text("\(flags[flag] ?? 0)").font(.aileron(12, .semibold)).monospacedDigit()
                    }
                    .font(.aileron(12))
                }
            }
            ScrollView {
                VStack(spacing: 12) {
                    // The decision order needs room for its labels: below the counts in a narrow window.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            total.frame(width: 168).frame(maxHeight: .infinity, alignment: .top).card().fixedSize(
                                horizontal: true, vertical: false)
                            unneeded.frame(width: 198).frame(maxHeight: .infinity, alignment: .top).card().fixedSize(
                                horizontal: true, vertical: false)
                            decisionOrder.frame(minWidth: 680, maxHeight: .infinity, alignment: .top).card()
                        }
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                total.frame(maxHeight: .infinity, alignment: .top).card()
                                unneeded.frame(maxHeight: .infinity, alignment: .top).card()
                            }
                            decisionOrder.card()
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    table(rules)
                }
                .padding(EdgeInsets(top: 20, leading: 24, bottom: 28, trailing: 24))
            }
        }
    }

    private var decisionOrder: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Caption("Decision order")
                Spacer()
                Legend(parts: [("Allow", .allow), ("Block", .block), ("Ask", .ink2)])
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Self.steps.indices, id: \.self) { index in
                    VStack(spacing: 6) {
                        Text("\(index + 1)").font(.aileron(11, .bold))
                            .frame(width: 25, height: 25)
                            .background(.s3, in: .circle)
                        Text(Self.steps[index].label).font(.aileron(12)).foregroundStyle(.ink2).lineLimit(1).fixedSize()
                        HStack(spacing: 3) {
                            ForEach(Self.steps[index].outs.indices, id: \.self) { out in
                                Capsule().fill(Self.steps[index].outs[out]).frame(width: 14, height: 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // From the first node's centre to the last one's.
            .background(alignment: .topLeading) {
                GeometryReader { geometry in
                    let step = geometry.size.width / CGFloat(Self.steps.count)
                    Rectangle().fill(.line2)
                        .frame(width: step * CGFloat(Self.steps.count - 1), height: 1)
                        .offset(x: step / 2, y: 12)
                }
            }
        }
    }

    private func table(_ rules: [Rule]) -> some View {
        let stats = filter.stats
        let profiles = filter.config.profiles
        let rows = Self.rows(rules)
        let most = Double(max(rows.map { hits($0).count }.max() ?? 0, 1))
        let columns = VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(profiles.indices, id: \.self) { index in
                    let profile = profiles[index]
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.profile(index, profile.color)).frame(width: 10, height: 10)
                        Caption(profile.name).lineLimit(1)
                        if profile.id == stats.profile { Circle().fill(.good).frame(width: 7, height: 7).help("Active now") }
                    }
                    .frame(width: 120, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(profile.id == stats.profile ? Color.white.opacity(0.03) : .clear)
                }
            }
            .frame(height: 30)
            ForEach(rows) { row in
                let always = row.rule(nil)?.action
                HStack(spacing: 0) {
                    ForEach(profiles) { profile in
                        let own = row.rule(profile.id)?.action
                        let tip =
                            own.map { "\($0 == .allow ? "Allow" : "Block") while \(profile.name) is active" }
                            ?? "Follows Always: \(always.map { $0 == .allow ? "Allow" : "Block" } ?? "undecided")"
                        Pick(value: own, follows: own == nil ? always : nil, tip: tip) { action in
                            filter.update { $0.pick(action, for: row.app, host: row.host, profile: profile.id) }
                        }
                        .frame(width: 120, alignment: .leading)
                        .frame(maxHeight: .infinity)
                        .background(profile.id == stats.profile ? Color.white.opacity(0.03) : .clear)
                    }
                }
                .modifier(RowFrame(height: flag(row) == nil ? 48 : 60))
            }
        }
        .padding(.horizontal, profiles.isEmpty ? 0 : 8)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Caption("Rules by profile")
                Spacer()
                Label("Allow", systemImage: "checkmark")
                Label("Block", systemImage: "xmark")
                Label {
                    Text("Empty: follows Always")
                } icon: {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(.line2).frame(width: 10, height: 10)
                }
            }
            .font(.aileron(12))
            .foregroundStyle(.ink2)
            // Only the profile columns scroll sideways. Every part uses the same row heights, so rows line up.
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Caption("App and host").frame(width: 220, alignment: .leading)
                        Caption("Always").frame(width: 92, alignment: .leading)
                    }
                    .frame(height: 30, alignment: .top)
                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            appCell(row).frame(width: 220, alignment: .leading)
                            let always = row.rule(nil)?.action
                            Pick(
                                value: always, follows: nil,
                                tip: always.map { "\($0 == .allow ? "Allow" : "Block") always" } ?? "Undecided: the mode decides"
                            ) {
                                action in filter.update { $0.pick(action, for: row.app, host: row.host, profile: nil) }
                            }
                            .frame(width: 92, alignment: .leading)
                        }
                        .modifier(RowFrame(height: flag(row) == nil ? 48 : 60))
                        .overlay(alignment: .leading) {
                            if flag(row) != nil { Rectangle().fill(.warn).frame(width: 3).offset(x: -16) }
                        }
                    }
                }
                // As wide as the columns, so no gap is left. A scroll view would take all spare width.
                ViewThatFits(in: .horizontal) {
                    columns
                    ScrollView(.horizontal) { columns }
                        // Soft edges: columns hide under the fixed parts.
                        .overlay(alignment: .leading) { edge(.trailing) }
                        .overlay(alignment: .trailing) { edge(.leading) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Caption("Hits").frame(width: 136, alignment: .leading)
                        Caption("Last hit").frame(width: 104, alignment: .leading)
                        Color.clear.frame(width: 28, height: 1)
                    }
                    .frame(height: 30, alignment: .top)
                    ForEach(rows) { row in
                        let hit = hits(row)
                        HStack(spacing: 0) {
                            HStack(spacing: 10) {
                                GeometryReader { geometry in
                                    UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                                        .fill(row.rule(nil)?.action == .block ? .block : .allow)
                                        .frame(width: hit.count > 0 ? max(2, geometry.size.width * Double(hit.count) / most) : 0)
                                }
                                .frame(width: 64, height: 8)
                                Text(hit.count.formatted()).monospacedDigit().frame(width: 52, alignment: .trailing)
                            }
                            .frame(width: 136, alignment: .leading)
                            Text(hit.last.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                                .foregroundStyle(hit.last == nil ? .ink3 : .ink)
                                .lineLimit(1)
                                .frame(width: 104, alignment: .leading)
                            IconButton(icon: "trash", help: "Delete this row's rules") {
                                filter.update { $0.rules.removeAll { $0.app == row.app && $0.host == row.host } }
                            }
                        }
                        .modifier(RowFrame(height: flag(row) == nil ? 48 : 60))
                    }
                }
            }
        }
        .card()
    }

    private func appCell(_ row: Row) -> some View {
        let stats = filter.stats
        return HStack(spacing: 10) {
            AppIcon(path: stats.paths[row.app], size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.name(row.app)).font(.aileron(13, .semibold)).lineLimit(1).truncationMode(.middle)
                Text(row.host ?? "All hosts").font(.aileron(11)).foregroundStyle(.ink3).lineLimit(1).truncationMode(.middle)
                if let flag = flag(row) {
                    Label(flag.rawValue, systemImage: "exclamationmark.triangle.fill")
                        .font(.aileron(11, .semibold))
                        .foregroundStyle(.warn)
                }
            }
        }
        .padding(.trailing, 8)
    }

    private func hits(_ row: Row) -> (count: Int, last: Date?) {
        let hits = row.rules.compactMap { filter.stats.hits[$0.id] }
        return (hits.reduce(0) { $0 + $1.count }, hits.map(\.last).max())
    }

    private func edge(_ fade: UnitPoint) -> some View {
        LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: fade == .trailing ? .leading : .trailing, endPoint: fade)
            .frame(width: 12)
            .allowsHitTesting(false)
    }

    // In the order each app and host first appears.
    private static func rows(_ rules: [Rule]) -> [Row] {
        var rows: [Row] = []
        for rule in rules {
            if let index = rows.firstIndex(where: { $0.app == rule.app && $0.host == rule.host }) {
                rows[index].rules.append(rule)
            } else {
                rows.append(Row(app: rule.app, host: rule.host, rules: [rule]))
            }
        }
        return rows
    }

    private struct Row: Identifiable {
        let app: String
        let host: String?
        var rules: [Rule]
        var id: String { app + "\n" + (host ?? "") }

        func rule(_ profile: UUID?) -> Rule? { rules.first { $0.profile == profile } }
    }

    private func flag(_ row: Row) -> Flag? { row.rules.lazy.compactMap { filter.stats.flags[$0.id] }.first }
}

// One table row: a fixed height, so the fixed and scrolling parts line up, and a line on top.
private struct RowFrame: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(height: height)
            .overlay(alignment: .top) { Rectangle().fill(.line).frame(height: 1) }
    }
}

// Allow and Block for one column. Picking the chosen one again clears it.
private struct Pick: View {
    let value: Action?
    // What an empty profile cell inherits from Always: a faint outline.
    let follows: Action?
    let tip: String
    let choose: (Action) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach([Action.allow, .block], id: \.self) { action in
                let tint: Color = action == .allow ? .allow : .block
                let chosen = value == action
                Button {
                    choose(action)
                } label: {
                    Image(systemName: action == .allow ? "checkmark" : "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(chosen ? tint : follows == action ? tint.opacity(0.85) : .ink2)
                        .frame(width: 26, height: 22)
                        .background(chosen ? tint.opacity(0.16) : .clear, in: .rect(cornerRadius: 6))
                        .overlay {
                            if chosen || follows == action {
                                RoundedRectangle(cornerRadius: 6).strokeBorder(tint.opacity(chosen ? 0.55 : 0.45))
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action == .allow ? "Allow" : "Block")
            }
        }
        .padding(2)
        .background(.s1, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.line))
        .help(tip)
    }
}

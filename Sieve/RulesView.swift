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
        let most = Double(max(rules.map { stats.hits[$0.id]?.count ?? 0 }.max() ?? 0, 1))
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow {
                ForEach(["App", "Host", "Action", "Profile", "Hits", "Last hit", "", ""], id: \.self) { title in
                    Caption(title)
                }
            }
            .padding(.bottom, 10)
            ForEach(rules) { rule in
                let hit = stats.hits[rule.id]
                let flag = stats.flags[rule.id]
                Rectangle().fill(.line).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                GridRow {
                    HStack(spacing: 10) {
                        AppIcon(path: stats.paths[rule.app], size: 24)
                        Text(stats.name(rule.app)).font(.aileron(13, .semibold)).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(minHeight: 48)
                    .overlay(alignment: .leading) {
                        if flag != nil { Rectangle().fill(.warn).frame(width: 3).offset(x: -16) }
                    }
                    Text(rule.host ?? "All hosts").foregroundStyle(rule.host == nil ? .ink3 : .ink).lineLimit(1).truncationMode(.middle)
                    Chip(action: rule.action)
                    Picker("Profile", selection: profile(rule.id)) {
                        Text("Always").tag(nil as UUID?)
                        ForEach(filter.config.profiles) { Text($0.name).tag($0.id as UUID?) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    HStack(spacing: 10) {
                        GeometryReader { geometry in
                            let count = Double(hit?.count ?? 0)
                            UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                                .fill(rule.action == .allow ? .allow : .block)
                                .frame(width: count > 0 ? max(2, geometry.size.width * count / most) : 0)
                        }
                        .frame(width: 96, height: 8)
                        Text((hit?.count ?? 0).formatted()).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                    Text(hit.map { $0.last.formatted(.relative(presentation: .named)) } ?? "Never")
                        .foregroundStyle(hit == nil ? .ink3 : .ink)
                    Group {
                        if let flag {
                            Chip(text: flag.rawValue, icon: "exclamationmark.triangle.fill", iconColor: .warn, fill: .warn.opacity(0.14))
                        }
                    }
                    .gridColumnAlignment(.trailing)
                    IconButton(icon: "trash", help: "Delete") {
                        filter.update { $0.rules.removeAll { $0.id == rule.id } }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.s1, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.line))
    }

    private func profile(_ id: UUID) -> Binding<UUID?> {
        Binding(
            get: { filter.config.rules.first { $0.id == id }?.profile },
            set: { profile in
                filter.update { config in
                    if let index = config.rules.firstIndex(where: { $0.id == id }) { config.rules[index].profile = profile }
                }
            }
        )
    }
}

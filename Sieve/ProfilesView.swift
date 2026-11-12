import AppKit
import SwiftUI

struct ProfilesView: View {
    let filter: Filter

    // `Calendar` weekdays, Monday first. 1 is Sunday.
    private let week = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        let profiles = filter.config.profiles
        if profiles.isEmpty {
            EmptyState(icon: "wifi", title: "No profiles yet", text: "A profile switches rules by network or by time.")
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 16) {
                            Caption("This week")
                            Spacer()
                            Legend(parts: profiles.indices.map { (profiles[$0].name, Color.profile($0, profiles[$0].color)) })
                            Chip(text: router(filter.stats.networks.sorted().first) ?? "No network", icon: "wifi")
                        }
                        weekView(profiles)
                    }
                    .card()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 12) {
                        ForEach(profiles.indices, id: \.self) { index in card(profiles[index], index: index) }
                    }
                }
                .padding(EdgeInsets(top: 20, leading: 24, bottom: 28, trailing: 24))
            }
        }
    }

    private func weekView(_ profiles: [Profile]) -> some View {
        let now = Calendar.current.dateComponents([.weekday, .hour, .minute], from: .now)
        let minute = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(week, id: \.self) { day in
                GridRow {
                    Text(Calendar.current.shortWeekdaySymbols[day - 1]).font(.aileron(11, .semibold))
                        .foregroundStyle(day == now.weekday ? .ink : .ink3)
                        .frame(width: 34, alignment: .leading)
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(.bg)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.line))
                            ForEach(profiles.indices.reversed(), id: \.self) { index in
                                let blocks = profiles[index].schedules.filter { $0.weekdays.contains(day) }
                                ForEach(blocks.indices, id: \.self) { block in
                                    let schedule = blocks[block]
                                    ForEach(spans(schedule), id: \.0) { from, to in
                                        RoundedRectangle(cornerRadius: 3).fill(Color.profile(index, profiles[index].color))
                                            .frame(width: width * CGFloat(to - from) / 1440, height: 14)
                                            .offset(x: width * CGFloat(from) / 1440)
                                            .help("\(profiles[index].name): \(clock(schedule.start)) to \(clock(schedule.end))")
                                    }
                                }
                            }
                            if day == now.weekday {
                                Rectangle().fill(.ink).frame(width: 2, height: 24).offset(x: width * CGFloat(minute) / 1440 - 1)
                                    .help("Now, \(clock(minute))")
                            }
                        }
                    }
                    .frame(height: 18)
                }
            }
            GridRow {
                Color.clear.frame(width: 34, height: 1)
                GeometryReader { geometry in
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text(clock(hour * 60).prefix(2)).font(.aileron(10)).foregroundStyle(.ink3)
                            .position(x: geometry.size.width * CGFloat(hour) / 24, y: 7)
                    }
                }
                .frame(height: 14)
            }
        }
    }

    private func card(_ profile: Profile, index: Int) -> some View {
        let color = Color.profile(index, profile.color)
        let id = profile.id
        let count = filter.config.rules.filter { $0.profile == id }.count
        let rules = Text("\(count) \(count == 1 ? "rule" : "rules")").foregroundStyle(.ink3).monospacedDigit()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ColorPicker("Colour", selection: colour(profile.id, index), supportsOpacity: false)
                    .labelsHidden()
                    .help("Colour")
                TextField("Name", text: name(id)).textFieldStyle(.roundedBorder).font(.aileron(14, .semibold))
                if filter.stats.profile == id {
                    HStack(spacing: 6) {
                        Circle().fill(.good).frame(width: 7, height: 7)
                        Text("Active")
                    }
                    .font(.aileron(11, .semibold))
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(.s3, in: .capsule)
                }
                rules.font(.aileron(12)).fixedSize()
                IconButton(icon: "trash", help: "Delete") {
                    // Rules of a deleted profile could never count again.
                    filter.update { config in
                        config.profiles.removeAll { $0.id == id }
                        config.rules.removeAll { $0.profile == id }
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "wifi").foregroundStyle(.ink2)
                Text(router(profile.network) ?? "No network").foregroundStyle(.ink2).lineLimit(1)
                Spacer()
                Button("Use this network") {
                    let network = filter.stats.networks.sorted().first
                    filter.update { $0.profiles[id]?.network = network }
                }
                .disabled(filter.stats.networks.isEmpty)
                IconButton(icon: "xmark", help: "Clear network") { filter.update { $0.profiles[id]?.network = nil } }
                    .disabled(profile.network == nil)
            }
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(.ink2)
                Text(profile.schedules.isEmpty ? "No schedule" : "Times")
                    .foregroundStyle(profile.schedules.isEmpty ? .ink3 : .ink2)
                Spacer()
                Button("Add time", systemImage: "plus") {
                    filter.update { $0.profiles[id]?.schedules.append(Schedule(weekdays: [], start: 9 * 60, end: 17 * 60)) }
                }
                .controlSize(.small)
            }
            ForEach(profile.schedules.indices, id: \.self) { block in
                timeBlock(profile.schedules[block], profile: id, block: block, color: color)
            }
        }
        .card()
    }

    // One time block: its weekdays, a bar of its hours, and its times.
    private func timeBlock(_ schedule: Schedule, profile id: UUID, block: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 3) {
                ForEach(week, id: \.self) { day in
                    let on = schedule.weekdays.contains(day)
                    Button {
                        weekday(id, block, day).wrappedValue.toggle()
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[day - 1]).font(.aileron(12, .semibold))
                            .foregroundStyle(on ? .ink : .ink3)
                            .frame(width: 28, height: 28)
                            .background(on ? color.opacity(0.3) : .s1, in: .rect(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? color : .line2))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(Calendar.current.weekdaySymbols[day - 1])
                }
                Spacer()
                IconButton(icon: "xmark", help: "Remove this time") {
                    filter.update { config in
                        if config.profiles[id]?.schedules.indices.contains(block) == true {
                            config.profiles[id]?.schedules.remove(at: block)
                        }
                    }
                }
            }
            GeometryReader { geometry in
                Capsule().fill(.s3).overlay(alignment: .leading) {
                    ForEach(spans(schedule), id: \.0) { from, to in
                        Capsule().fill(color)
                            .frame(width: geometry.size.width * CGFloat(to - from) / 1440)
                            .offset(x: geometry.size.width * CGFloat(from) / 1440)
                    }
                }
            }
            .frame(height: 6)
            HStack(spacing: 8) {
                TimeField(minutes: minutes(id, block, \.start))
                Text("to").foregroundStyle(.ink3)
                TimeField(minutes: minutes(id, block, \.end))
            }
        }
        .padding(10)
        .background(.bg, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.line))
    }

    // An end before the start runs past midnight: two spans in one day.
    private func spans(_ schedule: Schedule) -> [(Int, Int)] {
        schedule.start <= schedule.end ? [(schedule.start, schedule.end)] : [(0, schedule.end), (schedule.start, 1440)]
    }

    private func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func router(_ signature: String?) -> String? {
        let prefix = "IPv4.Router="
        return signature?.split(separator: ";").first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    // `Color` is not `Codable`: store it in sRGB as `#rrggbb`.
    private func colour(_ id: UUID, _ index: Int) -> Binding<Color> {
        Binding(
            get: { .profile(index, filter.config.profiles[id]?.color) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let hex = String(
                    format: "#%02x%02x%02x", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255),
                    Int(rgb.blueComponent * 255))
                filter.update { $0.profiles[id]?.color = hex }
            }
        )
    }

    private func name(_ id: UUID) -> Binding<String> {
        Binding(
            get: { filter.config.profiles[id]?.name ?? "" },
            set: { name in filter.update { $0.profiles[id]?.name = name } }
        )
    }

    // A block without weekdays stays until removed, so a click too many loses no times.
    private func weekday(_ id: UUID, _ block: Int, _ day: Int) -> Binding<Bool> {
        Binding(
            get: { schedule(id, block)?.weekdays.contains(day) == true },
            set: { on in
                filter.update { config in
                    guard config.profiles[id]?.schedules.indices.contains(block) == true else { return }
                    if on {
                        config.profiles[id]?.schedules[block].weekdays.insert(day)
                    } else {
                        config.profiles[id]?.schedules[block].weekdays.remove(day)
                    }
                }
            }
        )
    }

    private func minutes(_ id: UUID, _ block: Int, _ path: WritableKeyPath<Schedule, Int>) -> Binding<Int> {
        Binding(
            get: { schedule(id, block)?[keyPath: path] ?? 0 },
            set: { minutes in
                filter.update { config in
                    guard config.profiles[id]?.schedules.indices.contains(block) == true else { return }
                    config.profiles[id]?.schedules[block][keyPath: path] = minutes
                }
            }
        )
    }

    // A block may be gone by the time a binding reads it.
    private func schedule(_ id: UUID, _ block: Int) -> Schedule? {
        filter.config.profiles[id]?.schedules.dropFirst(block).first
    }
}

// The hour and the minute, each a menu of every value. 23:59 ends a day.
private struct TimeField: View {
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 2) {
            Picker("Hour", selection: Binding(get: { minutes / 60 }, set: { minutes = $0 * 60 + minutes % 60 })) {
                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            Text(":").foregroundStyle(.ink3)
            Picker("Minute", selection: Binding(get: { minutes % 60 }, set: { minutes = minutes / 60 * 60 + $0 })) {
                ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .monospacedDigit()
        .fixedSize()
    }
}

private extension Array where Element == Profile {
    subscript(id: UUID) -> Profile? {
        get { first { $0.id == id } }
        set {
            guard let index = firstIndex(where: { $0.id == id }) else { return }
            if let newValue { self[index] = newValue } else { remove(at: index) }
        }
    }
}

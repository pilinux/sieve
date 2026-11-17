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
                                    RoundedRectangle(cornerRadius: 3).fill(Color.profile(index, profiles[index].color))
                                        .frame(width: width * CGFloat(schedule.end - schedule.start) / 1440, height: 14)
                                        .offset(x: width * CGFloat(schedule.start) / 1440)
                                        .help("\(profiles[index].name): \(clock(schedule.start)) to \(clock(schedule.end))")
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
        let rules = Text(counted(count, "rule")).foregroundStyle(.ink3).monospacedDigit()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                // Cards are laid out by position. The ID makes a fresh field, so a deleted profile's edit does not pass to the next card.
                ColourWell(filter: filter, id: id, index: index).id(id).held()
                NameField(filter: filter, id: id, name: profile.name).id(id).held()
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
                IconButton(icon: "trash", help: "Delete", held: true) {
                    // A deleted profile's rules could never apply again, so remove them too.
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
                let networks = filter.stats.networks.sorted()
                if networks.count > 1 {
                    // On Wi-Fi and Ethernet at once, only the user knows which one the profile is for.
                    Menu("Use this network") {
                        ForEach(networks, id: \.self) { network in
                            Button(router(network) ?? network) { filter.update { $0.profiles[id]?.network = network } }
                        }
                    }
                    .fixedSize()
                    .held()
                } else {
                    Button("Use this network") { filter.update { $0.profiles[id]?.network = networks.first } }
                        .disabled(networks.isEmpty)
                        .held()
                }
                IconButton(icon: "xmark", help: "Clear network") { filter.update { $0.profiles[id]?.network = nil } }
                    .disabled(profile.network == nil)
                    .held()
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
                .held()
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
                    .held()
                }
                Spacer()
                IconButton(icon: "xmark", help: "Remove this time", held: true) {
                    filter.update { config in
                        if config.profiles[id]?.schedules.indices.contains(block) == true {
                            config.profiles[id]?.schedules.remove(at: block)
                        }
                    }
                }
            }
            GeometryReader { geometry in
                Capsule().fill(.s3).overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * CGFloat(schedule.end - schedule.start) / 1440)
                        .offset(x: geometry.size.width * CGFloat(schedule.start) / 1440)
                }
            }
            .frame(height: 6)
            HStack(spacing: 8) {
                TimeField(minutes: minutes(id, block, \.start), range: 0...schedule.end - 1).held()
                Text("to").foregroundStyle(.ink3)
                // 24:00 is the end of the day. The end minute is not covered, so ending at 23:59 would leave a gap.
                TimeField(minutes: minutes(id, block, \.end), range: schedule.start + 1...1440).held()
            }
        }
        .padding(10)
        .background(.bg, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.line))
    }

    private func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func router(_ signature: String?) -> String? {
        let prefix = "IPv4.Router="
        return signature?.split(separator: ";").first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    // A block with no weekdays stays until the user removes it, so an extra click does not lose its times.
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

// A profile's colour. Each save sends and writes the whole config, so it waits until a drag in the colour panel stops.
private struct ColourWell: View {
    let filter: Filter
    let id: UUID
    let index: Int
    // `Color` is not `Codable`, so the colour is kept in sRGB as `#rrggbb`. Nil until the user picks one.
    @State private var hex: String?

    var body: some View {
        ColorPicker(
            "Colour",
            selection: Binding(
                get: { .profile(index, hex ?? filter.config.profiles[id]?.color) },
                set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    hex = String(
                        format: "#%02x%02x%02x", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255),
                        Int(rgb.blueComponent * 255))
                }),
            supportsOpacity: false
        )
        .labelsHidden()
        .help("Colour")
        .task(id: hex) {
            guard (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
            save()
        }
        .onDisappear(perform: save)
    }

    private func save() {
        guard let hex, let old = filter.config.profiles[id], old.color != hex else { return }
        filter.update { $0.profiles[id]?.color = hex }
    }
}

// A profile's name. Each save sends and writes the whole config, so it saves on Return or when the field loses focus.
private struct NameField: View {
    let filter: Filter
    let id: UUID
    @State var name: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $name)
            .textFieldStyle(.roundedBorder)
            .font(.aileron(14, .semibold))
            .focused($focused)
            .onSubmit(save)
            .onChange(of: focused) { if !focused { save() } }
            .onDisappear(perform: save)
    }

    private func save() {
        guard let old = filter.config.profiles[id]?.name, old != name else { return }
        filter.update { $0.profiles[id]?.name = name }
    }
}

// Two menus, one for the hour and one for the minute. Only times in `range` show, so a block always ends after it starts.
private struct TimeField: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 2) {
            // When the hour changes, keep the minute if the range allows it.
            let hour = Binding(
                get: { minutes / 60 },
                set: { minutes = min(max($0 * 60 + minutes % 60, range.lowerBound), range.upperBound) }
            )
            Picker("Hour", selection: hour) {
                ForEach(range.lowerBound / 60...range.upperBound / 60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            Text(":").foregroundStyle(.ink3)
            Picker("Minute", selection: Binding(get: { minutes % 60 }, set: { minutes = minutes / 60 * 60 + $0 })) {
                ForEach((0..<60).filter { range.contains(minutes / 60 * 60 + $0) }, id: \.self) {
                    Text(String(format: "%02d", $0)).tag($0)
                }
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

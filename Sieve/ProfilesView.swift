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
                            Legend(parts: profiles.indices.map { (profiles[$0].name, Color.profile($0)) })
                            Chip(text: router(filter.stats.networks.sorted().first) ?? "No network", icon: "wifi")
                        }
                        weekView(profiles)
                    }
                    .card()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 12) {
                        ForEach(profiles.indices, id: \.self) { index in card(profiles[index], color: .profile(index)) }
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
                                if let schedule = profiles[index].schedule, schedule.weekdays.contains(day) {
                                    ForEach(spans(schedule), id: \.0) { from, to in
                                        RoundedRectangle(cornerRadius: 3).fill(Color.profile(index))
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

    private func card(_ profile: Profile, color: Color) -> some View {
        let id = profile.id
        let count = filter.config.rules.filter { $0.profile == id }.count
        let rules = Text("\(count) \(count == 1 ? "rule" : "rules")").foregroundStyle(.ink3).monospacedDigit()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
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
            HStack(spacing: 4) {
                Image(systemName: "clock").foregroundStyle(.ink2).padding(.trailing, 4)
                ForEach(week, id: \.self) { day in
                    let on = profile.schedule?.weekdays.contains(day) == true
                    Button {
                        weekday(id, day).wrappedValue.toggle()
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[day - 1]).font(.aileron(12, .semibold))
                            .foregroundStyle(on ? .ink : .ink3)
                            .frame(width: 30, height: 30)
                            .background(on ? color.opacity(0.3) : .bg, in: .rect(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? color : .line2))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(Calendar.current.weekdaySymbols[day - 1])
                }
            }
            if let schedule = profile.schedule {
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
                    DatePicker("From", selection: time(id, \.start), displayedComponents: .hourAndMinute).labelsHidden()
                    Text("to").foregroundStyle(.ink3)
                    DatePicker("To", selection: time(id, \.end), displayedComponents: .hourAndMinute).labelsHidden()
                    Spacer()
                    rules
                }
            } else {
                HStack {
                    Text("No schedule").foregroundStyle(.ink3)
                    Spacer()
                    rules
                }
            }
        }
        .card()
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

    private func name(_ id: UUID) -> Binding<String> {
        Binding(
            get: { filter.config.profiles[id]?.name ?? "" },
            set: { name in filter.update { $0.profiles[id]?.name = name } }
        )
    }

    // The schedule exists while at least one weekday is on.
    private func weekday(_ id: UUID, _ day: Int) -> Binding<Bool> {
        Binding(
            get: { filter.config.profiles[id]?.schedule?.weekdays.contains(day) == true },
            set: { on in
                filter.update { config in
                    var schedule = config.profiles[id]?.schedule ?? Schedule(weekdays: [], start: 9 * 60, end: 17 * 60)
                    if on { schedule.weekdays.insert(day) } else { schedule.weekdays.remove(day) }
                    config.profiles[id]?.schedule = schedule.weekdays.isEmpty ? nil : schedule
                }
            }
        )
    }

    private func time(_ id: UUID, _ path: WritableKeyPath<Schedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = filter.config.profiles[id]?.schedule?[keyPath: path] ?? 0
                return Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(minutes * 60))
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                filter.update { $0.profiles[id]?.schedule?[keyPath: path] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
            }
        )
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

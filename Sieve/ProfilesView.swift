import SwiftUI

struct ProfilesView: View {
    let filter: Filter

    var body: some View {
        VStack(alignment: .leading) {
            Button("Add profile") { filter.update { $0.profiles.append(Profile(name: "New profile")) } }
            List(filter.config.profiles) { profile in
                let id = profile.id
                VStack(alignment: .leading) {
                    HStack {
                        Text("Name")
                        TextField("Name", text: name(id))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        if filter.stats.profile == id {
                            Text("Active").foregroundStyle(.green)
                        }
                        Button("Delete") {
                            // Rules of a deleted profile could never count again.
                            filter.update { config in
                                config.profiles.removeAll { $0.id == id }
                                config.rules.removeAll { $0.profile == id }
                            }
                        }
                    }
                    HStack {
                        Text(profile.network == nil ? "No network" : "On a saved network")
                        Button("Use on this network") {
                            let network = filter.stats.networks.sorted().first
                            filter.update { $0.profiles[id]?.network = network }
                        }
                        .disabled(filter.stats.networks.isEmpty)
                        Button("Clear") { filter.update { $0.profiles[id]?.network = nil } }
                            .disabled(profile.network == nil)
                    }
                    HStack {
                        ForEach(1...7, id: \.self) { day in
                            Toggle(Calendar.current.veryShortWeekdaySymbols[day - 1], isOn: weekday(id, day))
                                .toggleStyle(.button)
                        }
                        if profile.schedule != nil {
                            DatePicker("From", selection: time(id, \.start), displayedComponents: .hourAndMinute)
                            DatePicker("to", selection: time(id, \.end), displayedComponents: .hourAndMinute)
                        }
                    }
                }
            }
        }
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

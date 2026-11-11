//
//  ContentView.swift
//  Sieve
//
//  Created by Mahir on 11.11.26.
//

import ServiceManagement
import SwiftUI

struct ContentView: View {
    let filter: Filter
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(filter.status)
                Button("Turn on") { filter.turnOn() }
                Toggle("Launch at login", isOn: launchAtLogin)
                Spacer()
                ModePicker(filter: filter)
            }
            TabView {
                Tab("Apps", systemImage: "app") {
                    HSplitView {
                        List(selection: $selected) {
                            let undecided = filter.stats.undecided(filter.config)
                            Section("Undecided") {
                                ForEach(undecided, id: \.self) { app in
                                    HStack {
                                        Text(app).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Button("Allow") { filter.update { $0.setAction(.allow, for: app) } }
                                        Button("Block") { filter.update { $0.setAction(.block, for: app) } }
                                    }
                                }
                            }
                            Section("Apps") {
                                ForEach(filter.stats.apps.keys.filter { !undecided.contains($0) }.sorted(), id: \.self) { app in
                                    AppSwitch(filter: filter, app: app)
                                }
                            }
                        }
                        List {
                            if let selected {
                                Section("Grade \(filter.stats.grade(selected))") {
                                    HStack {
                                        Text("Data limit")
                                        TextField("Data limit", value: limit(selected), format: .number, prompt: Text("None"))
                                            .labelsHidden()
                                            .frame(width: 80)
                                        Text("MB")
                                        // A period needs a limit first.
                                        if limit(selected).wrappedValue != nil {
                                            Picker("per", selection: period(selected)) {
                                                Text("Day").tag(Period.day)
                                                Text("Month").tag(Period.month)
                                            }
                                            .fixedSize()
                                        }
                                    }
                                    ForEach(filter.stats.apps[selected, default: []].sorted(), id: \.self) { host in
                                        Picker(selection: rule(app: selected, host: host)) {
                                            Text("Allow").tag(Action.allow as Action?)
                                            Text("Block").tag(Action.block as Action?)
                                        } label: {
                                            Text(host)
                                            if filter.stats.trackers.contains(host) {
                                                Text("Tracker").foregroundStyle(.red)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                    }
                                }
                            }
                        }
                    }
                }
                Tab("Lists", systemImage: "list.bullet") {
                    ListsView(filter: filter)
                }
                Tab("Rules", systemImage: "checklist") {
                    RulesView(filter: filter)
                }
                Tab("Profiles", systemImage: "wifi") {
                    ProfilesView(filter: filter)
                }
            }
        }
        .padding()
        .task {
            await filter.resume()
            await filter.poll()
        }
    }

    // Shows the real state: if (un)registering fails, the switch stays put.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { launchesAtLogin }, set: { on in
            let service = SMAppService.mainApp
            try? on ? service.register() : service.unregister()
            launchesAtLogin = service.status == .enabled
        })
    }

    // No rule yet: neither segment is selected.
    // In MB. Empty: no limit.
    private func limit(_ app: String) -> Binding<Int?> {
        Binding(
            get: { filter.config.limits.first { $0.app == app }.map { $0.bytes / 1_000_000 } },
            set: { megabytes in
                filter.update { config in
                    let period = config.limits.first { $0.app == app }?.period ?? .day
                    config.setLimit(megabytes.map { $0 * 1_000_000 }, period: period, for: app)
                }
            }
        )
    }

    private func period(_ app: String) -> Binding<Period> {
        Binding(
            get: { filter.config.limits.first { $0.app == app }?.period ?? .day },
            set: { period in
                filter.update { config in
                    if let index = config.limits.firstIndex(where: { $0.app == app }) { config.limits[index].period = period }
                }
            }
        )
    }

    private func rule(app: String, host: String) -> Binding<Action?> {
        Binding(
            get: { filter.config.action(for: app, host: host) },
            set: { action in
                if let action { filter.update { $0.setAction(action, for: app, host: host) } }
            }
        )
    }
}

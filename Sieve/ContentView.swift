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
                        List(filter.stats.apps[selected ?? "", default: []].sorted(), id: \.self) { host in
                            Picker(host, selection: rule(app: selected ?? "", host: host)) {
                                Text("Allow").tag(Action.allow as Action?)
                                Text("Block").tag(Action.block as Action?)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                Tab("Lists", systemImage: "list.bullet") {
                    ListsView(filter: filter)
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
    private func rule(app: String, host: String) -> Binding<Action?> {
        Binding(
            get: { filter.config.action(for: app, host: host) },
            set: { action in
                if let action { filter.update { $0.setAction(action, for: app, host: host) } }
            }
        )
    }
}

//
//  ContentView.swift
//  Sieve
//
//  Created by Mahir on 11.11.26.
//

import ServiceManagement
import SwiftUI

struct ContentView: View {
    @State private var filter = Filter()
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(filter.status)
                Button("Turn on") { filter.turnOn() }
                Toggle("Launch at login", isOn: launchAtLogin)
                Spacer()
                Picker("Mode", selection: mode) {
                    Text("Off").tag(Mode.off)
                    Text("Ask").tag(Mode.ask)
                    Text("Quiet").tag(Mode.quiet)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            HSplitView {
                List(filter.stats.apps.keys.sorted(), id: \.self, selection: $selected) { app in
                    Toggle(app, isOn: allowed(app))
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
        .padding()
        .task {
            await filter.resume()
            while !Task.isCancelled {
                await filter.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var mode: Binding<Mode> {
        Binding(get: { filter.config.mode }, set: { mode in filter.update { $0.mode = mode } })
    }

    // Shows the real state: if (un)registering fails, the switch stays put.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { launchesAtLogin }, set: { on in
            let service = SMAppService.mainApp
            try? on ? service.register() : service.unregister()
            launchesAtLogin = service.status == .enabled
        })
    }

    private func allowed(_ app: String) -> Binding<Bool> {
        Binding(
            get: { filter.config.action(for: app) != .block },
            set: { on in filter.update { $0.setAction(on ? .allow : .block, for: app) } }
        )
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

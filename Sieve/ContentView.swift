//
//  ContentView.swift
//  Sieve
//
//  Created by Mahir on 11.11.26.
//

import SwiftUI

struct ContentView: View {
    @State private var filter = Filter()

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(filter.status)
                Button("Turn on") { filter.turnOn() }
                Spacer()
                Picker("Mode", selection: mode) {
                    Text("Off").tag(Mode.off)
                    Text("Quiet").tag(Mode.quiet)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            List(filter.stats.apps.keys.sorted(), id: \.self) { app in
                Toggle(app, isOn: allowed(app))
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

    private func allowed(_ app: String) -> Binding<Bool> {
        Binding(
            get: { filter.config.action(for: app) != .block },
            set: { on in filter.update { $0.setAction(on ? .allow : .block, for: app) } }
        )
    }
}

//
//  SieveApp.swift
//  Sieve
//
//  Created by Mahir on 11.11.26.
//

import SwiftUI

@main
struct SieveApp: App {
    @State private var filter = Filter()

    var body: some Scene {
        WindowGroup {
            ContentView(filter: filter)
        }
        MenuBarExtra("Sieve", systemImage: "line.3.horizontal.decrease.circle") {
            MenuView(filter: filter)
        }
        .menuBarExtraStyle(.window)
    }
}

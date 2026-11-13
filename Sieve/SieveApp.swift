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

    init() {
        Font.registerAileron()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(filter: filter)
        }
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1240, height: 800)
        .commands {
            // help menu.
            CommandGroup(replacing: .help) {
                // privacy policy.
                if let url = URL(string: "https://github.com/pilinux/sieve/blob/main/PRIVACY.md") {
                    Link("Privacy Policy", destination: url)
                }
            }
        }
        MenuBarExtra("Sieve", systemImage: "line.3.horizontal.decrease.circle") {
            MenuView(filter: filter)
        }
        .menuBarExtraStyle(.window)
    }
}

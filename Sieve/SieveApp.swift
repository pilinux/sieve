//
//  SieveApp.swift
//  Sieve
//
//  Created by Mahir on 11.11.26.
//

import AppKit
import SwiftUI

@main
struct SieveApp: App {
    @State private var filter = Filter()

    init() {
        Font.registerAileron()
        // A SwiftUI text field keeps editing until another view takes focus. A click anywhere else ends it, so the
        // field saves, as on Return. The click itself goes on as usual.
        _ = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated {
                guard let window = event.window, window.firstResponder is NSText else { return }
                let hit = window.contentView?.hitTest(event.locationInWindow)
                if !(hit is NSText || hit is NSTextField) { window.makeFirstResponder(nil) }
            }
            return event
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(filter: filter)
        }
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1240, height: 800)
        .commands {
            // Sieve has no help book, so the policy replaces the empty Help item.
            CommandGroup(replacing: .help) {
                if let url = URL(string: "https://github.com/pilinux/sieve/blob/main/PRIVACY.md") {
                    Link("Privacy Policy", destination: url)
                }
            }
        }
        MenuBarExtra {
            MenuView(filter: filter)
        } label: {
            Image(filter.status == .on ? "MenuMark" : "MenuMarkOff").accessibilityLabel("Sieve")
        }
        .menuBarExtraStyle(.window)
    }
}

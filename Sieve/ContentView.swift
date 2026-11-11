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
        VStack {
            Text(filter.status)
            Button("Turn on") { filter.turnOn() }
        }
        .padding()
        .task { await filter.resume() }
    }
}

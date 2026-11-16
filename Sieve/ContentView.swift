//
//  ContentView.swift
//  Sieve
//
//  Created by Mahir on 11.11.26.
//

import SwiftUI

struct ContentView: View {
    let filter: Filter
    @State private var screen = Screen.apps

    var body: some View {
        Group {
            if filter.status == .on {
                // The toolbar makes the title bar taller, which puts the window buttons inside the sidebar pane.
                HStack(spacing: 0) {
                    Sidebar(filter: filter, screen: $screen)
                    VStack(spacing: 0) {
                        Text(screen.rawValue).font(.aileron(18, .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 16)
                            .frame(height: 60)
                        if filter.stats.brokenConfig {
                            BrokenConfigNotice(filter: filter).padding(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 24))
                        }
                        Group {
                            switch screen {
                            case .apps: AppsView(filter: filter)
                            case .lists: ListsView(filter: filter)
                            case .rules: RulesView(filter: filter)
                            case .profiles: ProfilesView(filter: filter)
                            case .diagnostics: DiagnosticsView(filter: filter)
                            }
                        }
                        // A soft scroll edge under the title. A mask costs less than a blur.
                        .mask {
                            VStack(spacing: 0) {
                                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 14)
                                Color.black
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if let message = filter.message {
                                HStack(spacing: 10) {
                                    Image(systemName: message.failed ? "exclamationmark.triangle.fill" : "checkmark")
                                        .foregroundStyle(message.failed ? .serious : .good)
                                    Text(message.text)
                                }
                                .font(.aileron(13, .semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .glassEffect(.regular, in: .capsule)
                                .padding(.bottom, 20)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .animation(.easeOut(duration: 0.2), value: filter.message?.text)
                        .task(id: filter.message?.text) {
                            try? await Task.sleep(for: .seconds(4))
                            if !Task.isCancelled { filter.message = nil }
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)
                .navigationTitle(screen.rawValue)
                .toolbar { toolbar }
            } else {
                SetupView(filter: filter).ignoresSafeArea()
            }
        }
        .toolbar(removing: .title)
        .font(.aileron(13))
        .foregroundStyle(.ink)
        .frame(minWidth: 1240, minHeight: 760)
        .containerBackground(.bg, for: .window)
        .preferredColorScheme(.dark)
        .task { await filter.poll() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarSpacer(.flexible)
        ToolbarItem {
            // One container draws all the capsules at once, which is cheaper than drawing each one alone.
            GlassEffectContainer {
                HStack(spacing: 16) {
                    if screen == .profiles {
                        ToolButton(title: "Add profile", icon: "plus") {
                            filter.update { $0.profiles.append(Profile(name: "New profile")) }
                        }
                    }
                    if screen == .apps { ClearAllHistory(filter: filter) }
                    if screen == .diagnostics { DiagnosticsTools(filter: filter) }
                    HStack(spacing: 10) {
                        RateLine(values: filter.trend(nil)).frame(width: 72, height: 22)
                        Text(rate(filter.totalRate))
                            .font(.aileron(13, .semibold)).monospacedDigit()
                            .frame(minWidth: 76, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .glassEffect(.regular, in: .capsule)
                    ModePicker(filter: filter, glass: true)
                }
            }
            // Matches the design's 24 pt margin. The toolbar already adds 6.
            .padding(.trailing, 18)
            // Line up with the title, which sits lower than the window buttons.
            .offset(y: 4)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

enum Screen: String, CaseIterable {
    case apps = "Apps", lists = "Lists", rules = "Rules", profiles = "Profiles", diagnostics = "Diagnostics"

    var icon: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .lists: "list.bullet"
        case .rules: "checklist"
        case .profiles: "wifi"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}

private struct Sidebar: View {
    let filter: Filter
    @Binding var screen: Screen

    var body: some View {
        let stats = filter.stats
        let active = filter.config.profiles.firstIndex { $0.id == stats.profile }
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image("Mark").resizable().frame(width: 26, height: 26)
                Text("Sieve").font(.aileron(17, .bold))
            }
            // Leave room for the window buttons.
            .padding(.top, 52)
            .padding(.horizontal, 8)
            .padding(.bottom, 22)
            ForEach(Screen.allCases, id: \.self) { item in
                let count =
                    switch item {
                    case .apps: stats.undecided(filter.config).count
                    case .rules: filter.config.rules.filter { stats.flags[$0.id] != nil }.count
                    default: 0
                    }
                Button {
                    screen = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon).frame(width: 16).foregroundStyle(item == screen ? .allow : .ink2)
                        Text(item.rawValue)
                        Spacer()
                        if count > 0 {
                            Text("\(count)").font(.aileron(11, .semibold))
                                .padding(.horizontal, 6)
                                .frame(minWidth: 20, minHeight: 18)
                                .background(item == .rules ? Color.warn.opacity(0.18) : .s3, in: .capsule)
                        }
                    }
                    .font(.aileron(13, .semibold))
                    .foregroundStyle(item == screen ? .ink : .ink2)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(item == screen ? .white.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            // Keep the status near the top. If the window is partly off screen, the bottom of the sidebar can be hidden.
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    let on = filter.config.mode != .off
                    Circle().fill(on ? .good : .ink3).frame(width: 8, height: 8)
                        .background(Circle().fill(on ? Color.good.opacity(0.2) : .clear).frame(width: 14, height: 14))
                    Text(on ? "On" : "Off").font(.aileron(13, .semibold))
                    Spacer()
                    if let active {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.profile(active, filter.config.profiles[active].color)).frame(
                                width: 10, height: 10)
                            Text(filter.config.profiles[active].name)
                        }
                        .font(.aileron(11, .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(.s3, in: .capsule)
                    }
                }
                HStack {
                    Text("Blocked today").foregroundStyle(.ink2)
                    Spacer()
                    Text("\(stats.blocked[Stats.day(.now)] ?? 0)").font(.aileron(13, .semibold)).monospacedDigit()
                }
                .font(.aileron(12))
            }
            .card(padding: 12)
            .padding(.top, 16)
            Spacer()
            LaunchAtLogin().padding(.horizontal, 6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(width: 208)
        .frame(maxHeight: .infinity)
        // Keep the corner concentric with the window corner.
        .glassEffect(.regular, in: .rect(cornerRadius: 19))
        .padding(EdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 8))
    }
}

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
            if filter.status == "On" {
                HStack(spacing: 0) {
                    Sidebar(filter: filter, screen: $screen)
                    VStack(spacing: 0) {
                        header
                        Rectangle().fill(.line).frame(height: 1)
                        switch screen {
                        case .apps: AppsView(filter: filter)
                        case .lists: ListsView(filter: filter)
                        case .rules: RulesView(filter: filter)
                        case .profiles: ProfilesView(filter: filter)
                        }
                    }
                }
            } else {
                SetupView(filter: filter)
            }
        }
        .font(.aileron(13))
        .foregroundStyle(.ink)
        .frame(minWidth: 1100, minHeight: 700)
        .ignoresSafeArea()
        .containerBackground(.bg, for: .window)
        .preferredColorScheme(.dark)
        .task {
            await filter.resume()
            await filter.poll()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(screen.rawValue).font(.aileron(18, .bold))
            Spacer()
            if screen == .profiles {
                Button("Add profile", systemImage: "plus") {
                    filter.update { $0.profiles.append(Profile(name: "New profile")) }
                }
            }
            RateLine(values: filter.trend(nil)).frame(width: 72, height: 22)
            Text(rate(filter.rates.values.reduce(0, +)))
                .font(.aileron(13, .semibold)).monospacedDigit()
                .frame(minWidth: 76, alignment: .trailing)
            ModePicker(filter: filter)
        }
        .padding(.horizontal, 24)
        .frame(height: 60)
    }
}

enum Screen: String, CaseIterable {
    case apps = "Apps", lists = "Lists", rules = "Rules", profiles = "Profiles"

    var icon: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .lists: "list.bullet"
        case .rules: "checklist"
        case .profiles: "wifi"
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
                Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 20)).foregroundStyle(.allow)
                Text("Sieve").font(.aileron(17, .bold))
            }
            // Room for the window buttons.
            .padding(.top, 52)
            .padding(.horizontal, 8)
            .padding(.bottom, 22)
            ForEach(Screen.allCases, id: \.self) { item in
                let count = switch item {
                case .apps: stats.undecided(filter.config).count
                case .rules: filter.config.rules.filter { stats.flags[$0.id] != nil }.count
                default: 0
                }
                Button { screen = item } label: {
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
                    .background(item == screen ? .s2 : .clear, in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    let on = filter.config.mode != .off
                    Circle().fill(on ? .good : .ink3).frame(width: 8, height: 8)
                        .background(Circle().fill(on ? Color.good.opacity(0.2) : .clear).frame(width: 14, height: 14))
                    Text(on ? "On" : "Off").font(.aileron(13, .semibold))
                    Spacer()
                    if let active {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.profile(active)).frame(width: 10, height: 10)
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
            LaunchAtLogin().padding(.horizontal, 6).padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(width: 208)
        .frame(maxHeight: .infinity)
        .background(.side)
        .overlay(alignment: .trailing) { Rectangle().fill(.line).frame(width: 1) }
    }
}

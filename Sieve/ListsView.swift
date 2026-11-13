import SwiftUI
import UniformTypeIdentifiers

struct ListsView: View {
    let filter: Filter
    @State private var url = ""
    @State private var action = Action.block
    @State private var picking = false

    var body: some View {
        let config = filter.config
        let stats = filter.stats
        let shield = config.lists.first { $0.id == DomainList.trackerShield.id }
        let others = config.lists.filter { $0.id != DomainList.trackerShield.id }
        let blocking = config.lists.filter { $0.enabled && $0.action == .block }
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    if let shield { shieldCard(shield) }
                    VStack(alignment: .leading, spacing: 14) {
                        Caption("Add a list")
                        TextField("https URL", text: $url).textFieldStyle(.roundedBorder)
                        HStack {
                            Segments(verdict: action) { action = $0 }
                            Spacer()
                            Button("Upload", systemImage: "square.and.arrow.up") { picking = true }
                            Button("Add", systemImage: "plus") { add() }
                                .buttonStyle(.borderedProminent)
                                .tint(.allow)
                                .disabled(URL(string: url)?.scheme != "https")
                        }
                    }
                    .card()
                    .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { result in
                        switch result {
                        case .success(let file):
                            let list = DomainList(name: file.lastPathComponent, action: action)
                            Task { await filter.upload(list, from: file) }
                        case .failure(let error):
                            filter.message = ("Cannot open the file: \(error.localizedDescription)", true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            Caption("Lists")
                            Text("\(others.count)").foregroundStyle(.ink3)
                        }
                        .padding(.bottom, 4)
                        ForEach(others) { list in
                            Rectangle().fill(.line).frame(height: 1).padding(.top, 8)
                            HStack(spacing: 12) {
                                Toggle(list.name, isOn: enabled(list.id)).toggleStyle(.switch).labelsHidden().tint(.allow)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(list.name).font(.aileron(13, .semibold))
                                    Text(list.url ?? "Uploaded file").font(.aileron(11)).foregroundStyle(.ink3)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                if let size = stats.listSizes[list.id] {
                                    Text(size.formatted()).foregroundStyle(.ink3).monospacedDigit()
                                }
                                Chip(action: list.action)
                                if list.url != nil {
                                    IconButton(icon: "arrow.clockwise", help: "Refresh") { Task { await filter.load(list) } }
                                }
                                IconButton(icon: "trash", help: "Delete this list") {
                                    filter.update { $0.lists.removeAll { $0.id == list.id } }
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .card()
                }
                .frame(width: 440)
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Kpi(title: "Domains blocked", value: (stats.blockedDomains ?? 0).formatted()) {
                            Text("\(blocking.count) lists on")
                        }
                        Kpi(title: "Trackers seen", value: "\(stats.trackers.count)") {
                            Label("hosts on a block list", systemImage: "exclamationmark.triangle")
                        }
                        Kpi(title: "Blocked today", value: "\(stats.blocked[Stats.day(.now)] ?? 0)") {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 3).fill(.block).frame(width: 10, height: 10)
                                Text("flows dropped")
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 14) {
                        Caption("Apps that reach trackers")
                        let apps = stats.apps.map { (key: $0.key, count: $0.value.keys.filter(stats.trackers.contains).count) }
                            .filter { $0.count > 0 }
                            .sorted { $0.count > $1.count }
                            .prefix(7)
                        RankedBars(
                            items: apps.map {
                                .init(key: $0.key, name: stats.name($0.key), value: Double($0.count), text: "\($0.count) hosts")
                            },
                            color: .block, nameWidth: 190
                        ) { item in AppIcon(path: stats.paths[item.key], size: 22) }
                    }
                    .card()
                    VStack(alignment: .leading, spacing: 14) {
                        Caption("Most common trackers")
                        let hosts = stats.trackers.map { host in (host: host, count: stats.apps.values.filter { $0[host] != nil }.count) }
                            .sorted { ($0.count, $1.host) > ($1.count, $0.host) }
                            .prefix(7)
                        RankedBars(
                            items: hosts.map { .init(name: $0.host, value: Double($0.count), text: "\($0.count) apps") },
                            color: .block, nameWidth: 190
                        ) { _ in
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.warn).frame(width: 22)
                        }
                    }
                    .card()
                }
            }
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 28, trailing: 24))
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

    private func shieldCard(_ shield: DomainList) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: "shield").font(.system(size: 26, weight: .medium))
                    .foregroundStyle(shield.enabled ? .block : .ink3)
                    .frame(width: 56, height: 56)
                    .background(shield.enabled ? Color.block.opacity(0.16) : .s3, in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(shield.name).font(.aileron(16, .bold))
                    if let size = filter.stats.listSizes[shield.id] {
                        Text("\(size.formatted()) domains").foregroundStyle(.ink3).monospacedDigit()
                    }
                }
                Spacer()
                Toggle(shield.name, isOn: enabled(shield.id)).toggleStyle(.switch).labelsHidden().controlSize(.large).tint(.allow)
            }
            HStack {
                Text("Ads, trackers, malware · Steven Black's hosts").font(.aileron(12)).foregroundStyle(.ink2)
                Spacer()
                IconButton(icon: "arrow.clockwise", help: "Refresh") { Task { await filter.load(shield) } }
            }
        }
        .card()
    }

    private func add() {
        guard let parsed = URL(string: url) else { return }
        let list = DomainList(name: parsed.host() ?? parsed.lastPathComponent, url: url, action: action)
        filter.update { $0.lists.append(list) }
        url = ""
        Task { await filter.load(list) }
    }

    private func enabled(_ id: String) -> Binding<Bool> {
        Binding(
            get: { filter.config.lists.first { $0.id == id }?.enabled ?? false },
            set: { on in
                filter.update { config in
                    if let index = config.lists.firstIndex(where: { $0.id == id }) { config.lists[index].enabled = on }
                }
            }
        )
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct ListsView: View {
    let filter: Filter
    @State private var url = ""
    @State private var action = Action.block
    @State private var picking = false
    @State private var pickingIPInfo = false
    @State private var domain = ""
    @State private var checked: (host: String, entries: [String: String])?

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
                    VStack(alignment: .leading, spacing: 12) {
                        Caption("Check a domain")
                        TextField("Host name or URL", text: $domain).textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await check() } }
                        if let checked { checkResult(checked) }
                    }
                    .card()
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
                    ipInfoCard
                }
                .frame(width: 440)
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Kpi(title: "Domains blocked", value: (stats.blockedDomains ?? 0).formatted()) {
                            Text("\(counted(blocking.count, "list")) on")
                        }
                        Kpi(title: "Trackers seen", value: "\(stats.trackers.count)") {
                            Label("hosts on a block list", systemImage: "exclamationmark.triangle")
                        }
                        BlockedToday(stats: stats)
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
                                .init(
                                    key: $0.key, name: stats.name($0.key), value: Double($0.count),
                                    text:
                                        "\(counted($0.count, "host")) · \(counted(stats.trackerCalls($0.key), "call"))"
                                )
                            },
                            color: .block, nameWidth: 190, valueWidth: 150,
                            details: { item in
                                stats.apps[item.key, default: [:]].keys.filter(stats.trackers.contains)
                                    .map { (host: $0, calls: stats.trackerFlows?[item.key]?[$0] ?? 0) }
                                    .sorted { ($0.calls, $1.host) > ($1.calls, $0.host) }
                                    .map { (name: $0.host, text: counted($0.calls, "call")) }
                            }
                        ) { item in AppIcon(path: stats.paths[item.key], size: 22) }
                    }
                    .card()
                    VStack(alignment: .leading, spacing: 14) {
                        Caption("Most common trackers")
                        let hosts = stats.trackers.map { host in (host: host, count: stats.apps.values.filter { $0[host] != nil }.count) }
                            .sorted { ($0.count, $1.host) > ($1.count, $0.host) }
                            .prefix(7)
                        RankedBars(
                            items: hosts.map {
                                .init(
                                    name: $0.host, value: Double($0.count),
                                    text:
                                        "\(counted($0.count, "app")) · \(counted(stats.trackerCalls(host: $0.host), "call"))"
                                )
                            },
                            color: .block, nameWidth: 190, valueWidth: 150,
                            details: { item in
                                stats.apps.filter { $0.value[item.name] != nil }
                                    .map { (name: stats.name($0.key), calls: stats.trackerFlows?[$0.key]?[item.name] ?? 0) }
                                    .sorted { ($0.calls, $1.name) > ($1.calls, $0.name) }
                                    .map { (name: $0.name, text: counted($0.calls, "call")) }
                            }
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
    }

    // A URL works too. Only its host counts.
    private func check() async {
        let text = domain.trimmingCharacters(in: .whitespaces)
        guard let host = DomainList.normalize(text.contains("://") ? URL(string: text)?.host ?? "" : text) else { return }
        guard let entries = await filter.listEntries(for: host) else {
            filter.message = ("The filter cannot be reached, so the lists cannot be checked.", true)
            return
        }
        checked = (host, entries)
    }

    // The lists' verdict, as `Config.isListBlocked` decides it, then each list that has the host.
    private func checkResult(_ checked: (host: String, entries: [String: String])) -> some View {
        let lists = filter.config.lists.filter { checked.entries[$0.id] != nil }
        let on = lists.filter(\.enabled)
        let verdict =
            if on.contains(where: { $0.action == .allow }) {
                "An allow list lets \(checked.host) through."
            } else if !on.isEmpty {
                "Lists block \(checked.host)."
            } else if !lists.isEmpty {
                "Only lists that are off have \(checked.host)."
            } else {
                "No list has \(checked.host)."
            }
        return VStack(alignment: .leading, spacing: 8) {
            Text(verdict).font(.aileron(13, .semibold))
            ForEach(lists) { list in
                HStack(spacing: 8) {
                    Text(list.name).lineLimit(1)
                    Chip(action: list.action)
                    if !list.enabled { Chip(text: "Off") }
                    Spacer()
                    Text(checked.entries[list.id] ?? "").foregroundStyle(.ink3).lineLimit(1).truncationMode(.middle)
                        .help("The entry that matched. It covers its subdomains too.")
                }
                .font(.aileron(12))
            }
            Text("Lists only. An app's own rules come first.").font(.aileron(11)).foregroundStyle(.ink3)
        }
    }

    // The uploaded IPinfo Lite file. Sieve never downloads it, since the download needs the user's own IPinfo token.
    private var ipInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Caption("IP data")
            if let progress = filter.ipInfoProgress {
                ProgressView(value: progress) { Text("Reading the IPinfo file") }
            } else if let ipInfo = filter.ipInfo {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("IPinfo Lite").font(.aileron(13, .semibold))
                        Text(
                            "\(counted(ipInfo.table.sourceCount, "range")) · uploaded \(ipInfo.date.formatted(date: .abbreviated, time: .omitted))"
                        )
                        .font(.aileron(11)).foregroundStyle(.ink3).monospacedDigit()
                    }
                    Spacer()
                    IconButton(icon: "square.and.arrow.up", help: "Upload a newer copy") { pickingIPInfo = true }
                    IconButton(icon: "trash", help: "Remove the IP data") { filter.removeIPInfo() }
                }
                Text(
                    "X-Ray, Rules, and prompts show each address's country and network owner. CDN, public DNS, and local addresses show those labels in place of a country, with or without this file."
                )
                .font(.aileron(12)).foregroundStyle(.ink3)
                Text("IP data from [IPinfo](https://ipinfo.io) · CC BY-SA 4.0").font(.aileron(11)).foregroundStyle(.ink3)
            } else {
                Text("Show each IP address's country and network owner.")
                Text(
                    "Download **ipinfo_lite.csv.gz** with a free account at [ipinfo.io/lite](https://ipinfo.io/lite), then upload it here. It stays on this Mac. Sieve sends no address anywhere."
                )
                .foregroundStyle(.ink3)
                HStack {
                    Spacer()
                    Button("Upload", systemImage: "square.and.arrow.up") { pickingIPInfo = true }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .fileImporter(isPresented: $pickingIPInfo, allowedContentTypes: [.gzip, .commaSeparatedText]) { result in
            switch result {
            case .success(let file): Task { await filter.uploadIPInfo(from: file) }
            case .failure(let error): filter.message = ("Cannot open the file: \(error.localizedDescription)", true)
            }
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
                        Text(counted(size, "domain")).foregroundStyle(.ink3).monospacedDigit()
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

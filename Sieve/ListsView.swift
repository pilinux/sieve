import SwiftUI
import UniformTypeIdentifiers

struct ListsView: View {
    let filter: Filter
    @State private var url = ""
    @State private var action = Action.block
    @State private var picking = false
    @State private var pickingIPInfo = false
    @State private var pickingAllowlist = false
    @State private var confirmingAllowOnly = false
    @State private var deletingAllowlist = false
    @State private var domain = ""
    @State private var checked: (host: String, entries: [String: String])?
    @State private var downloading: String?
    @State private var deleting: DomainList?

    // Steven Black's extensions, each without the base list. None ships with Sieve, so each one downloads when the
    // user first turns it on.
    private static let extensions = [
        ("fakenews", "Fake news", "Sites that spread false news"),
        ("gambling", "Gambling", "Betting and casino sites"),
        ("porn", "Adult content", "Pornography and other explicit sites"),
        ("social", "Social", "Facebook, TikTok, X, and others"),
    ].map { key, label, about in
        (
            list: DomainList(
                id: "tracker-shield-\(key)", name: "Tracker Shield · \(label)",
                url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/\(key)-only/hosts", action: .block
            ),
            label: label, about: about
        )
    }

    var body: some View {
        let config = filter.config
        let stats = filter.stats
        let shield = config.lists.first { $0.id == DomainList.trackerShield.id }
        let others = config.lists.filter { list in
            list.id != DomainList.trackerShield.id && !Self.extensions.contains { $0.list.id == list.id }
        }
        let blocking = config.lists.filter { $0.enabled && $0.action == .block }
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    if let shield { shieldCard(shield) }
                    allowlistCard
                    VStack(alignment: .leading, spacing: 14) {
                        Caption("Add a list")
                        SearchField(text: $url, prompt: "https URL", icon: "link")
                        HStack {
                            Segments(verdict: action) { action = $0 }
                            Spacer()
                            Button("Upload", systemImage: "square.and.arrow.up") { picking = true }.held()
                            Button("Add", systemImage: "plus") { add() }
                                .buttonStyle(.borderedProminent)
                                .tint(.allow)
                                .disabled(URL(string: url)?.scheme != "https")
                                .held()
                        }
                    }
                    .card()
                    .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { result in
                        let action = action
                        usePicked(result) { await filter.upload(DomainList(name: $0.lastPathComponent, action: action), from: $0) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Caption("Check a domain")
                        SearchField(text: $domain, prompt: "Host name or URL").onSubmit { Task { await check() } }
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
                                Toggle(list.name, isOn: enabled(list.id)).toggleStyle(.switch).labelsHidden().tint(.allow).held()
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
                                    IconButton(icon: "arrow.clockwise", help: "Refresh", held: true) { Task { await filter.load(list) } }
                                }
                                IconButton(icon: "trash", help: "Delete this list", held: true) {
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
                        BlockedToday(filter: filter)
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
                            color: .block, nameWidth: 190, valueWidth: 150, copiesDetails: true,
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
                            color: .block, nameWidth: 190, valueWidth: 150, copiesNames: true,
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
            HStack {
                Text(verdict).font(.aileron(13, .semibold))
                Spacer()
                IconButton(icon: "xmark", help: "Clear the result") { self.checked = nil }
            }
            ForEach(lists) { list in
                HStack(spacing: 8) {
                    Text(list.name).lineLimit(1)
                    Chip(action: list.action)
                    if !list.enabled { Chip(text: "Off") }
                    Spacer()
                    Copyable(
                        text: checked.entries[list.id] ?? "",
                        help: "The entry that matched. It covers its subdomains too. Click to copy."
                    )
                    .foregroundStyle(.ink3).lineLimit(1).truncationMode(.middle)
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
                    IconButton(icon: "square.and.arrow.up", help: "Upload a newer copy", held: true) { pickingIPInfo = true }
                    IconButton(icon: "trash", help: "Remove the IP data", held: true) { Task { await filter.removeIPInfo() } }
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
                    Button("Upload", systemImage: "square.and.arrow.up") { pickingIPInfo = true }.held()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .fileImporter(isPresented: $pickingIPInfo, allowedContentTypes: [.gzip, .commaSeparatedText]) { result in
            usePicked(result) { await filter.uploadIPInfo(from: $0) }
        }
    }

    private func shieldCard(_ shield: DomainList) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                tile("shield", on: shield.enabled, tint: .block)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shield.name).font(.aileron(16, .bold))
                    if let size = filter.stats.listSizes[shield.id] {
                        Text(counted(size, "domain")).foregroundStyle(.ink3).monospacedDigit()
                    }
                }
                Spacer()
                Toggle(shield.name, isOn: enabled(shield.id)).toggleStyle(.switch).labelsHidden().controlSize(.large).tint(.allow)
                    .held()
            }
            HStack {
                Text("Ads, trackers, malware · Steven Black's hosts").font(.aileron(12)).foregroundStyle(.ink2)
                Spacer()
                IconButton(icon: "arrow.clockwise", help: "Refresh", held: true) { Task { await filter.load(shield) } }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Caption("Extensions")
                    Spacer()
                    Text("Each downloads when you turn it on").font(.aileron(11)).foregroundStyle(.ink3)
                }
                .padding(.bottom, 4)
                ForEach(Self.extensions, id: \.list.id) { item in
                    Rectangle().fill(.line).frame(height: 1).padding(.top, 8)
                    extensionRow(item.list, label: item.label, about: item.about).padding(.top, 8)
                }
            }
        }
        .card()
        .confirmationDialog(
            "Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { list in
            Button("Delete", role: .destructive) { filter.update { $0.lists.removeAll { $0.id == list.id } } }
        } message: { _ in
            Text("Sieve stops blocking its domains and deletes its copy. Turn it on to download it again.")
        }
    }

    // A downloaded extension is a list in the config. Off keeps its copy, and Delete drops it.
    private func extensionRow(_ list: DomainList, label: String, about: String) -> some View {
        let saved = filter.config.lists.first { $0.id == list.id }
        let busy = downloading == list.id
        return HStack(spacing: 12) {
            Toggle(
                label,
                isOn: Binding(
                    get: { busy || saved?.enabled == true },
                    set: { on in if saved == nil { download(list) } else { enabled(list.id).wrappedValue = on } }
                )
            )
            .toggleStyle(.switch).labelsHidden().tint(.allow)
            .disabled(downloading != nil)
            .held()
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.aileron(13, .semibold))
                Text(about).font(.aileron(11)).foregroundStyle(.ink3).lineLimit(1)
            }
            // The subtitle can be cut off, so the pointer shows it whole.
            .help(about)
            Spacer()
            if busy {
                Text("Downloading").foregroundStyle(.ink3)
                ProgressView().controlSize(.small)
            } else if saved == nil {
                Text("Not downloaded").foregroundStyle(.ink3)
            } else {
                if let size = filter.stats.listSizes[list.id] {
                    Text(counted(size, "domain")).foregroundStyle(.ink3).monospacedDigit()
                }
                IconButton(icon: "arrow.clockwise", help: "Download a fresh copy", held: true) { Task { await filter.load(list) } }
                IconButton(icon: "trash", help: "Turn off and delete the downloaded copy", held: true) { deleting = list }
            }
        }
    }

    // The list joins the config only after its first download succeeds, so a failed one leaves nothing behind.
    private func download(_ list: DomainList) {
        downloading = list.id
        Task {
            if await filter.load(list) {
                await filter.update { config in
                    if !config.lists.contains(where: { $0.id == list.id }) { config.lists.append(list) }
                }?.value
            }
            downloading = nil
        }
    }

    // Allowlist only: one uploaded file of hosts, IP addresses, and ranges. A new upload replaces it.
    private var allowlistCard: some View {
        let count = filter.stats.listSizes[Allowlist.id] ?? 0
        let on = count > 0 && filter.config.allowOnly == true
        let upload = filter.allowlistUpload
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                tile("pedestrian.gate.closed", on: on, tint: .allow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allowlist only").font(.aileron(16, .bold))
                    Text(count > 0 ? counted(count, "entry") : "No list uploaded").foregroundStyle(.ink3).monospacedDigit()
                }
                Spacer()
                Toggle(
                    "Allowlist only",
                    isOn: Binding(
                        get: { on },
                        set: { wanted in
                            if wanted { confirmingAllowOnly = true } else { filter.update { $0.allowOnly = nil } }
                        })
                )
                .toggleStyle(.switch).labelsHidden().controlSize(.large).tint(.allow)
                .disabled(count == 0)
                .held()
            }
            Text("Only hosts and IP addresses on your list can connect. DNS, time, and certificate checks stay allowed.")
                .font(.aileron(12)).foregroundStyle(.ink3)
            if on {
                Label(
                    "List downloads need their host on your list, such as raw.githubusercontent.com for Tracker Shield.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.aileron(12)).foregroundStyle(.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.s1, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.line2))
            }
            if count > 0 {
                Rectangle().fill(.line).frame(height: 1)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(upload?.name ?? "Allowlist").font(.aileron(13, .semibold))
                        if let upload {
                            Text("Uploaded \(upload.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.aileron(11)).foregroundStyle(.ink3)
                        }
                    }
                    Spacer()
                    IconButton(icon: "square.and.arrow.down", help: "Save a copy of the list, without duplicates", held: true) {
                        Task { await saveAllowlist() }
                    }
                    IconButton(icon: "square.and.arrow.up", help: "Upload a new file. It replaces the list.", held: true) {
                        pickingAllowlist = true
                    }
                    IconButton(icon: "trash", help: "Delete the allowlist", held: true) { deletingAllowlist = true }
                        .confirmationDialog("Delete the allowlist?", isPresented: $deletingAllowlist) {
                            Button("Delete", role: .destructive) { Task { await filter.removeAllowlist() } }
                        } message: {
                            Text("Allowlist only turns off, and Sieve deletes the list. Upload a file to use it again.")
                        }
                }
                if let tally = upload?.tally { tallyView(tally) }
            } else {
                Text(
                    "A **.csv** or **.txt** file with one entry per line: a host such as **example.com**, an IP address, or a range such as **10.0.0.0/8**. A host covers its subdomains. Sieve removes duplicates."
                )
                .font(.aileron(12)).foregroundStyle(.ink3)
                HStack {
                    Spacer()
                    Button("Upload", systemImage: "square.and.arrow.up") { pickingAllowlist = true }.held()
                }
            }
        }
        .card()
        .fileImporter(isPresented: $pickingAllowlist, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            usePicked(result) { await filter.uploadAllowlist(from: $0) }
        }
        // It blocks every app, Apple apps included, so it asks first.
        .confirmationDialog("Turn on Allowlist only?", isPresented: $confirmingAllowOnly) {
            Button("Turn On") { filter.update { $0.allowOnly = true } }
        } message: {
            Text(
                "Only the \(counted(count, "entry")) on your list can connect. DNS, time, and certificate checks stay allowed. Every other connection is blocked, Apple apps included."
            )
        }
    }

    // The counts of the last upload, with a hint on each.
    private func tallyView(_ tally: Allowlist.Tally) -> some View {
        let tiles = [
            ("kept", tally.kept, "Entries on the list"),
            ("duplicates", tally.duplicates, "Lines equal to another after normalizing"),
            ("covered", tally.covered, "A listed parent domain or range already covers them"),
            ("invalid", tally.invalid, "Not a host, IP address, or range"),
        ]
        let more = tally.invalid - tally.invalidLines.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(tiles, id: \.0) { label, value, help in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value.formatted()).font(.aileron(18, .light)).monospacedDigit()
                            .foregroundStyle(label == "invalid" && value > 0 ? .warn : .ink)
                        Text(label).font(.aileron(11)).foregroundStyle(.ink3)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.s2, in: .rect(cornerRadius: 8))
                    .help(help)
                }
            }
            if tally.invalid > 0 {
                Text(
                    "Skipped \(tally.invalid == 1 ? "line" : "lines") \(tally.invalidLines.map(String.init).joined(separator: ", "))\(more > 0 ? ", and \(more) more" : "")."
                )
                .font(.aileron(11)).foregroundStyle(.ink3)
            }
        }
    }

    // The list shows what may connect, so while Sieve is locked, a copy needs the unlock too.
    private func saveAllowlist() async {
        guard await filter.mayChange("save a copy of its allowlist") else { return }
        guard let data = await filter.allowlist() else {
            filter.message = ("The filter cannot be reached, so the allowlist cannot be saved.", true)
            return
        }
        await saveCopy(named: "allowlist.txt", failure: "Cannot save a copy of the allowlist") { data }
    }

    // Hands a picked file to `use`, or says why it could not be opened.
    private func usePicked(_ result: Result<URL, any Error>, _ use: @escaping (URL) async -> Void) {
        switch result {
        case .success(let file): Task { await use(file) }
        case .failure(let error): filter.message = ("Cannot open the file: \(error.localizedDescription)", true)
        }
    }

    // The big icon of a card that turns a feature on.
    private func tile(_ icon: String, on: Bool, tint: Color) -> some View {
        Image(systemName: icon).font(.system(size: 26, weight: .medium))
            .foregroundStyle(on ? tint : .ink3)
            .frame(width: 56, height: 56)
            .background(on ? tint.opacity(0.16) : .s3, in: .rect(cornerRadius: 16))
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

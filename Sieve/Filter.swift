import AppKit
import NetworkExtension
import Observation
import SwiftUI
import SystemExtensions

/// The app's error log, in its own container.
let errorLog = ErrorLog(
    folder: URL.applicationSupportDirectory.appending(path: "me.pilinux.Sieve"), source: "app", subsystem: "me.pilinux.Sieve")

/// Installs the system extension, turns on the content filter, and talks to it over XPC.
@Observable
final class Filter: NSObject {
    /// Activating until `resume()` knows whether the filter was turned on before. It becomes On only after the config is read.
    private(set) var status = Status.activating
    private(set) var config = Config()
    private(set) var stats = Stats()
    /// The bytes and blocked counts, read every second, with `stats.vpns` for `Stats.totalBytes`.
    /// Only the small views that show them read this, so a change to `stats` comes at most every 10 seconds.
    private(set) var usage = Stats()
    /// Bytes per second, by app key.
    private(set) var rates: [String: Double] = [:]
    /// Bytes per second of all apps together, leaving out VPN apps as `Stats.totalBytes` does.
    private(set) var totalRate: Double = 0
    // Up to 60 samples of `rates`, and of `totalRate`, oldest first.
    private var history: [[String: Double]] = []
    private var totalHistory: [Double] = []
    /// A short message for the user, such as a loaded list or a failed save. The window clears it.
    var message: (text: String, failed: Bool)?
    /// The uploaded IPinfo Lite data, and when it was uploaded. Nil until the user uploads a file.
    private(set) var ipInfo = Filter.readIPInfo()
    /// The share of a picked IPinfo file read so far, from 0 to 1, while the upload runs.
    private(set) var ipInfoProgress: Double?
    /// Both error logs, by source, as last read. There is no `extension` key if the extension could not be reached.
    private(set) var logs: [String: LogFile] = [:]
    let lock = Lock()
    /// The file name, time, and counts of the last allowlist upload. The app keeps them in its defaults for the Lists card.
    private(set) var allowlistUpload = UserDefaults.standard.data(forKey: "allowlistUpload").flatMap {
        try? JSONDecoder().decode(AllowlistUpload.self, from: $0)
    }

    private static let extensionID = "me.pilinux.Sieve.SieveExtension"
    // The extension inside this app, as macOS installs it.
    private static let extensionBundle = Bundle(
        url: Bundle.main.bundleURL.appending(path: "Contents/Library/SystemExtensions/\(extensionID).systemextension"))
    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var sample = (bytes: [String: Int](), time: Date.now)
    // True while one `poll()` call reads.
    @ObservationIgnored private var polling = false
    // Counts local edits. A config read that started before the latest edit would undo that edit, so the read is ignored.
    @ObservationIgnored private var edits = 0
    // True once the filter is turned on. From then on, the link to the extension must stay up.
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var link: Task<Void, Never>?
    // True from Turn on until its activation request is sent.
    @ObservationIgnored private var activating = false

    // Start at launch, not from a window, because Ask mode needs the app as its client even when every window is closed.
    override init() {
        super.init()
        Task { await resume() }
        Task { await followSystemSettings() }
    }

    // The user can turn the filter off in System Settings at any time. Then nothing is filtered, so show Off.
    private func followSystemSettings() async {
        for await _ in NotificationCenter.default.notifications(named: .NEFilterConfigurationDidChange) {
            let manager = NEFilterManager.shared()
            guard status == .on, (try? await manager.loadFromPreferences()) != nil, !manager.isEnabled else { continue }
            enabled = false
            status = .off
        }
    }

    // Once turned on, activate again on each launch, so a new build replaces the old extension.
    // A filter the user turned off in System Settings stays off until they press Turn on.
    private func resume() async {
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
            if manager.providerConfiguration != nil, manager.isEnabled {
                turnOn()
            } else {
                status = .off
            }
        } catch {
            errorLog.error("system", "Cannot load the filter configuration", error)
            status = .failed(error.localizedDescription)
        }
    }

    /// Reads the extension's state, then activates it.
    func turnOn() {
        status = .activating
        activating = true
        checkExtension()
    }

    // The answer comes to `request(_:foundProperties:)`.
    private func checkExtension() {
        submit(.propertiesRequest(forExtensionWithIdentifier: Self.extensionID, queue: .main))
    }

    private func submit(_ request: OSSystemExtensionRequest) {
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Reads all the stats from the extension. The config needs no read, because the app is the only one that writes it.
    func refresh() async {
        if let data = await send({ $0.stats(reply: $1) }),
            let stats = decode(Stats.self, data)
        {
            // `@Observable` redraws every reader on each set, even with an equal value, so set only a changed one.
            if self.stats != stats { self.stats = stats }
            let usage = Stats(bytes: stats.bytes, blocked: stats.blocked, blockedByList: stats.blockedByList, vpns: stats.vpns)
            if self.usage != usage { self.usage = usage }
            measure(stats.bytes)
        }
    }

    // Reads only the bytes and blocked counts.
    private func readUsage() async {
        if let data = await send({ $0.usage(reply: $1) }),
            let usage = decode(Stats.self, data)
        {
            let usage = Stats(bytes: usage.bytes, blocked: usage.blocked, blockedByList: usage.blockedByList, vpns: stats.vpns)
            if self.usage != usage { self.usage = usage }
            measure(usage.bytes)
        }
    }

    private func measure(_ bytes: [String: Int]) {
        // A refresh after a change can come right after a poll. Skip a sample that comes too soon.
        let elapsed = Date.now.timeIntervalSince(sample.time)
        guard elapsed >= 0.5 else { return }
        let rates = Dictionary(
            uniqueKeysWithValues: bytes.map { app, bytes in
                // Never go below zero. Clearing history resets an app's bytes.
                (app, max(Double(bytes - (sample.bytes[app] ?? bytes)) / elapsed, 0))
            })
        sample = (bytes, .now)
        let totalRate = rates.filter { stats.vpns?.contains($0.key) != true }.values.reduce(0, +)
        let history = Array((history + [rates]).suffix(60))
        let totalHistory = Array((totalHistory + [totalRate]).suffix(60))
        if self.rates != rates { self.rates = rates }
        if self.totalRate != totalRate { self.totalRate = totalRate }
        if self.history != history { self.history = history }
        if self.totalHistory != totalHistory { self.totalHistory = totalHistory }
    }

    /// The rate history of one app, or `totalRate`'s history when nil.
    func trend(_ app: String?) -> [Double] {
        guard let app else { return totalHistory }
        return history.map { $0[app] ?? 0 }
    }

    /// Reads all the stats now and every 10 seconds, and the bytes every second in between, until cancelled.
    /// The window and the menu bar panel both call it. Only one call reads, and another takes over when that one ends.
    func poll() async {
        var leads = false
        defer { if leads { polling = false } }
        var tick = 0
        while !Task.isCancelled {
            if !polling { (polling, leads) = (true, true) }
            if leads {
                if tick.isMultiple(of: 10) { await refresh() } else { await readUsage() }
                tick += 1
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// True while the lock is on and Sieve is not unlocked.
    var isLocked: Bool { config.locked == true && !lock.unlocked }

    /// While the lock is on, asks for the unlock. Returns whether the change may go ahead.
    /// - Parameter reason: what macOS shows after "Sieve is trying to".
    func mayChange(_ reason: String = "change its settings") async -> Bool {
        guard config.locked == true else { return true }
        return await lock.unlock(reason)
    }

    /// Changes the config here, then in the extension. The task ends when the extension has the change.
    /// Does nothing until the config is read, because editing the defaults would replace every stored rule.
    /// While the lock is on, the change waits for the unlock, and a cancelled unlock drops it.
    @discardableResult
    func update(_ change: @escaping (inout Config) -> Void) -> Task<Void, Never>? {
        guard status == .on else { return nil }
        guard config.locked != true else {
            return Task { if await mayChange() { await save(change)?.value } }
        }
        return save(change)
    }

    // Changes the config here right away, then in the extension.
    private func save(_ change: (inout Config) -> Void) -> Task<Void, Never>? {
        let old = config
        change(&config)
        config.approveCode(since: old, running: stats.codes ?? [:])
        edits += 1
        let edit = edits
        guard let data = try? JSONEncoder().encode(config) else { return nil }
        return Task {
            if let saved = await send({ $0.setConfig(data, reply: $1) }) {
                if let config = decode(Config.self, saved), edit == edits { self.config = config }
            } else if edit == edits {
                // The filter did not get the edit. Show the config it has, and tell the user.
                self.config = old
                message = ("Cannot save the change. The filter does not respond.", true)
            }
            // Rule flags and pruned stats depend on the new config. The prompt's reply does not need to wait for them.
            Task { await refresh() }
        }
    }

    /// Clears the app's history in the extension, then reads the stats again.
    func forget(_ app: String) async {
        guard await mayChange() else { return }
        _ = await send { $0.forget(app, reply: $1) }
        await refresh()
    }

    /// Clears every app's history in the extension, then reads the stats again.
    func clearHistory() async {
        guard await mayChange() else { return }
        _ = await send { $0.clearHistory(reply: $1) }
        await refresh()
    }

    /// The entry of each list that covers the host, by list ID. Nil if the filter cannot be reached.
    func listEntries(for host: String) async -> [String: String]? {
        guard let data = await send({ $0.listEntries(host, reply: $1) }) else { return nil }
        return decode([String: String].self, data)
    }

    /// The config file the extension could not read. Nil or empty if there is none.
    func brokenConfig() async -> Data? {
        await send { $0.brokenConfig(reply: $1) }
    }

    /// Deletes that file in the extension, then reads the stats again.
    func discardBrokenConfig() async {
        guard await mayChange() else { return }
        _ = await send { $0.discardBrokenConfig(reply: $1) }
        await refresh()
    }

    /// Downloads the list and hands it to the extension.
    func load(_ list: DomainList) async {
        guard await mayChange() else { return }
        do {
            guard let url = list.url.flatMap(URL.init(string:)) else { throw URLError(.badURL) }
            let (bytes, response) = try await URLSession.shared.bytes(from: url)
            if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            // Stop at the size limit, so a server that never stops sending cannot fill memory or disk.
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > DomainList.maxBytes {
                    bytes.task.cancel()
                    throw URLError(.dataLengthExceedsMaximum)
                }
            }
            // A reply with no hosts, such as an error page, would replace a good copy.
            guard try await hand(list, data) else {
                errorLog.warning("lists", "List \(list.id) has no hosts. Kept the old copy")
                message = ("\(list.name) has no hosts. Kept the old copy.", true)
                return
            }
            message = ("Loaded \(list.name)", false)
        } catch {
            errorLog.warning("lists", "Cannot load list \(list.id)", error)
            message = ("Cannot load \(list.name): \(error.localizedDescription)", true)
        }
    }

    /// Reads a list file the user picked, hands it to the extension, and adds the list.
    func upload(_ list: DomainList, from file: URL) async {
        guard await mayChange() else { return }
        do {
            guard try await hand(list, readPicked(file)) else {
                message = ("\(list.name) has no hosts", true)
                return
            }
            update { $0.lists.append(list) }
            message = ("Loaded \(list.name)", false)
        } catch {
            errorLog.warning("lists", "Cannot read a picked list file", error)
            message = ("Cannot load \(list.name): \(error.localizedDescription)", true)
        }
    }

    // Reads a file the user picked, up to `DomainList.maxBytes`.
    private func readPicked(_ file: URL) throws -> Data {
        // The sandbox lets the app read a picked file only inside this scope.
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= DomainList.maxBytes
        else { throw URLError(.dataLengthExceedsMaximum) }
        return try Data(contentsOf: file)
    }

    // Hands a list to the extension. Returns false if the list holds no hosts.
    private func hand(_ list: DomainList, _ data: Data) async throws -> Bool {
        guard !DomainList.parse(String(decoding: data, as: UTF8.self)).isEmpty else { return false }
        if await send({ $0.setList(list.id, domains: data, reply: $1) }) == nil {
            throw URLError(.cannotConnectToHost)
        }
        return true
    }

    /// Reads a picked allowlist file, drops duplicates, and hands the entries to the extension.
    /// A file with no entry keeps the old list, since it would block every connection.
    func uploadAllowlist(from file: URL) async {
        guard await mayChange() else { return }
        do {
            let (list, tally) = Allowlist.parse(String(decoding: try readPicked(file), as: UTF8.self))
            guard !list.entries.isEmpty else {
                message = ("\(file.lastPathComponent) has no host or IP address. Kept the old allowlist.", true)
                return
            }
            let text = Data(list.entries.joined(separator: "\n").utf8)
            guard await send({ $0.setList(Allowlist.id, domains: text, reply: $1) }) != nil else {
                throw URLError(.cannotConnectToHost)
            }
            let upload = AllowlistUpload(name: file.lastPathComponent, date: .now, tally: tally)
            allowlistUpload = upload
            UserDefaults.standard.set(try? JSONEncoder().encode(upload), forKey: "allowlistUpload")
            message = ("Loaded \(file.lastPathComponent): \(counted(list.entries.count, "entry"))", false)
            await refresh()
        } catch {
            errorLog.warning("lists", "Cannot read a picked allowlist file", error)
            message = ("Cannot load \(file.lastPathComponent): \(error.localizedDescription)", true)
        }
    }

    /// Turns Allowlist only off, then deletes the list. In that order, an empty list never blocks every connection.
    func removeAllowlist() async {
        guard await mayChange() else { return }
        await update { $0.allowOnly = nil }?.value
        guard await send({ $0.setList(Allowlist.id, domains: Data(), reply: $1) }) != nil else {
            message = ("Cannot delete the allowlist. The filter does not respond.", true)
            return
        }
        allowlistUpload = nil
        UserDefaults.standard.removeObject(forKey: "allowlistUpload")
        await refresh()
    }

    /// The allowlist's entries, one per line. Nil if the filter cannot be reached.
    func allowlist() async -> Data? {
        await send { $0.allowlist(reply: $1) }
    }

    // The compact copy of the uploaded IPinfo file. Only the app reads it.
    private static let ipInfoFile = URL.applicationSupportDirectory.appending(path: "me.pilinux.Sieve/ipinfo.bin")

    // Maps the saved copy into memory, so a lookup reads only the pages it needs. Nil if there is none.
    private static func readIPInfo() -> (table: AddressTable, date: Date)? {
        guard let data = try? Data(contentsOf: ipInfoFile, options: .alwaysMapped), let table = AddressTable(data: data)
        else { return nil }
        let date = (try? ipInfoFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        return (table, date)
    }

    /// Reads a picked IPinfo Lite file, plain or gzip, and saves a compact copy. A file that fails to read keeps the old copy.
    func uploadIPInfo(from file: URL) async {
        guard await mayChange() else { return }
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        ipInfoProgress = 0
        defer { ipInfoProgress = nil }
        let target = Self.ipInfoFile
        do {
            // Reading millions of lines takes seconds, so it runs off the main actor.
            try await Task.detached {
                let table = try IPInfoLite.table(from: file) { share in
                    Task { @MainActor in if self.ipInfoProgress != nil { self.ipInfoProgress = share } }
                }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try table.data.write(to: target, options: .atomic)
            }.value
            ipInfo = Self.readIPInfo()
            message = ("Loaded \(file.lastPathComponent)", false)
        } catch {
            errorLog.warning("ipinfo", "Cannot read a picked IPinfo file", error)
            message = ("Cannot read \(file.lastPathComponent): \(error.localizedDescription) Kept the old copy.", true)
        }
    }

    /// Deletes the saved IPinfo copy.
    func removeIPInfo() async {
        guard await mayChange() else { return }
        do {
            try FileManager.default.removeItem(at: Self.ipInfoFile)
        } catch {
            errorLog.warning("ipinfo", "Cannot delete the IPinfo copy", error)
        }
        ipInfo = nil
    }

    /// Reads both error logs into `logs`.
    func readErrorLogs() async {
        var logs = ["app": LogFile(data: errorLog.contents(), now: .now)]
        if let data = await send({ $0.readErrorLog(reply: $1) }) { logs["extension"] = LogFile(data: data, now: .now) }
        self.logs = logs
    }

    /// Clears both error logs, then reads them again. The extension's log stays if the extension cannot be reached.
    func resetErrorLogs() async {
        guard await mayChange("reset its error log") else { return }
        errorLog.reset()
        _ = await send { $0.resetErrorLog(reply: $1) }
        await readErrorLogs()
    }

    // Sends one message. Returns nil if the extension cannot be reached.
    private func send(_ message: (FilterXPC, @escaping @Sendable (Data) -> Void) -> Void) async -> Data? {
        let result: Result<Data, any Error> = await withCheckedContinuation { continuation in
            // XPC calls either the reply or the error handler, never both.
            // `@Sendable` keeps the handler off the main actor. XPC calls it on its own queue.
            let proxy =
                xpc().remoteObjectProxyWithErrorHandler { @Sendable error in
                    continuation.resume(returning: .failure(error))
                } as? FilterXPC
            guard let proxy else { return continuation.resume(returning: .failure(CocoaError(.featureUnsupported))) }
            message(proxy) { continuation.resume(returning: .success($0)) }
        }
        // Before the filter is On, a missing link is expected.
        if case .failure(let error) = result, status == .on { errorLog.warning("xpc", "Cannot reach the filter", error) }
        return try? result.get()
    }

    // Returns nil if the extension's reply does not decode.
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            errorLog.warning("xpc", "A \(T.self) reply does not decode", error)
            return nil
        }
    }

    private func xpc() -> NSXPCConnection {
        if let connection { return connection }
        let name = Self.extensionBundle?.machServiceName ?? ""
        let connection = NSXPCConnection(machServiceName: name)
        // Another process can offer the same name. Talk only to the Sieve extension, signed by the team the name starts with.
        connection.setCodeSigningRequirement(peerRequirement(identifier: Self.extensionID, team: name.prefix { $0 != "." }))
        connection.remoteObjectInterface = NSXPCInterface(with: FilterXPC.self)
        connection.exportedInterface = NSXPCInterface(with: PromptXPC.self)
        connection.exportedObject = self
        connection.interruptionHandler = { @Sendable [weak self] in
            Task { @MainActor in await self?.reconnect() }
        }
        connection.invalidationHandler = { @Sendable [weak self] in
            Task { @MainActor in
                self?.connection = nil
                await self?.reconnect()
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func enable() async {
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
            let configuration = NEFilterProviderConfiguration()
            configuration.filterSockets = true
            manager.providerConfiguration = configuration
            manager.localizedDescription = "Sieve"
            manager.isEnabled = true
            try await manager.saveToPreferences()
            enabled = true
            await reconnect()
        } catch {
            errorLog.error("system", "Cannot save the filter configuration", error)
            status = .failed(error.localizedDescription)
        }
    }

    // Returns once the extension has sent its config. At that point the filter is On.
    // The extension takes the sender of a message as its Ask mode client, and forgets it when the link drops.
    // A failed send drops the link again, so only one loop runs.
    private func reconnect() async {
        if link == nil {
            link = Task {
                var tries = 0
                while enabled, !(await readConfig()) {
                    // The user may have switched the extension off. macOS does not always post a change for it.
                    if tries == 0 { checkExtension() }
                    // launchd can refuse the extension's Mach service name while an old build still holds it.
                    if tries >= 10, status == .activating {
                        errorLog.error("system", "The filter does not respond")
                        status = .failed("The filter does not respond. Restart your Mac.")
                    }
                    tries += 1
                    try? await Task.sleep(for: .seconds(1))
                }
                if enabled { status = .on }
                link = nil
            }
        }
        await link?.value
    }

    // Returns false if the extension cannot be reached.
    private func readConfig() async -> Bool {
        let start = edits
        guard let data = await send({ $0.config(reply: $1) }),
            let config = decode(Config.self, data)
        else { return false }
        if edits == start { self.config = config }
        return true
    }
}

/// The last allowlist upload, for the Lists card.
struct AllowlistUpload: Codable {
    var name: String
    var date: Date
    var tally: Allowlist.Tally
}

/// The filter's status, from Turn on to On.
enum Status: Equatable {
    case off, activating, needsApproval, on
    /// What went wrong, in words for the user.
    case failed(String)

    /// The text the window and the menu show.
    var text: String {
        switch self {
        case .off: "Off"
        case .activating: "Activating"
        case .needsApproval: "Allow Sieve in System Settings"
        case .on: "On"
        case .failed(let message): "Error: \(message)"
        }
    }
}

extension Filter: PromptXPC {
    nonisolated func prompt(
        app: String, path: String, signer: String, host: String, address: String,
        reply: @escaping @Sendable (Bool, Bool) -> Void
    ) {
        Task { @MainActor in
            // With no window open, nothing polls, but the tracker mark needs fresh stats.
            await refresh()
            // No close button, so only Allow or Block can end the prompt.
            let panel = NSPanel(
                contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
            )
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isMovableByWindowBackground = true
            panel.appearance = NSAppearance(named: .darkAqua)
            // Make the window clear, so the prompt's glass is its background.
            panel.isOpaque = false
            panel.backgroundColor = .clear
            // Keep the prompt in front, also while the unlock sheet or another app is active.
            panel.level = .floating
            panel.hidesOnDeactivate = false
            // Wait without a modal loop. `runModal(for:)` would hold the main actor, so the unlock could never run.
            let answer = await withCheckedContinuation { (continuation: CheckedContinuation<(action: Action, hostOnly: Bool), Never>) in
                var answered = false
                let view = NSHostingView(
                    rootView: PromptView(filter: self, app: app, path: path, signer: signer, host: host, address: address) {
                        action, hostOnly in
                        // A second click before the panel closes must not answer twice.
                        guard !answered else { return }
                        answered = true
                        continuation.resume(returning: (action, hostOnly))
                    })
                panel.contentView = view
                panel.setContentSize(view.fittingSize)
                panel.center()
                NSApp.activate()
                panel.makeKeyAndOrderFront(nil)
            }
            panel.close()
            // The app is the only one that writes the config, so the rule is saved before the extension resumes the flows.
            // The reply carries the answer as well, so a failed save cannot turn Block into Allow.
            await update { $0.setAction(answer.action, for: app, host: answer.hostOnly ? host : nil) }?.value
            reply(answer.action == .allow, answer.hostOnly)
        }
    }
}

// The request calls back on the main queue.
extension Filter: @preconcurrency OSSystemExtensionRequestDelegate {
    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        status = .needsApproval
    }

    // When it is switched off under Network Extensions, the extension still counts as active, and only the user can
    // switch it back on. Activation then waits in `enable()` until they do.
    // Old builds stay listed until a reboot, some still marked enabled, so only the copy from this build counts.
    func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let version = Self.extensionBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        // Only while the link is down. A late answer must not hide a link that has come back.
        if activating || link != nil, properties.contains(where: { $0.bundleVersion == version && !$0.isEnabled }) {
            status = .needsApproval
        }
        guard activating else { return }
        activating = false
        submit(.activationRequest(forExtensionWithIdentifier: Self.extensionID, queue: .main))
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { await enable() }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        errorLog.error("system", "The system extension request failed", error)
        status = .failed(error.localizedDescription)
    }
}

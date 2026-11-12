import AppKit
import NetworkExtension
import Observation
import SwiftUI
import SystemExtensions

/// Installs the system extension, turns on the content filter, and talks to it over XPC.
@Observable
final class Filter: NSObject {
    /// Activating until `resume()` knows whether the filter was turned on before. On only once the config is read.
    private(set) var status = "Activating"
    private(set) var config = Config()
    private(set) var stats = Stats()
    /// Bytes per second, by app key.
    private(set) var rates: [String: Double] = [:]
    /// Up to 60 samples of `rates`, oldest first.
    private(set) var history: [[String: Double]] = []
    /// The result of the last list load. The view clears it.
    var message: (text: String, failed: Bool)?

    private static let extensionID = "me.pilinux.Sieve.SieveExtension"
    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var sample = (bytes: [String: Int](), time: Date.now)
    // Counts local edits. A config read that started before the latest edit would undo it, so it is dropped.
    @ObservationIgnored private var edits = 0
    // True once the filter is turned on: from then on the link to the extension must stay up.
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var link: Task<Void, Never>?

    // At launch, not from a window: Ask mode needs the app as its client even with every window closed.
    override init() {
        super.init()
        Task { await resume() }
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
                status = "Off"
            }
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    func turnOn() {
        status = "Activating"
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.extensionID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Reads all the stats from the extension. The config needs no read: the app is its only writer.
    func refresh() async {
        if let data = await send({ $0.stats(reply: $1) }),
            let stats = try? JSONDecoder().decode(Stats.self, from: data)
        {
            self.stats = stats
            measure(stats.bytes)
        }
    }

    // Reads only the bytes and blocked counts.
    private func readUsage() async {
        if let data = await send({ $0.usage(reply: $1) }),
            let usage = try? JSONDecoder().decode(Stats.self, from: data)
        {
            stats.bytes = usage.bytes
            stats.blocked = usage.blocked
            measure(usage.bytes)
        }
    }

    private func measure(_ bytes: [String: Int]) {
        // The window and the menu may both poll. Skip a sample that comes too soon.
        let elapsed = Date.now.timeIntervalSince(sample.time)
        guard elapsed >= 0.5 else { return }
        rates = Dictionary(
            uniqueKeysWithValues: bytes.map { app, bytes in
                // Never below zero: clearing an app's history resets its bytes.
                (app, max(Double(bytes - (sample.bytes[app] ?? bytes)) / elapsed, 0))
            })
        sample = (bytes, .now)
        history = Array((history + [rates]).suffix(60))
    }

    /// The rate history of one app, or of all apps when nil.
    func trend(_ app: String?) -> [Double] {
        history.map { sample in app.map { sample[$0] ?? 0 } ?? sample.values.reduce(0, +) }
    }

    /// Reads all the stats at once and every 10 seconds, the bytes every second in between, until cancelled.
    func poll() async {
        var tick = 0
        while !Task.isCancelled {
            if tick.isMultiple(of: 10) { await refresh() } else { await readUsage() }
            tick += 1
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Changes the config here at once, then in the extension. The task ends when the extension has it.
    /// Does nothing until the config is read: an edit of the defaults would replace every stored rule.
    @discardableResult
    func update(_ change: (inout Config) -> Void) -> Task<Void, Never>? {
        guard status == "On" else { return nil }
        let old = config
        change(&config)
        config.approveCode(since: old, running: stats.codes ?? [:])
        edits += 1
        let edit = edits
        guard let data = try? JSONEncoder().encode(config) else { return nil }
        return Task {
            if let saved = await send({ $0.setConfig(data, reply: $1) }),
                let config = try? JSONDecoder().decode(Config.self, from: saved), edit == edits
            {
                self.config = config
            }
            // Rule flags and pruned stats follow the new config. The prompt's reply need not wait for them.
            Task { await refresh() }
        }
    }

    /// Clears the app's history in the extension, then reads the stats again.
    func forget(_ app: String) async {
        _ = await send { $0.forget(app, reply: $1) }
        await refresh()
    }

    /// The config file the extension could not read. Nil or empty if there is none.
    func brokenConfig() async -> Data? {
        await send { $0.brokenConfig(reply: $1) }
    }

    /// Deletes that file in the extension, then reads the stats again.
    func discardBrokenConfig() async {
        _ = await send { $0.discardBrokenConfig(reply: $1) }
        await refresh()
    }

    /// Downloads the list and hands it to the extension.
    func load(_ list: DomainList) async {
        do {
            guard let url = URL(string: list.url) else { throw URLError(.badURL) }
            // To a file, so a huge list never fills memory here or in the extension.
            let (file, response) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: file) }
            if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= DomainList.maxBytes
            else { throw URLError(.dataLengthExceedsMaximum) }
            let data = try Data(contentsOf: file)
            // A reply with no hosts, such as an error page, would replace a good copy.
            guard !DomainList.parse(String(decoding: data, as: UTF8.self)).isEmpty else {
                message = ("\(list.name) has no hosts. Kept the old copy.", true)
                return
            }
            if await send({ $0.setList(list.id, domains: data, reply: $1) }) == nil {
                throw URLError(.cannotConnectToHost)
            }
            message = ("Loaded \(list.name)", false)
        } catch {
            message = ("Cannot load \(list.name): \(error.localizedDescription)", true)
        }
    }

    // Sends one message. Nil if the extension cannot be reached.
    private func send(_ message: (FilterXPC, @escaping @Sendable (Data) -> Void) -> Void) async -> Data? {
        await withCheckedContinuation { continuation in
            // XPC calls either the reply or the error handler, never both.
            // `@Sendable` keeps the handler off the main actor. XPC calls it on its own queue.
            let proxy =
                xpc().remoteObjectProxyWithErrorHandler { @Sendable _ in
                    continuation.resume(returning: nil)
                } as? FilterXPC
            guard let proxy else { return continuation.resume(returning: nil) }
            message(proxy) { continuation.resume(returning: $0) }
        }
    }

    private func xpc() -> NSXPCConnection {
        if let connection { return connection }
        let url = Bundle.main.bundleURL.appending(path: "Contents/Library/SystemExtensions/\(Self.extensionID).systemextension")
        let name = Bundle(url: url)?.machServiceName ?? ""
        let connection = NSXPCConnection(machServiceName: name)
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
            status = "On"
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    // Returns once the extension has sent its config.
    // The extension takes the sender of a message as its Ask mode client, and forgets it when the link drops.
    // A failed send drops the link again, so only one loop runs.
    private func reconnect() async {
        if link == nil {
            link = Task {
                while enabled, !(await readConfig()) {
                    try? await Task.sleep(for: .seconds(1))
                }
                link = nil
            }
        }
        await link?.value
    }

    // False if the extension cannot be reached.
    private func readConfig() async -> Bool {
        let start = edits
        guard let data = await send({ $0.config(reply: $1) }),
            let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return false }
        if edits == start { self.config = config }
        return true
    }
}

extension Filter: PromptXPC {
    nonisolated func prompt(app: String, path: String, signer: String, host: String, reply: @escaping @Sendable () -> Void) {
        Task { @MainActor in
            // With no window open, no poll runs. The tracker mark needs fresh stats.
            await refresh()
            var answer = (action: Action.allow, hostOnly: false)
            // No close button: only Allow or Block end the prompt.
            let panel = NSPanel(
                contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
            )
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isMovableByWindowBackground = true
            panel.appearance = NSAppearance(named: .darkAqua)
            // Clear, so the prompt's glass is its background.
            panel.isOpaque = false
            panel.backgroundColor = .clear
            let view = NSHostingView(
                rootView: PromptView(filter: self, app: app, path: path, signer: signer, host: host) { action, hostOnly in
                    answer = (action, hostOnly)
                    NSApp.stopModal()
                })
            panel.contentView = view
            panel.setContentSize(view.fittingSize)
            panel.center()
            NSApp.activate()
            NSApp.runModal(for: panel)
            panel.close()
            // The app is the only writer of the config: the rule is saved before the extension resumes the flows.
            await update { $0.setAction(answer.action, for: app, host: answer.hostOnly ? host : nil) }?.value
            reply()
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
        status = "Allow Sieve in System Settings"
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { await enable() }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        status = "Error: \(error.localizedDescription)"
    }
}

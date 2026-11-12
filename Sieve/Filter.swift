import AppKit
import NetworkExtension
import Observation
import SwiftUI
import SystemExtensions

/// Installs the system extension, turns on the content filter, and talks to it over XPC.
@Observable
final class Filter: NSObject {
    /// Activating until `resume()` knows whether the filter was turned on before.
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

    /// Once turned on, activate again on each launch, so a new build replaces the old extension.
    func resume() async {
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
            if manager.providerConfiguration != nil {
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

    /// Reads config and stats from the extension.
    func refresh() async {
        if let data = await send({ $0.config(reply: $1) }),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            self.config = config
        }
        if let data = await send({ $0.stats(reply: $1) }),
           let stats = try? JSONDecoder().decode(Stats.self, from: data) {
            self.stats = stats
            // The window and the menu may both poll. Skip a sample that comes too soon.
            let elapsed = Date.now.timeIntervalSince(sample.time)
            if elapsed >= 0.5 {
                rates = Dictionary(uniqueKeysWithValues: stats.bytes.map { app, bytes in
                    (app, Double(bytes - (sample.bytes[app] ?? bytes)) / elapsed)
                })
                sample = (stats.bytes, .now)
                history = Array((history + [rates]).suffix(60))
            }
        }
    }

    /// The rate history of one app, or of all apps when nil.
    func trend(_ app: String?) -> [Double] {
        history.map { sample in app.map { sample[$0] ?? 0 } ?? sample.values.reduce(0, +) }
    }

    /// Refreshes once a second until cancelled.
    func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Changes the config here at once, then in the extension.
    func update(_ change: (inout Config) -> Void) {
        change(&config)
        guard let data = try? JSONEncoder().encode(config) else { return }
        Task {
            if let saved = await send({ $0.setConfig(data, reply: $1) }),
               let config = try? JSONDecoder().decode(Config.self, from: saved) {
                self.config = config
            }
        }
    }

    /// Downloads the list and hands it to the extension.
    func load(_ list: DomainList) async {
        do {
            guard let url = URL(string: list.url) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                throw URLError(.badServerResponse)
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
            let proxy = xpc().remoteObjectProxyWithErrorHandler { @Sendable _ in
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
        connection.invalidationHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.connection = nil }
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
            status = "On"
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }
}

extension Filter: PromptXPC {
    nonisolated func prompt(app: String, host: String, reply: @escaping @Sendable (String, Bool) -> Void) {
        Task { @MainActor in
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
            let view = NSHostingView(rootView: PromptView(filter: self, app: app, host: host) { action, hostOnly in
                answer = (action, hostOnly)
                NSApp.stopModal()
            })
            panel.contentView = view
            panel.setContentSize(view.fittingSize)
            panel.center()
            NSApp.activate()
            NSApp.runModal(for: panel)
            panel.close()
            reply(answer.action.rawValue, answer.hostOnly)
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

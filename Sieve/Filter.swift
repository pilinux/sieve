import NetworkExtension
import Observation
import SystemExtensions

/// Installs the system extension, turns on the content filter, and talks to it over XPC.
@Observable
final class Filter: NSObject {
    private(set) var status = "Off"
    private(set) var config = Config()
    private(set) var stats = Stats()

    private static let extensionID = "me.pilinux.Sieve.SieveExtension"
    @ObservationIgnored private var connection: NSXPCConnection?

    /// Once turned on, activate again on each launch, so a new build replaces the old extension.
    func resume() async {
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
            if manager.providerConfiguration != nil {
                turnOn()
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

    /// Sends one message. Nil if the extension cannot be reached.
    private func send(_ message: (FilterXPC, @escaping @Sendable (Data) -> Void) -> Void) async -> Data? {
        await withCheckedContinuation { continuation in
            // XPC calls either the reply or the error handler, never both.
            let proxy = xpc().remoteObjectProxyWithErrorHandler { _ in
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
        connection.invalidationHandler = { [weak self] in
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

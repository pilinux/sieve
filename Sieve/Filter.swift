import NetworkExtension
import Observation
import SystemExtensions

/// Installs the system extension and turns on the content filter.
@Observable
final class Filter: NSObject {
    private(set) var status = "Off"

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
            forExtensionWithIdentifier: "me.pilinux.Sieve.SieveExtension",
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
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

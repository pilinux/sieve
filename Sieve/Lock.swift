import AppKit
import LocalAuthentication
import Observation

/// Whether the user unlocked Sieve. It locks again when the screen locks, when the Mac sleeps,
/// and 5 minutes after the unlock or the last change. Quitting the app locks it too.
@Observable
final class Lock {
    private(set) var unlocked = false
    @ObservationIgnored private var timer: Task<Void, Never>?
    // Changes that ask at the same time share one sheet.
    @ObservationIgnored private var asking: Task<Bool, Never>?

    init() {
        Task {
            for await _ in DistributedNotificationCenter.default().notifications(named: .init("com.apple.screenIsLocked")) {
                lock()
            }
        }
        Task {
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.willSleepNotification) {
                lock()
            }
        }
    }

    /// Asks for Touch ID or the Mac password, unless Sieve is unlocked. Returns whether it is unlocked now.
    /// Each call restarts the 5 minutes.
    /// - Parameter reason: what macOS shows after "Sieve is trying to".
    func unlock(_ reason: String) async -> Bool {
        if !unlocked {
            let asking =
                asking
                ?? Task {
                    // A cancel throws. Sieve stays locked, and the change does not happen.
                    (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
                }
            self.asking = asking
            unlocked = await asking.value
            self.asking = nil
        }
        if unlocked {
            timer?.cancel()
            timer = Task {
                try? await Task.sleep(for: .seconds(5 * 60))
                if !Task.isCancelled { unlocked = false }
            }
        }
        return unlocked
    }

    func lock() {
        unlocked = false
        timer?.cancel()
    }
}

import Foundation
import SystemConfiguration

/// Watches the `NetworkSignature` of each network the Mac is on. A VPN tunnel has none.
final class Networks: @unchecked Sendable {
    private static let pattern = "State:/Network/Service/[^/]+/IPv4"
    private let changed: @Sendable (Set<String>) -> Void
    private var store: SCDynamicStore?

    /// Calls `changed` now and after each network change.
    init(changed: @escaping @Sendable (Set<String>) -> Void) {
        self.changed = changed
        var context = SCDynamicStoreContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        store = SCDynamicStoreCreate(
            nil, "Sieve" as CFString,
            { store, _, info in
                guard let info else { return }
                Unmanaged<Networks>.fromOpaque(info).takeUnretainedValue().read(store)
            }, &context)
        guard let store else { return }
        SCDynamicStoreSetNotificationKeys(store, nil, [Self.pattern] as CFArray)
        SCDynamicStoreSetDispatchQueue(store, DispatchQueue(label: "me.pilinux.Sieve.networks"))
        read(store)
    }

    private func read(_ store: SCDynamicStore) {
        let values = SCDynamicStoreCopyMultiple(store, nil, [Self.pattern] as CFArray) as? [String: Any] ?? [:]
        changed(Set(values.values.compactMap { ($0 as? [String: Any])?["NetworkSignature"] as? String }))
    }
}

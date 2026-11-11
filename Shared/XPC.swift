import Foundation

/// What the app asks the extension. Values travel as JSON.
@objc protocol FilterXPC {
    func config(reply: @escaping @Sendable (Data) -> Void)
    func setConfig(_ config: Data, reply: @escaping @Sendable (Data) -> Void)
    func stats(reply: @escaping @Sendable (Data) -> Void)
}

/// What the extension asks the app, in Ask mode.
@objc protocol PromptXPC {
    /// Replies with an `Action` raw value.
    func prompt(app: String, host: String, reply: @escaping @Sendable (String) -> Void)
}

extension Bundle {
    /// The extension's XPC service name, from its Info.plist.
    var machServiceName: String? {
        (object(forInfoDictionaryKey: "NetworkExtension") as? [String: Any])?["NEMachServiceName"] as? String
    }
}

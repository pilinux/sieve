import Foundation

/// What the app asks the extension. Values travel as JSON.
@objc protocol FilterXPC {
    func config(reply: @escaping @Sendable (Data) -> Void)
    func setConfig(_ config: Data, reply: @escaping @Sendable (Data) -> Void)
    func stats(reply: @escaping @Sendable (Data) -> Void)
    /// A `Stats` with only `bytes` and `blocked`. Cheap enough to poll each second.
    func usage(reply: @escaping @Sendable (Data) -> Void)
    /// Stores a downloaded list, as UTF-8 text. Replies when done.
    func setList(_ id: String, domains: Data, reply: @escaping @Sendable (Data) -> Void)
    /// Clears an app's history, not its config. Replies when done.
    func forget(_ app: String, reply: @escaping @Sendable (Data) -> Void)
    /// The config file that could not be read. Empty if there is none.
    func brokenConfig(reply: @escaping @Sendable (Data) -> Void)
    /// Deletes that file. Replies when done.
    func discardBrokenConfig(reply: @escaping @Sendable (Data) -> Void)
}

/// What the extension asks the app, in Ask mode.
@objc protocol PromptXPC {
    /// Replies with the answer once the app has tried to save it as a rule: Allow or Block, and whether it
    /// covers only `host`. `signer` is a Team ID, `Apple`, or empty if not verified.
    /// `address` is the remote IP address, or empty if not known yet.
    func prompt(
        app: String, path: String, signer: String, host: String, address: String,
        reply: @escaping @Sendable (_ allow: Bool, _ hostOnly: Bool) -> Void)
}

extension Bundle {
    /// The extension's XPC service name, from its Info.plist.
    var machServiceName: String? {
        (object(forInfoDictionaryKey: "NetworkExtension") as? [String: Any])?["NEMachServiceName"] as? String
    }
}

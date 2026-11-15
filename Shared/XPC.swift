import Foundation

/// Calls from the app to the extension. Values are sent as JSON. Each call replies once its work is done.
@objc protocol FilterXPC {
    func config(reply: @escaping @Sendable (Data) -> Void)
    func setConfig(_ config: Data, reply: @escaping @Sendable (Data) -> Void)
    func stats(reply: @escaping @Sendable (Data) -> Void)
    /// A `Stats` with only the bytes and blocked counts. It is cheap enough to call every second.
    func usage(reply: @escaping @Sendable (Data) -> Void)
    /// Saves a downloaded list, sent as UTF-8 text.
    func setList(_ id: String, domains: Data, reply: @escaping @Sendable (Data) -> Void)
    /// Clears one app's history but keeps its config.
    func forget(_ app: String, reply: @escaping @Sendable (Data) -> Void)
    /// Clears the history of every app but keeps the config.
    func clearHistory(reply: @escaping @Sendable (Data) -> Void)
    /// Returns the config file that could not be read, or empty data if there is none.
    func brokenConfig(reply: @escaping @Sendable (Data) -> Void)
    /// Deletes that file.
    func discardBrokenConfig(reply: @escaping @Sendable (Data) -> Void)
    /// Returns the extension's `errors.jsonl` as it is stored.
    func readErrorLog(reply: @escaping @Sendable (Data) -> Void)
    /// Clears that log.
    func resetErrorLog(reply: @escaping @Sendable (Data) -> Void)
}

/// Calls from the extension to the app, for Ask mode.
@objc protocol PromptXPC {
    /// Asks the user about a flow. Replies with Allow or Block, and whether the answer covers only `host`.
    /// The app tries to save the answer as a rule before it replies. `signer` is a Team ID, `Apple`, or empty if not verified.
    /// `address` is the remote IP address, or empty if it is not known yet.
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

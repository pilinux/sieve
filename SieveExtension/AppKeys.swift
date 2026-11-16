import Foundation
import Security

/// The app behind a flow.
final class App: Sendable {
    /// For third-party code, `TEAMID.identifier`. For Apple code, the signing identifier. For anything else, the path.
    let key: String
    /// The app bundle or executable on disk.
    let path: String
    /// A Team ID backed by a certificate, `Apple`, or empty.
    let signer: String
    /// Apple code that is allowed without a rule. User tools such as `curl` and WebKit's networking service
    /// do not count, since any app can use them.
    let isApple: Bool
    /// For a path key, the pin of the running code: its code directory hash in hex, or `file:INODE:CTIME` when the sandbox cannot read the file.
    /// Nil if the code has no signature, or if the file on disk is not the code that is running.
    let code: String?
    /// A VPN or proxy provider. Its flows carry other apps' traffic again.
    let isVPN: Bool

    init(_ key: String, path: String = "", signer: String = "", code: String? = nil, isVPN: Bool = false) {
        self.key = key
        self.path = path
        self.signer = signer
        self.code = code
        self.isVPN = isVPN
        // Keep daemons in `/usr/libexec`, `/usr/sbin`, and `/System` allowed. Otherwise each one would prompt.
        // An `.xpc` service runs for whichever app called it, and no public API names that app.
        isApple =
            signer == "Apple" && !(path + "/").contains(".xpc/")
            && !["/usr/bin/", "/bin/", "/Library/Developer/"].contains { path.hasPrefix($0) }
    }
}

/// Finds the app behind a flow.
struct AppKeys {
    // A signature lookup reads from disk, so look up each process once.
    private let cache = NSCache<NSData, App>()

    func app(for auditToken: Data) -> App? {
        if let cached = cache.object(forKey: auditToken as NSData) {
            return cached
        }
        // The audit token names one process, so a reused PID cannot be mistaken for it.
        guard let app = Self.guest([kSecGuestAttributeAudit: auditToken]).flatMap(Self.lookUp) ?? Self.byPath(auditToken)
        else { return nil }
        cache.setObject(app, forKey: auditToken as NSData)
        return app
    }

    // The sandbox lets the extension read only some executables, and a signature lookup must read the file.
    // Without the signature, the path names the code, and the file's inode and status-change time pin it.
    private static func byPath(_ auditToken: Data) -> App? {
        guard auditToken.count == MemoryLayout<audit_token_t>.size else { return nil }
        var token = auditToken.withUnsafeBytes { $0.load(as: audit_token_t.self) }
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath_audittoken(&token, &buffer, UInt32(buffer.count))
        // No path means the process is gone.
        guard length > 0 else { return nil }
        let path = String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
        if Config.isProtected(path) { return App(path, path: path, signer: "Apple") }
        var info = stat()
        guard stat(path, &info) == 0 else { return App(path, path: path) }
        // Replacing or editing the file changes the pin, and no file call can set either value.
        let ctime = info.st_ctimespec
        return App(path, path: path, code: "file:\(info.st_ino):\(ctime.tv_sec).\(ctime.tv_nsec)")
    }

    private static func lookUp(_ code: SecCode) -> App? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        // A provider inside an app bundle makes the whole app a VPN.
        let isVPN = isVPN(staticCode)
        guard let own = identify(staticCode, running: code, isVPN: isVPN) else { return nil }

        // Code inside an app bundle counts as the outermost app, but only if the same signer signed both.
        // Anyone can copy an app and put their own code inside the copy.
        var outerCode: SecStaticCode?
        if !own.signer.isEmpty, let end = own.path.range(of: ".app/")?.lowerBound,
            SecStaticCodeCreateWithPath(
                URL(fileURLWithPath: String(own.path[..<end]) + ".app") as CFURL, [], &outerCode) == errSecSuccess,
            let outerCode, let outer = identify(outerCode, running: nil, isVPN: isVPN), outer.signer == own.signer
        {
            return outer
        }
        return own
    }

    // Returns the app a signature names, and who vouches for it.
    // With `running`, the check covers the code in memory as well as the file on disk.
    private static func identify(_ code: SecStaticCode, running: SecCode?, isVPN: Bool) -> App? {
        var url: CFURL?
        guard SecCodeCopyPath(code, [], &url) == errSecSuccess, let path = (url as URL?)?.path else { return nil }

        func satisfies(_ text: String) -> Bool {
            var requirement: SecRequirement?
            guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement
            else { return false }
            if let running {
                return SecCodeCheckValidity(running, [], requirement) == errSecSuccess
            }
            // Check the signature only, not every file in the bundle.
            let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources | kSecCSDoNotValidateExecutable)
            return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let info = info as? [String: Any],
            let identifier = info[kSecCodeInfoIdentifier as String] as? String
        else { return App(path, path: path, isVPN: isVPN) }

        // Anyone who can write to the path can put other code there. The hash names the code itself.
        func pathKey() -> App {
            let hash = (info[kSecCodeInfoUnique as String] as? Data)?.map { String(format: "%02x", $0) }.joined()
            return App(path, path: path, code: hash.flatMap { satisfies("cdhash H\"\($0)\"") ? $0 : nil }, isVPN: isVPN)
        }

        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String {
            // A Team ID proves nothing until a certificate backs it. Apple re-signs Mac App Store apps with its own certificate.
            // A Team ID is only letters and digits. Any other character could change the meaning of the requirement.
            guard team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
                satisfies(
                    "anchor apple generic and (certificate leaf[subject.OU] = \"\(team)\""
                        + " or certificate leaf[field.1.2.840.113635.100.6.1.9])")
            else { return pathKey() }
            return App("\(team).\(identifier)", path: path, signer: team, isVPN: isVPN)
        }
        if satisfies("anchor apple") {
            return App(identifier, path: path, signer: "Apple", isVPN: isVPN)
        }
        return pathKey()
    }

    // Whether the code is a packet tunnel or app proxy provider. Both send other apps' traffic again in their own flows.
    private static func isVPN(_ code: SecStaticCode) -> Bool {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
            let entitlements = (info as? [String: Any])?[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
            let types = entitlements["com.apple.developer.networking.networkextension"] as? [String]
        else { return false }
        // A system extension's type ends in `-systemextension`.
        return types.contains { $0.hasPrefix("packet-tunnel-provider") || $0.hasPrefix("app-proxy-provider") }
    }

    private static func guest(_ attributes: [CFString: Any]) -> SecCode? {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code) == errSecSuccess else {
            return nil
        }
        return code
    }
}

import Foundation
import Security

/// The app behind a flow.
final class App: Sendable {
    /// Third-party code: `TEAMID.identifier`. Apple code: the signing identifier. Anything else: the path.
    let key: String
    /// The app bundle or executable on disk.
    let path: String
    /// A Team ID backed by a certificate, `Apple`, or empty.
    let signer: String
    /// Apple code allowed with no rule. Not a user tool such as `curl`, which any app can run.
    let isApple: Bool

    init(_ key: String, path: String = "", signer: String = "") {
        self.key = key
        self.path = path
        self.signer = signer
        // Daemons in `/usr/libexec`, `/usr/sbin`, and `/System` stay allowed, or each would prompt.
        isApple = signer == "Apple" && !["/usr/bin/", "/bin/", "/Library/Developer/"].contains { path.hasPrefix($0) }
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
        // The PID is `val.5`. `audit_token_to_pid` returns the same, but needs libbsm.
        let pid = auditToken.withUnsafeBytes { $0.loadUnaligned(as: audit_token_t.self) }.val.5
        // The token names one process, so a reused PID cannot stand in for it.
        guard let code = Self.guest([kSecGuestAttributeAudit: auditToken]),
            let app = Self.lookUp(code, pid: pid_t(bitPattern: pid))
        else { return nil }
        cache.setObject(app, forKey: auditToken as NSData)
        return app
    }

    private static func lookUp(_ code: SecCode, pid: pid_t) -> App? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            let own = identify(staticCode, running: code)
        else { return nil }

        // An XPC service, such as WebKit's networking process, counts as the app that launched it.
        // Only Apple's: anyone can name a folder `.xpc`. Not command-line tools: those would count as the terminal app.
        if own.signer == "Apple", (own.path + "/").contains(".xpc/"), let responsible = responsiblePID?(pid),
            responsible > 0, responsible != pid, let parent = guest([kSecGuestAttributePid: responsible])
        {
            return lookUp(parent, pid: responsible)
        }

        // Code inside an app bundle counts as the outermost app, but only if the same signer signed both.
        // Anyone can copy an app and put their own code inside the copy.
        var outerCode: SecStaticCode?
        if !own.signer.isEmpty, let end = own.path.range(of: ".app/")?.lowerBound,
            SecStaticCodeCreateWithPath(
                URL(fileURLWithPath: String(own.path[..<end]) + ".app") as CFURL, [], &outerCode) == errSecSuccess,
            let outerCode, let outer = identify(outerCode, running: nil), outer.signer == own.signer
        {
            return outer
        }
        return own
    }

    // The app a signature names, with who vouches for it.
    // With `running`, the check covers the code in memory, not only the file on disk.
    private static func identify(_ code: SecStaticCode, running: SecCode?) -> App? {
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
        else { return App(path, path: path) }

        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String {
            // The Team ID is a claim until a certificate backs it. Apple re-signs Mac App Store apps with its own.
            // A Team ID is letters and digits; anything else could rewrite the requirement.
            guard team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
                satisfies(
                    "anchor apple generic and (certificate leaf[subject.OU] = \"\(team)\""
                        + " or certificate leaf[field.1.2.840.113635.100.6.1.9])")
            else { return App(path, path: path) }
            return App("\(team).\(identifier)", path: path, signer: team)
        }
        if satisfies("anchor apple") {
            return App(identifier, path: path, signer: "Apple")
        }
        return App(path, path: path)
    }

    private static func guest(_ attributes: [CFString: Any]) -> SecCode? {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code) == errSecSuccess else {
            return nil
        }
        return code
    }

    // Private macOS function with no public replacement. Nil if a future macOS removes it.
    private static let responsiblePID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()
}

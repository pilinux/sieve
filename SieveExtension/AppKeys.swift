import Foundation
import Security

/// The app behind a flow.
final class App: Sendable {
    /// Third-party code: `TEAMID.identifier`. Apple code: the signing identifier. Anything else: the path.
    let key: String
    /// The app bundle or executable on disk.
    let path: String
    let isApple: Bool

    init(_ key: String, path: String = "", isApple: Bool = false) {
        self.key = key
        self.path = path
        self.isApple = isApple
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
        guard let app = Self.lookUp(pid: pid_t(bitPattern: pid)) else { return nil }
        cache.setObject(app, forKey: auditToken as NSData)
        return app
    }

    private static func lookUp(pid: pid_t) -> App? {
        guard var path = path(of: pid) else { return nil }

        // An XPC service, such as WebKit's networking process, counts as the app that launched it.
        // Not command-line tools: those would count as the terminal app.
        if path.contains(".xpc/"), let responsible = responsiblePID?(pid), responsible > 0,
           let appPath = Self.path(of: responsible) {
            path = appPath
        }

        // Code inside an app bundle counts as the outermost app.
        if let end = path.range(of: ".app/")?.lowerBound {
            path = String(path[..<end]) + ".app"
        }

        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
              let info = info as? [String: Any],
              let identifier = info[kSecCodeInfoIdentifier as String] as? String
        else { return App(path, path: path) }

        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String {
            return App("\(team).\(identifier)", path: path)
        }
        // Check the signature only, not every file in the bundle.
        let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources | kSecCSDoNotValidateExecutable)
        var apple: SecRequirement?
        if SecRequirementCreateWithString("anchor apple" as CFString, [], &apple) == errSecSuccess, let apple,
           SecStaticCodeCheckValidity(code, flags, apple) == errSecSuccess {
            return App(identifier, path: path, isApple: true)
        }
        return App(path, path: path)
    }

    private static func path(of pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE, a macro Swift cannot import.
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    // Private macOS function with no public replacement. Nil if a future macOS removes it.
    private static let responsiblePID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()
}

import Foundation
import os
import Synchronization

/// Config and stats, shared by the filter and XPC, saved as JSON files.
final class Store: Sendable {
    private struct State {
        var config = Config()
        var stats = Stats()
        var statsChanged = false
    }

    private let state = Mutex(State())
    private let folder = URL.applicationSupportDirectory.appending(path: "me.pilinux.Sieve")
    private let logger = Logger(subsystem: "me.pilinux.Sieve.SieveExtension", category: "store")

    var config: Config { state.withLock { $0.config } }
    var stats: Stats { state.withLock { $0.stats } }

    func load() {
        let config = read(Config.self, "config.json")
        let stats = read(Stats.self, "stats.json")
        state.withLock {
            $0.config = config ?? Config()
            $0.stats = stats ?? Stats()
        }
        if config == nil { write(Config(), "config.json") }
    }

    func setConfig(_ config: Config) {
        state.withLock { $0.config = config }
        write(config, "config.json")
    }

    func setAction(_ action: Action, for app: String, host: String?) {
        let config = state.withLock {
            $0.config.setAction(action, for: app, host: host)
            return $0.config
        }
        write(config, "config.json")
    }

    /// Decides one flow and records the app and host. Nil means: ask the user.
    func verdict(app: App, host: String?) -> Action? {
        state.withLock {
            var hosts = $0.stats.apps[app.key] ?? []
            if let host { hosts.insert(host) }
            if $0.stats.apps[app.key] != hosts {
                $0.stats.apps[app.key] = hosts
                $0.statsChanged = true
            }
            return $0.config.verdict(app: app.key, host: host, isApple: app.isApple)
        }
    }

    func saveStats() {
        let stats: Stats? = state.withLock {
            defer { $0.statsChanged = false }
            return $0.statsChanged ? $0.stats : nil
        }
        if let stats { write(stats, "stats.json") }
    }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: folder.appending(path: name)))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            // Keep the broken file for the user to inspect.
            logger.error("Cannot read \(name, privacy: .public), using defaults: \(error, privacy: .public)")
            return nil
        }
    }

    private func write(_ value: some Encodable, _ name: String) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: folder.appending(path: name), options: .atomic)
        } catch {
            logger.error("Cannot write \(name, privacy: .public): \(error, privacy: .public)")
        }
    }
}

import Foundation
import Testing

struct CodeTests {
    let tool = "/opt/homebrew/bin/wget"
    let allowed = "e9941fa71be198eed966d1bf219f1471f10c303a"
    let swapped = "21ec44b85d0f790e541f22426eeb4b6d7502099e"

    @Test func onlySystemPathsAreProtected() {
        #expect(Config.isProtected("/usr/libexec/trustd"))
        #expect(Config.isProtected("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"))
        #expect(Config.isProtected("/bin/ls"))
        #expect(Config.isProtected("/sbin/ping"))
        #expect(!Config.isProtected("/usr/local/bin/tool"))
        #expect(!Config.isProtected("/System/Volumes/Data/opt/homebrew/bin/curl"))
        #expect(!Config.isProtected("/opt/homebrew/bin/curl"))
        #expect(!Config.isProtected("/Users/me/Applications/Tool.app/Contents/MacOS/Tool"))
        #expect(!Config.isProtected("/usrx/tool"))
    }

    @Test func signerTrustsAnyCode() {
        #expect(Config().trusts("EQHXZ8M8AV.com.google.Chrome", signer: "EQHXZ8M8AV", code: nil))
    }

    @Test func pathKeyTrustsOnlyAllowedCode() {
        let config = Config(codes: [tool: allowed])
        #expect(config.trusts(tool, signer: "", code: allowed))
        #expect(!config.trusts(tool, signer: "", code: swapped))
        #expect(!config.trusts(tool, signer: "", code: nil))
        #expect(!Config().trusts(tool, signer: "", code: allowed))
    }

    @Test func untrustedCodeLosesAllowRules() {
        let config = Config(
            mode: .ask, rules: [Rule(app: tool, action: .allow), Rule(app: tool, host: "example.com", action: .allow)])
        let verdict = { (host: String?, trusted: Bool) in
            config.decide(app: tool, host: host, isApple: false, domains: [:], trusted: trusted).action
        }
        #expect(verdict(nil, true) == .allow)
        #expect(verdict(nil, false) == nil)
        #expect(verdict("example.com", false) == nil)
    }

    @Test func untrustedCodeKeepsBlockRules() {
        let work = UUID()
        let config = Config(
            mode: .ask,
            rules: [
                Rule(app: tool, action: .block), Rule(app: tool, action: .allow, profile: work),
                Rule(app: tool, host: "ads.example.com", action: .block),
                Rule(app: tool, host: "cdn.ads.example.com", action: .allow),
            ])
        let verdict = { (host: String?, trusted: Bool) in
            config.decide(app: tool, host: host, isApple: false, domains: [:], profile: work, trusted: trusted).action
        }
        #expect(verdict(nil, true) == .allow)
        #expect(verdict(nil, false) == .block)
        #expect(verdict("cdn.ads.example.com", false) == .block)
    }

    @Test func newAllowRuleAllowsRunningCode() {
        var config = Config()
        var old = config
        config.setAction(.allow, for: tool)
        config.approveCode(since: old, running: [tool: allowed])
        #expect(config.codes == [tool: allowed])
        old = config
        config.profiles.append(Profile(name: "Work"))
        config.approveCode(since: old, running: [tool: swapped])
        #expect(config.codes == [tool: allowed])
    }

    @Test func onlyAllowAllowsCode() {
        var config = Config(rules: [Rule(app: tool, action: .allow)], codes: [tool: allowed])
        var old = config
        config.pick(.block, for: tool, host: nil, profile: nil)
        config.approveCode(since: old, running: [tool: swapped])
        #expect(config.codes == [tool: allowed])
        old = config
        config.pick(.allow, for: tool, host: nil, profile: nil)
        config.approveCode(since: old, running: [tool: swapped])
        #expect(config.codes == [tool: swapped])
    }

    @Test func deletingTheLastRuleForgetsTheCode() {
        var config = Config(rules: [Rule(app: tool, action: .allow)], codes: [tool: allowed])
        let old = config
        config.rules = []
        config.approveCode(since: old, running: [:])
        #expect(config.codes == [:])
    }

    @Test func configWithoutCodesStillLoads() throws {
        let data = Data(#"{"mode":"ask","rules":[],"lists":[],"limits":[],"profiles":[]}"#.utf8)
        #expect(try JSONDecoder().decode(Config.self, from: data).codes == nil)
    }

    @Test func unknownRunningCodeKeepsTheAllowedHash() {
        var config = Config(rules: [Rule(app: tool, action: .allow)], codes: [tool: allowed])
        let old = config
        config.setAction(.allow, for: tool, host: "example.com")
        config.approveCode(since: old, running: [:])
        #expect(config.codes == [tool: allowed])
    }
}

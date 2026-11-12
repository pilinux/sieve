import Foundation
import Testing

struct PickTests {
    let app = "EQHXZ8M8AV.com.google.Chrome"
    let work = UUID()

    @Test func pickAddsChangesAndRemoves() {
        var config = Config()
        config.pick(.block, for: app, host: nil, profile: work)
        #expect(config.rules.map(\.action) == [.block])
        #expect(config.rules.first?.profile == work)
        config.pick(.allow, for: app, host: nil, profile: work)
        #expect(config.rules.map(\.action) == [.allow])
        config.pick(.allow, for: app, host: nil, profile: work)
        #expect(config.rules.isEmpty)
    }

    @Test func pickLeavesOtherColumnsAlone() {
        var config = Config(rules: [Rule(app: app, action: .allow), Rule(app: app, host: "ads.example.com", action: .block)])
        config.pick(.block, for: app, host: nil, profile: work)
        config.pick(.allow, for: app, host: nil, profile: nil)
        #expect(config.rules.count == 2)
        #expect(config.rules.contains { $0.host == "ads.example.com" && $0.action == .block })
        #expect(config.rules.contains { $0.profile == work && $0.action == .block })
    }

    @Test func profileWithoutColourStillLoads() throws {
        let data = Data(#"{"name":"Home","id":"60F2B57D-C7DB-4485-B98A-5802900DC6A5","schedules":[]}"#.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: data)
        #expect(profile.color == nil)
    }
}

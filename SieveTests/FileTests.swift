import Foundation
import Testing

// Files as the build of 2026-11-12 saved them. A new field that breaks them must be optional instead.
struct FileTests {
    @Test func configOfAnEarlierBuildLoads() throws {
        let data = Data(
            #"""
            {"limits":[{"app":"EQHXZ8M8AV.com.google.Chrome","bytes":1000000,"period":"month"}],
            "lists":[{"action":"block","enabled":false,"id":"tracker-shield","name":"Tracker Shield",
            "url":"https:\/\/raw.githubusercontent.com\/StevenBlack\/hosts\/master\/hosts"}],
            "mode":"ask",
            "profiles":[{"color":"#4fb3c9","id":"60F2B57D-C7DB-4485-B98A-5802900DC6A5","name":"Work",
            "network":"IPv4.Router=10.0.0.1","schedules":[{"end":1020,"start":540,"weekdays":[3,2]}]}],
            "rules":[{"action":"block","app":"EQHXZ8M8AV.com.google.Chrome","host":"ads.example.com",
            "id":"0B1C6E2A-3F4D-4E5F-8A9B-1C2D3E4F5A6B","profile":"60F2B57D-C7DB-4485-B98A-5802900DC6A5"}]}
            """#.utf8)
        let config = try JSONDecoder().decode(Config.self, from: data)
        #expect(config.mode == .ask)
        #expect(config.rules.first?.host == "ads.example.com")
        #expect(config.profiles.first?.schedules.first?.weekdays == [2, 3])
        #expect(config.limits.first?.period == .month)
    }

    @Test func statsOfAnEarlierBuildLoad() throws {
        let data = Data(
            #"""
            {"apple":["com.apple.Safari"],"apps":{"EQHXZ8M8AV.com.google.Chrome":{"ads.example.com":"2026-11-12"}},
            "blocked":{"2026-11-12":3},"blockedTrackers":{},"brokenConfig":false,
            "bytes":{"EQHXZ8M8AV.com.google.Chrome":2048},
            "daily":{"2026-11-12":{"EQHXZ8M8AV.com.google.Chrome":2048}},"flags":[],
            "hits":["0B1C6E2A-3F4D-4E5F-8A9B-1C2D3E4F5A6B",{"count":3,"last":800000000}],"listSizes":{},
            "networks":[],"paths":{"EQHXZ8M8AV.com.google.Chrome":"\/Applications\/Google Chrome.app"},
            "seen":{"EQHXZ8M8AV.com.google.Chrome":"2026-11-12"},"trackers":["ads.example.com"]}
            """#.utf8)
        let stats = try JSONDecoder().decode(Stats.self, from: data)
        #expect(stats.blocked["2026-11-12"] == 3)
        #expect(stats.hits.values.first?.count == 3)
        #expect(stats.hosts("EQHXZ8M8AV.com.google.Chrome") == ["ads.example.com"])
        #expect(stats.addresses == nil)
    }

    // As the build with IP addresses saves them.
    @Test func statsWithAddressesLoad() throws {
        let data = Data(
            #"""
            {"addresses":{"EQHXZ8M8AV.com.google.Chrome":{"192.0.2.1":{"day":"2026-11-13","host":"ads.example.com"},
            "2001:db8::1":{"day":"2026-11-13"}}},
            "apple":[],"apps":{"EQHXZ8M8AV.com.google.Chrome":{"ads.example.com":"2026-11-13"}},
            "blocked":{},"blockedTrackers":{},"brokenConfig":false,"bytes":{},"daily":{},"flags":[],"hits":[],
            "listSizes":{},"networks":[],"paths":{},"seen":{"EQHXZ8M8AV.com.google.Chrome":"2026-11-13"},"trackers":[]}
            """#.utf8)
        let stats = try JSONDecoder().decode(Stats.self, from: data)
        #expect(
            stats.addresses?["EQHXZ8M8AV.com.google.Chrome"] == [
                "192.0.2.1": Address(day: "2026-11-13", host: "ads.example.com"),
                "2001:db8::1": Address(day: "2026-11-13"),
            ]
        )
    }
}

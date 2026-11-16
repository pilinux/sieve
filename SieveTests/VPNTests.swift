import Foundation
import Testing

struct VPNTests {
    // The browser's 100 bytes run through the VPN, which carries them as 110 bytes.
    let stats = Stats(
        seen: ["browser": "2026-11-16", "vpn": "2026-11-01"],
        bytes: ["browser": 120, "vpn": 110],
        daily: ["2026-11-16": ["browser": 100, "vpn": 110], "2026-11-15": ["browser": 20]],
        vpns: ["vpn"]
    )

    @Test func totalsLeaveOutVPNApps() {
        #expect(stats.totalBytes == 120)
        #expect(stats.totalBytes(day: "2026-11-16") == 100)
        #expect(stats.totalBytes(day: "2026-11-15") == 20)
        #expect(stats.totalBytes(day: "2026-11-14") == 0)
    }

    @Test func totalsCountAllAppsWithNoVPN() {
        var stats = stats
        stats.vpns = nil
        #expect(stats.totalBytes == 230)
    }

    @Test func pruneDropsTheVPNMarkWithTheApp() {
        var stats = stats
        stats.prune(Config(), cutoff: "2026-11-10")
        #expect(stats.vpns == [])
    }
}

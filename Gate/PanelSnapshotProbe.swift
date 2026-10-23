import AppKit
import SwiftUI

@main
struct PanelSnapshotProbe {
    @MainActor
    static func main() async {
        let environment = ProcessInfo.processInfo.environment
        let snapshot = await SnapshotHTTPClient.load(fallback: UsageSnapshot())
        precondition(snapshot.email == nil && snapshot.plan == nil, "local snapshot exposes account identity")
        precondition(snapshot.fiveHour?.usedPercent == Int(environment["CODEX_QUOTA_EXPECT_FIVE_HOUR"] ?? ""), "5h snapshot is stale")
        precondition(snapshot.weekly?.usedPercent == Int(environment["CODEX_QUOTA_EXPECT_WEEKLY"] ?? ""), "weekly snapshot is stale")
        precondition(snapshot.dailyUsage.count == Int(environment["CODEX_QUOTA_EXPECT_DAILY_COUNT"] ?? ""), "trend snapshot is incomplete")
        precondition(snapshot.dailyUsage.last?.tokens == Int64(environment["CODEX_QUOTA_EXPECT_LAST_TOKENS"] ?? ""), "trend snapshot is stale")
        for mode in DesktopPanelMode.allCases {
            let renderer = ImageRenderer(content: QuotaPanelContent(mode: mode, snapshot: snapshot, glassOpacity: 1).frame(width: mode.size.width, height: mode.size.height))
            precondition(renderer.nsImage != nil, "live snapshot did not render in \(mode.rawValue) mode")
        }
        print("All three panel contents received and rendered the live snapshot.")
    }
}

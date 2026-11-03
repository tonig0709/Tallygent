import Foundation
import CryptoKit
import Darwin
import AppKit

// Uses the production coordinator with a local, non-networked protocol fixture.
enum GlassSettingsSnapshot { static func load() -> GlassRenderSettings { .standard } }

@main
struct ModelCatalogProbe {
    @MainActor
    static func main() async {
        precondition(ProcessInfo.processInfo.environment["CODEX_QUOTA_ISOLATED_REGISTRY"] == "1")
        await catalogAndReceipts()
        await accountAndLifecycle()
        await refreshAndResetReads()
        await connectionReadFailures()
        print("Production catalog/capture probe passed: pagination, duplicate IDs, immediate quota publication, reset-only changes, optional usage failures, refresh errors/timeouts, unchanged reads, account isolation and reconnect ownership.")
    }

    @MainActor
    private static func wait(_ message: String, seconds: TimeInterval = 5, until ready: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !ready() && Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
        precondition(ready(), message)
    }

    private static func scope(_ email: String) -> String {
        SHA256.hash(data: Data(email.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func seedOldAccount() {
        SnapshotStore.save(UsageSnapshot(
            fiveHour: .init(usedPercent: 99, windowDurationMinutes: 300, resetsAt: nil),
            weekly: .init(usedPercent: 99, windowDurationMinutes: 10_080, resetsAt: nil),
            dailyUsage: [.init(startDate: "fixture-old", tokens: 999)],
            email: "old-catalog-fixture@example.invalid", receivedAt: .now))
    }

    @MainActor
    private static func catalogAndReceipts() async {
        setenv("TALLYGENT_CATALOG_PROBE_PHASE", "catalog", 1)
        seedOldAccount()
        let server = CodexAppServer()
        var batches: [[QuotaObservation]] = []
        server.onQuotaObservation = { [weak server] rows in
            precondition(rows.count == 2 && rows.allSatisfy { $0.provider == .codex && $0.source == .codexRateLimits })
            precondition(rows.allSatisfy { $0.accountScope == scope("catalog-fixture@example.invalid") })
            if batches.isEmpty {
                precondition(server?.snapshot.fiveHour?.remainingPercent == 88 && server?.snapshot.dailyUsage.isEmpty == true,
                             "old account data survived validation or quota publication waited for optional usage")
            }
            batches.append(rows)
        }
        defer { server.onQuotaObservation = nil; server.disconnect() }
        server.refreshModelCatalog()
        await wait("source quota was not captured before delayed usage") { batches.count == 1 }
        let firstReceipt = batches[0][0].receivedAt
        precondition(server.snapshot.fiveHour?.remainingPercent == 88 && server.snapshot.receivedAt == firstReceipt && !server.isRefreshing,
                     "fresh quota waited for delayed optional usage or did not end refresh feedback")
        precondition(SnapshotStore.load().receivedAt == firstReceipt,
                     "source receipt was not persisted with the immediately published quota")
        await wait("model pagination did not finish") { server.models.count == 2 }
        precondition(server.models.map(\.identifier).sorted() == ["fixture-advisor", "fixture-efficient"], "production model/list pagination did not finish")
        precondition(server.models.allSatisfy(\.isValid), "production catalog produced unsupported effort values")
        let goodModels = server.models
        server.setAppearance(.light)
        server.updateGlassSettings(.init(appearance: .light, opacity: 0.4))
        server.refreshModelCatalog() // This fixture releases held usage only after source capture was observed.
        await wait("catalog failure or delayed usage never completed") { !server.isLoadingModels && server.snapshot.hasQuota }
        precondition(server.snapshot.fiveHour?.remainingPercent == 88 && server.snapshot.weekly?.remainingPercent == 54,
                     "model catalog request IDs interfered with quota refresh")
        precondition(server.snapshot.receivedAt == firstReceipt && Date().timeIntervalSince(firstReceipt) >= 0.5,
                     "delayed daily usage replaced the actual source receipt time")
        precondition(batches.count == 1, "duplicate response ID generated another observation")
        precondition(!server.isLoadingModels && server.models == goodModels, "failed catalog refresh destroyed the last catalog or never completed")
        if case .connected = server.state { } else { preconditionFailure("catalog failure broke monitoring connection") }
        precondition(batches.count == 1, "appearance or catalog work invented a quota observation")

        server.refresh()
        await wait("unchanged successful read did not produce a fresh observation") { batches.count == 2 }
        let secondReceipt = batches[1][0].receivedAt
        precondition(Set(batches.map { $0[0].eventID }).count == 2 && secondReceipt > firstReceipt,
                     "different source responses reused event identity or receipt time")
        precondition(batches[0].map(\.usedPercent) == batches[1].map(\.usedPercent), "fixture was not an unchanged-read regression")
        precondition(server.snapshot.receivedAt == secondReceipt && !server.isRefreshing && batches.count == 2,
                     "missing optional usage blocked fresh quota or a replay generated history")
        precondition(SnapshotStore.load().receivedAt == secondReceipt && server.snapshot.updatedAt == SnapshotStore.load().updatedAt,
                     "an unchanged successful read left persistent receipt freshness behind")
    }

    @MainActor
    private static func accountAndLifecycle() async {
        setenv("TALLYGENT_CATALOG_PROBE_PHASE", "account", 1)
        seedOldAccount()
        let server = CodexAppServer()
        var batches: [[QuotaObservation]] = []
        server.onQuotaObservation = { [weak server] rows in
            if rows.first?.accountScope == scope("new-catalog-fixture@example.invalid") {
                precondition(server?.snapshot.fiveHour?.remainingPercent == 67 && server?.snapshot.dailyUsage.isEmpty == true,
                             "new account inherited old quota/history or source receipt was not published immediately")
            }
            batches.append(rows)
        }
        defer { server.onQuotaObservation = nil; server.disconnect(); unsetenv("TALLYGENT_CATALOG_PROBE_PHASE") }
        server.connect()
        await wait("initial account fixture did not synchronize") { batches.count == 1 && server.snapshot.hasQuota }
        server.refresh() // The fixture holds both old-account responses until the identity change.
        server.refreshModelCatalog() // Emits two account/updated notifications and reversed account replies.
        await wait("account change did not accept the current account's quota") {
            server.snapshot.email == "new-catalog-fixture@example.invalid" && server.snapshot.weekly?.remainingPercent == 34
        }
        precondition(batches.count == 2 && batches[1].allSatisfy { $0.accountScope == scope("new-catalog-fixture@example.invalid") },
                     "late old-account response entered history or was labeled with the new account")
        precondition(server.snapshot.fiveHour?.remainingPercent == 67 && server.snapshot.receivedAt == batches[1][0].receivedAt,
                     "stale account metadata or delayed old quota overwrote the new account")
        precondition(batches[0][0].accountScope != batches[1][0].accountScope, "known accounts were merged")

        // The terminated process can report its exit only after the new connection exists.
        server.disconnect()
        server.connect()
        await wait("old process termination cleared the replacement connection") {
            batches.count == 3 && server.snapshot.email == "catalog-fixture@example.invalid" && server.snapshot.weekly?.remainingPercent == 54
        }
        if case .connected = server.state { } else { preconditionFailure("replacement connection lost lifecycle ownership") }
        precondition(Set(batches.map { $0[0].eventID }).count == 3, "reconnection reused an observation identity")
        server.disconnect()
        let count = batches.count
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try? await Task.sleep(nanoseconds: 400_000_000)
        precondition(batches.count == count && server.state == .disconnected,
                     "wake resumed a disabled collector and could trigger an unrequested sign-in")
    }

    @MainActor
    private static func refreshAndResetReads() async {
        setenv("TALLYGENT_CATALOG_PROBE_PHASE", "refresh", 1)
        seedOldAccount()
        let server = CodexAppServer()
        var batches: [[QuotaObservation]] = []
        server.onQuotaObservation = { batches.append($0) }
        defer { server.onQuotaObservation = nil; server.disconnect(); unsetenv("TALLYGENT_CATALOG_PROBE_PHASE") }
        server.connect()
        await wait("initial refresh fixture did not publish quota and optional trend") {
            batches.count == 1 && server.snapshot.dailyUsage.last?.tokens == 100
        }
        let first = server.snapshot
        precondition(first.fiveHour?.usedPercent == 20 && first.weekly?.usedPercent == 40 && !server.isRefreshing)
        let firstReset = first.fiveHour!.resetsAt!
        let firstWeeklyReset = first.weekly!.resetsAt!

        server.refresh()
        precondition(server.isRefreshing, "refresh click has no immediate busy feedback")
        await wait("reset-only change was not published") { batches.count == 2 }
        precondition(server.snapshot.fiveHour?.usedPercent == first.fiveHour?.usedPercent &&
                     server.snapshot.weekly?.usedPercent == first.weekly?.usedPercent &&
                     server.snapshot.fiveHour?.resetsAt == firstReset.addingTimeInterval(7200) &&
                     server.snapshot.weekly?.resetsAt == firstWeeklyReset.addingTimeInterval(7200),
                     "reset time was retained from a different response despite unchanged usage")
        precondition(!server.isRefreshing && server.snapshot.dailyUsage.last?.tokens == 100,
                     "unsupported optional usage held quota refresh or erased the last valid trend")
        precondition(SnapshotStore.load().fiveHour == server.snapshot.fiveHour &&
                     SnapshotStore.load().weekly == server.snapshot.weekly,
                     "reset-only change did not reach the persistent snapshot")

        server.refresh()
        await wait("explicitly missing reset did not replace old reset") { batches.count == 3 }
        precondition(server.snapshot.fiveHour?.resetsAt == nil && server.snapshot.weekly?.resetsAt == nil,
                     "nil source reset was filled with a stale cached date")
        let beforeFailure = server.snapshot
        server.refresh()
        await wait("malformed quota reply did not terminate refresh with an error") {
            if case .failed = server.state { return !server.isRefreshing }
            return false
        }
        precondition(server.snapshot == beforeFailure && batches.count == 3,
                     "invalid quota response overwrote valid data or invented a history observation")

        server.refresh()
        await wait("manual refresh did not recover after malformed response") { batches.count == 4 }
        let beforeRPCFailure = server.snapshot
        server.refresh()
        await wait("quota RPC error was silently ignored") {
            if case .failed = server.state { return !server.isRefreshing }
            return false
        }
        precondition(server.snapshot == beforeRPCFailure && batches.count == 4,
                     "quota RPC error rewrote valid data or source receipt time")
        if case .failed(let message) = server.state {
            precondition(!message.contains("secret-marker"), "raw provider error leaked into presentation")
        }

        // First request remains in flight until an explicit fixture signal; repeated
        // clicks queue one fresh read without relying on runner scheduling or sleeps.
        server.refresh()
        await wait("failed refresh did not validate the account before reading again") {
            if case .connected = server.state { return server.isRefreshing }
            return false
        }
        server.refresh()
        server.refreshModelCatalog() // Releases the held quota reply, then the queued read.
        await wait("queued manual refresh did not finish both fresh reads") {
            batches.count == 6 && server.snapshot.fiveHour?.usedPercent == 32 && !server.isRefreshing
        }
        precondition(batches[4][0].usedPercent == 31 && batches[5][0].usedPercent == 32 &&
                     Set(batches.map { $0[0].eventID }).count == 6,
                     "queued or replayed responses lost order or reused an observation")
        precondition(server.snapshot.dailyUsage.last?.tokens == 100,
                     "optional usage errors erased a previously validated trend")

        let beforeTimeout = server.snapshot
        server.refresh()
        await wait("missing quota response stayed silently busy", seconds: 12) {
            if case .failed = server.state { return !server.isRefreshing }
            return false
        }
        precondition(server.snapshot == beforeTimeout && batches.count == 6,
                     "quota timeout refreshed cached data or destroyed the last valid snapshot")
        server.refresh()
        await wait("refresh after timeout could not read a new response") {
            server.snapshot.fiveHour?.usedPercent == 77 && !server.isRefreshing
        }
        precondition(server.snapshot.weekly?.usedPercent == 78 &&
                     SnapshotStore.load().receivedAt == server.snapshot.receivedAt,
                     "a late timed-out response replaced the current reading or its persisted receipt")
        print("Production refresh regression: reset dates, nil reset, immediate receipts, optional-method failure, queued reads, errors and timeout recovery: PASS")
    }

    @MainActor
    private static func connectionReadFailures() async {
        for phase in ["malformed-account", "bad-initialize"] {
            setenv("TALLYGENT_CATALOG_PROBE_PHASE", phase, 1)
            seedOldAccount()
            let server = CodexAppServer()
            var batches: [[QuotaObservation]] = []
            server.onQuotaObservation = { batches.append($0) }
            defer { server.onQuotaObservation = nil; server.disconnect(); unsetenv("TALLYGENT_CATALOG_PROBE_PHASE") }
            server.connect()
            await wait("invalid connection response did not end refresh with an error: \(phase)") {
                if case .failed = server.state { return !server.isRefreshing }
                return false
            }
            precondition(batches.isEmpty, "invalid connection response produced a quota observation: \(phase)")
            if case .failed(let message) = server.state {
                precondition(!message.contains("secret-marker"), "raw initialization error entered presentation")
            }
            // Initialization failure needs a new process. Account read failure should
            // recover in the existing process, not reinterpret malformed data as logout.
            if phase == "bad-initialize" { setenv("TALLYGENT_CATALOG_PROBE_PHASE", "refresh", 1) }
            server.refresh()
            await wait("manual refresh could not recover from \(phase)") {
                if case .connected = server.state { return batches.count == 1 && !server.isRefreshing }
                return false
            }
            let expected = phase == "bad-initialize" ? 20 : 12
            precondition(server.snapshot.fiveHour?.usedPercent == expected &&
                         server.snapshot.email == "catalog-fixture@example.invalid",
                         "connection recovery reused stale quota or unexpectedly requested login")
        }
        print("Production connection regression: malformed account and failed initialization recover without forced login: PASS")
    }
}

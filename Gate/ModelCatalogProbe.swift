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
        print("Production catalog/capture probe passed: pagination, duplicate IDs, source receipt timing, unchanged reads, account isolation and reconnect ownership.")
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
                precondition(server?.snapshot.hasQuota == false && server?.snapshot.dailyUsage.isEmpty == true,
                             "old account quota survived initial identity validation")
            }
            batches.append(rows)
        }
        defer { server.onQuotaObservation = nil; server.disconnect() }
        server.refreshModelCatalog()
        await wait("source quota was not captured before delayed usage") { batches.count == 1 }
        let firstReceipt = batches[0][0].receivedAt
        precondition(!server.snapshot.hasQuota, "capture waited for daily usage instead of source receipt")
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
        await wait("missing usage did not finish the partial quota refresh", seconds: 12) { server.snapshot.receivedAt == secondReceipt }
        precondition(Date().timeIntervalSince(secondReceipt) >= 8 && batches.count == 2,
                     "missing usage changed source time or a replay generated history")
    }

    @MainActor
    private static func accountAndLifecycle() async {
        setenv("TALLYGENT_CATALOG_PROBE_PHASE", "account", 1)
        seedOldAccount()
        let server = CodexAppServer()
        var batches: [[QuotaObservation]] = []
        server.onQuotaObservation = { [weak server] rows in
            if rows.first?.accountScope == scope("new-catalog-fixture@example.invalid") {
                precondition(server?.snapshot.hasQuota == false && server?.snapshot.dailyUsage.isEmpty == true,
                             "new account temporarily inherited old quota or token history")
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
}

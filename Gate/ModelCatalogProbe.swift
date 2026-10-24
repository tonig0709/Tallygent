import Foundation

// Uses the production coordinator with a local, non-networked protocol fixture.
enum GlassSettingsSnapshot { static func load() -> GlassRenderSettings { .standard } }

@main
struct ModelCatalogProbe {
    @MainActor
    static func main() async {
        precondition(ProcessInfo.processInfo.environment["CODEX_QUOTA_ISOLATED_REGISTRY"] == "1")
        let server = CodexAppServer()
        server.refreshModelCatalog()
        let deadline = Date().addingTimeInterval(15)
        while server.models.count < 2 && Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
        precondition(server.models.map(\.identifier).sorted() == ["fixture-advisor", "fixture-efficient"], "production model/list pagination did not finish")
        precondition(server.models.allSatisfy(\.isValid), "production catalog produced unsupported effort values")
        while !server.snapshot.hasQuota && Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
        precondition(server.snapshot.fiveHour?.remainingPercent == 88 && server.snapshot.weekly?.remainingPercent == 54,
                     "model catalog request IDs interfered with quota refresh")
        let goodModels = server.models
        server.refreshModelCatalog()
        let failureDeadline = Date().addingTimeInterval(15)
        while server.isLoadingModels && Date() < failureDeadline { try? await Task.sleep(nanoseconds: 50_000_000) }
        precondition(!server.isLoadingModels && server.models == goodModels, "failed catalog refresh destroyed the last catalog or never completed")
        if case .connected = server.state { } else { preconditionFailure("catalog failure broke monitoring connection") }
        server.disconnect()
        print("Production model catalog probe passed: initialization, pagination, ID isolation, failure recovery and unchanged monitoring.")
    }
}

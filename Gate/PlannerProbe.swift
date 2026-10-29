import Foundation

@main
struct PlannerProbe {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static func expect(_ value: Bool, _ message: String) { precondition(value, message) }
    private static func rejects(_ message: String, _ block: () throws -> Void) {
        do { try block(); preconditionFailure(message) } catch { }
    }
    private static func model(_ id: String, role: PlannerModelRole, defaultModel: Bool = false) -> PlannerModel {
        PlannerModel(provider: .codex, identifier: id, name: id, detail: "deterministic test fixture",
                     efforts: ["low", "medium", "high"], defaultEffort: "medium", isDefault: defaultModel,
                     role: role, source: "test fixture", discoveredAt: now, manuallyConfigured: false)
    }
    private static var quota: PlannerQuota {
        PlannerQuota(provider: .codex, scope: "test-scope", source: "test fixture", receivedAt: now,
                     windows: [PlannerQuotaWindow(id: "fiveHour", title: "5h", remainingPercent: 90, resetsAt: now.addingTimeInterval(3_600)),
                               PlannerQuotaWindow(id: "weekly", title: "Week", remainingPercent: 60, resetsAt: now.addingTimeInterval(100_000))], connected: true)
    }

    @MainActor
    static func main() async throws {
        let models = [model("fixture-efficient", role: .efficient), model("fixture-balanced", role: .balanced, defaultModel: true), model("fixture-quality", role: .quality)]
        let routine = PlannerProfile.classify("修正文案拼写 typo")
        let architecture = PlannerProfile.classify("设计支付认证系统架构 architecture auth")
        let traditional = PlannerProfile.classify("設計支付認證系統架構")
        expect(traditional.category == .architecture && traditional.risk == .high,
               "Traditional Chinese input bypassed the existing architecture/security rules")
        let taskB = PlannerProfile.resolved("修正文案拼写 typo", previous: architecture, manual: false)
        expect(taskB.category == .routine && taskB.complexity == .low && taskB.uncertainty == .low,
               "Task B inherited task A's automatic profile")
        expect(PlannerProfile.resolved("修正文案", previous: architecture, manual: true) == architecture,
               "Automatic classification discarded an explicit manual profile")
        let feature = PlannerProfile(category: .feature)
        func advice(_ profile: PlannerProfile = feature, _ preference: PlannerPreference = .balanced,
                    _ input: PlannerQuota = quota, _ catalog: [PlannerModel] = models,
                    _ history: [PlannerTaskRecord] = [], override: PlannerConfiguration? = nil) -> PlannerAdvice {
            PlannerEngine.advise(profile: profile, preference: preference, models: catalog, quota: input,
                                 reserve: 10, records: history, override: override, at: now)
        }
        let small = advice(routine, .efficiency)
        expect(small.recommended?.model.role == .efficient && small.recommended?.effort == "low", "Routine efficiency advice ignores task size")
        let highRisk = advice(architecture, .quality)
        expect(highRisk.recommended?.model.role == .quality && highRisk.recommended?.effort == "high", "High-risk advice ignores quality guardrail")
        expect(advice(architecture, .efficiency).recommended?.effort == "high", "Efficiency bypasses security guardrail")
        expect(advice().recommended?.model.isDefault == true && advice().recommended?.effort == "medium", "Ordinary feature has no balanced default")
        expect(advice().recommended?.isValid == true && advice().alternatives.allSatisfy(\.isValid), "Invalid model/effort was recommended")
        expect(advice(feature, .balanced, quota, []).recommended == nil, "No catalog produced invented models")
        var unsupported = models[0]; unsupported.efforts = ["low"]; unsupported.defaultEffort = "low"
        expect(advice(architecture, .quality, quota, [unsupported]).recommended == nil, "Unsupported high-risk effort combination was invented")
        expect(advice(architecture, .quality, quota, [unsupported], override: PlannerConfiguration(model: unsupported, effort: "low")).recommended?.effort == "low",
               "An explicit low-effort override is not available to the user")

        var missing = quota; missing.windows = []
        expect(advice(feature, .balanced, missing).recommended != nil && advice(feature, .balanced, missing).warnings.contains { $0.contains("缺失") }, "Missing quota should preserve clearly unvalidated task advice")
        var partial = quota; partial.windows.removeFirst()
        expect(advice(feature, .balanced, partial).warnings.contains { $0.contains("未提供5h") }, "Partial quota omitted an unknown short-term constraint")
        var stale = quota; stale.receivedAt = now.addingTimeInterval(-600)
        expect(advice(feature, .balanced, stale).warnings.contains { $0.contains("较旧") }, "Stale quota not exposed")
        var constrained = quota; constrained.windows[1].remainingPercent = 5
        expect(advice(feature, .balanced, constrained).shouldWait, "Weekly reserve was hidden by generous short-term quota")
        expect(advice(feature, .quality, constrained).recommended?.model.role == .quality, "Quota pressure silently weakened quality requirement")
        var expired = quota; expired.windows[0].resetsAt = now
        expect(advice(feature, .balanced, expired).warnings.contains { $0.contains("重置点") }, "Expired window is treated as current quota")
        expect(advice().evidence.contains("历史不足"), "Cold start fabricates historical evidence")

        let efficient = PlannerConfiguration(model: models[0], effort: "medium")
        var records: [PlannerTaskRecord] = (0..<5).map { index in
            PlannerTaskRecord(title: nil, profile: feature, preference: .efficiency, configuration: efficient,
                              createdAt: now.addingTimeInterval(-Double(index)), startedAt: now, completedAt: now,
                              before: quota, after: quota, outcome: .failed, tokens: PlannerTokenUsage(input: 100, output: 200))
        }
        expect(advice(feature, .efficiency, quota, models, records).recommended?.model.identifier != models[0].identifier,
               "Repeated failures do not discourage a nominally efficient configuration")
        let insufficient = PlannerEngine.summary(records: Array(records.prefix(4)), profile: feature, configuration: efficient, scope: "test-scope")
        expect(!insufficient.discourages && insufficient.medianReportedTokens == nil, "Less than five samples fabricated quantitative calibration")
        expect(PlannerEngine.summary(records: records, profile: feature, configuration: efficient, scope: "other").evaluated == 0,
               "Task evidence crossed account boundaries")
        expect(records[0].attribution.contains("并发"), "Shared quota was attributed to a single task")
        records[0].completedAt = now.addingTimeInterval(4_000)
        records[0].after?.receivedAt = now.addingTimeInterval(4_000)
        expect(records[0].attribution.contains("重置"), "Quota reset did not invalidate task attribution")
        let manual = PlannerConfiguration(model: models[2], effort: "medium")
        expect(advice(feature, .balanced, quota, models, [], override: manual).recommended == manual, "Valid manual override was ignored")
        expect(advice(feature, .balanced, quota, models, [], override: PlannerConfiguration(model: models[2], effort: "invented")).recommended?.effort != "invented", "Invalid override bypassed catalog")
        var duplicateEfforts = models[0]; duplicateEfforts.efforts = ["medium", "medium"]
        expect(!duplicateEfforts.isValid, "Duplicate effort IDs can break the native picker")
        expect(!PlannerModel.safeIdentifier("model\"; do-not-execute"), "Unsafe configuration escaped model validation")

        let response: [String: Any] = ["result": ["data": [
            ["model": "fixture-visible", "displayName": "Visible", "description": "Fast and efficient", "hidden": false,
             "defaultReasoningEffort": "medium", "supportedReasoningEfforts": [["reasoningEffort": "medium"]], "isDefault": true],
            ["model": "fixture-hidden", "displayName": "Hidden", "hidden": true,
             "defaultReasoningEffort": "low", "supportedReasoningEfforts": [["reasoningEffort": "low"]]],
            ["model": "fixture-unavailable", "displayName": "Unavailable", "available": false,
             "defaultReasoningEffort": "low", "supportedReasoningEfforts": [["reasoningEffort": "low"]]]
        ], "nextCursor": "page-2"]]
        let page = try PlannerModel.parsePage(response, at: now)
        expect(page.models.count == 1 && page.cursor == "page-2" && page.models[0].role == .efficient, "Catalog parser loses availability/effort/page contract")
        rejects("Malformed catalog accepted") { _ = try PlannerModel.parsePage(["result": ["data": "broken"]], at: now) }
        var oldCatalog = models; oldCatalog[0].discoveredAt = now.addingTimeInterval(-4_000)
        expect(advice(routine, .efficiency, quota, oldCatalog).recommended?.model.identifier != models[0].identifier, "Stale catalog entry used")
        var manualDuplicate = models[0]; manualDuplicate.manuallyConfigured = true
        let merged = PlannerModel.merged(live: models, manual: manualDuplicate, provider: .codex, at: now)
        expect(merged.count == models.count && merged.first { $0.id == manualDuplicate.id }?.manuallyConfigured == false,
               "Recovered catalog duplicates or loses authority to a fallback Picker ID")
        let staleFallback = PlannerModel.merged(live: oldCatalog, manual: manualDuplicate, provider: .codex, at: now)
        expect(staleFallback.first { $0.id == manualDuplicate.id }?.manuallyConfigured == true,
               "A stale catalog prevents explicitly declared fallback configuration")

        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let url = root.appendingPathComponent("planner.json")
        try PlannerPersistence.save(records, to: url)
        expect(try PlannerPersistence.load(from: url) == records, "History did not persist losslessly")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
        expect(permissions.intValue & 0o777 == 0o600, "Task history permissions are not private")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        object.removeValue(forKey: "schemaVersion")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        expect(try PlannerPersistence.load(from: url) == records, "Version-zero migration cannot read records")
        try PlannerPersistence.save(records, to: url)
        object["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let future = try Data(contentsOf: url)
        rejects("Future schema was overwritten") { try PlannerPersistence.save([], to: url) }
        expect(try Data(contentsOf: url) == future, "Rejecting migration lost original data")
        try PlannerPersistence.save([], to: url, replacingInvalidFile: true)
        expect(try PlannerPersistence.load(from: url).isEmpty, "Explicit history reset failed")
        let store = PlannerStore(url: url)
        await store.load()
        expect(store.isLoaded, "Planner store did not load")
        _ = await store.saveTask(profile: feature, preference: .balanced, configuration: manual, title: nil, quota: quota, start: false)
        let id = store.records[0].id
        await store.start(id, quota: quota)
        expect(store.records[0].outcome == .running, "Planned task did not start")
        await store.complete(id, outcome: .succeeded, quota: quota, retries: 1, quality: 4,
                             rework: false, verification: .passed, tokens: nil)
        expect(store.records[0].outcome == .succeeded && store.records[0].title == nil, "Completion lost feedback or stored unrequested raw text")
        await store.clear()
        expect(store.records.isEmpty, "User cannot remove local task history")
        print("Planner gate passed: classifier, dynamic catalog, valid effort, all quota windows, freshness, reserves, feedback, attribution, overrides, persistence and schema protection.")
    }
}

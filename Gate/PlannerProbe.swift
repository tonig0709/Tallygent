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
        let insufficient = PlannerEngine.summary(records: Array(records.prefix(4)), profile: feature, configuration: efficient, scope: "test-scope", at: now)
        expect(insufficient.evaluated == 4 && !insufficient.discourages && insufficient.medianReportedTokens == nil, "Less than five samples fabricated quantitative calibration")
        expect(PlannerEngine.summary(records: records, profile: feature, configuration: efficient, scope: "other", at: now).evaluated == 0,
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

        // Natural-language classification must use task signals, not English substrings.
        let plainEnglish = PlannerProfile.classify("Build a biography page for an author")
        expect(plainEnglish.category != .ui && plainEnglish.risk == .low,
               "English substrings inside build/author triggered UI or authentication rules")
        let urgent = PlannerProfile.classify("紧急修复线上偶发崩溃，支付认证跨模块迁移")
        expect(urgent.urgent && urgent.complexity == .high && urgent.uncertainty == .high && urgent.risk == .high,
               "Natural-language urgency or combined task signals were lost")
        expect(!PlannerProfile.resolved("修正文案拼写", previous: urgent, manual: false).urgent,
               "A new ordinary task inherited the previous task's automatic urgency")
        let englishUrgent = PlannerProfile.classify("Urgent: debug an intermittent crash in the payment migration")
        expect(englishUrgent.urgent && englishUrgent.category == .debugging && englishUrgent.risk == .high,
               "English natural-language task was not classified")
        let complex = PlannerProfile(category: .architecture, complexity: .high, uncertainty: .medium, risk: .low)
        let complexAdvice = advice(complex, .efficiency)
        expect(complexAdvice.recommended?.model.role == .quality && complexAdvice.recommended?.effort == "high",
               "Efficiency preference weakened a complex task's model/effort guardrail")
        expect(complexAdvice.alternatives.allSatisfy { PlannerModel.effortRank($0.effort) >= 4 },
               "Alternative configurations bypassed the complex-task reasoning floor")
        let blank = PlannerEngine.advise(task: " \n\t ", preference: .balanced, models: models,
                                         quota: quota, reserve: 10, records: [], at: now)
        expect(blank.recommended == nil && blank.decision == .needsInformation && blank.confidence == .low,
               "An empty task received a confident runnable configuration")
        let fromText = PlannerEngine.advise(task: "设计支付认证系统架构", preference: .efficiency,
                                            models: models, quota: quota, reserve: 10, records: [], at: now)
        expect(fromText.recommended?.model.role == .quality && fromText.recommended?.effort == "high",
               "The natural-language entry point does not apply conservative classification")
        expect(fromText.tokenEstimate == nil, "Cold-start rules fabricated a token estimate")
        let manualTask = PlannerEngine.advise(task: "紧急修复支付认证", previous: routine, manual: true, urgent: false,
                                              preference: .efficiency, models: models, quota: quota, reserve: 10, records: [], at: now)
        expect(manualTask.recommended?.effort == "high", "Manual task traits bypassed text-detected sensitive risk")
        let fallback = advice(complex, .efficiency, quota, [models[1]])
        expect(fallback.recommended?.model.role == .balanced && fallback.recommended?.effort == "high"
               && fallback.confidence == .low && !fallback.warnings.isEmpty,
               "Missing quality-role model did not produce a guarded, explicit fallback")

        // Quota percentages describe constraints, never an inferred token balance.
        let checked = advice()
        expect(checked.quotaAssessment.status == .available && checked.quotaAssessment.usablePercent == 50,
               "The tightest quota window minus reserve was not exposed")
        expect(checked.decision == .configuration, "A fresh complete quota did not permit a configuration")
        for incomplete in [missing, partial, stale, expired] {
            let result = advice(feature, .balanced, incomplete)
            expect(result.quotaAssessment.status == .unknown && result.quotaAssessment.usablePercent == nil,
                   "Missing/stale/expired quota was presented as verified headroom")
            expect(result.decision == .needsInformation && result.confidence == .low,
                   "Unverified quota returned a confident run decision")
        }
        expect(advice(feature, .balanced, constrained).decision == .wait,
               "An exhausted weekly window did not return a wait decision")
        var zeroQuota = quota; zeroQuota.windows[0].remainingPercent = 0
        let zeroReserve = PlannerEngine.advise(profile: feature, preference: .balanced, models: models,
                                               quota: zeroQuota, reserve: 0, records: [], at: now)
        expect(zeroReserve.shouldWait && zeroReserve.quotaAssessment.status == .wait,
               "Zero percent remaining was considered usable with zero reserve")
        for percent in [-1, 101] {
            var invalidQuota = quota; invalidQuota.windows[0].remainingPercent = percent
            let result = advice(feature, .balanced, invalidQuota)
            expect(result.quotaAssessment.status == .unknown && result.decision == .needsInformation,
                   "Out-of-range quota percentages were treated as verified")
        }
        var duplicateQuota = quota; duplicateQuota.windows.append(duplicateQuota.windows[0])
        expect(advice(feature, .balanced, duplicateQuota).quotaAssessment.status == .unknown,
               "Duplicate quota-window identifiers were accepted as authoritative")
        var wrongDuration = quota; wrongDuration.windows[0].durationMinutes = 10_080
        expect(advice(feature, .balanced, wrongDuration).quotaAssessment.status == .unknown,
               "A weekly duration masquerading as a five-hour window was accepted")
        var futureQuota = quota; futureQuota.receivedAt = now.addingTimeInterval(60)
        expect(advice(feature, .balanced, futureQuota).quotaAssessment.status == .unknown,
               "A future-dated quota record was accepted as fresh")

        // Candidate selection remains deterministic and within the actual catalog.
        expect(advice(feature, .balanced, quota, Array(models.reversed())).recommended?.id == checked.recommended?.id,
               "Catalog ordering changed the deterministic recommendation")
        let duplicateCatalogAdvice = advice(feature, .balanced, quota, models + models)
        let emitted = ([duplicateCatalogAdvice.recommended].compactMap { $0 } + duplicateCatalogAdvice.alternatives).map(\.id)
        expect(Set(emitted).count == emitted.count, "Duplicate catalog rows produced duplicate recommendation IDs")
        var conflictingModel = models[1]; conflictingModel.efforts = ["low"]; conflictingModel.defaultEffort = "low"
        let conflictingCatalog = PlannerModel.merged(live: models + [conflictingModel], manual: nil, provider: .codex, at: now)
        expect(!conflictingCatalog.contains { $0.id == conflictingModel.id },
               "Conflicting effort contracts for one model ID were resolved arbitrarily")
        var invalidManual = manualDuplicate; invalidManual.identifier = "unsafe identifier"
        expect(PlannerModel.merged(live: [], manual: invalidManual, provider: .codex, at: now).isEmpty,
               "An invalid manual model bypassed merged catalog validation")
        var unknownEffort = models[1]; unknownEffort.efforts = ["mystery"]; unknownEffort.defaultEffort = "mystery"
        let unknownAutomatic = advice(feature, .balanced, quota, [unknownEffort])
        expect(unknownAutomatic.recommended == nil && unknownAutomatic.decision == .unavailable,
               "An unknown effort was automatically assigned a reasoning rank")
        let unknownManual = advice(feature, .balanced, quota, [unknownEffort], override: PlannerConfiguration(model: unknownEffort, effort: "mystery"))
        expect(unknownManual.recommended?.effort == "mystery" && unknownManual.confidence == .low && !unknownManual.warnings.isEmpty,
               "Explicit unknown-effort override lost its warning or low confidence")
        expect(!unknownManual.qualitySatisfied && unknownManual.decision == .needsInformation,
               "Unknown manual effort rank was incorrectly accepted as satisfying quality")
        var otherProvider = models[0]; otherProvider.provider = .claude
        expect(advice(feature, .balanced, quota, [otherProvider]).recommended == nil,
               "A candidate from a different quota provider leaked into recommendations")

        // Local token ranges require at least five usable, comparable reports.
        let balancedConfiguration = PlannerConfiguration(model: models[1], effort: "medium")
        let tokenReports: [PlannerTaskRecord] = (1...5).map { index in
            PlannerTaskRecord(title: nil, profile: feature, preference: .balanced, configuration: balancedConfiguration,
                              createdAt: now.addingTimeInterval(-60), startedAt: now.addingTimeInterval(-30), completedAt: now,
                              before: quota, after: quota, outcome: .succeeded, verification: .passed,
                              tokens: PlannerTokenUsage(input: Int64(index * 100), output: Int64(index * 100)))
        }
        let calibrated = advice(feature, .balanced, quota, models, tokenReports)
        expect(calibrated.tokenEstimate?.sampleCount == 5 && calibrated.tokenEstimate?.median == 600,
               "Comparable reported tokens were not summarized with a reproducible median")
        if let estimate = calibrated.tokenEstimate {
            expect(estimate.lower <= estimate.median && estimate.median <= estimate.upper,
                   "The historical token range does not contain its median")
        }
        expect(advice(feature, .balanced, quota, models, Array(tokenReports.prefix(4))).tokenEstimate == nil,
               "Fewer than five reports produced a numeric cost estimate")
        var invalidTokens = tokenReports
        invalidTokens[0].tokens = PlannerTokenUsage(input: -1, output: 100)
        expect(advice(feature, .balanced, quota, models, invalidTokens).tokenEstimate == nil,
               "Invalid token reports were counted toward the estimate threshold")
        var wrongScope = tokenReports
        for index in wrongScope.indices { wrongScope[index].before?.scope = "another-account"; wrongScope[index].after?.scope = "another-account" }
        expect(advice(feature, .balanced, quota, models, wrongScope).tokenEstimate == nil,
               "Historical token estimates crossed account boundaries")
        func reportSummary(_ input: [PlannerTaskRecord]) -> PlannerHistorySummary {
            PlannerEngine.summary(records: input, profile: feature, configuration: balancedConfiguration,
                                  scope: "test-scope", at: now)
        }
        let repeatedReport = reportSummary(Array(repeating: tokenReports[0], count: 5))
        expect(repeatedReport.evaluated == 1 && repeatedReport.tokenEstimate == nil,
               "Duplicate report UUIDs fabricated a five-sample calibration")
        var conflictingReport = tokenReports[0]
        conflictingReport.outcome = .failed; conflictingReport.verification = .failed
        expect(reportSummary([tokenReports[0], conflictingReport]).evaluated == 0
               && reportSummary([conflictingReport, tokenReports[0]]).evaluated == 0,
               "Contradictory records with one UUID calibrated recommendations based on input order")
        var sixthReport = tokenReports[0]; sixthReport.id = UUID(); sixthReport.tokens = .init(input: 600, output: 600)
        expect(reportSummary(tokenReports + [sixthReport]).medianReportedTokens == 700,
               "An even number of reports did not average the two central token totals")
        var futureReports = tokenReports
        for index in futureReports.indices { futureReports[index].completedAt = now.addingTimeInterval(60) }
        expect(reportSummary(futureReports).evaluated == 0,
               "Future task completions influenced current recommendations")
        var reversedReports = tokenReports
        for index in reversedReports.indices { reversedReports[index].startedAt = now.addingTimeInterval(1) }
        expect(reportSummary(reversedReports).evaluated == 0,
               "Task completion before its start was accepted as comparable evidence")
        var reversedCreation = tokenReports
        for index in reversedCreation.indices { reversedCreation[index].createdAt = now }
        expect(reportSummary(reversedCreation).evaluated == 0,
               "Task creation after its start was accepted as comparable evidence")
        var mismatchedProviders = tokenReports
        for index in mismatchedProviders.indices {
            mismatchedProviders[index].before?.provider = .claude
            mismatchedProviders[index].after?.provider = .claude
        }
        expect(reportSummary(mismatchedProviders).evaluated == 0,
               "Quota reports from another provider calibrated a Codex configuration")
        var changedProvider = tokenReports
        for index in changedProvider.indices { changedProvider[index].after?.provider = .claude }
        expect(reportSummary(changedProvider).evaluated == 0,
               "A provider change during the task was counted as comparable evidence")
        var emptyAttribution = tokenReports[0]
        emptyAttribution.before?.windows = []; emptyAttribution.after?.windows = []
        expect(emptyAttribution.attribution.contains("不可归因"),
               "Empty quota snapshots passed the attribution window checks")
        var addedWindow = tokenReports[0]; addedWindow.before?.windows.removeFirst()
        expect(addedWindow.attribution.contains("不可归因"),
               "A new quota window appearing after execution passed attribution checks")
        expect(mismatchedProviders[0].attribution.contains("范围变化"),
               "A quota provider different from the configuration passed attribution checks")

        // Multi-dimensional profiling uses task evidence, not description length.
        let profileCases: [(String, PlannerCategory, PlannerLevel, PlannerLevel, PlannerLevel)] = [
            ("Format comments in one file", .routine, .low, .low, .low),
            ("Fix an isolated bug in one file and add unit tests", .debugging, .low, .low, .low),
            ("Implement a multi-file feature with API dependencies", .feature, .high, .medium, .low),
            ("Design architecture for a repository-wide cross-service refactor", .architecture, .high, .medium, .low),
            ("Debug an intermittent crash with unknown root cause", .debugging, .medium, .high, .low),
            ("Review authentication and payment changes with regression tests", .review, .medium, .medium, .high),
            ("Analyze entire codebase with long context", .review, .high, .medium, .low),
            ("make it better", .other, .medium, .high, .low),
            ("分階段設計系統架構，加入單元測試", .architecture, .high, .medium, .low)
        ]
        for (text, category, complexity, uncertainty, risk) in profileCases {
            let profile = PlannerProfile.classify(text)
            expect(profile.category == category && profile.complexity == complexity
                   && profile.uncertainty == uncertainty && profile.risk == risk,
                   "Multi-dimensional task fixture was misclassified: \(text)")
            expect(profile.dimensions != nil, "Natural-language task omitted its dimension evidence")
        }
        let isolatedProfile = PlannerProfile.classify(profileCases[1].0)
        expect(isolatedProfile.dimensions?.scope == .low && isolatedProfile.dimensions?.context == .low
               && isolatedProfile.dimensions?.automatedVerification == true
               && isolatedProfile.dimensions?.verification == .medium,
               "Isolated scope and repeatable verification were not represented independently")
        let multiProfile = PlannerProfile.classify(profileCases[2].0)
        expect(multiProfile.dimensions?.scope == .high && multiProfile.dimensions?.integration == .medium
               && multiProfile.dimensions?.context == nil,
               "Unobserved context requirements were invented from multi-file scope")
        let contextProfile = PlannerProfile.classify(profileCases[6].0)
        expect(contextProfile.dimensions?.context == .high && contextProfile.dimensions?.confidence == .medium,
               "Long-context analysis lost the source of its elevated requirement")
        let stagedProfile = PlannerProfile.classify(profileCases[8].0)
        expect(stagedProfile.dimensions?.decomposable == true && stagedProfile.dimensions?.automatedVerification == true,
               "Traditional Chinese stage and test signals were not normalized")
        expect(PlannerProfile.classify("Format comments in one file" + String(repeating: " details", count: 900)).complexity == .low,
               "Description length was used as a direct complexity proxy")
        expect(PlannerProfile.classify("make it better").dimensions?.confidence == .low,
               "An underspecified task received strong classification evidence")
        var legacyProfileObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(feature)) as! [String: Any]
        legacyProfileObject.removeValue(forKey: "dimensions")
        let migratedProfile = try JSONDecoder().decode(PlannerProfile.self, from: JSONSerialization.data(withJSONObject: legacyProfileObject))
        expect(migratedProfile == feature && migratedProfile.dimensions == nil,
               "Existing schema-1 profile records cannot decode or acquired fabricated dimensions")

        // Enumerate only real supported model/effort combinations, including non-selected ones.
        let candidateAdvice = advice()
        let expectedCandidateIDs = models.flatMap { item in
            item.efforts.filter { PlannerModel.effortRank($0) >= 3 }.map {
                PlannerConfiguration(model: item, effort: $0).id
            }
        }.sorted()
        expect(candidateAdvice.evaluations.map { $0.configuration.id } == expectedCandidateIDs
               && candidateAdvice.evaluations.allSatisfy { $0.configuration.isValid },
               "Candidate evaluation skipped or invented supported model/effort combinations")
        expect(candidateAdvice.evaluations.allSatisfy { $0.completionTokens == nil && $0.adverseBurden == nil },
               "Cold-start candidate evidence fabricated free resource costs or failure probabilities")
        var unknownRole = models[1]; unknownRole.role = .unknown
        let unknownRoleAdvice = advice(feature, .balanced, quota, [unknownRole])
        expect(unknownRoleAdvice.evaluations.allSatisfy { $0.ordinalResourceTier == nil && $0.completionTokens == nil }
               && !unknownRoleAdvice.qualitySatisfied && unknownRoleAdvice.decision == .needsInformation,
               "Unknown model capability was treated as measured, free or quality-feasible")
        expect(!fallback.qualitySatisfied && fallback.decision == .needsInformation,
               "An explicitly weaker quality fallback was presented as an equivalent runnable suggestion")
        expect(candidateAdvice.qualitySatisfied && candidateAdvice.policyVersion == PlannerPolicy.version,
               "A feasible recommendation omitted its quality decision or versioned policy")

        // User reserves and provider exhaustion are deliberately distinct constraints.
        let reserveWait = constrained.assessment(reserve: 10, at: now)
        expect(reserveWait.status == .wait && !reserveWait.providerExhausted,
               "A voluntary reserve was mislabeled as a provider-imposed block")
        expect(zeroQuota.assessment(reserve: 0, at: now).providerExhausted,
               "A confirmed zero balance was not distinguished from a voluntary reserve")

        func pace(_ windowID: String, rate: Double = 36) -> PlannerQuotaPace {
            let window = quota.windows.first { $0.id == windowID }!
            return PlannerQuotaPace(provider: quota.provider, scope: quota.scope, windowID: windowID,
                                    receivedAt: now, resetsAt: window.resetsAt,
                                    remainingPercent: window.remainingPercent, ratePerHour: rate,
                                    samples: 4, observedSpan: 300)
        }
        func pressure(_ input: [PlannerQuotaPace], quota inputQuota: PlannerQuota = quota,
                      policy: PlannerPolicy = PlannerPolicy()) -> Double? {
            PlannerEngine.quotaPressure(quota: inputQuota, reserve: 10, pacing: input, at: now, policy: policy)
        }
        let shortPace = pace("fiveHour", rate: 180)
        let weeklyPace = pace("weekly")
        let shortPressure = pressure([shortPace])!
        let weeklyPressure = pressure([weeklyPace])!
        expect(shortPressure > 1 && weeklyPressure > 1
               && pressure([shortPace, weeklyPace]) == max(shortPressure, weeklyPressure),
               "Shared short/weekly constraints were summed as independent model-specific prices")
        expect(pressure([shortPace, weeklyPace]) == pressure([weeklyPace, shortPace]),
               "Pacing input order changed deterministic shared-window pressure")
        expect(pressure([shortPace, shortPace]) == nil,
               "Duplicate pacing entries were arbitrarily selected or double-counted")
        var invalidPaces: [PlannerQuotaPace] = []
        var wrongPaceScope = shortPace; wrongPaceScope.scope = "another-account"; invalidPaces.append(wrongPaceScope)
        var wrongPaceProvider = shortPace; wrongPaceProvider.provider = .claude; invalidPaces.append(wrongPaceProvider)
        var oldPaceCycle = shortPace; oldPaceCycle.resetsAt = now.addingTimeInterval(3_599); invalidPaces.append(oldPaceCycle)
        var oldPaceBalance = shortPace; oldPaceBalance.remainingPercent -= 1; invalidPaces.append(oldPaceBalance)
        var stalePace = shortPace; stalePace.receivedAt = now.addingTimeInterval(-121); invalidPaces.append(stalePace)
        var futurePace = shortPace; futurePace.receivedAt = now.addingTimeInterval(6); invalidPaces.append(futurePace)
        var fewPaceSamples = shortPace; fewPaceSamples.samples = 3; invalidPaces.append(fewPaceSamples)
        var shortPaceSpan = shortPace; shortPaceSpan.observedSpan = 299; invalidPaces.append(shortPaceSpan)
        var weakResolution = shortPace; weakResolution.ratePerHour = 35.9; invalidPaces.append(weakResolution)
        for value in [Double.nan, .infinity, -1, 0] {
            var invalidRate = shortPace; invalidRate.ratePerHour = value; invalidPaces.append(invalidRate)
        }
        for value in [Double.nan, .infinity, -1] {
            var invalidSpan = shortPace; invalidSpan.observedSpan = value; invalidPaces.append(invalidSpan)
        }
        var overlongPace = shortPace; overlongPace.observedSpan = 3_601; invalidPaces.append(overlongPace)
        for input in invalidPaces {
            expect(pressure([input]) == nil, "Invalid, stale, cross-scope or low-resolution pace affected quota pressure")
        }
        expect(pressure([shortPace], quota: stale) == nil && pressure([]) == nil,
               "Unknown or stale observations were converted to zero-pressure evidence")
        var noScopeQuota = quota; noScopeQuota.scope = nil
        expect(pressure([shortPace], quota: noScopeQuota) == nil,
               "A pace was applied without a verified account/session scope")
        var nearResetQuota = quota; nearResetQuota.windows[0].resetsAt = now.addingTimeInterval(1)
        var nearResetPace = shortPace; nearResetPace.resetsAt = nearResetQuota.windows[0].resetsAt
        expect(pressure([nearResetPace], quota: nearResetQuota) == 1,
               "A close reset discounted scarcity below neutral and encouraged quota waste")
        expect(pressure([weeklyPace], policy: PlannerPolicy(maximumPressure: 2)) == 2,
               "Configured quota pressure cap was not respected")
        let boundedPolicy = PlannerPolicy(minimumSamples: 0, feedbackMaximumAgeDays: 0, maximumPressure: .nan)
        expect(boundedPolicy.minimumSamples == 5 && boundedPolicy.feedbackMaximumAgeDays == 1
               && boundedPolicy.maximumPressure == 4,
               "Invalid policy settings bypassed evidence minimums or allowed nonfinite pressure")
        let underPressure = PlannerEngine.advise(profile: feature, preference: .balanced, models: models,
                                                 quota: quota, reserve: 10, records: [], at: now,
                                                 pacing: [shortPace, weeklyPace])
        expect(underPressure.quotaPressure == max(shortPressure, weeklyPressure)
               && underPressure.qualitySatisfied
               && underPressure.recommended.map { PlannerModel.effortRank($0.effort) >= 3 } == true,
               "Scarcity bypassed the quality floor or was not exposed with the recommendation")
        let ampleRoutine = advice(routine, .balanced)
        let pacedRoutine = PlannerEngine.advise(profile: routine, preference: .balanced, models: models,
            quota: quota, reserve: 10, records: [], at: now, pacing: [shortPace, weeklyPace])
        expect(ampleRoutine.recommended?.model.role == .balanced && pacedRoutine.recommended?.model.role == .efficient
               && pacedRoutine.qualitySatisfied && pacedRoutine.recommended?.effort == "low",
               "Measured scarcity did not change resource priorities within the same sufficient quality floor")
        let pacedQuality = PlannerEngine.advise(profile: architecture, preference: .quality, models: models,
            quota: quota, reserve: 10, records: [], at: now, pacing: [shortPace, weeklyPace])
        expect(pacedQuality.recommended == highRisk.recommended && pacedQuality.qualitySatisfied,
               "Scarcity changed a high-risk quality-first configuration")

        // Completion cost requires verified successful feedback, not recommendation selection.
        let completionEvidence = reportSummary(tokenReports)
        expect(completionEvidence.verifiedCompletions == 5 && completionEvidence.completionTokens?.sampleCount == 5,
               "Verified completion reports did not expose their reproducible Token summary")
        expect(reportSummary(Array(tokenReports.prefix(4))).completionTokens == nil,
               "Too few verified completions produced a completion-cost estimate")
        var unverifiedReports = tokenReports
        for index in unverifiedReports.indices { unverifiedReports[index].verification = .notRun }
        expect(reportSummary(unverifiedReports).completionTokens == nil,
               "Unverified self-reported completions were treated as verified completion costs")
        var failedReports = tokenReports
        for index in failedReports.indices { failedReports[index].outcome = .failed }
        expect(reportSummary(failedReports).completionTokens == nil,
               "Failed first attempts were compared as full successful completion costs")
        let stricterSummary = PlannerEngine.summary(records: failedReports, profile: feature,
            configuration: balancedConfiguration, scope: "test-scope", at: now,
            policy: PlannerPolicy(minimumSamples: 10))
        expect(!stricterSummary.discourages && stricterSummary.tokenEstimate == nil,
               "Configured sample minimum was ignored by a fixed five-report feedback rule")
        var reworkedReports = tokenReports
        for index in reworkedReports.indices { reworkedReports[index].manualRework = true }
        expect(reportSummary(reworkedReports).completionTokens == nil,
               "Unmeasured manual rework was silently assigned zero completion cost")
        var oldReports = tokenReports
        for index in oldReports.indices {
            oldReports[index].createdAt = now.addingTimeInterval(-91 * 86_400 - 60)
            oldReports[index].startedAt = now.addingTimeInterval(-91 * 86_400 - 30)
            oldReports[index].completedAt = now.addingTimeInterval(-91 * 86_400)
        }
        expect(reportSummary(oldReports).evaluated == 0,
               "Obsolete feedback bypassed the versioned evidence-age policy")
        let healthyModel = model("fixture-known-healthy", role: .balanced, defaultModel: true)
        let untestedModel = model("fixture-untested", role: .balanced)
        var healthyRecords = tokenReports
        for index in healthyRecords.indices {
            healthyRecords[index].configuration = PlannerConfiguration(model: healthyModel, effort: "medium")
        }
        let mixedEvidence = advice(feature, .efficiency, quota, [healthyModel, untestedModel], healthyRecords)
        expect(mixedEvidence.recommended?.model.id == healthyModel.id
               && mixedEvidence.evaluations.filter { $0.configuration.model.id == untestedModel.id }.allSatisfy {
                   $0.adverseBurden == nil && $0.completionTokens == nil
               }, "Missing feedback was rewarded as a zero-failure or free-resource advantage")

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
        print("Planner gate passed: bilingual task analysis, guarded ranking and fallback, qualitative confidence, validated quota states, comparable token ranges, feedback isolation, attribution, overrides, persistence and schema protection.")
    }
}

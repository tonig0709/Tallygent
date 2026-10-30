import Foundation

/// Synthetic policy-contract comparison, not a model-quality or subscription-cost benchmark.
/// All model names, tasks and quota snapshots below are fixtures; no inference is performed.
@main
struct PlannerBenchmark {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private struct TaskFixture {
        let id: String
        let text: String
        let minimumEffort: Int
        let minimumRole: Int
        let incomplete: Bool
    }

    private struct StateFixture {
        let id: String
        var quota: PlannerQuota
        var models: [PlannerModel]
        var unknown: Bool = false
        var exhausted: Bool = false
    }

    private struct Selection {
        var configuration: PlannerConfiguration?
        var alternatives: [PlannerConfiguration] = []
        var decision: String
        var wait: Bool
        var lowConfidence: Bool
        var explanation: Bool
    }

    private static func model(_ id: String, role: PlannerModelRole, isDefault: Bool = false) -> PlannerModel {
        PlannerModel(provider: .codex, identifier: id, name: id, detail: "synthetic declared role, not a measured capability",
                     efforts: ["low", "medium", "high"], defaultEffort: "medium", isDefault: isDefault,
                     role: role, source: "synthetic benchmark fixture", discoveredAt: now, manuallyConfigured: false)
    }

    private static let tasks: [TaskFixture] = [
        .init(id: "formatting-en", text: "Apply code formatting to one file; verify the formatter produces no diff.", minimumEffort: 2, minimumRole: 0, incomplete: false),
        .init(id: "isolated-bug-en", text: "Fix a small isolated bug in one function with an existing failing unit test.", minimumEffort: 2, minimumRole: 0, incomplete: false),
        .init(id: "multi-file-feature-zh", text: "实现跨模块多文件功能，连接前端与后端服务，补充集成测试。", minimumEffort: 4, minimumRole: 2, incomplete: false),
        .init(id: "architecture-en", text: "Design a repository-wide architecture refactor across multiple services and dependencies.", minimumEffort: 4, minimumRole: 2, incomplete: false),
        .init(id: "ambiguous-debug-zh", text: "排查无法复现的偶发崩溃，根因未知，涉及并发。", minimumEffort: 4, minimumRole: 2, incomplete: false),
        .init(id: "security-en", text: "Fix authentication and payment authorization; verify security regressions.", minimumEffort: 4, minimumRole: 2, incomplete: false),
        .init(id: "long-context-en", text: "Analyze a large codebase with long context across multiple components before proposing changes.", minimumEffort: 4, minimumRole: 2, incomplete: false),
        .init(id: "underspecified-zh", text: "改一下。", minimumEffort: 2, minimumRole: 0, incomplete: true),
        .init(id: "isolated-feature-zh", text: "在单个设置页面增加一个选项，复用现有接口，验收为保存后可以恢复。", minimumEffort: 3, minimumRole: 1, incomplete: false)
    ]

    private static func roleOrdinal(_ role: PlannerModelRole) -> Int {
        switch role { case .efficient: 0; case .balanced: 1; case .quality: 2; case .unknown: -1 }
    }

    private static func decisionName(_ value: PlannerDecision) -> String {
        switch value {
        case .configuration: "configuration"
        case .wait: "wait"
        case .needsInformation: "needsInformation"
        case .unavailable: "unavailable"
        }
    }

    private static func states() -> [StateFixture] {
        let models = [model("fixture-efficient", role: .efficient),
                      model("fixture-balanced", role: .balanced, isDefault: true),
                      model("fixture-quality", role: .quality)]
        let quota = PlannerQuota(provider: .codex, scope: "benchmark-scope", source: "synthetic snapshot", receivedAt: now,
                                 windows: [.init(id: "fiveHour", title: "5h", remainingPercent: 90, resetsAt: now.addingTimeInterval(10_800), durationMinutes: 300),
                                           .init(id: "weekly", title: "Week", remainingPercent: 70, resetsAt: now.addingTimeInterval(259_200), durationMinutes: 10_080)], connected: true)
        let ample = StateFixture(id: "ample-no-history", quota: quota, models: models)
        func changed(_ id: String, _ edit: (inout StateFixture) -> Void) -> StateFixture {
            var state = StateFixture(id: id, quota: ample.quota, models: ample.models)
            edit(&state)
            return state
        }
        return [ample,
                changed("short-window-empty") { $0.quota.windows[0].remainingPercent = 0; $0.exhausted = true },
                changed("weekly-window-empty") { $0.quota.windows[1].remainingPercent = 0; $0.exhausted = true },
                changed("short-window-reserve") { $0.quota.windows[0].remainingPercent = 8 },
                changed("weekly-window-reserve") { $0.quota.windows[1].remainingPercent = 8 },
                changed("reset-approaching") { $0.quota.windows[0].remainingPercent = 80; $0.quota.windows[0].resetsAt = now.addingTimeInterval(60) },
                changed("stale") { $0.quota.receivedAt = now.addingTimeInterval(-600); $0.unknown = true },
                changed("unknown-quota") { $0.quota.windows = []; $0.unknown = true },
                changed("expired-reset") { $0.quota.windows[0].resetsAt = now; $0.unknown = true },
                changed("partial-window") { $0.quota.windows.removeFirst(); $0.unknown = true },
                changed("missing-reset") { $0.quota.windows[0].resetsAt = nil; $0.unknown = true },
                changed("no-quality-role") { $0.models.removeLast() },
                changed("unsupported-efforts") {
                    $0.models = $0.models.map { model in var value = model; value.efforts = ["low"]; value.defaultEffort = "low"; return value }
                },
                changed("no-valid-candidate") { $0.models = [] }]
    }

    private static func engine(_ task: TaskFixture, _ preference: PlannerPreference, _ state: StateFixture,
                               reversed: Bool = false) -> Selection {
        let result = PlannerEngine.advise(task: task.text, preference: preference,
                                          models: reversed ? Array(state.models.reversed()) : state.models,
                                          quota: state.quota, reserve: 10, records: [], at: now)
        return Selection(configuration: result.recommended, alternatives: result.alternatives,
                         decision: decisionName(result.decision), wait: result.shouldWait,
                         lowConfidence: result.confidence == .low, explanation: !result.reasons.isEmpty)
    }

    private static func baseline(_ strategy: String, _ task: TaskFixture, _ state: StateFixture) -> Selection {
        let available = PlannerModel.merged(live: state.models, manual: nil, provider: state.quota.provider, at: now)
        let candidates = available.flatMap { model in
            model.efforts.filter { PlannerModel.effortRank($0) < 99 }.map { PlannerConfiguration(model: model, effort: $0) }
        }
        let chosen: PlannerConfiguration?
        switch strategy {
        case "always-strong":
            chosen = candidates.sorted {
                let left = [roleOrdinal($0.model.role), PlannerModel.effortRank($0.effort)]
                let right = [roleOrdinal($1.model.role), PlannerModel.effortRank($1.effort)]
                return left == right ? $0.id < $1.id : right.lexicographicallyPrecedes(left)
            }.first
        case "nominal-cheapest-compatible":
            chosen = candidates.sorted {
                let left = [roleOrdinal($0.model.role), PlannerModel.effortRank($0.effort)]
                let right = [roleOrdinal($1.model.role), PlannerModel.effortRank($1.effort)]
                return left == right ? $0.id < $1.id : left.lexicographicallyPrecedes(right)
            }.first
        default:
            // A fixed baseline, independent of the current task classifier: default model,
            // fixture minimum effort (or its next supported level), stable ID tie-break.
            chosen = candidates.filter { PlannerModel.effortRank($0.effort) >= task.minimumEffort }.sorted {
                let left = [$0.model.isDefault ? 0 : 1, PlannerModel.effortRank($0.effort)]
                let right = [$1.model.isDefault ? 0 : 1, PlannerModel.effortRank($1.effort)]
                return left == right ? $0.id < $1.id : left.lexicographicallyPrecedes(right)
            }.first
        }
        let quota = state.quota.assessment(reserve: 10, at: now)
        return Selection(configuration: chosen,
                         decision: chosen == nil ? "unavailable" : (quota.status == .wait ? "wait" : (quota.status == .unknown || task.incomplete ? "needsInformation" : "configuration")),
                         wait: quota.status == .wait, lowConfidence: state.unknown || task.incomplete,
                         explanation: true)
    }

    private static func signature(_ value: Selection) -> [String] {
        [value.configuration?.id ?? "none", value.decision, String(value.wait), String(value.lowConfidence)] + value.alternatives.map(\.id)
    }

    static func main() throws {
        let strategies = ["engine", "always-strong", "nominal-cheapest-compatible", "static-default-heuristic"]
        var rows: [[String: Any]] = []
        var summaries: [[String: Any]] = []
        for strategy in strategies {
            var counts = ["cases": 0, "recommendations": 0, "conditionalQualityMismatches": 0,
                          "unqualifiedQualityFloorViolations": 0, "catalogViolations": 0,
                          "exhaustionViolations": 0, "uncertaintyViolations": 0,
                          "inconsistentRankings": 0, "missingExplanations": 0]
            var seconds = 0.0
            for task in tasks {
                for preference in PlannerPreference.allCases {
                    for state in states() {
                        let start = ProcessInfo.processInfo.systemUptime
                        let selected = strategy == "engine" ? engine(task, preference, state) : baseline(strategy, task, state)
                        seconds += ProcessInfo.processInfo.systemUptime - start
                        let again = strategy == "engine" ? engine(task, preference, state, reversed: true) : baseline(strategy, task, state)
                        counts["cases"]! += 1
                        let configuration = selected.configuration
                        let qualityMismatch = configuration.map { roleOrdinal($0.model.role) < task.minimumRole || PlannerModel.effortRank($0.effort) < task.minimumEffort } ?? false
                        if configuration != nil { counts["recommendations"]! += 1 }
                        if qualityMismatch {
                            counts[selected.decision == "configuration" ? "unqualifiedQualityFloorViolations" : "conditionalQualityMismatches"]! += 1
                        }
                        let catalog = PlannerModel.merged(live: state.models, manual: nil, provider: state.quota.provider, at: now)
                        let all = [configuration].compactMap { $0 } + selected.alternatives
                        let catalogViolation = all.contains { configuration in
                            !configuration.isValid || !catalog.contains { $0.id == configuration.model.id && $0.efforts.contains(configuration.effort) }
                        }
                        let exhaustionViolation = state.exhausted && !selected.wait
                        let uncertaintyViolation = (state.unknown || task.incomplete) && configuration != nil
                            && (!selected.lowConfidence || selected.decision == "configuration")
                        let inconsistent = signature(selected) != signature(again)
                        if catalogViolation { counts["catalogViolations"]! += 1 }
                        if exhaustionViolation { counts["exhaustionViolations"]! += 1 }
                        if uncertaintyViolation { counts["uncertaintyViolations"]! += 1 }
                        if inconsistent { counts["inconsistentRankings"]! += 1 }
                        if !selected.explanation { counts["missingExplanations"]! += 1 }
                        rows.append(["task": task.id, "state": state.id, "preference": preference.rawValue,
                                     "strategy": strategy, "configuration": configuration?.id as Any? ?? NSNull(),
                                     "alternatives": selected.alternatives.map(\.id), "decision": selected.decision,
                                     "wait": selected.wait, "lowConfidence": selected.lowConfidence,
                                     "ordinalQualityMismatch": qualityMismatch,
                                     "declaredRole": configuration?.model.role.rawValue as Any? ?? NSNull(),
                                     "effortOrdinal": configuration.map { PlannerModel.effortRank($0.effort) } as Any? ?? NSNull(),
                                     "estimatedSubscriptionCost": NSNull(), "estimatedTaskSuccessProbability": NSNull()])
                    }
                }
            }
            precondition(counts["catalogViolations"] == 0 && counts["inconsistentRankings"] == 0,
                         "Synthetic routing benchmark exposed a catalog or determinism violation")
            if strategy == "engine" && CommandLine.arguments.contains("--enforce-policy") {
                precondition(["unqualifiedQualityFloorViolations", "exhaustionViolations", "uncertaintyViolations", "missingExplanations"]
                    .allSatisfy { counts[$0] == 0 }, "Upgraded Planner policy contract regressed")
            }
            summaries.append(["strategy": strategy, "counts": counts,
                              "elapsedSeconds": seconds, "meanDecisionMilliseconds": seconds * 1_000 / Double(counts["cases"]!)])
        }
        let report: [String: Any] = [
            "schemaVersion": 1, "evaluation": "deterministic synthetic policy-contract fixtures; NOT real model success, latency or quota savings",
            "fixtureCount": tasks.count * states().count * PlannerPreference.allCases.count,
            "qualityPolicy": "Hand-authored ordinal role/effort floors per fixture, not measured model capability. Conditional mismatches are reported separately from unqualified run advice.",
            "costPolicy": "No verified per-model subscription price, isolated task consumption or success probability is available. Cost and success fields remain null. Nominal-cheapest is only a declared-role then effort ordinal baseline; no units are combined.",
            "runtimePolicy": "Wall-clock duration of local decision code, not model execution latency; informational and host-dependent.",
            "summaries": summaries, "cases": rows
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if CommandLine.arguments.count > 1 {
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
            print("Synthetic Planner comparison: \(tasks.count * states().count * PlannerPreference.allCases.count) fixtures × \(strategies.count) policies. JSON: \(CommandLine.arguments[1])")
            for summary in summaries { print(try String(data: JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]), encoding: .utf8)!) }
        } else { print(String(decoding: data, as: UTF8.self)) }
    }
}

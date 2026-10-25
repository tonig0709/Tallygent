import Foundation

public struct UsageHistoryPoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let remainingPercent: Int
    /// Different segments must not be joined by a chart line.
    public let segmentID: String
}

public struct UsageDepletionEstimate: Equatable, Sendable {
    public let earliest: Date
    public let latest: Date
    public let lowerRatePerHour: Double
    public let upperRatePerHour: Double
    public let assumptions: [String]
}

public struct UsageWindowInsight: Identifiable, Equatable, Sendable {
    public var id: String { "\(provider.rawValue):\(windowID)" }
    public let provider: AgentService
    public let windowID: String
    public let latest: QuotaObservation?
    public let currentRemainingPercent: Int?
    public let isFresh: Bool
    public let sampleCount: Int
    public let segmentSamples: Int
    public let observedSpan: TimeInterval
    public let ratePerHour: Double?
    public let forecast: UsageDepletionEstimate?
    public let unavailableReason: String?
    public let history: [UsageHistoryPoint]

    public var title: String { windowID == "fiveHour" ? "5h 额度" : "周额度" }
    public var scopeLabel: String {
        guard let latest else { return "尚无来源记录" }
        if latest.accountScope != nil { return "按账户隔离" }
        return latest.sessionScope != nil ? "仅此会话；账户范围未核实" : "身份范围未知"
    }
}

public struct UsageResetEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let provider: AgentService
    public let windowID: String
    public let resetsAt: Date
    public let source: ObservationSource
    public let receivedAt: Date
    public let isFresh: Bool
    public var title: String { windowID == "fiveHour" ? "5h 额度" : "周额度" }
}

public struct UsageBacktestSummary: Equatable, Sendable {
    public let attemptedCount: Int
    public let evaluatedCount: Int
    public var unavailableCount: Int { attemptedCount - evaluatedCount }
    public let meanAbsoluteErrorPercentagePoints: Double?
    public let baselineMeanAbsoluteErrorPercentagePoints: Double?
    public let horizonMinutes: Int
    public let explanation: String
}

public struct UsageInsightsReport: Equatable, Sendable {
    public let generatedAt: Date
    public let windows: [UsageWindowInsight]
    public let resetTimeline: [UsageResetEvent]
    public let backtest: UsageBacktestSummary
    public let pacingExplanation: String
}

/// Account-wide percentage observations are not task costs or token balances.
public enum UsageInsights {
    public static func freshnessInterval(for provider: AgentService) -> TimeInterval {
        provider == .codex ? 120 : 300
    }

    public static func analyze(observations: [QuotaObservation], now: Date = .now) -> UsageInsightsReport {
        let rows = normalized(observations, at: now)
        let windows = AgentService.allCases.flatMap { provider in
            ["fiveHour", "weekly"].map { window in
                insight(rows: rows.filter { $0.provider == provider && $0.windowID == window },
                        provider: provider, windowID: window, now: now)
            }
        }
        let resets = windows.compactMap { window -> UsageResetEvent? in
            guard let row = window.latest, row.validity == .valid,
                  let reset = row.resetsAt, reset > now else { return nil }
            return UsageResetEvent(id: cycleKey(row), provider: row.provider, windowID: row.windowID,
                                   resetsAt: reset, source: row.source, receivedAt: row.receivedAt,
                                   isFresh: window.isFresh)
        }.sorted { $0.resetsAt < $1.resetsAt }
        return UsageInsightsReport(generatedAt: now, windows: windows, resetTimeline: resets,
                                   backtest: backtest(rows: rows),
                                   pacingExplanation: "来源没有确认固定周期或滚动恢复语义，暂不绘制理想消耗线；5h 与周额度分别约束，不合计成总余额。")
    }

    static func contextKey(_ row: QuotaObservation) -> String {
        "\(row.provider.rawValue)|\(row.accountScope ?? "unknown-account")|\(row.sessionScope ?? "unknown-session")"
    }

    static func seriesKey(_ row: QuotaObservation) -> String {
        "\(contextKey(row))|\(row.source.rawValue)|\(row.windowID)"
    }

    static func cycleKey(_ row: QuotaObservation) -> String {
        "\(seriesKey(row))|\(row.resetsAt?.timeIntervalSince1970.description ?? "unknown-reset")"
    }

    private static func normalized(_ input: [QuotaObservation], at now: Date) -> [QuotaObservation] {
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        var seen = Set<String>()
        return input.filter { row in
            row.schemaVersion == 1 && row.receivedAt >= cutoff && row.receivedAt <= now &&
            row.receivedAt.timeIntervalSince1970.isFinite &&
            ["fiveHour", "weekly"].contains(row.windowID) &&
            (row.usedPercent.map { (0...100).contains($0) } ?? true) &&
            (row.durationMinutes.map { $0 > 0 } ?? true) &&
            (row.resetsAt.map { $0.timeIntervalSince1970.isFinite } ?? true) && seen.insert(row.id).inserted
        }.sorted {
            $0.receivedAt == $1.receivedAt ? $0.id < $1.id : $0.receivedAt < $1.receivedAt
        }
    }

    private static func isValid(_ row: QuotaObservation) -> Bool {
        row.validity == .valid && row.usedPercent != nil
    }

    private static func joins(_ previous: QuotaObservation, _ current: QuotaObservation) -> Bool {
        let gap = current.receivedAt.timeIntervalSince(previous.receivedAt)
        return isValid(previous) && isValid(current) &&
            (current.accountScope != nil || current.sessionScope != nil) &&
            seriesKey(previous) == seriesKey(current) && previous.durationMinutes == current.durationMinutes &&
            previous.quotaPool == current.quotaPool && previous.resetsAt == current.resetsAt &&
            gap > 0 && gap <= (current.provider == .codex ? 300 : 900) &&
            (previous.resetsAt.map { $0 > current.receivedAt } ?? true) &&
            current.usedPercent! >= previous.usedPercent!
    }

    private static func insight(rows: [QuotaObservation], provider: AgentService, windowID: String,
                                now: Date) -> UsageWindowInsight {
        guard let latest = rows.last else {
            return UsageWindowInsight(provider: provider, windowID: windowID, latest: nil,
                currentRemainingPercent: nil, isFresh: false, sampleCount: 0, segmentSamples: 0,
                observedSpan: 0, ratePerHour: nil, forecast: nil,
                unavailableReason: "尚无真实额度观测；历史从启用采集后开始积累。", history: [])
        }
        // Never display an old account as a continuation of the currently observed one.
        let context = Array(rows.reversed().prefix { contextKey($0) == contextKey(latest) }.reversed())
        var history: [UsageHistoryPoint] = []
        var segment: [QuotaObservation] = []
        var previous: QuotaObservation?
        for row in context {
            guard isValid(row) else { previous = nil; segment = []; continue }
            if previous.map({ !joins($0, row) }) ?? true { segment = [] }
            segment.append(row)
            history.append(UsageHistoryPoint(id: row.id, date: row.receivedAt,
                remainingPercent: 100 - row.usedPercent!, segmentID: segment[0].id))
            previous = row
        }
        let valid = isValid(latest)
        let expired = latest.resetsAt.map { $0 <= now } ?? false
        let fresh = valid && !expired && now.timeIntervalSince(latest.receivedAt) <= freshnessInterval(for: provider)
        let current = valid && !expired ? latest.usedPercent.map { 100 - $0 } : nil
        let recent = segment.filter { latest.receivedAt.timeIntervalSince($0.receivedAt) <= 3_600 }
        let span = recent.first.map { latest.receivedAt.timeIntervalSince($0.receivedAt) } ?? 0
        var reason: String?
        var rate: Double?
        var estimate: UsageDepletionEstimate?
        if !valid { reason = "来源此次未提供这个额度窗口，不沿用旧值作为新数据。" }
        else if expired { reason = "来源所报重置时间已到；等待新观测确认，不假设额度已恢复。" }
        else if !fresh { reason = "来源记录已陈旧，暂无法估计；Mac 时钟变化不代表额度刷新。" }
        else if latest.accountScope == nil && latest.sessionScope == nil {
            reason = "身份范围未知，无法安全合并多次观测来估计速度。"
        } else if latest.durationMinutes == nil || latest.resetsAt == nil {
            reason = "来源缺少周期长度或重置时间，暂无法确认额度窗口。"
        } else if recent.count < 4 || span < 300 {
            reason = "同一窗口至少需要 4 次连续观测、跨度 5 分钟；历史仍不足。"
        } else {
            let delta = latest.usedPercent! - recent[0].usedPercent!
            if delta < 3 {
                reason = "近期变化不足 3 个百分点；整数百分比的分辨率不足以可靠外推，不代表额度无限。"
            } else {
                let hours = span / 3_600
                rate = Double(delta) / hours
                let lower = Double(delta - 1) / hours
                let upper = Double(delta + 1) / hours
                let remaining = Double(100 - latest.usedPercent!)
                let earliest = latest.receivedAt.addingTimeInterval(remaining / upper * 3_600)
                let last = latest.receivedAt.addingTimeInterval(remaining / lower * 3_600)
                if remaining == 0 {
                    reason = "最新观测已到 0%；这是来源读数，不是未来耗尽预测。"
                } else if earliest <= now {
                    reason = "估算的最早耗尽时间已过去，请刷新来源确认当前额度。"
                } else if let reset = latest.resetsAt, last >= reset {
                    reason = "估算范围跨越下一重置，重置后的容量未知，因此不继续外推。"
                } else {
                    estimate = UsageDepletionEstimate(earliest: earliest, latest: last,
                        lowerRatePerHour: lower, upperRatePerHour: upper,
                        assumptions: [
                            "假设近期账户整体消耗速度保持不变；其他设备和任务会改变结果。",
                            "范围只反映整数百分比的 ±1 点端点误差，不是统计置信区间。",
                            "不跨重置、身份/来源变化或长时间缺测外推；不是任务成本或 Token 预测。"
                        ])
                }
            }
        }
        return UsageWindowInsight(provider: provider, windowID: windowID, latest: latest,
            currentRemainingPercent: current, isFresh: fresh, sampleCount: context.filter(isValid).count,
            segmentSamples: recent.count, observedSpan: span, ratePerHour: rate, forecast: estimate,
            unavailableReason: reason, history: history)
    }

    private static func backtest(rows: [QuotaObservation]) -> UsageBacktestSummary {
        var attempted = 0
        var errors: [Double] = []
        var baseline: [Double] = []
        for provider in AgentService.allCases {
            for windowID in ["fiveHour", "weekly"] {
                // ponytail: bounded replay, most recent 500 samples and 12 anchors per window.
                // A background historical evaluator is warranted only if this proves useful.
                let group = Array(rows.filter { $0.provider == provider && $0.windowID == windowID }.suffix(500))
                var anchors: [Int] = []
                var lastAnchor = Date.distantFuture
                for index in group.indices.reversed() where lastAnchor.timeIntervalSince(group[index].receivedAt) >= 300 {
                    anchors.append(index); lastAnchor = group[index].receivedAt
                    if anchors.count == 12 { break }
                }
                for index in anchors {
                    attempted += 1
                    let anchor = group[index]
                    // The model sees only the prefix, never the future target.
                    let training = insight(rows: Array(group.prefix(index + 1)), provider: provider,
                                           windowID: windowID, now: anchor.receivedAt)
                    guard training.forecast != nil, let rate = training.ratePerHour,
                          let used = anchor.usedPercent else { continue }
                    let targetTime = anchor.receivedAt.addingTimeInterval(300)
                    guard let targetIndex = group.indices.first(where: {
                        $0 > index && group[$0].receivedAt >= targetTime &&
                        group[$0].receivedAt.timeIntervalSince(targetTime) <= 60
                    }), let targetUsed = group[targetIndex].usedPercent else { continue }
                    guard (index + 1...targetIndex).allSatisfy({ joins(group[$0 - 1], group[$0]) }) else { continue }
                    let elapsed = group[targetIndex].receivedAt.timeIntervalSince(anchor.receivedAt)
                    let predicted = min(100, Double(used) + rate * elapsed / 3_600)
                    errors.append(abs(Double(targetUsed) - predicted))
                    baseline.append(abs(Double(targetUsed - used)))
                }
            }
        }
        return UsageBacktestSummary(attemptedCount: attempted, evaluatedCount: errors.count,
            meanAbsoluteErrorPercentagePoints: errors.isEmpty ? nil : errors.reduce(0, +) / Double(errors.count),
            baselineMeanAbsoluteErrorPercentagePoints: baseline.isEmpty ? nil : baseline.reduce(0, +) / Double(baseline.count),
            horizonMinutes: 5,
            explanation: "仅用历史前缀预测约 5 分钟后的账户百分比；与保持当前读数的基线比较。最近每窗口最多 12 个回放点；未满足条件的点计为不可估计。这不是耗尽时间准确率或置信概率。")
    }
}

public enum UsageAlertKind: String, Codable, Sendable { case lowQuota, expectedReset }

public struct UsageAlertEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: UsageAlertKind
    public let provider: AgentService
    public let windowID: String
    public let title: String
    public let body: String
}

/// Native notification delivery belongs to the app; this state only deduplicates decisions.
public struct UsageAlertState: Codable, Sendable {
    private struct Baseline: Codable, Sendable {
        let provider: AgentService
        let windowID: String
        let remaining: Int
        let receivedAt: Date
    }
    private struct Reset: Codable, Sendable {
        let provider: AgentService
        let windowID: String
        let date: Date
    }
    private var enabledSince: Date?
    private var baselines: [String: Baseline] = [:]
    private var resets: [String: Reset] = [:]
    private var delivered: [String: Date] = [:]

    public init() {}

    public mutating func evaluate(report: UsageInsightsReport, enabled: Bool,
                                 now: Date = .now) -> [UsageAlertEvent] {
        guard enabled else { enabledSince = nil; baselines = [:]; resets = [:]; return [] }
        let first = enabledSince == nil
        if first { enabledSince = now }
        var events: [UsageAlertEvent] = []
        delivered = delivered.filter { now.timeIntervalSince($0.value) <= 30 * 86_400 }
        // Account and cycle transitions establish new baselines, not threshold crossings.
        for window in report.windows {
            guard let row = window.latest else { continue }
            let series = UsageInsights.seriesKey(row)
            let cycle = UsageInsights.cycleKey(row)
            baselines = baselines.filter {
                $0.value.provider != row.provider || $0.value.windowID != row.windowID || $0.key == cycle
            }
            resets = resets.filter {
                $0.value.provider != row.provider || $0.value.windowID != row.windowID ||
                    ($0.key == series && row.validity == .valid && $0.value.date == row.resetsAt)
            }
        }
        for (key, reset) in resets where reset.date <= now {
            let eventID = "reset|\(key)|\(reset.date.timeIntervalSince1970)"
            if !first, now.timeIntervalSince(reset.date) <= 300, delivered[eventID] == nil {
                let windowTitle = reset.windowID == "fiveHour" ? "5h 额度" : "周额度"
                events.append(UsageAlertEvent(id: eventID, kind: .expectedReset, provider: reset.provider,
                    windowID: reset.windowID, title: "\(reset.provider.title) \(windowTitle)预计重置时间已到",
                    body: "来源此前预计此时重置；请查看新额度记录确认，不代表额度已经恢复。"))
                delivered[eventID] = now
            }
            resets.removeValue(forKey: key)
        }
        for window in report.windows {
            guard window.isFresh, let row = window.latest, let remaining = window.currentRemainingPercent,
                  row.accountScope != nil || row.sessionScope != nil,
                  row.receivedAt <= now,
                  now.timeIntervalSince(row.receivedAt) <= UsageInsights.freshnessInterval(for: row.provider)
            else { continue }
            let series = UsageInsights.seriesKey(row)
            let key = UsageInsights.cycleKey(row)
            if let reset = row.resetsAt, reset > now {
                resets[series] = Reset(provider: row.provider, windowID: row.windowID, date: reset)
            }
            if !first, row.receivedAt > enabledSince!, let old = baselines[key],
               row.receivedAt > old.receivedAt,
               row.receivedAt.timeIntervalSince(old.receivedAt) <= 1_800,
               old.remaining > 20, remaining <= 20 {
                let eventID = "low|\(UsageInsights.cycleKey(row))|\(row.id)"
                if delivered[eventID] == nil {
                    events.append(UsageAlertEvent(id: eventID, kind: .lowQuota, provider: row.provider,
                        windowID: row.windowID, title: "\(row.provider.title) \(window.title)偏低",
                        body: "最新来源读数剩余 \(remaining)%。5h 和周额度分别计算；不会自动执行或迁移任务。"))
                    delivered[eventID] = now
                }
            }
            baselines[key] = Baseline(provider: row.provider, windowID: row.windowID,
                                      remaining: remaining, receivedAt: row.receivedAt)
        }
        // A change of account/session must not retain an unbounded set of identities.
        if baselines.count > 16 { baselines = [:] }
        if resets.count > 16 { resets = [:] }
        if delivered.count > 256 {
            delivered = Dictionary(uniqueKeysWithValues: delivered.sorted { $0.value > $1.value }.prefix(256).map { ($0.key, $0.value) })
        }
        return events
    }
}

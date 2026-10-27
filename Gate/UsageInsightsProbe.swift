import Foundation

@main
enum UsageInsightsProbe {
    static let start = Date(timeIntervalSince1970: 1_780_000_000)
    static let scope = String(repeating: "a", count: 64)

    static func row(_ index: Int, used: Int? = nil, at date: Date? = nil,
                    provider: AgentService = .codex, window: String = "fiveHour",
                    account: String? = scope, session: String? = nil,
                    reset: Date? = start.addingTimeInterval(14_400), duration: Int? = 300,
                    validity: ObservationValidity = .valid) -> QuotaObservation {
        QuotaObservation(id: "r-\(UUID().uuidString)", eventID: "e-\(index)", provider: provider,
            accountScope: account, sessionScope: session, windowID: window,
            durationMinutes: duration, usedPercent: validity == .valid ? (used ?? 20 + index * 2) : nil,
            resetsAt: reset, source: provider == .codex ? .codexRateLimits : .claudeStatusLine,
            receivedAt: date ?? start.addingTimeInterval(Double(index) * 120), validity: validity,
            reason: validity == .unavailable ? "windowUnavailable" : nil)
    }

    static func five(_ rows: [QuotaObservation], at now: Date) -> UsageWindowInsight {
        UsageInsights.analyze(observations: rows, now: now).windows.first { $0.provider == .codex && $0.windowID == "fiveHour" }!
    }

    static func main() throws {
        let normal = (0...10).map { row($0) }
        let now = normal.last!.receivedAt
        let report = UsageInsights.analyze(observations: normal, now: now)
        let current = five(normal, at: now)
        precondition(report.windows.count == 4 && current.currentRemainingPercent == 60)
        precondition(current.isFresh && current.sampleCount == 11 && current.segmentSamples == 11)
        precondition(current.ratePerHour == 60 && current.forecast != nil)
        precondition(current.forecast!.earliest < current.forecast!.latest)
        precondition(current.forecast!.latest < normal.last!.resetsAt!)
        precondition(report.windows.filter { $0.latest == nil }.count == 3)
        precondition(report.resetTimeline.count == 1)
        precondition(report.pacingExplanation.contains("滚动"))

        let stale = five(normal, at: now.addingTimeInterval(121))
        precondition(!stale.isFresh && stale.forecast == nil && stale.unavailableReason!.contains("陈旧"))
        let expired = five(normal.map { row(0, used: $0.usedPercent, at: $0.receivedAt, reset: now) }, at: now)
        precondition(!expired.isFresh && expired.currentRemainingPercent == nil)

        let flat = (0...10).map { row($0, used: 20) }
        let flatInsight = five(flat, at: now)
        precondition(flatInsight.ratePerHour == nil && flatInsight.forecast == nil)
        precondition(flatInsight.unavailableReason!.contains("不代表额度无限"))
        precondition(five((0...10).map { row($0, used: $0 == 10 ? 21 : 20) }, at: now).forecast == nil)
        precondition(five(Array(normal.suffix(3)), at: now).forecast == nil)
        let unknown = (0...10).map { row($0, account: nil) }
        let unidentified = five(unknown, at: now)
        precondition(unidentified.forecast == nil && unidentified.segmentSamples == 1)
        precondition(Set(unidentified.history.map(\.segmentID)).count == unknown.count)
        precondition(five((0...10).map { row($0, reset: nil) }, at: now).forecast == nil)
        precondition(five((0...10).map { row($0, duration: nil) }, at: now).forecast == nil)

        let gap = row(12, used: 50, at: now.addingTimeInterval(600))
        let gapInsight = five(normal + [gap], at: gap.receivedAt)
        precondition(gapInsight.segmentSamples == 1 && gapInsight.forecast == nil)
        precondition(gapInsight.history.last!.segmentID != gapInsight.history[9].segmentID)
        let drop = row(11, used: 5)
        precondition(five(normal + [drop], at: drop.receivedAt).segmentSamples == 1)
        let changedReset = row(11, reset: start.addingTimeInterval(15_000))
        precondition(five(normal + [changedReset], at: changedReset.receivedAt).segmentSamples == 1)
        let changedAccount = row(11, account: String(repeating: "b", count: 64))
        let isolated = five(normal + [changedAccount], at: changedAccount.receivedAt)
        precondition(isolated.sampleCount == 1 && isolated.history.count == 1)
        let unavailable = row(11, validity: .unavailable)
        precondition(five(normal + [unavailable], at: unavailable.receivedAt).currentRemainingPercent == nil)
        let changedPool = QuotaObservation(provider: .codex, accountScope: scope, windowID: "fiveHour",
            durationMinutes: 300, usedPercent: 45, resetsAt: normal.last!.resetsAt,
            source: .codexRateLimits, receivedAt: now.addingTimeInterval(60), quotaPool: "new-pool")
        precondition(five(normal + [changedPool], at: changedPool.receivedAt).segmentSamples == 1)

        // Re-reading a cached ID is not another sample, but a fresh unchanged read is.
        precondition(five(normal + normal, at: now).sampleCount == normal.count)
        let unchanged = row(11, used: 40)
        precondition(five(normal + [unchanged], at: unchanged.receivedAt).sampleCount == 12)
        let future = row(30, used: 99)
        precondition(five(normal + [future], at: now) == current)
        let crossesReset = normal.map { row(0, used: $0.usedPercent, at: $0.receivedAt, reset: now.addingTimeInterval(900)) }
        precondition(five(crossesReset, at: now).forecast == nil)
        precondition(five(crossesReset, at: now).unavailableReason!.contains("跨越下一重置"))
        let nearEmpty = (0...10).map { row($0, used: 79 + $0 * 2) }
        precondition(five(nearEmpty, at: now.addingTimeInterval(70)).forecast == nil)
        precondition(five(nearEmpty, at: now.addingTimeInterval(70)).unavailableReason!.contains("时间已过去"))

        let claude = (0...10).map { row($0, provider: .claude, account: nil, session: scope) }
        let mixed = UsageInsights.analyze(observations: normal + claude, now: now.addingTimeInterval(200))
        precondition(mixed.windows.first { $0.provider == .claude && $0.windowID == "fiveHour" }!.isFresh)
        precondition(!mixed.windows.first { $0.provider == .codex && $0.windowID == "fiveHour" }!.isFresh)
        precondition(mixed.resetTimeline.count == 2)
        let parsed = ISO8601DateFormatter()
        precondition(parsed.date(from: "2026-06-01T08:00:00+08:00") == parsed.date(from: "2026-06-01T00:00:00Z"))

        let replay = UsageInsights.analyze(observations: (0...29).map { row($0) }, now: start.addingTimeInterval(29 * 120))
        precondition(replay.backtest.evaluatedCount > 0 && replay.backtest.unavailableCount > 0)
        precondition(replay.backtest.meanAbsoluteErrorPercentagePoints! < 0.001)
        precondition(replay.backtest.baselineMeanAbsoluteErrorPercentagePoints! > 0)

        func single(_ used: Int, at date: Date, account: String = scope,
                    reset: Date = start.addingTimeInterval(14_400)) -> UsageInsightsReport {
            UsageInsights.analyze(observations: [row(0, used: used, at: date, account: account, reset: reset)], now: date)
        }
        var alerts = UsageAlertState()
        precondition(alerts.evaluate(report: single(50, at: now), enabled: false, now: now).isEmpty)
        precondition(alerts.evaluate(report: single(50, at: now), enabled: true, now: now).isEmpty)
        let low = single(82, at: now.addingTimeInterval(60))
        let lowEvents = alerts.evaluate(report: low, enabled: true, now: low.generatedAt)
        precondition(lowEvents.count == 1 && lowEvents[0].kind == .lowQuota)
        precondition(alerts.evaluate(report: low, enabled: true, now: low.generatedAt).isEmpty)
        let resumed = single(60, at: now.addingTimeInterval(120))
        precondition(alerts.evaluate(report: resumed, enabled: true, now: resumed.generatedAt).isEmpty)
        let lowAgain = single(83, at: now.addingTimeInterval(180))
        precondition(alerts.evaluate(report: lowAgain, enabled: true, now: lowAgain.generatedAt).count == 1)
        let data = try JSONEncoder().encode(alerts)
        alerts = try JSONDecoder().decode(UsageAlertState.self, from: data)
        precondition(alerts.evaluate(report: lowAgain, enabled: true, now: lowAgain.generatedAt).isEmpty)
        let switched = single(95, at: now.addingTimeInterval(240), account: String(repeating: "b", count: 64))
        precondition(alerts.evaluate(report: switched, enabled: true, now: switched.generatedAt).isEmpty)
        precondition(alerts.evaluate(report: switched, enabled: false, now: switched.generatedAt).isEmpty)
        precondition(alerts.evaluate(report: switched, enabled: true, now: switched.generatedAt).isEmpty)

        var staleAlert = UsageAlertState()
        _ = staleAlert.evaluate(report: single(50, at: now), enabled: true, now: now)
        precondition(staleAlert.evaluate(report: low, enabled: true, now: now.addingTimeInterval(300)).isEmpty)
        var resetAlert = UsageAlertState()
        let resetAt = now.addingTimeInterval(30)
        let beforeReset = single(50, at: now, reset: resetAt)
        _ = resetAlert.evaluate(report: beforeReset, enabled: true, now: now)
        let afterReset = UsageInsights.analyze(observations: [beforeReset.windows[0].latest!], now: resetAt.addingTimeInterval(1))
        let resetEvents = resetAlert.evaluate(report: afterReset, enabled: true, now: afterReset.generatedAt)
        precondition(resetEvents.count == 1 && resetEvents[0].kind == .expectedReset)
        precondition(resetEvents[0].title.contains("5h 额度"), "reset reminder must identify its quota window")
        precondition(resetAlert.evaluate(report: afterReset, enabled: true, now: afterReset.generatedAt).isEmpty)
        var slept = UsageAlertState()
        _ = slept.evaluate(report: beforeReset, enabled: true, now: now)
        precondition(slept.evaluate(report: afterReset, enabled: true, now: resetAt.addingTimeInterval(301)).isEmpty)
        print("Insights regression passed: segmentation, freshness, integer resolution, replay, identity, reset and alert deduplication.")
    }
}

import Foundation

@main
enum PanelTrendProbe {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let account = String(repeating: "a", count: 64)
    static let otherAccount = String(repeating: "b", count: 64)
    static let session = String(repeating: "c", count: 64)

    static func row(_ id: String, seconds: TimeInterval = -30, used: Int = 20,
                    provider: AgentService = .codex, window: String = "fiveHour",
                    scope: String? = account, reset: Date? = now.addingTimeInterval(3_600),
                    unavailable: Bool = false) -> QuotaObservation {
        QuotaObservation(id: id, eventID: id, provider: provider,
            accountScope: provider == .codex ? scope : nil, sessionScope: provider == .claude ? scope : nil,
            windowID: window, durationMinutes: window == "fiveHour" ? 300 : 10_080,
            usedPercent: unavailable ? nil : used, resetsAt: reset,
            source: provider == .codex ? .codexRateLimits : .claudeStatusLine,
            receivedAt: now.addingTimeInterval(seconds), validity: unavailable ? .unavailable : .valid,
            reason: unavailable ? "windowUnavailable" : nil)
    }

    static func make(_ rows: [QuotaObservation], source: PanelChartSource = .quota24Hours,
                     provider: AgentService = .codex, scope: String? = account,
                     at date: Date = now) -> PanelTrendPresentation {
        PanelTrendPresentation.make(report: UsageInsights.analyze(observations: rows, now: date),
            provider: provider, scope: scope, source: source, style: .line, now: date)
    }

    static func point(_ id: String, date: Date, percent: Int = 80, segment: String = "segment") -> UsageHistoryPoint {
        UsageHistoryPoint(id: id, date: date, remainingPercent: percent, segmentID: segment)
    }

    @MainActor
    static func main() async throws {
        let suite = "dev.tallygent.panel-trend-probe." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        // Test-only disposable suite; cleanup never targets production preferences.
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("future-source", forKey: PanelChartSource.defaultsKey)
        defaults.set("future-style", forKey: PanelChartStyle.defaultsKey)
        precondition(PanelChartSource.stored(in: defaults) == .sevenDayTokens)
        precondition(PanelChartStyle.stored(in: defaults) == .bars)
        defaults.set("quota12Hours", forKey: PanelChartSource.defaultsKey)
        defaults.set("line", forKey: PanelChartStyle.defaultsKey)
        precondition(PanelChartSource.stored(in: defaults) == .quota12Hours && PanelChartStyle.stored(in: defaults) == .line)
        precondition(PanelChartSource.quota12Hours.hours == 12 && PanelChartSource.quota24Hours.hours == 24)
        precondition(PanelChartSource.sevenDayTokens.hours == nil)

        let bounds = [row("too-old", seconds: -24 * 3_600 - 1), row("at-24", seconds: -24 * 3_600),
                      row("at-12", seconds: -12 * 3_600), row("recent"), row("future", seconds: 1)]
        let day = make(bounds)
        let half = make(bounds, source: .quota12Hours)
        precondition(day.domain.duration == 24 * 3_600 && half.domain.duration == 12 * 3_600)
        precondition(day.series.count == 2 && day.series[0].observedCount == 3)
        precondition(half.series[0].observedCount == 2 && half.series[0].points.first!.id == "at-12")
        precondition(day.series[1].points.isEmpty && !day.isEmpty)
        precondition(day.series[0].currentRemainingPercent == 80 && day.series[0].isFresh)
        precondition(make(bounds, scope: nil).isEmpty && make(bounds, scope: "").isEmpty)
        precondition(make(bounds, scope: otherAccount).series.allSatisfy { $0.latest == nil && $0.points.isEmpty && $0.bars.isEmpty })

        // Do not prefilter A→B→A rows: only the final, contiguous A context may remain.
        let switches = [row("first-a", seconds: -180), row("b", seconds: -120, scope: otherAccount), row("again-a", seconds: -60)]
        precondition(make(switches).series[0].points.map(\.id) == ["again-a"])
        let mixed = bounds + [row("claude", provider: .claude, scope: session), row("week", provider: .claude, window: "weekly", scope: session)]
        let claude = make(mixed, provider: .claude, scope: session)
        precondition(claude.series.allSatisfy { $0.points.count == 1 && $0.latest?.provider == .claude })
        precondition(make(mixed, provider: .claude, scope: account).isEmpty)

        let split = [row("s1", seconds: -500), row("s2", seconds: -450, used: 21),
                     row("gap", seconds: -100, used: 30), row("drop", seconds: -50, used: 5),
                     row("missing", seconds: -40, unavailable: true), row("after-missing", seconds: -30, used: 7)]
        let splitPoints = make(split).series[0].points
        precondition(splitPoints.count == 5 && Set(splitPoints.map(\.segmentID)).count == 4)
        precondition(PanelTrendPresentation.isolatedSegmentIDs(in: splitPoints).count == 3)
        let changedReset = make([row("r1", seconds: -60), row("r2", reset: now.addingTimeInterval(7_200))])
        precondition(Set(changedReset.series[0].points.map(\.segmentID)).count == 2)
        let unavailable = make([row("valid", seconds: -60), row("unavailable", unavailable: true)])
        precondition(unavailable.series[0].points.count == 1 && unavailable.series[0].currentRemainingPercent == nil)
        precondition(!unavailable.series[0].isFresh)
        let stale = make([row("stale", seconds: -121)])
        precondition(!stale.series[0].isFresh && stale.series[0].points.count == 1)
        let expired = make([row("expired", reset: now)])
        precondition(!expired.series[0].isFresh && expired.series[0].currentRemainingPercent == nil)
        precondition(expired.series[0].points.count == 1, "An expired current quota must not erase valid historical observations")
        precondition(make([]).isEmpty)
        let absent = PanelTrendPresentation.make(report: nil, provider: .codex, scope: account, source: .quota24Hours, style: .bars, now: now)
        precondition(absent.isEmpty && absent.series.count == 2)

        let dense = (0..<5_000).map { index in
            point("p-\(index)", date: now.addingTimeInterval(Double(index) - 5_000),
                  segment: index == 2_500 ? "isolated" : (index < 2_500 ? "before" : "after"))
        }
        let sampled = PanelTrendPresentation.sampledPoints(dense, maximum: 12)
        precondition(sampled.count == 12 && sampled.first == dense.first && sampled.last == dense.last)
        precondition(sampled.contains { $0.segmentID == "isolated" })
        precondition(PanelTrendPresentation.isolatedSegmentIDs(in: sampled).contains("isolated"))
        precondition(PanelTrendPresentation.sampledPoints(dense, maximum: 0).isEmpty)
        precondition(PanelTrendPresentation.sampledPoints(dense, maximum: -1).isEmpty)
        precondition(PanelTrendPresentation.sampledPoints(dense, maximum: 1) == [dense.last!])
        precondition(PanelTrendPresentation.sampledPoints(dense, maximum: Int.max).count == 720)
        let isolated = dense.map { point($0.id, date: $0.date, segment: $0.id) }
        let isolatedSample = PanelTrendPresentation.sampledPoints(isolated)
        precondition(isolatedSample.count == 360 && PanelTrendPresentation.isolatedSegmentIDs(in: isolatedSample).count == 360)

        let iso = ISO8601DateFormatter()
        func date(_ value: String) -> Date { iso.date(from: value)! }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let hourlyDomain = DateInterval(start: date("2026-10-27T10:00:00Z"), end: date("2026-10-27T13:00:00Z"))
        let hourly = PanelTrendPresentation.hourlyBuckets([
            point("h1", date: date("2026-10-27T10:05:00Z"), percent: 88),
            point("h2", date: date("2026-10-27T10:55:00Z"), percent: 77),
            point("h3", date: date("2026-10-27T12:10:00Z"), percent: 60),
            point("h4", date: hourlyDomain.end, percent: 50)
        ], domain: hourlyDomain, calendar: utc)
        precondition(hourly.map(\.remainingPercent) == [77, 60], "An exact right-edge observation belongs to the new hour, not the previous hour")
        precondition(hourly[0].endDate <= hourly[1].startDate && hourly[1].endDate == hourlyDomain.end)
        precondition(hourly.allSatisfy { $0.startDate < $0.endDate && $0.date >= hourlyDomain.start && $0.date <= hourlyDomain.end })
        let boundaryReset = PanelTrendPresentation.hourlyBuckets([
            point("exhausted", date: date("2026-10-27T12:55:00Z"), percent: 0, segment: "old-cycle"),
            point("reset-at-13", date: hourlyDomain.end, percent: 100, segment: "new-cycle")
        ], domain: hourlyDomain, calendar: utc)
        precondition(boundaryReset.count == 1 && boundaryReset[0].remainingPercent == 0,
                     "A reset at the next hour cannot refill the previous hourly bar")
        var newYork = Calendar(identifier: .gregorian); newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let fallDomain = DateInterval(start: date("2026-11-01T04:00:00Z"), end: date("2026-11-01T09:00:00Z"))
        let fall = PanelTrendPresentation.hourlyBuckets([
            point("first-1am", date: date("2026-11-01T05:30:00Z")),
            point("second-1am", date: date("2026-11-01T06:30:00Z")),
            point("later", date: date("2026-11-01T08:30:00Z"))
        ], domain: fallDomain, calendar: newYork)
        precondition(fall.count == 3 && Set(fall.map(\.id)).count == 3, "Repeated DST clock hours must not collapse")

        // One existing Store/IO read serves the panel, independent of Insights' selected range.
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let database = root.appendingPathComponent("panel-observations.sqlite")
        let rows = [row("cache-old", seconds: -23 * 3_600), row("cache-middle", seconds: -90 * 60), row("cache-new")]
        try ObservationHistory.append(rows, at: database, now: now)
        final class Clock { var value = PanelTrendProbe.now }
        let clock = Clock()
        let store = InsightsStore(url: database, defaults: defaults, now: { clock.value })
        await store.reload(force: true)
        precondition(store.observations.count == 3 && store.panelReport.windows[0].history.count == 3)
        store.selectRange(.hour)
        await store.reload(force: true)
        precondition(store.observations.count == 1 && store.report.windows[0].history.count == 1)
        precondition(store.panelReport.windows[0].history.count == 3, "Insights 1h must not truncate the 24h panel cache")

        let saved = try Data(contentsOf: database)
        try Data("not a database".utf8).write(to: database)
        clock.value = now.addingTimeInterval(121)
        await store.reload(force: true)
        precondition(store.message != nil && store.panelReport.windows[0].isFresh == false)
        precondition(store.panelReport.windows[0].history.count == 3, "A failed read retains history but cannot claim a fresh source")
        try saved.write(to: database)
        await store.clear()
        precondition(store.observations.isEmpty && store.panelReport.windows.allSatisfy { $0.history.isEmpty })
        print("Panel trend regression passed: preferences, independent 12h/24h cache, live scope, gaps, reset, bounded samples, hourly remaining values and DST.")
    }
}

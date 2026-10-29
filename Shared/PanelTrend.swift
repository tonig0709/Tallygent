import Foundation

/// Shared native axis formats; source quota values are already in the 0...100 range.
enum UsageChartAxis {
    static let remainingPercent = FloatingPointFormatStyle<Double>.Percent()
        .scale(1).precision(.fractionLength(0))
    static let localTime = Date.FormatStyle().hour().minute()
    static let localDateTime = Date.FormatStyle().month(.twoDigits).day(.twoDigits).hour().minute()

    // Native tick labels at the two edges must extend inward, not outside the plot.
    static func labelAnchorX(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0.5 }
        return index == 0 ? 0 : (index == count - 1 ? 1 : 0.5)
    }
}

public enum PanelChartSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case sevenDayTokens, quota12Hours, quota24Hours
    public static let defaultsKey = "desktopPanelChartSource"
    public var id: Self { self }
    public var title: String {
        switch self {
        case .sevenDayTokens: L("近 7 天 Token")
        case .quota12Hours: L("过去 12 小时额度")
        case .quota24Hours: L("过去 24 小时额度")
        }
    }
    public var hours: Int? {
        switch self { case .sevenDayTokens: nil; case .quota12Hours: 12; case .quota24Hours: 24 }
    }
    public static func stored(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .sevenDayTokens
    }
}

public enum PanelChartStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case bars, line
    public static let defaultsKey = "desktopPanelChartStyle"
    public var id: Self { self }
    public var title: String { self == .bars ? L("柱状图") : L("折线图") }
    public static func stored(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .bars
    }
}

/// The last valid remaining-percentage observation in a clock hour, not hourly consumption.
public struct PanelTrendHour: Identifiable, Equatable, Sendable {
    public let id: String
    public let startDate: Date
    public let endDate: Date
    public let receivedAt: Date
    public let remainingPercent: Int
    public let segmentID: String
    public var date: Date { startDate.addingTimeInterval(endDate.timeIntervalSince(startDate) / 2) }
}

public struct PanelTrendSeries: Identifiable, Equatable, Sendable {
    public var id: String { windowID }
    public let windowID: String
    public let title: String
    public let points: [UsageHistoryPoint]
    public let bars: [PanelTrendHour]
    public let isFresh: Bool
    public let latest: QuotaObservation?
    public let currentRemainingPercent: Int?
    public let observedCount: Int
    public let message: String?
}

public struct PanelTrendPresentation: Equatable, Sendable {
    public let source: PanelChartSource
    public let style: PanelChartStyle
    public let domain: DateInterval
    public let series: [PanelTrendSeries]
    public var isEmpty: Bool { source.hours != nil && series.allSatisfy { $0.points.isEmpty } }
    public let message: String?

    public static func make(report: UsageInsightsReport?, provider: AgentService, scope: String?,
                            source: PanelChartSource, style: PanelChartStyle, now: Date = .now) -> Self {
        let date = now.timeIntervalSince1970.isFinite ? now : Date(timeIntervalSince1970: 0)
        let domain = DateInterval(start: date.addingTimeInterval(-Double(source.hours ?? 168) * 3_600), end: date)
        guard source.hours != nil else { return Self(source: source, style: style, domain: domain, series: [], message: nil) }
        let values = ["fiveHour", "weekly"].map { windowID -> PanelTrendSeries in
            let value = report?.windows.first { $0.provider == provider && $0.windowID == windowID }
            let title = windowID == "fiveHour" ? L("5h 额度") : L("周额度")
            func empty(_ message: String) -> PanelTrendSeries {
                PanelTrendSeries(windowID: windowID, title: title, points: [], bars: [], isFresh: false,
                                 latest: nil, currentRemainingPercent: nil, observedCount: 0, message: message)
            }
            guard let scope, !scope.isEmpty else { return empty(L("当前身份范围未知，暂无可核实历史")) }
            guard let value, let latest = value.latest,
                  (provider == .codex ? latest.accountScope : latest.sessionScope) == scope else {
                return empty(L("等待当前账户或会话的历史观测"))
            }
            guard latest.receivedAt <= date else { return empty(L("等待当前时间内的历史观测")) }
            // Analyze before matching the live scope: filtering raw A→B→A rows first would erase the switch boundary.
            let visible = value.history.filter {
                $0.date >= domain.start && $0.date <= date && $0.date.timeIntervalSince1970.isFinite &&
                (0...100).contains($0.remainingPercent)
            }
            let valid = latest.validity == .valid && latest.usedPercent.map { (0...100).contains($0) } == true
            let expired = latest.resetsAt.map { $0 <= date } ?? false
            let fresh = valid && !expired && date.timeIntervalSince(latest.receivedAt) <= UsageInsights.freshnessInterval(for: provider)
            let message: String?
            if visible.isEmpty { message = L("所选时段暂无有效观测") }
            else if !valid { message = L("当前窗口暂无数据；仅保留已收到的历史") }
            else if expired { message = L("重置时间已到，等待来源确认") }
            else if !fresh { message = L("历史记录较旧，等待新观测") }
            else { message = nil }
            return PanelTrendSeries(windowID: windowID, title: title, points: sampledPoints(visible),
                bars: hourlyBuckets(visible, domain: domain), isFresh: fresh, latest: latest,
                currentRemainingPercent: valid && !expired ? latest.usedPercent.map { 100 - $0 } : nil,
                observedCount: visible.count, message: message)
        }
        let message = values.allSatisfy { $0.points.isEmpty }
            ? L("历史从启用采集后积累；空白不代表 0%") : nil
        return Self(source: source, style: style, domain: domain, series: values, message: message)
    }

    /// Keep segment boundaries when possible; a hard display cap never changes analysis or connects different segments.
    public static func sampledPoints(_ values: [UsageHistoryPoint], maximum: Int = 360) -> [UsageHistoryPoint] {
        let limit = min(720, maximum)
        guard limit > 0 else { return [] }
        guard values.count > limit else { return values }
        if limit == 1 { return Array(values.suffix(1)) }
        func spaced(_ indices: [Int], count: Int) -> [Int] {
            guard count > 0 else { return [] }
            if count == 1 { return [indices[indices.count - 1]] }
            return (0..<count).map { indices[$0 * (indices.count - 1) / (count - 1)] }
        }
        let boundaries = values.indices.filter { index in
            index == 0 || index == values.count - 1 ||
            values[index - 1].segmentID != values[index].segmentID ||
            values[index + 1].segmentID != values[index].segmentID
        }
        if boundaries.count >= limit { return spaced(boundaries, count: limit).map { values[$0] } }
        var selected = Set(boundaries)
        let interior = values.indices.filter { !selected.contains($0) }
        selected.formUnion(spaced(interior, count: limit - selected.count))
        return selected.sorted().map { values[$0] }
    }

    /// Draw a PointMark for these sampled segments; a one-point LineMark otherwise has no visible stroke.
    public static func isolatedSegmentIDs(in points: [UsageHistoryPoint]) -> Set<String> {
        let counts = Dictionary(grouping: points, by: \.segmentID).mapValues(\.count)
        return Set(counts.filter { $0.value == 1 }.keys)
    }

    public static func hourlyBuckets(_ points: [UsageHistoryPoint], domain: DateInterval,
                                     calendar: Calendar = .current) -> [PanelTrendHour] {
        guard domain.duration > 0, domain.duration <= 24 * 3_600 else { return [] }
        var hours: [Date: PanelTrendHour] = [:]
        for point in points.sorted(by: { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }) {
            guard point.date >= domain.start, point.date <= domain.end,
                  point.date.timeIntervalSince1970.isFinite, (0...100).contains(point.remainingPercent) else { continue }
            // Clock hours are half-open: an exact 13:00 observation must not rewrite the 12:00 hour.
            guard let hour = calendar.dateInterval(of: .hour, for: point.date) else { continue }
            let start = max(hour.start, domain.start), end = min(hour.end, domain.end)
            guard start < end else { continue }
            hours[hour.start] = PanelTrendHour(id: String(hour.start.timeIntervalSinceReferenceDate),
                startDate: start, endDate: end, receivedAt: point.date,
                remainingPercent: point.remainingPercent, segmentID: point.segmentID)
        }
        return hours.sorted { $0.key < $1.key }.map(\.value)
    }
}

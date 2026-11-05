import Foundation

public struct QuotaCurvePoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let remainingPercent: Double
}

public struct QuotaCurveRun: Identifiable, Equatable, Sendable {
    public let id: String
    public let isEstimated: Bool
    public let points: [QuotaCurvePoint]
}

/// Display-only, shape-preserving local interpolation, not a quota forecast.
/// Exact at retained observations; no values outside their time/value bounds.
public enum QuotaCurve {
    public static func fit(_ points: [UsageHistoryPoint], maximumPoints: Int = 720) -> [QuotaCurveRun] {
        let budget = min(4_096, max(0, maximumPoints))
        guard budget > 0 else { return [] }
        var chains: [[UsageHistoryPoint]] = []
        var chain: [UsageHistoryPoint] = []
        func finish() {
            if !chain.isEmpty { chains.append(chain); chain = [] }
        }
        for point in points {
            guard point.date.timeIntervalSinceReferenceDate.isFinite,
                  (0...100).contains(point.remainingPercent) else { finish(); continue }
            if let last = chain.last {
                let interval = point.date.timeIntervalSince(last.date)
                let slope = Double(point.remainingPercent - last.remainingPercent) / interval
                let groupMatches: Bool
                if let group = last.curveGroupID, !group.isEmpty {
                    groupMatches = group == point.curveGroupID
                } else {
                    groupMatches = point.curveGroupID == nil && last.segmentID == point.segmentID
                }
                if !groupMatches || interval <= 0 || !interval.isFinite || !slope.isFinite ||
                    !point.date.timeIntervalSince(chain[0].date).isFinite ||
                    point.remainingPercent > last.remainingPercent { finish() }
            }
            // Remove only redundant flat knots with identical edge provenance.
            // A solid↔estimated transition always keeps both observed endpoints.
            while chain.count >= 2 {
                let a = chain[chain.count - 2], b = chain[chain.count - 1]
                let estimated = a.segmentID != b.segmentID
                guard a.remainingPercent == b.remainingPercent,
                      b.remainingPercent == point.remainingPercent,
                      estimated == (b.segmentID != point.segmentID),
                      estimated == (a.segmentID != point.segmentID) else { break }
                chain.removeLast()
            }
            chain.append(point)
        }
        finish()
        guard !chains.isEmpty else { return [] }
        if budget == 1, let point = chains.last?.last {
            let id = "curve:last:\(point.id)"
            return [QuotaCurveRun(id: id, isEstimated: false,
                points: [QuotaCurvePoint(id: id, date: point.date, remainingPercent: Double(point.remainingPercent))])]
        }

        // ponytail: a screen-sized display budget, never a change to raw history,
        // exports, rates or forecasts. Excess hard-disconnected chains stay separate.
        let chainIndices = spacedIndices(chains.count, count: max(1, budget / 2))
        let visible = chainIndices.map { chains[$0] }
        let base = visible.map { min(2, $0.count) }
        let spare = max(0, budget - base.reduce(0, +))
        let demand = zip(visible, base).map { $0.count - $1 }
        let totalDemand = demand.reduce(0, +)
        var cumulativeDemand = 0, allocated = 0
        var reduced: [(points: [UsageHistoryPoint], estimated: [Bool])] = []
        for index in visible.indices {
            let values = visible[index]
            cumulativeDemand += demand[index]
            let share = totalDemand == 0 ? 0 : Int(Double(spare) * Double(cumulativeDemand) / Double(totalDemand))
            let count = min(values.count, base[index] + share - allocated)
            allocated = share
            let selected = areaIndices(values, count: count)
            var gapPrefix = [0]
            for pair in zip(values, values.dropFirst()) {
                gapPrefix.append(gapPrefix.last! + (pair.0.segmentID != pair.1.segmentID ? 1 : 0))
            }
            let estimated = zip(selected, selected.dropFirst()).map { gapPrefix[$1] > gapPrefix[$0] }
            reduced.append((selected.map { values[$0] }, estimated))
        }
        let durationScale = max(1, reduced.map { $0.points.last!.date.timeIntervalSince($0.points.first!.date) }.max() ?? 1)
        let scaledDuration = reduced.reduce(0.0) { $0 + $1.points.last!.date.timeIntervalSince($1.points.first!.date) / durationScale }
        var result: [QuotaCurveRun] = []
        var remainingSamples = budget
        for (chainIndex, value) in reduced.enumerated() {
            let knots = value.points
            let prefix = "curve:\(chainIndices[chainIndex]):\(knots[0].id)"
            if knots.count == 1 {
                result.append(QuotaCurveRun(id: prefix, isEstimated: false,
                    points: [QuotaCurvePoint(id: prefix, date: knots[0].date,
                                              remainingPercent: Double(knots[0].remainingPercent))]))
                continue
            }
            let intervals = zip(knots, knots.dropFirst()).map { $1.date.timeIntervalSince($0.date) }
            let differences = zip(knots, knots.dropFirst()).map { Double($1.remainingPercent - $0.remainingPercent) }
            let secants = zip(differences, intervals).map(/)
            let tangents = slopes(intervals: intervals, secants: secants)
            var runPoints: [QuotaCurvePoint] = []
            var runEstimated = value.estimated[0]
            var runIndex = 0
            func append(_ interval: Int, fraction: Double, value: Double) {
                let date = fraction == 0 ? knots[interval].date : (fraction == 1 ? knots[interval + 1].date :
                    knots[interval].date.addingTimeInterval(intervals[interval] * fraction))
                if fraction > 0 && fraction < 1 &&
                    (date <= knots[interval].date || date >= knots[interval + 1].date || date <= runPoints.last!.date) { return }
                runPoints.append(QuotaCurvePoint(id: "\(prefix):\(interval):\(fraction)", date: date, remainingPercent: value))
            }
            func emit() {
                result.append(QuotaCurveRun(id: "\(prefix):\(runIndex)", isEstimated: runEstimated, points: runPoints))
                runPoints = []; runIndex += 1
            }
            for index in intervals.indices {
                if value.estimated[index] != runEstimated {
                    emit(); runEstimated = value.estimated[index]
                }
                let a = Double(knots[index].remainingPercent), b = Double(knots[index + 1].remainingPercent)
                if runPoints.isEmpty { append(index, fraction: 0, value: a) }
                let extra = scaledDuration > 0 ? min(remainingSamples, Int((Double(budget) * (intervals[index] / durationScale) / scaledDuration).rounded(.down))) : 0
                remainingSamples -= extra
                if extra > 0 {
                    for sample in 1...extra {
                        let t = Double(sample) / Double(extra + 1), t2 = t * t, t3 = t2 * t
                        let y = (2 * t3 - 3 * t2 + 1) * a + (t3 - 2 * t2 + t) * intervals[index] * tangents[index] +
                            (-2 * t3 + 3 * t2) * b + (t3 - t2) * intervals[index] * tangents[index + 1]
                        append(index, fraction: t, value: min(a, max(b, y)))
                    }
                }
                append(index, fraction: 1, value: b)
            }
            emit()
        }
        return result
    }

    private static func spacedIndices(_ count: Int, count limit: Int) -> [Int] {
        guard count > 0, limit > 0 else { return [] }
        if count <= limit { return Array(0..<count) }
        if limit == 1 { return [count - 1] }
        return (0..<limit).map { Int(Double($0) * Double(count - 1) / Double(limit - 1)) }
    }

    /// Largest-area buckets retain local knees better than uniform display thinning.
    /// Inspired by ECharts' LTTB sampler; this local implementation uses normalized
    /// actual receipt time (not row index), so irregular sampling keeps its geometry.
    private static func areaIndices(_ points: [UsageHistoryPoint], count limit: Int) -> [Int] {
        guard points.count > limit, limit > 2 else { return spacedIndices(points.count, count: limit) }
        let last = points.count - 1, origin = points[0].date
        let span = points[last].date.timeIntervalSince(origin)
        guard span.isFinite, span > 0 else { return spacedIndices(points.count, count: limit) }
        func coordinates(_ index: Int) -> (x: Double, y: Double) {
            (points[index].date.timeIntervalSince(origin) / span, Double(points[index].remainingPercent) / 100)
        }
        let width = Double(points.count - 2) / Double(limit - 2)
        var selected = [0], previous = 0
        for bucket in 0..<(limit - 2) {
            let start = 1 + Int(Double(bucket) * width)
            let end = min(last, 1 + Int(Double(bucket + 1) * width))
            let nextEnd = min(points.count, 1 + Int(Double(bucket + 2) * width))
            var averageX = 0.0, averageY = 0.0
            for index in end..<nextEnd {
                let value = coordinates(index)
                averageX += value.x; averageY += value.y
            }
            let count = Double(nextEnd - end)
            averageX /= count; averageY /= count
            let anchor = coordinates(previous)
            var winner = start, largest = -1.0
            for index in start..<end {
                let value = coordinates(index)
                let area = abs((value.x - anchor.x) * (averageY - anchor.y) -
                               (averageX - anchor.x) * (value.y - anchor.y))
                if area > largest { largest = area; winner = index }
            }
            selected.append(winner); previous = winner
        }
        selected.append(last)
        return selected
    }

    private static func slopes(intervals: [Double], secants: [Double]) -> [Double] {
        guard secants.count > 1 else { return [secants[0], secants[0]] }
        var values = [Double](repeating: 0, count: secants.count + 1)
        for index in 1..<secants.count {
            let a = secants[index - 1], b = secants[index]
            if a == 0 || b == 0 { continue }
            let scale = max(intervals[index - 1], intervals[index])
            let h0 = intervals[index - 1] / scale, h1 = intervals[index] / scale
            let w0 = h0 + 2 * h1, w1 = 2 * h0 + h1
            values[index] = (w0 + w1) / (w0 / a + w1 / b)
        }
        func endpoint(_ h0: Double, _ h1: Double, _ d0: Double, _ d1: Double) -> Double {
            let scale = max(h0, h1), a = h0 / scale, b = h1 / scale
            let value = ((2 * a + b) * d0 - a * d1) / (a + b)
            guard value.isFinite else { return d0 }
            return d0 == 0 || value >= 0 ? 0 : max(3 * d0, value)
        }
        values[0] = endpoint(intervals[0], intervals[1], secants[0], secants[1])
        let last = secants.count - 1
        values[last + 1] = endpoint(intervals[last], intervals[last - 1], secants[last], secants[last - 1])
        return values
    }
}

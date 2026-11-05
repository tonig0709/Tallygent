import Foundation

@main
enum QuotaCurveProbe {
    static let origin = Date(timeIntervalSinceReferenceDate: 0)
    static func point(_ seconds: Double, _ percent: Int, segment: String = "observed", group: String? = "confirmed-cycle") -> UsageHistoryPoint {
        .init(id: "\(seconds):\(percent):\(segment)", date: origin.addingTimeInterval(seconds),
              remainingPercent: percent, segmentID: segment, curveGroupID: group)
    }
    static func values(_ runs: [QuotaCurveRun]) -> [QuotaCurvePoint] { runs.flatMap(\.points) }
    static func descending(_ points: [QuotaCurvePoint]) -> Bool {
        zip(points, points.dropFirst()).allSatisfy { $1.remainingPercent <= $0.remainingPercent + 1e-9 }
    }
    static func main() {
        precondition(QuotaCurve.fit([]).isEmpty && QuotaCurve.fit([point(0, 80)], maximumPoints: 0).isEmpty)
        let singleton = QuotaCurve.fit([point(10, 80)])
        precondition(singleton.count == 1 && singleton[0].points.count == 1 && !singleton[0].isEstimated)
        let knots = [point(0, 100), point(1, 98), point(17, 95), point(30, 95), point(73, 20), point(100, 0)]
        let fitted = QuotaCurve.fit(knots)
        let plotted = values(fitted)
        precondition(fitted.count == 1 && !fitted[0].isEstimated && plotted.count > knots.count)
        precondition(descending(plotted) && plotted.allSatisfy { (0...100).contains($0.remainingPercent) })
        precondition(plotted.first!.date == knots.first!.date && plotted.last!.date == knots.last!.date)
        for knot in knots {
            precondition(plotted.contains { $0.date == knot.date && $0.remainingPercent == Double(knot.remainingPercent) }, "retained observation was not interpolated exactly")
        }
        let flat = QuotaCurve.fit((0..<100).map { point(Double($0), 80) })
        precondition(values(flat).allSatisfy { $0.remainingPercent == 80 })
        let gap = QuotaCurve.fit([point(0, 90, segment: "a"), point(5, 89, segment: "a"),
                                 point(3_600, 40, segment: "b"), point(3_605, 39, segment: "b")])
        precondition(gap.map(\.isEstimated) == [false, true, false])
        precondition(gap[0].points.last!.date == gap[1].points.first!.date && gap[1].points.last!.date == gap[2].points.first!.date)
        precondition(descending(values(gap)))
        let noAuthorization = QuotaCurve.fit([point(0, 90, segment: "a", group: nil), point(100, 80, segment: "b", group: nil)])
        precondition(noAuthorization.count == 2 && noAuthorization.allSatisfy { $0.points.count == 1 && !$0.isEstimated })
        let groups = QuotaCurve.fit([point(0, 90, group: "cycle1"), point(60, 80, group: "cycle2")])
        precondition(groups.count == 2)
        let reset = QuotaCurve.fit([point(0, 5), point(60, 100), point(120, 99)])
        precondition(reset.count == 2 && reset[0].points.count == 1 && descending(reset[1].points))
        for barrier in [point(30, -1), point(30, 101), point(.nan, 80)] {
            let runs = QuotaCurve.fit([point(0, 90), barrier, point(60, 80)])
            precondition(runs.count == 2 && runs.allSatisfy { $0.points.count == 1 })
        }
        for second in [0.0, -1] {
            let runs = QuotaCurve.fit([point(0, 90), point(second, 85), point(60, 80)])
            precondition(runs.count == 2 && runs[0].points.count == 1)
        }
        for input in [[point(0, 100), point(1e-200, 99), point(1e200, 20)],
                      [point(-1.7e308, 100), point(0, 90), point(1.7e308, 80)],
                      [point(0, 100), point(Double.leastNonzeroMagnitude, 90), point(1, 80)]] {
            let runs = QuotaCurve.fit(input)
            precondition(runs.allSatisfy { descending($0.points) })
            precondition(values(runs).allSatisfy {
                $0.date.timeIntervalSinceReferenceDate.isFinite && $0.remainingPercent.isFinite &&
                    (0...100).contains($0.remainingPercent) && $0.date >= input.first!.date && $0.date <= input.last!.date
            }, "extreme finite intervals escaped numeric/time bounds")
        }
        // At a low display budget uniform indices [0,2,5,8] miss the sharp knee.
        let times = [0.0, 1, 2, 3, 4, 100, 101, 102, 103]
        let levels = [100, 99, 98, 97, 40, 39, 38, 37, 0]
        let irregular = zip(times, levels).map { point($0, $1) }
        let area = values(QuotaCurve.fit(irregular, maximumPoints: 4))
        precondition(![0, 2, 5, 8].map { irregular[$0] }.contains(irregular[4]))
        precondition(area.contains { $0.date == irregular[4].date && $0.remainingPercent == 40 }, "area sampling discarded the sharp knee uniform thinning misses")
        precondition(area.first!.date == irregular.first!.date && area.last!.date == irregular.last!.date)
        let actualTime = values(QuotaCurve.fit(irregular, maximumPoints: 3))
        let regularTime = values(QuotaCurve.fit(levels.enumerated().map { point(Double($0), $1) }, maximumPoints: 3))
        precondition(actualTime.contains { $0.date == irregular[4].date && $0.remainingPercent == 40 } &&
                     regularTime.contains { $0.date == origin.addingTimeInterval(3) && $0.remainingPercent == 97 },
                     "area selection ignored actual receipt times")
        precondition(QuotaCurve.fit(irregular, maximumPoints: 4).allSatisfy { !$0.isEstimated }, "display thinning mislabeled uninterrupted observations as missing data")
        let skippedGap = (0..<100).map { point(Double($0), 100 - $0, segment: $0 < 20 || $0 >= 80 ? "a" : "b") }
        precondition(QuotaCurve.fit(skippedGap, maximumPoints: 3).contains( where: \.isEstimated),
                     "area thinning erased a skipped gap's estimated provenance")
        let enormous = [point(0, 100), point(1e-200, 99), point(1e200, 98), point(1e201, 90), point(1e202, 0)]
        precondition(values(QuotaCurve.fit(enormous, maximumPoints: 3)).allSatisfy {
            $0.date.timeIntervalSinceReferenceDate.isFinite && $0.remainingPercent.isFinite && (0...100).contains($0.remainingPercent)
        }, "normalized area selection escaped finite bounds")
        let alternating = (0..<20_000).map { index in point(Double(index), 80, segment: "s\(index / 2)") }
        let start = Date()
        let dense = QuotaCurve.fit(alternating)
        let denseValues = values(dense)
        precondition(denseValues.count <= 2 * 720 + dense.count, "native chart output exceeds its display budget")
        precondition(denseValues.allSatisfy { $0.remainingPercent == 80 } && denseValues.first!.date == alternating.first!.date && denseValues.last!.date == alternating.last!.date)
        precondition(Date().timeIntervalSince(start) < 3, "20k display fit is unexpectedly expensive")
        let isolated = QuotaCurve.fit((0..<20_000).map { point(Double($0), 80, group: "g\($0)") })
        precondition(isolated.count <= 360 && isolated.allSatisfy { $0.points.count == 1 })
        precondition(QuotaCurve.fit(knots, maximumPoints: Int.max).flatMap(\.points).count < 9_000)
        precondition(values(QuotaCurve.fit(knots, maximumPoints: 1)).count == 1)
        let bad = [QuotaCurvePoint(id: "a", date: origin, remainingPercent: 50),
                   QuotaCurvePoint(id: "b", date: origin.addingTimeInterval(1), remainingPercent: 51)]
        precondition(!descending(bad), "monotonicity negative control accepted a known-bad overshoot")
        print("Quota curve: PASS (exact retained knots, monotone bounds, time-aware area sampling, retained knees, plateaus, authorized estimated gaps, hard boundaries, invalid input, 20k bounded display and negative control)")
    }
}

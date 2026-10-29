import CodexQuotaCore
import Foundation
#if canImport(AppKit)
import AppKit
import SwiftUI
#endif

let rateData = Data(#"{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":28,"windowDurationMins":10080,"resetsAt":1800000000}}}}"#.utf8)
let rateLimits = try AppServerParser.rateLimitWindows(from: AppServerParser.object(from: rateData))
let weekly = rateLimits.weekly
precondition(rateLimits.fiveHour?.remainingPercent == 80)
precondition(rateLimits.fiveHour?.windowDurationMinutes == 300)
precondition(weekly?.remainingPercent == 72)
precondition(weekly?.windowDurationMinutes == 10_080)

let weeklyOnlyData = Data(#"{"id":3,"result":{"rateLimits":{"secondary":{"usedPercent":28,"windowDurationMins":10080}}}}"#.utf8)
let weeklyOnly = try AppServerParser.rateLimitWindows(from: AppServerParser.object(from: weeklyOnlyData))
precondition(weeklyOnly.fiveHour == nil)
precondition(weeklyOnly.weekly?.remainingPercent == 72)

func parseLimits(_ json: String) throws -> RateLimitWindows {
    try AppServerParser.rateLimitWindows(from: AppServerParser.object(from: Data(json.utf8)))
}
let fiveHourOnly = try parseLimits(#"{"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300}}}}"#)
precondition(fiveHourOnly.fiveHour?.remainingPercent == 80 && fiveHourOnly.weekly == nil,
             "A lone 5h window must not be mislabeled as weekly quota")
let reversed = try parseLimits(#"{"result":{"rateLimits":{"primary":{"usedPercent":28,"windowDurationMins":10080,"resetsAt":1800000000},"secondary":{"usedPercent":20,"windowDurationMins":300}}}}"#)
precondition(reversed == rateLimits, "Provider field order changed the recognized window types")
for json in [#"{"result":{"rateLimits":{}}}"#,
             #"{"result":{"rateLimits":{"primary":null,"secondary":null}}}"#,
             #"{"result":{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":60}}}}"#] {
    let absent = try parseLimits(json)
    precondition(absent.fiveHour == nil && absent.weekly == nil, "Missing or unknown windows invented quota")
}
for fields in [#""usedPercent":-1,"windowDurationMins":300"#,
               #""usedPercent":101,"windowDurationMins":300"#,
               #""usedPercent":true,"windowDurationMins":300"#,
               #""usedPercent":12.5,"windowDurationMins":300"#,
               #""usedPercent":"12","windowDurationMins":300"#,
               #""usedPercent":12,"windowDurationMins":true"#,
               #""usedPercent":12"#,
               #""usedPercent":12,"windowDurationMins":300,"resetsAt":-1"#,
               #""usedPercent":12,"windowDurationMins":300,"resetsAt":true"#,
               #""usedPercent":12,"windowDurationMins":300,"resetsAt":4102444801"#,
               #""usedPercent":12,"windowDurationMins":300,"resetsAt":1800000000.5"#] {
    do {
        _ = try parseLimits("{\"result\":{\"rateLimits\":{\"primary\":{\(fields)}}}}")
        preconditionFailure("Malformed normalized quota crossed the provider boundary")
    } catch is AppServerParserError { }
}
do {
    _ = try AppServerParser.weeklyWindow(from: AppServerParser.object(from: Data(#"{"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300}}}}"#.utf8)))
    preconditionFailure("Legacy weekly-only accessor invented a missing weekly window")
} catch AppServerParserError.missingRateLimits { }

let usageData = Data(#"{"id":4,"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-07-17","tokens":12500000}]}}"#.utf8)
let usage = try AppServerParser.dailyUsage(from: AppServerParser.object(from: usageData))
precondition(usage == [DailyUsage(startDate: "2026-07-17", tokens: 12_500_000)])

precondition(QuotaLevel(remainingPercent: 60) == .healthy)
precondition(QuotaLevel(remainingPercent: 30) == .warning)
precondition(QuotaLevel(remainingPercent: 29) == .critical)
precondition(WidgetGlassOpacity.clamped(0) == WidgetGlassOpacity.minimum)
precondition(WidgetGlassOpacity.clamped(2) == WidgetGlassOpacity.maximum)
precondition(WidgetGlassOpacity.clamped(0.7) == 0.7)
precondition(WidgetGlassOpacity.normalized(WidgetGlassOpacity.minimum) == 0)
precondition(WidgetGlassOpacity.normalized(WidgetGlassOpacity.maximum) == 1)
precondition(WidgetGlassOpacity.darkFilmOpacity(WidgetGlassOpacity.minimum) == 0.08)
precondition(WidgetGlassOpacity.darkFilmOpacity(WidgetGlassOpacity.maximum) == 0.94)
precondition(WidgetGlassOpacity.darkFilmOpacity(0.5) < WidgetGlassOpacity.darkFilmOpacity(0.86))
precondition(UsageSnapshot.placeholder.resolvedAppearance == .dark)
precondition(DesktopPanelMode.small.size == CGSize(width: 164, height: 164))
precondition(DesktopPanelMode.medium.size == CGSize(width: 344, height: 164))
precondition(DesktopPanelMode.large.size == CGSize(width: 680, height: 300))
precondition(DesktopPanelMode.small.size.height == DesktopPanelMode.medium.size.height)
let modeDefaults = UserDefaults(suiteName: "dev.codexquota.mode-check.\(UUID().uuidString)")!
precondition(DesktopPanelMode.stored(in: modeDefaults) == .large)
modeDefaults.set("invalid", forKey: DesktopPanelMode.defaultsKey)
precondition(DesktopPanelMode.stored(in: modeDefaults) == .large)
modeDefaults.removeObject(forKey: DesktopPanelMode.defaultsKey)
precondition(SnapshotHTTPClient.endpoint.absoluteString == "http://127.0.0.1:48193/snapshot")

let clearOptics = GlassOptics(blurAmount: 0, dispersion: 0)
let fullOptics = GlassOptics(blurAmount: 1, dispersion: 0.30)
precondition(clearOptics.dispersionStrength == 0 && clearOptics.edgeOffset == 0 && clearOptics.edgeOpacity == 0)
precondition(clearOptics.frostOpacity == 0 && fullOptics.frostOpacity == 0.45)
precondition(fullOptics.dispersionStrength == 1 && fullOptics.edgeOffset == 3 && fullOptics.edgeOpacity == 0.55)
precondition(fullOptics.edgeWidth == 2, "color separation must remain visible at full strength")
var previousOptics = clearOptics
for step in 1...10 {
    let amount = Double(step) / 10
    let optics = GlassOptics(blurAmount: amount, dispersion: amount * 0.30)
    precondition(optics.edgeOffset > previousOptics.edgeOffset && optics.edgeOpacity > previousOptics.edgeOpacity)
    precondition(optics.edgeWidth > previousOptics.edgeWidth && optics.frostOpacity > previousOptics.frostOpacity)
    previousOptics = optics
}
let invalidOptics = GlassOptics(blurAmount: .nan, dispersion: .infinity)
precondition(invalidOptics.frostOpacity == 0 && invalidOptics.dispersionStrength == 0)
precondition(GlassOptics(blurAmount: -1, dispersion: -1).edgeOpacity == 0)
precondition(GlassOptics(blurAmount: 2, dispersion: 2).frostOpacity == fullOptics.frostOpacity)

#if canImport(AppKit)
@MainActor
func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.frame(width: width, height: height))
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data)
    else { preconditionFailure("Widget render produced no image") }
    return bitmap
}

@MainActor
func changedPixels(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, in region: CGRect) -> Int {
    let xRange = max(0, Int(CGFloat(lhs.pixelsWide) * region.minX))..<min(lhs.pixelsWide, Int(CGFloat(lhs.pixelsWide) * region.maxX))
    let yRange = max(0, Int(CGFloat(lhs.pixelsHigh) * region.minY))..<min(lhs.pixelsHigh, Int(CGFloat(lhs.pixelsHigh) * region.maxY))
    var count = 0
    for y in yRange {
        for x in xRange {
            guard let left = lhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  let right = rhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
            else { continue }
            let difference = abs(left.redComponent - right.redComponent) +
                abs(left.greenComponent - right.greenComponent) +
                abs(left.blueComponent - right.blueComponent) +
                abs(left.alphaComponent - right.alphaComponent)
            if difference > 0.12 { count += 1 }
        }
    }
    return count
}

@MainActor
func contrastPixelCounts(_ bitmap: NSBitmapImageRep, in region: CGRect) -> (dark: Int, bright: Int, total: Int) {
    let xRange = max(0, Int(CGFloat(bitmap.pixelsWide) * region.minX))..<min(bitmap.pixelsWide, Int(CGFloat(bitmap.pixelsWide) * region.maxX))
    let yRange = max(0, Int(CGFloat(bitmap.pixelsHigh) * region.minY))..<min(bitmap.pixelsHigh, Int(CGFloat(bitmap.pixelsHigh) * region.maxY))
    var dark = 0
    var bright = 0
    var total = 0
    for y in yRange {
        for x in xRange {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.alphaComponent > 0.1
            else { continue }
            let luminance = color.redComponent * 0.2126 +
                color.greenComponent * 0.7152 +
                color.blueComponent * 0.0722
            total += 1
            if luminance < 0.6 { dark += 1 }
            if luminance > 0.6 { bright += 1 }
        }
    }
    return (dark, bright, total)
}

@MainActor
func hasReadableContrast(_ bitmap: NSBitmapImageRep, in region: CGRect) -> Bool {
    let counts = contrastPixelCounts(bitmap, in: region)
    let minorityFloor = max(8, counts.total / 1_000)
    return counts.total > 0 &&
        min(counts.dark, counts.bright) > minorityFloor &&
        max(counts.dark, counts.bright) > counts.total / 5
}

/// An optical highlight may illuminate the continuous rim, never paint an inset interior bar.
/// Inspect the production highlight alone: wallpaper/compositor blur and content are unrelated.
@MainActor
func hasConfinedRimHighlight(_ bitmap: NSBitmapImageRep, size: CGSize, cornerRadius: CGFloat) -> Bool {
    let bounds = CGRect(origin: .zero, size: size)
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let interior = shape.inset(by: 4).path(in: bounds)
    let antialiasedOutline = shape.inset(by: -1).path(in: bounds)
    var rimPixels = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.alphaComponent > 0.02 else { continue }
            let point = CGPoint(x: (CGFloat(x) + 0.5) * size.width / CGFloat(bitmap.pixelsWide),
                                y: (CGFloat(y) + 0.5) * size.height / CGFloat(bitmap.pixelsHigh))
            // Rounded-rectangle paths are symmetric, so bitmap vertical orientation does not matter.
            if interior.contains(point) || !antialiasedOutline.contains(point) { return false }
            rimPixels += 1
        }
    }
    return rimPixels > 8
}

@MainActor
@discardableResult
func checkRender<Content: View, Background: View>(
    _ content: Content,
    on background: Background,
    width: CGFloat,
    height: CGFloat,
    label: String,
    regions: [(String, CGRect)]
) -> NSBitmapImageRep {
    // Native Glass is resolved by the desktop compositor, not ImageRenderer.
    // This check covers content visibility and contrast only; the release
    // checklist owns the real wallpaper-transmission smoke test.
    let wallpaper = LinearGradient(
        colors: [Color(red: 0.18, green: 0.42, blue: 0.62), Color(red: 0.52, green: 0.24, blue: 0.18)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    let baseline = render(ZStack { wallpaper; background }, width: width, height: height)
    let rendered = render(ZStack { wallpaper; background; content }, width: width, height: height)

    var visiblePixels = 0
    for y in 0..<rendered.pixelsHigh {
        for x in 0..<rendered.pixelsWide {
            guard let color = rendered.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if color.alphaComponent > 0.1 { visiblePixels += 1 }
        }
    }

    let pixelCount = rendered.pixelsWide * rendered.pixelsHigh
    let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
    precondition(visiblePixels > pixelCount * 9 / 10, "\(label) is blank or transparent")
    precondition(changedPixels(rendered, baseline, in: fullFrame) > pixelCount / 300, "\(label) content is indistinguishable from its glass background")
    precondition(hasReadableContrast(rendered, in: fullFrame), "\(label) is a solid or all-black surface")
    precondition(changedPixels(baseline, baseline, in: fullFrame) == 0, "render difference detector has a false positive")
    for (name, region) in regions {
        let regionPixels = Int(CGFloat(pixelCount) * region.width * region.height)
        precondition(changedPixels(rendered, baseline, in: region) > regionPixels / 500, "\(label) lacks visible \(name) content")
        precondition(hasReadableContrast(rendered, in: region), "\(label) lacks readable \(name) contrast")
    }
    return rendered
}

@MainActor
func saveTrendPreview(_ bitmap: NSBitmapImageRep, name: String) {
    guard let output = ProcessInfo.processInfo.environment["TALLYGENT_UI_CHECKS"] else { return }
    let directory = URL(fileURLWithPath: output, isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
}

let panelTrendFixtureScope = String(repeating: "e", count: 64)

func panelTrendFixture(at now: Date, changedHistory: Bool = false) -> UsageInsightsReport {
    let start = now.addingTimeInterval(-18 * 3_600)
    let rows = (0...216).filter { !(90...101).contains($0) }.flatMap { index in
        let date = start.addingTimeInterval(Double(index) * 300)
        let adjustment = changedHistory && (60...119).contains(index) ? 10 : 0
        return QuotaObservation.batch(provider: .codex, source: .codexRateLimits,
            receivedAt: date,
            fiveHour: UsageWindow(usedPercent: 5 + index % 60 + adjustment, windowDurationMinutes: 300,
                                  resetsAt: start.addingTimeInterval(Double(index / 60 + 1) * 18_000)),
            weekly: UsageWindow(usedPercent: 10 + index / 6 + adjustment, windowDurationMinutes: 10_080,
                                resetsAt: now.addingTimeInterval(6 * 86_400)),
            accountScope: panelTrendFixtureScope)
    }
    return UsageInsights.analyze(observations: rows, now: now)
}

await MainActor.run {
    let emptyDark = UsageSnapshot(appearance: .dark)
    let boundary = UsageSnapshot(
        fiveHour: UsageWindow(usedPercent: 40, windowDurationMinutes: 300, resetsAt: nil),
        weekly: UsageWindow(usedPercent: 71, windowDurationMinutes: 10_080, resetsAt: nil),
        dailyUsage: (1...7).map { DailyUsage(startDate: "2099-01-0\($0)", tokens: Int64($0 * 1_000_000)) },
        appearance: .dark
    )
    var boundaryLight = boundary
    boundaryLight.appearance = .light
    let smallRegions = [
        ("left quota ring", CGRect(x: 0.04, y: 0.05, width: 0.44, height: 0.9)),
        ("right quota ring", CGRect(x: 0.52, y: 0.05, width: 0.44, height: 0.9))
    ]
    let largeRegions = [
        ("quota area", CGRect(x: 0.04, y: 0.08, width: 0.42, height: 0.7)),
        ("trend area", CGRect(x: 0.5, y: 0.08, width: 0.46, height: 0.7))
    ]

    let appearances = [
        (name: "dark", snapshot: emptyDark, isLight: false),
        (name: "light", snapshot: boundaryLight, isLight: true)
    ]
    let opacities = [
        (name: "minimum", value: WidgetGlassOpacity.minimum),
        (name: "maximum", value: WidgetGlassOpacity.maximum)
    ]

    for appearance in appearances {
        for opacity in opacities {
            for mode in DesktopPanelMode.allCases {
                let regions = mode == .small ? smallRegions : mode == .large ? largeRegions : [
                    ("5h quota", CGRect(x: 0.06, y: 0.30, width: 0.88, height: 0.28)),
                    ("weekly quota", CGRect(x: 0.06, y: 0.59, width: 0.88, height: 0.28))
                ]
                checkRender(
                    QuotaPanelContent(mode: mode, snapshot: appearance.snapshot, glassOpacity: opacity.value),
                    on: LiquidGlassSurface(isLight: appearance.isLight, opacity: opacity.value, accent: .blue),
                    width: mode.size.width,
                    height: mode.size.height,
                    label: "\(mode.rawValue) \(appearance.name) \(opacity.name)-opacity panel",
                    regions: regions
                )
            }
        }
    }

    let trendNow = Date()
    let trendReport = panelTrendFixture(at: trendNow)
    let changedTrendReport = panelTrendFixture(at: trendNow, changedHistory: true)
    var trendBoundary = boundary
    trendBoundary.dailyUsage = (0..<7).map {
        DailyUsage(startDate: String(trendNow.addingTimeInterval(Double($0 - 6) * 86_400).ISO8601Format().prefix(10)),
                   tokens: Int64(($0 + 1) * 1_000_000))
    }
    // Keep the clock/header out of history-liveness comparisons. Both fixtures have
    // the same latest quota; only historical plot geometry is allowed to differ.
    let historicalPlot = CGRect(x: 0.52, y: 0.36, width: 0.42, height: 0.40)
    for appearance in [WidgetAppearance.dark, .light] {
        var snapshot = trendBoundary
        snapshot.appearance = appearance
        let light = appearance == .light
        for source in PanelChartSource.allCases {
            for style in PanelChartStyle.allCases {
                let trend = PanelTrendPresentation.make(report: trendReport, provider: .codex,
                    scope: panelTrendFixtureScope, source: source, style: style, now: trendNow)
                if source.hours != nil {
                    precondition(!trend.isEmpty && trend.series.allSatisfy { !$0.points.isEmpty }, "history render fixture is empty")
                }
                for opacity in opacities {
                    let image = checkRender(
                        QuotaPanelContent(mode: .large, snapshot: snapshot, glassOpacity: opacity.value, trend: trend),
                        on: LiquidGlassSurface(isLight: light, opacity: opacity.value, accent: .blue),
                        width: 680, height: 300,
                        label: "large \(source.rawValue) \(style.rawValue) \(appearance.rawValue) \(opacity.name)",
                        regions: largeRegions
                    )
                    if opacity.value == WidgetGlassOpacity.maximum {
                        if source == .quota12Hours, style == .line, !light { saveTrendPreview(image, name: "panel-trend-12h-line-dark") }
                        if source == .quota24Hours, style == .bars, light { saveTrendPreview(image, name: "panel-trend-24h-bars-light") }
                        if source == .sevenDayTokens, style == .line, !light { saveTrendPreview(image, name: "panel-trend-seven-day-line-dark") }
                    }
                }
                if source.hours != nil {
                    let changed = PanelTrendPresentation.make(report: changedTrendReport, provider: .codex,
                        scope: panelTrendFixtureScope, source: source, style: style, now: trendNow)
                    precondition(zip(trend.series, changed.series).allSatisfy { pair in pair.0.currentRemainingPercent == pair.1.currentRemainingPercent },
                                 "liveness fixture changed its current quota instead of only its history")
                    let before = render(QuotaPanelContent(mode: .large, snapshot: snapshot, glassOpacity: 1, trend: trend), width: 680, height: 300)
                    let after = render(QuotaPanelContent(mode: .large, snapshot: snapshot, glassOpacity: 1, trend: changed), width: 680, height: 300)
                    precondition(changedPixels(before, after, in: historicalPlot) > 50,
                                 "\(source.rawValue) \(style.rawValue) plot ignores refreshed source history")
                }
                for mode in [DesktopPanelMode.small, .medium] {
                    let before = render(QuotaPanelContent(mode: mode, snapshot: snapshot, glassOpacity: 1), width: mode.size.width, height: mode.size.height)
                    let after = render(QuotaPanelContent(mode: mode, snapshot: snapshot, glassOpacity: 1, trend: trend), width: mode.size.width, height: mode.size.height)
                    precondition(changedPixels(before, after, in: CGRect(x: 0, y: 0, width: 1, height: 1)) == 0,
                                 "large-panel chart preferences changed the \(mode.rawValue) panel")
                }
            }
            let bars = PanelTrendPresentation.make(report: trendReport, provider: .codex, scope: panelTrendFixtureScope,
                                                    source: source, style: .bars, now: trendNow)
            let line = PanelTrendPresentation.make(report: trendReport, provider: .codex, scope: panelTrendFixtureScope,
                                                    source: source, style: .line, now: trendNow)
            let barImage = render(QuotaPanelContent(mode: .large, snapshot: snapshot, glassOpacity: 1, trend: bars), width: 680, height: 300)
            let lineImage = render(QuotaPanelContent(mode: .large, snapshot: snapshot, glassOpacity: 1, trend: line), width: 680, height: 300)
            let upperPlot = CGRect(x: 0.52, y: 0.40, width: 0.42, height: 0.20)
            precondition(changedPixels(barImage, lineImage, in: upperPlot) > 50,
                         "\(source.rawValue) ignores the bar/line selection")
            if source == .sevenDayTokens {
                let legacy = render(QuotaPanelContent(mode: .large, snapshot: snapshot, glassOpacity: 1), width: 680, height: 300)
                precondition(changedPixels(legacy, barImage, in: historicalPlot) == 0,
                             "default chart preferences changed the existing seven-day bars")
            }
        }
        for (source, style) in [(PanelChartSource.quota12Hours, PanelChartStyle.line), (.quota24Hours, .bars)] {
            let empty = PanelTrendPresentation.make(report: nil, provider: .codex, scope: panelTrendFixtureScope,
                                                    source: source, style: style, now: trendNow)
            let image = checkRender(
                QuotaPanelContent(mode: .large, snapshot: snapshot, glassOpacity: 0.35, trend: empty),
                on: LiquidGlassSurface(isLight: light, opacity: 0.35, accent: .blue),
                width: 680, height: 300, label: "large empty-history \(source.rawValue) \(appearance.rawValue)",
                regions: largeRegions
            )
            if !light, source == .quota12Hours { saveTrendPreview(image, name: "panel-trend-empty-dark") }
        }
    }

    // A second provider uses the same native surface in all sizes, including
    // the waiting state. It must never become a black or sample-filled panel.
    for appearance in [WidgetAppearance.dark, .light] {
        for state in ["waiting", "quota", "expired"] {
            var fiveHour = state == "waiting" ? nil : boundary.fiveHour
            var weekly = state == "waiting" ? nil : boundary.weekly
            if state == "expired" {
                fiveHour?.resetsAt = Date(timeIntervalSince1970: 1)
                weekly?.resetsAt = Date(timeIntervalSince1970: 1)
            }
            let claude = UsageSnapshot(
                fiveHour: fiveHour,
                weekly: weekly,
                appearance: appearance, service: .claude
            )
            for mode in DesktopPanelMode.allCases {
                checkRender(
                    QuotaPanelContent(mode: mode, snapshot: claude, glassOpacity: 0.35),
                    on: LiquidGlassSurface(isLight: appearance == .light, opacity: 0.35, accent: .blue),
                    width: mode.size.width, height: mode.size.height,
                    label: "Claude \(mode.rawValue) \(appearance.rawValue) \(state)",
                    regions: [("content", CGRect(x: 0.05, y: 0.1, width: 0.9, height: 0.8))]
                )
            }
        }
    }

    let solidSmall = render(
        ZStack {
            LiquidGlassSurface(isLight: false, opacity: WidgetGlassOpacity.minimum, accent: .green)
            Color.black
        },
        width: 164,
        height: 164
    )
    let solidLarge = render(
        ZStack {
            LiquidGlassSurface(isLight: false, opacity: WidgetGlassOpacity.minimum, accent: .blue)
            Color.black
        },
        width: 704,
        height: 344
    )
    let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
    precondition(!hasReadableContrast(solidSmall, in: fullFrame), "solid-black small-widget negative control passed")
    precondition(!hasReadableContrast(solidLarge, in: fullFrame), "solid-black large-widget negative control passed")
    let solidMedium = render(Color.black, width: 344, height: 164)
    precondition(!hasReadableContrast(solidMedium, in: fullFrame), "solid-black medium-panel negative control passed")
    for mode in DesktopPanelMode.allCases {
        let before = render(QuotaPanelContent(mode: mode, snapshot: emptyDark, glassOpacity: 1), width: mode.size.width, height: mode.size.height)
        let after = render(QuotaPanelContent(mode: mode, snapshot: boundary, glassOpacity: 1), width: mode.size.width, height: mode.size.height)
        precondition(changedPixels(before, after, in: fullFrame) > 100, "\(mode.rawValue) panel ignores updated quota content")
    }
    for snapshot in [boundary, boundaryLight] {
        checkRender(
            QuotaPanelContent(mode: .medium, snapshot: snapshot, glassOpacity: 0.35)
                .clipShape(RoundedRectangle(cornerRadius: 64, style: .continuous)),
            on: LiquidGlassSurface(isLight: snapshot.resolvedAppearance == .light, opacity: 0.35, accent: .blue, cornerRadius: 64),
            width: 344,
            height: 164,
            label: "maximum-radius medium panel",
            regions: [
                ("5h quota", CGRect(x: 0.10, y: 0.34, width: 0.80, height: 0.23)),
                ("weekly quota", CGRect(x: 0.10, y: 0.60, width: 0.80, height: 0.23))
            ]
        )
    }

    let plainEdge = render(
        LiquidGlassSurface(isLight: true, opacity: 0.7, accent: .blue, dispersion: 0)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)),
        width: 240,
        height: 120
    )
    let dispersedEdge = render(
        LiquidGlassSurface(isLight: true, opacity: 0.7, accent: .blue, dispersion: 0.3)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)),
        width: 240,
        height: 120
    )
    precondition(
        changedPixels(plainEdge, dispersedEdge, in: fullFrame) > 100,
        "glass dispersion is imperceptible or clipped outside the glass"
    )
    let interior = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    precondition(changedPixels(plainEdge, dispersedEdge, in: interior) == 0, "edge color separation tints panel content")
    for isLight in [false, true] {
        let clear = render(LiquidGlassSurface(isLight: isLight, opacity: 0.35, accent: .blue, blurAmount: 0), width: 240, height: 120)
        let frosted = render(LiquidGlassSurface(isLight: isLight, opacity: 0.35, accent: .blue, blurAmount: 1), width: 240, height: 120)
        precondition(changedPixels(clear, frosted, in: interior) > 1_000, "frost-depth control has no visible interior haze effect")
        let opaque = render(LiquidGlassSurface(isLight: isLight, opacity: 1, accent: .blue, blurAmount: 0), width: 240, height: 120)
        let opaqueFrosted = render(LiquidGlassSurface(isLight: isLight, opacity: 1, accent: .blue, blurAmount: 1), width: 240, height: 120)
        precondition(changedPixels(opaque, opaqueFrosted, in: interior) == 0, "frost changes the fully opaque surface tone")
    }

    let tightCorner = render(
        LiquidGlassSurface(isLight: true, opacity: 0.7, accent: .blue, cornerRadius: 10),
        width: 240,
        height: 120
    )
    let roundCorner = render(
        LiquidGlassSurface(isLight: true, opacity: 0.7, accent: .blue, cornerRadius: 64),
        width: 240,
        height: 120
    )
    precondition(
        changedPixels(tightCorner, roundCorner, in: fullFrame) > 100,
        "glass corner-radius setting has no visible render effect"
    )

    let quietElasticity = render(
        LiquidGlassSurface(
            isLight: true,
            opacity: 0.7,
            accent: .blue,
            elasticity: 0,
            displacement: 0.5,
            refractionMode: .prominent
        ),
        width: 240,
        height: 120
    )
    let expressiveElasticity = render(
        LiquidGlassSurface(
            isLight: true,
            opacity: 0.7,
            accent: .blue,
            elasticity: 1,
            displacement: 0.5,
            refractionMode: .prominent
        ),
        width: 240,
        height: 120
    )
    precondition(
        changedPixels(quietElasticity, expressiveElasticity, in: fullFrame) > 100,
        "glass elasticity setting has no visible render effect"
    )

    for mode in DesktopPanelMode.allCases {
        for radius in [10.0, 30, 64] {
            for elasticity in [0.0, 1] {
                for hover in [CGSize.zero, CGSize(width: -1, height: -1), CGSize(width: 1, height: 1)] {
                    let highlight = render(
                        GlassRimHighlight(isLight: false, cornerRadius: radius, elasticity: elasticity,
                                          displacement: 1, hoverVector: hover),
                        width: mode.size.width, height: mode.size.height
                    )
                    precondition(hasConfinedRimHighlight(highlight, size: mode.size, cornerRadius: CGFloat(radius)),
                                 "\(mode.rawValue) radius\(radius) elasticity\(elasticity) hover\(hover) highlight leaves its continuous rim")
                }
            }
        }
    }
    let detachedBarSize = DesktopPanelMode.large.size
    let detachedBar = render(
        ZStack(alignment: .topLeading) {
            Color.clear
            Capsule().fill(.white.opacity(0.5))
                .frame(width: 160, height: 5.5)
                .blur(radius: 1.2)
                .padding(.leading, 28).padding(.top, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 64, style: .continuous)),
        width: detachedBarSize.width, height: detachedBarSize.height
    )
    precondition(!hasConfinedRimHighlight(detachedBar, size: detachedBarSize, cornerRadius: 64),
                 "rim-confinement detector accepted the original detached blurred white bar")
    print("Glass rim confinement passed: three sizes, continuous corners, elasticity/hover extremes, detached-bar negative control.")

    let quietDisplacement = render(
        LiquidGlassSurface(isLight: true, opacity: 0.7, accent: .blue, elasticity: 0.5, displacement: 0),
        width: 240,
        height: 120
    )
    let expressiveDisplacement = render(
        LiquidGlassSurface(isLight: true, opacity: 0.7, accent: .blue, elasticity: 0.5, displacement: 1),
        width: 240,
        height: 120
    )
    precondition(changedPixels(quietDisplacement, expressiveDisplacement, in: fullFrame) > 100, "glass displacement setting has no visible render effect")

    let standardRefraction = render(
        LiquidGlassSurface(isLight: true, opacity: 0.7, accent: .blue, displacement: 0.8, refractionMode: .standard),
        width: 240,
        height: 120
    )
    let polarRefraction = render(
        LiquidGlassSurface(isLight: true, opacity: 0.7, accent: .blue, displacement: 0.8, refractionMode: .polar),
        width: 240,
        height: 120
    )
    let prominentRefraction = render(
        LiquidGlassSurface(isLight: true, opacity: 0.7, accent: .blue, displacement: 0.8, refractionMode: .prominent),
        width: 240,
        height: 120
    )
    precondition(changedPixels(standardRefraction, polarRefraction, in: fullFrame) > 100, "polar refraction mode has no visible effect")
    precondition(changedPixels(polarRefraction, prominentRefraction, in: fullFrame) > 100, "prominent refraction mode has no visible effect")

    let weakEdge = render(
        LiquidGlassSurface(isLight: true, opacity: 0.7, accent: .blue, edgeStrength: 0, tone: .orange),
        width: 240,
        height: 120
    )
    let strongEdge = render(
        LiquidGlassSurface(isLight: true, opacity: 0.7, accent: .blue, edgeStrength: 1, tone: .orange),
        width: 240,
        height: 120
    )
    precondition(changedPixels(weakEdge, strongEdge, in: interior) == 0, "glass edge strength changes the interior tone")

}
#endif

let settings = GlassRenderSettings(
    appearance: .light,
    opacity: 0.51,
    edgeStrength: 0.73,
    elasticity: 0.82,
    displacement: 0.64,
    blurAmount: 0.29,
    saturation: 1.72,
    dispersion: 0.16,
    cornerRadius: 51,
    tone: "cool",
    refractionMode: .polar
)
let settingsSnapshot = UsageSnapshot(glassSettings: settings)
let settingsData = try JSONEncoder().encode(settingsSnapshot)
let decodedSettings = try JSONDecoder().decode(UsageSnapshot.self, from: settingsData)
precondition(decodedSettings.glassSettings == settings, "glass settings did not survive the app-to-widget snapshot round trip")

let invalidSettings = GlassRenderSettings(opacity: -1, elasticity: 3, displacement: -2, blurAmount: 9, saturation: 0, cornerRadius: 200, tone: "invalid").sanitized
precondition(invalidSettings.opacity == WidgetGlassOpacity.minimum, "glass opacity was not clamped")
precondition(invalidSettings.elasticity == 1 && invalidSettings.displacement == 0, "glass motion inputs were not clamped")
precondition(invalidSettings.blurAmount == 1 && invalidSettings.saturation == 1, "glass optics inputs were not clamped")
precondition(invalidSettings.cornerRadius == 64 && invalidSettings.tone == "neutral", "glass shape inputs were not clamped")

print("Quota parser, thresholds, and widget renders passed.")

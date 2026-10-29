import AppKit
import SwiftUI

// No account connection or persistent settings are needed for this window probe.
@MainActor
final class QuotaMonitor: ObservableObject {
    static let fixtureScope = String(repeating: "b", count: 64)
    enum State: Equatable {
        case disconnected, connecting, signingIn, connected(String?), failed(String)
    }
    @Published var state = State.connected(nil)
    @Published var snapshot = UsageSnapshot.placeholder
    @Published var service = AgentService.codex
    @Published var connectionMessage: String?
    @Published var models: [PlannerModel] = []
    @Published var modelCatalogMessage = "测试目录（无推理）"
    @Published var isLoadingModels = false
    @Published var codexCollectionEnabled = true
    @Published var claudeCollectionEnabled = true
    @Published var isConfiguringCollection = false
    let insights: InsightsStore
    let historyURL: URL
    init() {
        let path = ProcessInfo.processInfo.environment["TALLYGENT_HISTORY_DB"] ?? FileManager.default.temporaryDirectory.appendingPathComponent("tallygent-ui-\(UUID().uuidString)/history.sqlite").path
        let url = URL(fileURLWithPath: path)
        historyURL = url
        let date = Date()
        for index in 0...40 {
            let values = QuotaObservation.batch(provider: .codex, source: .codexRateLimits,
                receivedAt: date.addingTimeInterval(Double(index - 40) * 60),
                fiveHour: .init(usedPercent: 18 - (40 - index) / 3, windowDurationMinutes: 300, resetsAt: date.addingTimeInterval(14_400)),
                weekly: .init(usedPercent: 28 - (40 - index) / 10, windowDurationMinutes: 10_080, resetsAt: date.addingTimeInterval(6 * 86_400)),
                accountScope: Self.fixtureScope)
            try! ObservationHistory.append(values, at: url, now: date)
        }
        insights = InsightsStore(url: url)
        Task { await insights.reload(force: true) }
    }
    func setCollection(_ provider: AgentService, enabled: Bool) async {}
    func refreshModelCatalog() {}
    func plannerQuota() -> PlannerQuota {
        PlannerQuota(provider: service, scope: Self.fixtureScope, source: "隔离测试", receivedAt: .distantPast, windows: [], connected: false)
    }
    func selectService(_ value: AgentService) { service = value }
    func enableClaudeBridge() {}
    func removeClaudeBridge() {}
    func resetClaudeSession() {}
    func connect() async {}
    func refresh() {}
    #if CODEX_QUOTA_ADVANCED_GLASS
    func updateGlassSettings(_ settings: GlassRenderSettings) {}
    #endif
}

@main
struct DesktopPanelProbe {
    private static let applicationWindowStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    @MainActor
    static func main() {
        _ = NSApplication.shared
        verifyNativeLocalization()
        verifyLocalizedPanelRenders()
        if ProcessInfo.processInfo.environment["TALLYGENT_LAYOUT_ONLY"] == "1" {
            verifyMeaningfulControlLayouts(server: QuotaMonitor())
            print("Native localized layout probe passed: \(probeLanguage)")
            return
        }
        let window = DragProbeWindow(
            contentRect: NSRect(x: 100, y: 100, width: 680, height: 300),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        DesktopPanelWindowConfigurator().configure(window)
        precondition(window.styleMask.contains(.fullSizeContentView), "native title bar leaves a permanent strip above the glass")
        precondition(!window.styleMask.contains(.titled), "native title-bar reservation is still present")
        precondition(window.frame.size == NSSize(width: 680, height: 300), "panel has extra empty area outside glass")
        precondition(window.canBecomeKey, "borderless panel cannot receive keyboard focus")
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        for mode in DesktopPanelMode.allCases {
            DesktopPanelWindowConfigurator(size: mode.size).configure(window)
            precondition(window.frame.size == mode.size, "selected mode does not resize the native panel")
            precondition(window.frame.minX == topLeft.x && window.frame.maxY == topLeft.y, "mode change moved the panel anchor")
            precondition(!DesktopGlassPanelView.isNearEdge(CGPoint(x: mode.size.width / 2, y: mode.size.height / 2), size: mode.size), "compact panel chrome never hides")
        }
        let size = CGSize(width: 680, height: 300)
        precondition(!DesktopGlassPanelView.isNearEdge(CGPoint(x: 340, y: 150), size: size), "chrome stays visible at panel center")
        for point in [CGPoint(x: 5, y: 150), CGPoint(x: 675, y: 150), CGPoint(x: 340, y: 5), CGPoint(x: 340, y: 295)] {
            precondition(DesktopGlassPanelView.isNearEdge(point, size: size), "chrome fails to appear at a panel edge")
        }
        precondition(!DesktopGlassPanelView.isNearEdge(CGPoint(x: -1, y: 150), size: size), "chrome stays visible outside panel")
        precondition(window.isMovable && !window.ignoresMouseEvents, "desktop panel rejects mouse interaction")
        precondition(window.level.rawValue > Int(CGWindowLevelForKey(.desktopIconWindow)), "desktop panel is hidden behind Finder's event layer")
        precondition(window.level.rawValue < NSWindow.Level.normal.rawValue, "desktop panel covers normal application windows")

        let dragRegion = DesktopPanelDragRegion.DragView(frame: NSRect(origin: .zero, size: window.frame.size))
        window.contentView?.addSubview(dragRegion)
        precondition(dragRegion.acceptsFirstMouse(for: nil), "inactive panel requires an extra click before dragging")
        for mode in DesktopPanelMode.allCases {
            DesktopPanelWindowConfigurator(size: mode.size).configure(window)
            dragRegion.frame = NSRect(origin: .zero, size: mode.size)
            dragRegion.cornerRadius = 64
            for point in [NSPoint(x: mode.size.width / 2, y: mode.size.height / 2), NSPoint(x: mode.size.width / 2, y: 20), NSPoint(x: 20, y: mode.size.height / 2)] {
                precondition(window.contentView?.hitTest(point) === dragRegion, "body content cannot initiate native dragging")
                let event = NSEvent.mouseEvent(
                    with: .leftMouseDown, location: point, modifierFlags: [],
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                    clickCount: 1, pressure: 1
                )!
                dragRegion.mouseDown(with: event)
                precondition(window.forwardedEvent === event, "body drag lost the original mouse event")
            }
            precondition(dragRegion.hitTest(NSPoint(x: 1, y: 1)) == nil, "transparent corners intercept desktop clicks")
            let outline = RoundedRectangle(cornerRadius: 64, style: .continuous).path(in: dragRegion.bounds)
            for x in stride(from: 0.0, through: 64.0, by: 8) {
                for y in stride(from: 0.0, through: 64.0, by: 8) {
                    let point = NSPoint(x: x, y: y)
                    precondition((dragRegion.hitTest(point) != nil) == outline.contains(point), "drag hit area differs from the visible continuous corner")
                }
            }
        }
        window.close()
        let controller = DesktopPanelController.shared
        let server = QuotaMonitor()
        controller.show(server: server)
        let first = NSApp.windows.first { $0.identifier?.rawValue == DesktopGlassPanelView.windowID && $0.isVisible }!
        first.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        func dragViews(in view: NSView) -> [DesktopPanelDragRegion.DragView] {
            (view as? DesktopPanelDragRegion.DragView).map { [$0] } ?? view.subviews.flatMap { dragViews(in: $0) }
        }
        let productionDrag = first.contentView.flatMap { dragViews(in: $0).first }
        precondition(productionDrag?.bounds.size == DesktopPanelMode.stored().size, "production drag region is still limited to the header")
        controller.show(server: server)
        precondition(NSApp.windows.filter { $0.identifier?.rawValue == DesktopGlassPanelView.windowID && $0.isVisible }.count == 1, "show created a second desktop panel")
        precondition(controller.isVisible, "desktop panel did not open")
        controller.close()
        precondition(!first.isVisible && !controller.isVisible, "close left the desktop panel visible")
        controller.show(server: server)
        precondition(controller.isVisible, "desktop panel failed to reopen")
        controller.close()
        verifyLiveTrendPanel(server: server)
        for width in [760.0, 1_030, 1_120, 1_400] {
            var frames: [DesktopPanelMode: CGRect] = [:]
            let dashboard = NSHostingView(rootView: DashboardView(server: server, onGalleryLayout: { frames[$0] = $1 })
                .background(Color(nsColor: .windowBackgroundColor)))
            dashboard.frame = NSRect(x: 0, y: 0, width: width, height: 720)
            let dashboardWindow = NSWindow(contentRect: dashboard.frame, styleMask: applicationWindowStyle, backing: .buffered, defer: false)
            dashboardWindow.isReleasedWhenClosed = false
            dashboardWindow.contentView = dashboard
            dashboardWindow.makeKeyAndOrderFront(nil)
            dashboard.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            print("Dashboard layout width \(width), frame \(dashboard.frame), fitting \(dashboard.fittingSize)")
            print("Gallery page frames \(frames)")
            fflush(stdout)
            if [760.0, 1_120].contains(width),
               let output = ProcessInfo.processInfo.environment["TALLYGENT_UI_CHECKS"],
               let bitmap = dashboard.bitmapImageRepForCachingDisplay(in: dashboard.bounds) {
                let url = URL(fileURLWithPath: output, isDirectory: true)
                try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                dashboard.cacheDisplay(in: dashboard.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: url.appendingPathComponent("monitor-\(Int(width)).png"))
            }
            guard let selectedFrame = frames[.stored()] else {
                preconditionFailure("selected panel page did not produce an on-screen frame")
            }
            let viewport = selectedFrame.width
            precondition(viewport > 600 && viewport <= width - 40, "gallery exceeds the available dashboard width")
            precondition(abs(selectedFrame.minX) < 3, "resized gallery page does not match persisted panel mode")
            precondition(frames.values.allSatisfy { abs($0.width - viewport) < 2 }, "gallery page widths diverge when resizing")
            precondition(dashboard.fittingSize.width <= width + 2, "dashboard forces its contents outside the window")
            precondition(DashboardLayout.hasInlineInspector(width: width) == (width >= 1_080), "compact window keeps a clipped inspector")
            dashboardWindow.close()
        }
        for width in [760.0, 1_120] {
            let planner = NSHostingView(rootView: DashboardView(server: server, section: .planner)
                .background(Color(nsColor: .windowBackgroundColor)))
            planner.frame = NSRect(x: 0, y: 0, width: width, height: 760)
            let host = NSWindow(contentRect: planner.frame, styleMask: applicationWindowStyle, backing: .buffered, defer: false)
            host.isReleasedWhenClosed = false
            host.contentView = planner
            host.makeKeyAndOrderFront(nil)
            planner.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            precondition(planner.fittingSize.width <= width + 2, "Planner overflows a compact window")
            if let output = ProcessInfo.processInfo.environment["TALLYGENT_UI_CHECKS"],
               let bitmap = planner.bitmapImageRepForCachingDisplay(in: planner.bounds) {
                planner.cacheDisplay(in: planner.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("planner-\(Int(width)).png"))
            }
            host.close()
        }
        for width in [760.0, 1_120] {
            let insights = NSHostingView(rootView: DashboardView(server: server, section: .insights)
                .background(Color(nsColor: .windowBackgroundColor)))
            insights.frame = NSRect(x: 0, y: 0, width: width, height: 760)
            let host = NSWindow(contentRect: insights.frame, styleMask: applicationWindowStyle, backing: .buffered, defer: false)
            host.isReleasedWhenClosed = false
            host.contentView = insights
            host.makeKeyAndOrderFront(nil)
            insights.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            precondition(insights.fittingSize.width <= width + 2, "Insights overflows a compact window")
            precondition(!server.insights.report.windows.filter { $0.provider == .codex }.contains { $0.history.isEmpty }, "Insights fixture did not load source history")
            if let output = ProcessInfo.processInfo.environment["TALLYGENT_UI_CHECKS"],
               let bitmap = insights.bitmapImageRepForCachingDisplay(in: insights.bounds) {
                insights.cacheDisplay(in: insights.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("insights-\(Int(width)).png"))
            }
            host.close()
        }
        verifyMeaningfulControlLayouts(server: server)
        print("Desktop panel mouse routing and window-level probe passed.")
    }

    private static var probeLanguage: String {
        ProcessInfo.processInfo.environment["TALLYGENT_PROBE_LANGUAGE"] ?? "zh-Hans"
    }

    private static var probeLocale: String {
        switch probeLanguage {
        case "en": return "en_US"
        case "zh-Hant": return "zh_TW"
        default: return "zh_CN"
        }
    }

    /// Assert real native resource resolution, not only an environment locale redraw.
    private static func verifyNativeLocalization() {
        let expected = ["en": "Weekly quota", "zh-Hans": "周额度", "zh-Hant": "每週額度"]
        guard let weekly = expected[probeLanguage] else { preconditionFailure("unsupported probe language") }
        precondition(Bundle.main.preferredLocalizations.first == probeLanguage,
                     "native bundle did not resolve the requested language")
        precondition(L("周额度") == weekly, "dynamic text did not load the native language resource")
        let percentage = LF("剩余 %lld%%", Int64(25))
        precondition(percentage.contains("25%") && !percentage.contains("%lld"),
                     "localized integer/escaped-percent formatting is broken")
        precondition(Bundle.main.localizations.contains("en") && Bundle.main.localizations.contains("zh-Hans") &&
                     Bundle.main.localizations.contains("zh-Hant"), "native probe bundle is missing a supported language")
        print("Native localization resource: PASS (\(probeLanguage), \(weekly))")
    }

    @MainActor
    private static func verifyLocalizedPanelRenders() {
        func render<V: View>(_ content: V, size: CGSize) -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height)
                .environment(\.locale, Locale(identifier: probeLocale)))
            renderer.scale = 1
            guard let data = renderer.nsImage?.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data) else {
                preconditionFailure("localized panel produced no native image")
            }
            return bitmap
        }
        func evidence(_ image: NSBitmapImageRep, baseline: NSBitmapImageRep) -> (changed: Int, dark: Int, bright: Int) {
            var result = (changed: 0, dark: 0, bright: 0)
            for y in 0..<image.pixelsHigh {
                for x in 0..<image.pixelsWide {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          let base = baseline.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let difference = abs(color.redComponent - base.redComponent) + abs(color.greenComponent - base.greenComponent) +
                        abs(color.blueComponent - base.blueComponent) + abs(color.alphaComponent - base.alphaComponent)
                    if difference > 0.12 { result.changed += 1 }
                    let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                    if luminance < 0.6 { result.dark += 1 }
                    if luminance > 0.6 { result.bright += 1 }
                }
            }
            return result
        }
        for light in [false, true] {
            var snapshot = UsageSnapshot.placeholder
            snapshot.appearance = light ? .light : .dark
            for mode in DesktopPanelMode.allCases {
                let background = ZStack {
                    light ? Color.white : Color.black
                    LiquidGlassSurface(isLight: light, opacity: 1, accent: .blue)
                }
                let baseline = render(background, size: mode.size)
                let content = render(ZStack {
                    background
                    QuotaPanelContent(mode: mode, snapshot: snapshot, glassOpacity: 1)
                }.preferredColorScheme(light ? .light : .dark), size: mode.size)
                let counts = evidence(content, baseline: baseline)
                let pixels = content.pixelsWide * content.pixelsHigh
                let readableFloor = max(8, pixels / 1_000)
                precondition(counts.changed > pixels / 300 && min(counts.dark, counts.bright) > readableFloor,
                             "localized \(probeLanguage) \(mode.rawValue) panel is blank or unreadable")
                let solid = render(Color.black, size: mode.size)
                let negative = evidence(solid, baseline: baseline)
                precondition(min(negative.dark, negative.bright) == 0, "localized render gate accepted solid black")
                if let output = ProcessInfo.processInfo.environment["TALLYGENT_UI_CHECKS"] {
                    let directory = URL(fileURLWithPath: output, isDirectory: true)
                    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try! content.representation(using: .png, properties: [:])!.write(to:
                        directory.appendingPathComponent("\(probeLanguage)-panel-\(mode.rawValue)-\(light ? "light" : "dark").png"))
                }
            }
        }
        print("Localized small/medium/large light/dark content and solid-black negative control: PASS (\(probeLanguage))")
    }

    @MainActor
    private static func verifyLiveTrendPanel(server: QuotaMonitor) {
        let defaults = UserDefaults.standard
        let keys = [DesktopPanelMode.defaultsKey, PanelChartSource.defaultsKey, PanelChartStyle.defaultsKey]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        let controller = DesktopPanelController.shared
        defer {
            controller.close()
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(DesktopPanelMode.large.rawValue, forKey: DesktopPanelMode.defaultsKey)
        defaults.set(PanelChartSource.quota12Hours.rawValue, forKey: PanelChartSource.defaultsKey)
        defaults.set(PanelChartStyle.line.rawValue, forKey: PanelChartStyle.defaultsKey)
        let ready = Date().addingTimeInterval(3)
        while server.insights.panelReport.windows.filter({ $0.provider == .codex }).allSatisfy({ $0.history.isEmpty }) && Date() < ready {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(server.insights.panelReport.windows.contains { $0.provider == .codex && !$0.history.isEmpty },
                     "placed-panel history fixture did not load")
        controller.show(server: server)
        let panel = NSApp.windows.first { $0.identifier?.rawValue == DesktopGlassPanelView.windowID && $0.isVisible }!
        let view = panel.contentView!
        func capture() -> NSBitmapImageRep {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap
        }
        let line = capture()
        defaults.set(PanelChartStyle.bars.rawValue, forKey: PanelChartStyle.defaultsKey)
        let bars = capture()
        precondition(changedPlotPixels(line, bars) > 50, "placed panel ignores live bar/line preferences")
        defaults.set(PanelChartSource.quota24Hours.rawValue, forKey: PanelChartSource.defaultsKey)
        let day = capture()
        precondition(changedPlotPixels(bars, day) > 50, "placed panel ignores the live 12h/24h selection")
        let previousCount = server.insights.panelReport.windows.first { $0.provider == .codex && $0.windowID == "fiveHour" }!.history.count
        let now = Date()
        let earlier = QuotaObservation.batch(provider: .codex, source: .codexRateLimits,
            receivedAt: now.addingTimeInterval(-2 * 3_600),
            fiveHour: .init(usedPercent: 55, windowDurationMinutes: 300, resetsAt: now.addingTimeInterval(14_400)),
            weekly: .init(usedPercent: 45, windowDurationMinutes: 10_080, resetsAt: now.addingTimeInterval(6 * 86_400)),
            accountScope: QuotaMonitor.fixtureScope)
        try! ObservationHistory.append(earlier, at: server.historyURL, now: now)
        Task { await server.insights.reload(force: true) }
        let deadline = Date().addingTimeInterval(3)
        while (server.insights.panelReport.windows.first { $0.provider == .codex && $0.windowID == "fiveHour" }?.history.count ?? 0) <= previousCount && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition((server.insights.panelReport.windows.first { $0.provider == .codex && $0.windowID == "fiveHour" }?.history.count ?? 0) > previousCount,
                     "new history never reached the placed-panel presentation store")
        let updated = capture()
        precondition(changedPlotPixels(day, updated) > 50, "placed panel did not observe refreshed history")
        precondition(NSApp.windows.filter { $0.identifier?.rawValue == DesktopGlassPanelView.windowID && $0.isVisible }.count == 1,
                     "chart changes created a second desktop panel")

        let settings = NSHostingView(rootView: ScrollView {
            GlassSettingsView(compact: true).padding(20)
        }.preferredColorScheme(.light).background(Color(nsColor: .windowBackgroundColor)))
        settings.frame = NSRect(x: 0, y: 0, width: 360, height: 640)
        let settingsWindow = NSWindow(contentRect: settings.frame, styleMask: applicationWindowStyle, backing: .buffered, defer: false)
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.appearance = NSAppearance(named: .aqua)
        settingsWindow.contentView = settings
        settingsWindow.makeKeyAndOrderFront(nil)
        settings.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        saveLayoutImage(settings, name: "panel-settings-compact")
        settingsWindow.close()
        print("Placed-panel trend preferences and observed history refresh: PASS")
    }

    /// The symmetric central band excludes both clock and footer in either bitmap orientation.
    @MainActor
    private static func changedPlotPixels(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Int {
        precondition(lhs.pixelsWide == rhs.pixelsWide && lhs.pixelsHigh == rhs.pixelsHigh)
        var count = 0
        for y in Int(Double(lhs.pixelsHigh) * 0.40)..<Int(Double(lhs.pixelsHigh) * 0.60) {
            for x in Int(Double(lhs.pixelsWide) * 0.52)..<Int(Double(lhs.pixelsWide) * 0.94) {
                guard let a = lhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let b = rhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let difference = abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) +
                    abs(a.blueComponent - b.blueComponent) + abs(a.alphaComponent - b.alphaComponent)
                if difference > 0.12 { count += 1 }
            }
        }
        return count
    }

    private struct MeasuredControl {
        let frame: CGRect
        let ideal: CGSize
    }

    /// Internal labels must fit their natural text, not merely their outer NSHostingView.
    private static func layoutViolations(_ measured: [String: MeasuredControl], width: CGFloat,
                                         prefixes: [String], required: Set<String>) -> [String] {
        var failures = required.subtracting(Set(measured.keys)).sorted().map { "missing \($0)" }
        let relevant = measured.filter { id, _ in prefixes.contains { id.hasPrefix($0 + ".") } }
        for (id, value) in relevant {
            let frame = value.frame
            guard [frame.minX, frame.maxX, frame.width, frame.height, value.ideal.width, value.ideal.height].allSatisfy(\.isFinite),
                  frame.width > 0, frame.height > 0 else { failures.append("\(id) has empty/invalid geometry"); continue }
            if frame.minX < -2 || frame.maxX > width + 2 { failures.append("\(id) leaves horizontal viewport: \(frame)") }
            if id.hasSuffix(".label") {
                if frame.width + 2 < value.ideal.width { failures.append("\(id) squeezed \(frame.width) < natural \(value.ideal.width)") }
                if frame.height + 2 < value.ideal.height { failures.append("\(id) clips text height \(frame.height) < \(value.ideal.height)") }
                if frame.height > value.ideal.height * 1.4 + 1 { failures.append("\(id) wraps vertically \(frame.height) > single line \(value.ideal.height)") }
                let containerID = String(id.dropLast(".label".count)) + ".container"
                if let parent = relevant[containerID], frame.minX < parent.frame.minX - 2 || frame.maxX > parent.frame.maxX + 2 {
                    failures.append("\(id) leaves field container \(parent.frame)")
                }
            }
        }
        if let content = relevant["monitor.content.container"], let actions = relevant["monitor.actions.container"],
           actions.frame.minX < content.frame.minX - 2 || actions.frame.maxX > content.frame.maxX + 2 {
            failures.append("monitor actions leave their scroll content")
        }
        return failures
    }

    @MainActor
    private static func verifyMeaningfulControlLayouts(server: QuotaMonitor) {
        let widths: [CGFloat] = [1_400, 1_120, 1_080, 1_079, 1_030, 900, 760, 1_400]
        let sizes: [CGFloat] = [13, 21]
        let locales = [probeLocale]
        let appearances: [(String, ColorScheme, NSAppearance.Name)] = [("light", .light, .aqua), ("dark", .dark, .darkAqua)]
        var verified = 0
        // A long but synthetic account label exercises the footer without touching a real account.
        server.state = .connected("layout-regression-with-a-long-account-label@example.invalid")
        for section in [WorkspaceSection.monitor, .planner, .insights] {
            for locale in locales {
                for (theme, scheme, appearance) in appearances {
                    for fontSize in sizes {
                        var measured: [String: MeasuredControl] = [:]
                        let root = DashboardView(server: server, section: section, onControlLayout: { id, frame, ideal in
                            measured[id] = MeasuredControl(frame: frame, ideal: ideal)
                        })
                        .font(.system(size: fontSize))
                        .environment(\.locale, Locale(identifier: locale))
                        .preferredColorScheme(scheme)
                        .background(Color(nsColor: .windowBackgroundColor))
                        let view = NSHostingView(rootView: root)
                        view.frame = NSRect(x: 0, y: 0, width: 1_400, height: 760)
                        let window = NSWindow(contentRect: view.frame, styleMask: applicationWindowStyle, backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false
                        window.appearance = NSAppearance(named: appearance)
                        window.contentView = view
                        window.makeKeyAndOrderFront(nil)
                        let sequence: [CGFloat] = section == .monitor ? widths : [1_400, 1_120, 760, 1_120]
                        for (index, width) in sequence.enumerated() {
                            // The same native window and hosting view shrink and restore. Recreating a
                            // new view at each width cannot catch stale container measurements.
                            var prefixes = ["workspace"]
                            var required: Set<String> = ["workspace.label", "workspace.container", "workspace.toolbar.container"]
                            switch section {
                            case .monitor:
                                prefixes += ["monitor"]
                                required.formUnion(["monitor.service.label", "monitor.service.container", "monitor.content.container", "monitor.actions.container"])
                                if DashboardLayout.hasInlineInspector(width: width) {
                                    prefixes += ["glass", "panel"]
                                    required.formUnion(["glass.preset.label", "glass.appearance.label", "glass.refraction.label", "glass.tone.label",
                                                        "panel.chart.source.label", "panel.chart.style.label"])
                                }
                            case .planner:
                                prefixes += ["planner"]
                                required.insert("planner.provider.label")
                            case .insights:
                                prefixes += ["insights"]
                                required.formUnion(["insights.header.container", "insights.range.container", "insights.range.picker.container", "insights.content.container"])
                            }
                            for id in Array(required) where id.hasSuffix(".label") {
                                required.insert(String(id.dropLast(".label".count)) + ".container")
                            }
                            window.setContentSize(NSSize(width: width, height: 760))
                            let deadline = Date().addingTimeInterval(2)
                            var settled = false
                            repeat {
                                view.layoutSubtreeIfNeeded()
                                RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.02)))
                                settled = required.isSubset(of: Set(measured.keys)) &&
                                    abs((measured["workspace.toolbar.container"]?.frame.width ?? 0) - (width - 48)) < 2 &&
                                    abs(window.contentRect(forFrameRect: window.frame).width - width) < 2 &&
                                    abs(view.frame.width - width) < 2
                            } while !settled && Date() < deadline
                            var failures = layoutViolations(measured, width: width, prefixes: prefixes, required: required)
                            if !settled {
                                let message = "Layout settle timeout (2s): \(section.rawValue) \(locale) \(theme) font\(fontSize) width\(width); toolbar \(String(describing: measured["workspace.toolbar.container"]?.frame.width)); missing \(required.subtracting(Set(measured.keys)).sorted())"
                                failures.insert(message, at: 0)
                                let diagnostic = """
                                \(message)
                                Window frame=\(window.frame) contentRect=\(window.contentRect(forFrameRect: window.frame)) contentLayoutRect=\(window.contentLayoutRect)
                                Window contentMinSize=\(window.contentMinSize) minSize=\(window.minSize)
                                ContentView frame=\(String(describing: window.contentView?.frame)) bounds=\(String(describing: window.contentView?.bounds))
                                Hosting frame=\(view.frame) bounds=\(view.bounds) autoresizingMask=\(view.autoresizingMask) sizingOptions=\(view.sizingOptions) fittingSize=\(view.fittingSize)
                                Hosting intrinsicContentSize=\(view.intrinsicContentSize) translatesAutoresizingMaskIntoConstraints=\(view.translatesAutoresizingMaskIntoConstraints) isContentView=\(window.contentView === view)
                                Hosting horizontalConstraints=\(horizontalConstraints(in: view))
                                Parent type=\(view.superview.map { String(describing: type(of: $0)) } ?? "none") frame=\(String(describing: view.superview?.frame)) bounds=\(String(describing: view.superview?.bounds)) horizontalConstraints=\(horizontalConstraints(in: view.superview))

                                """
                                try? FileHandle.standardError.write(contentsOf: Data(diagnostic.utf8))
                            }
                            if !failures.isEmpty {
                                print("Control layout failed \(section.rawValue) \(locale) \(theme) font\(fontSize) width\(width):\n\(failures.joined(separator: "\n"))")
                                fflush(stdout)
                            }
                            precondition(failures.isEmpty, "internal control/label layout is compressed or clipped")
                            precondition(abs((measured["workspace.toolbar.container"]?.frame.width ?? 0) - (width - 48)) < 2,
                                         "internal toolbar did not update to the resized window width")
                            precondition(abs(window.contentRect(forFrameRect: window.frame).width - width) < 2, "native content rectangle did not resize to the requested width")
                            precondition(abs(view.frame.width - width) < 2, "native hosting view did not follow the requested width")
                            precondition(view.fittingSize.width <= width + 2, "window has horizontal overflow after resize")
                            verified += 1
                            if section == .monitor, theme == "dark", fontSize == 21 {
                                if width == 900 { saveLayoutImage(view, name: "monitor-cn21-900") }
                                if index == sequence.count - 1 { saveLayoutImage(view, name: "monitor-cn21-restored-1400") }
                            }
                        }
                        window.close()
                    }
                }
            }
        }

        // Expanded profile controls must also fit, not only the initially collapsed composer.
        for locale in locales {
            for (theme, scheme, appearance) in appearances {
                var measured: [String: MeasuredControl] = [:]
                let expanded = PlannerView(server: server, store: PlannerStore(), isActive: false, initialDetailsExpanded: true)
                    .font(.system(size: 21))
                    .environment(\.locale, Locale(identifier: locale))
                    .preferredColorScheme(scheme)
                    .environment(\.recordsControlLayout, true)
                    .coordinateSpace(name: ControlLayoutSpace.name)
                    .onPreferenceChange(ControlLayoutPreference.self) { values in
                        measured = values.reduce(into: [:]) { output, item in
                            if let frame = item.value.frame, let ideal = item.value.idealSize {
                                output[item.key] = MeasuredControl(frame: frame, ideal: ideal)
                            }
                        }
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                let view = NSHostingView(rootView: expanded)
                view.frame = NSRect(x: 0, y: 0, width: 1_120, height: 760)
                let window = NSWindow(contentRect: view.frame, styleMask: applicationWindowStyle, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: appearance)
                window.contentView = view
                window.makeKeyAndOrderFront(nil)
                for width in [1_120.0, 760, 1_120] {
                    window.setContentSize(NSSize(width: width, height: 760))
                    view.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                    var required: Set<String> = ["planner.provider.label", "planner.category.label", "planner.preference.label",
                        "planner.profile.规模.label", "planner.profile.不确定性.label", "planner.profile.风险.label"]
                    for id in Array(required) { required.insert(String(id.dropLast(".label".count)) + ".container") }
                    let failures = layoutViolations(measured, width: width, prefixes: ["planner"], required: required)
                    if !failures.isEmpty {
                        print("Expanded Planner layout failed \(locale) \(theme) font21 width\(width): \(failures.joined(separator: "; "))")
                        fflush(stdout)
                    }
                    precondition(failures.isEmpty, "expanded Planner profile labels are compressed or clipped")
                    precondition(abs(window.contentRect(forFrameRect: window.frame).width - width) < 2, "expanded Planner native window did not follow the requested width")
                    precondition(abs(view.frame.width - width) < 2, "expanded Planner hosting view did not follow the requested width")
                    precondition(view.fittingSize.width <= width + 2, "expanded Planner overflows its window")
                    verified += 1
                    if theme == "light", width == 760 { saveLayoutImage(view, name: "planner-cn21-expanded-760") }
                }
                window.close()
            }
        }

        // Negative control: render the actual native segmented Picker in a too-small row.
        // The CJK Text must compress or leave its field; the very same validator must reject it.
        var broken: [String: MeasuredControl] = [:]
        let negative = HStack(spacing: 12) {
            Text(L("监测服务")).controlLayoutProbe("negative.label")
            Picker(L("监测服务"), selection: .constant(AgentService.codex)) {
                Text("Codex").tag(AgentService.codex)
                Text(L("Claude Code · 实验性")).tag(AgentService.claude)
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
        }
        .frame(width: 180)
        .controlLayoutContainer("negative.container")
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(.system(size: 21))
        .preferredColorScheme(.light)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.recordsControlLayout, true)
        .coordinateSpace(name: ControlLayoutSpace.name)
        .onPreferenceChange(ControlLayoutPreference.self) { values in
            for (id, value) in values {
                if let frame = value.frame, let ideal = value.idealSize { broken[id] = MeasuredControl(frame: frame, ideal: ideal) }
            }
        }
        let badView = NSHostingView(rootView: negative)
        badView.frame = NSRect(x: 0, y: 0, width: 760, height: 240)
        let badWindow = NSWindow(contentRect: badView.frame, styleMask: applicationWindowStyle, backing: .buffered, defer: false)
        badWindow.isReleasedWhenClosed = false
        badWindow.appearance = NSAppearance(named: .aqua)
        badWindow.contentView = badView
        badWindow.makeKeyAndOrderFront(nil)
        badView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let negativeFailures = layoutViolations(broken, width: 760, prefixes: ["negative"], required: ["negative.label", "negative.container"])
        precondition(broken["negative.label"] != nil, "negative control label was not measured")
        precondition(negativeFailures.contains { $0.contains("negative.label") }, "layout gate accepted the known-bad compressed CJK picker label")
        print("Control layout negative control rejected: \(negativeFailures.joined(separator: "; "))")
        saveLayoutImage(badView, name: "negative-compressed-picker")
        badWindow.close()
        print("Internal control layout: PASS (\(verified) cases, locale/theme/font matrix, threshold widths, same-window shrink/restore, real negative control)")
    }

    @MainActor
    private static func horizontalConstraints(in view: NSView?) -> String {
        let attributes: Set<NSLayoutConstraint.Attribute> = [.left, .right, .leading, .trailing, .width, .centerX]
        return view?.constraints.filter { attributes.contains($0.firstAttribute) || attributes.contains($0.secondAttribute) }
            .map(\.description).joined(separator: " | ") ?? "none"
    }

    @MainActor
    private static func saveLayoutImage(_ view: NSView, name: String) {
        guard let output = ProcessInfo.processInfo.environment["TALLYGENT_UI_CHECKS"],
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let prefix = probeLanguage == "zh-Hans" ? "" : probeLanguage + "-"
        try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(prefix + name + ".png"))
    }
}

@MainActor
private final class DragProbeWindow: DesktopGlassWindow {
    var forwardedEvent: NSEvent?
    override func performDrag(with event: NSEvent) { forwardedEvent = event }
}

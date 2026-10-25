import AppKit
import SwiftUI

// No account connection or persistent settings are needed for this window probe.
@MainActor
final class QuotaMonitor: ObservableObject {
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
    init() {
        let path = ProcessInfo.processInfo.environment["TALLYGENT_HISTORY_DB"] ?? FileManager.default.temporaryDirectory.appendingPathComponent("tallygent-ui-\(UUID().uuidString)/history.sqlite").path
        let url = URL(fileURLWithPath: path)
        let date = Date()
        for index in 0...40 {
            let values = QuotaObservation.batch(provider: .codex, source: .codexRateLimits,
                receivedAt: date.addingTimeInterval(Double(index - 40) * 60),
                fiveHour: .init(usedPercent: 18 - (40 - index) / 3, windowDurationMinutes: 300, resetsAt: date.addingTimeInterval(14_400)),
                weekly: .init(usedPercent: 28 - (40 - index) / 10, windowDurationMinutes: 10_080, resetsAt: date.addingTimeInterval(6 * 86_400)),
                accountScope: String(repeating: "b", count: 64))
            try! ObservationHistory.append(values, at: url, now: date)
        }
        insights = InsightsStore(url: url)
        Task { await insights.reload(force: true) }
    }
    func setCollection(_ provider: AgentService, enabled: Bool) async {}
    func refreshModelCatalog() {}
    func plannerQuota() -> PlannerQuota {
        PlannerQuota(provider: service, scope: nil, source: "隔离测试", receivedAt: .distantPast, windows: [], connected: false)
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
    @MainActor
    static func main() {
        _ = NSApplication.shared
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
        for width in [760.0, 1_030, 1_120, 1_400] {
            var frames: [DesktopPanelMode: CGRect] = [:]
            let dashboard = NSHostingView(rootView: DashboardView(server: server, onGalleryLayout: { frames[$0] = $1 })
                .background(Color(nsColor: .windowBackgroundColor)))
            dashboard.frame = NSRect(x: 0, y: 0, width: width, height: 720)
            let dashboardWindow = NSWindow(contentRect: dashboard.frame, styleMask: [.titled], backing: .buffered, defer: false)
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
            let host = NSWindow(contentRect: planner.frame, styleMask: [.titled], backing: .buffered, defer: false)
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
            let host = NSWindow(contentRect: insights.frame, styleMask: [.titled], backing: .buffered, defer: false)
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
        let locales = ["zh_CN", "en_US"]
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
                        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false
                        window.appearance = NSAppearance(named: appearance)
                        window.contentView = view
                        window.makeKeyAndOrderFront(nil)
                        let sequence: [CGFloat] = section == .monitor ? widths : [1_120, 760, 1_120]
                        for (index, width) in sequence.enumerated() {
                            // The same native window and hosting view shrink and restore. Recreating a
                            // new view at each width cannot catch stale container measurements.
                            window.setContentSize(NSSize(width: width, height: 760))
                            view.layoutSubtreeIfNeeded()
                            RunLoop.main.run(until: Date().addingTimeInterval(index == 0 ? 0.3 : 0.12))
                            view.layoutSubtreeIfNeeded()
                            var prefixes = ["workspace"]
                            var required: Set<String> = ["workspace.label", "workspace.container", "workspace.toolbar.container"]
                            switch section {
                            case .monitor:
                                prefixes += ["monitor"]
                                required.formUnion(["monitor.service.label", "monitor.service.container", "monitor.content.container", "monitor.actions.container"])
                                if DashboardLayout.hasInlineInspector(width: width) {
                                    prefixes += ["glass"]
                                    required.formUnion(["glass.preset.label", "glass.appearance.label", "glass.refraction.label", "glass.tone.label"])
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
                            let failures = layoutViolations(measured, width: width, prefixes: prefixes, required: required)
                            if !failures.isEmpty {
                                print("Control layout failed \(section.rawValue) \(locale) \(theme) font\(fontSize) width\(width):\n\(failures.joined(separator: "\n"))")
                                fflush(stdout)
                            }
                            precondition(failures.isEmpty, "internal control/label layout is compressed or clipped")
                            precondition(abs((measured["workspace.toolbar.container"]?.frame.width ?? 0) - (width - 48)) < 2,
                                         "internal toolbar did not update to the resized window width")
                            precondition(view.fittingSize.width <= width + 2, "window has horizontal overflow after resize")
                            verified += 1
                            if section == .monitor, locale == "zh_CN", theme == "dark", fontSize == 21 {
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
                let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
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
                    precondition(view.fittingSize.width <= width + 2, "expanded Planner overflows its window")
                    verified += 1
                    if locale == "zh_CN", theme == "light", width == 760 { saveLayoutImage(view, name: "planner-cn21-expanded-760") }
                }
                window.close()
            }
        }

        // Negative control: render the actual native segmented Picker in a too-small row.
        // The CJK Text must compress or leave its field; the very same validator must reject it.
        var broken: [String: MeasuredControl] = [:]
        let negative = HStack(spacing: 12) {
            Text("监测服务").controlLayoutProbe("negative.label")
            Picker("监测服务", selection: .constant(AgentService.codex)) {
                Text("Codex").tag(AgentService.codex)
                Text("Claude Code · 实验性").tag(AgentService.claude)
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
        }
        .frame(width: 180)
        .controlLayoutContainer("negative.container")
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(.system(size: 21))
        .environment(\.recordsControlLayout, true)
        .coordinateSpace(name: ControlLayoutSpace.name)
        .onPreferenceChange(ControlLayoutPreference.self) { values in
            for (id, value) in values {
                if let frame = value.frame, let ideal = value.idealSize { broken[id] = MeasuredControl(frame: frame, ideal: ideal) }
            }
        }
        let badView = NSHostingView(rootView: negative)
        badView.frame = NSRect(x: 0, y: 0, width: 760, height: 240)
        let badWindow = NSWindow(contentRect: badView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        badWindow.isReleasedWhenClosed = false
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
    private static func saveLayoutImage(_ view: NSView, name: String) {
        guard let output = ProcessInfo.processInfo.environment["TALLYGENT_UI_CHECKS"],
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
    }
}

@MainActor
private final class DragProbeWindow: DesktopGlassWindow {
    var forwardedEvent: NSEvent?
    override func performDrag(with event: NSEvent) { forwardedEvent = event }
}

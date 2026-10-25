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
            if let output = ProcessInfo.processInfo.environment["TALLYGENT_UI_CHECKS"],
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
        print("Desktop panel mouse routing and window-level probe passed.")
    }
}

@MainActor
private final class DragProbeWindow: DesktopGlassWindow {
    var forwardedEvent: NSEvent?
    override func performDrag(with event: NSEvent) { forwardedEvent = event }
}

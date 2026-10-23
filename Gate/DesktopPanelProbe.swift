import AppKit
import SwiftUI

// No account connection or persistent settings are needed for this window probe.
@MainActor
final class CodexAppServer: ObservableObject {
    enum State: Equatable {
        case disconnected, connecting, signingIn, connected(String?), failed(String)
    }
    @Published var state = State.connected(nil)
    @Published var snapshot = UsageSnapshot.placeholder
    func connect() {}
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
        let server = CodexAppServer()
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
        let dashboard = NSHostingView(rootView: DashboardView(server: server))
        dashboard.frame = NSRect(x: 0, y: 0, width: 1030, height: 560)
        let dashboardWindow = NSWindow(contentRect: dashboard.frame, styleMask: [.titled], backing: .buffered, defer: false)
        dashboardWindow.isReleasedWhenClosed = false
        dashboardWindow.contentView = dashboard
        dashboardWindow.makeKeyAndOrderFront(nil)
        dashboard.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        guard let gallery = scrollViews(in: dashboard).first(where: { ($0.documentView?.frame.width ?? 0) > 1800 }) else {
            preconditionFailure("native panel gallery scroll view is missing")
        }
        let expectedOffset = CGFloat(DesktopPanelMode.allCases.firstIndex(of: .stored())!) * 680
        precondition(abs(gallery.contentView.bounds.minX - expectedOffset) < 2, "initial gallery page does not match the persisted panel mode")
        print("Dashboard fitted height: \(dashboard.fittingSize.height), gallery offset: \(gallery.contentView.bounds.minX)")
        precondition(dashboard.fittingSize.height >= 559, "restored dashboard height clips panel selector controls")
        dashboardWindow.close()
        print("Desktop panel mouse routing and window-level probe passed.")
    }
}

@MainActor
private final class DragProbeWindow: DesktopGlassWindow {
    var forwardedEvent: NSEvent?
    override func performDrag(with event: NSEvent) { forwardedEvent = event }
}

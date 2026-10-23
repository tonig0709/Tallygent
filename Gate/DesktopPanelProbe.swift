import AppKit
import SwiftUI

// No account connection or persistent settings are needed for this window probe.
@MainActor
final class CodexAppServer: ObservableObject {
    @Published var snapshot = UsageSnapshot.placeholder
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
        let size = CGSize(width: 680, height: 300)
        precondition(!DesktopGlassPanelView.isNearEdge(CGPoint(x: 340, y: 150), size: size), "chrome stays visible at panel center")
        for point in [CGPoint(x: 5, y: 150), CGPoint(x: 675, y: 150), CGPoint(x: 340, y: 5), CGPoint(x: 340, y: 295)] {
            precondition(DesktopGlassPanelView.isNearEdge(point, size: size), "chrome fails to appear at a panel edge")
        }
        precondition(!DesktopGlassPanelView.isNearEdge(CGPoint(x: -1, y: 150), size: size), "chrome stays visible outside panel")
        precondition(window.isMovable && !window.ignoresMouseEvents, "desktop panel rejects mouse interaction")
        precondition(window.level.rawValue > Int(CGWindowLevelForKey(.desktopIconWindow)), "desktop panel is hidden behind Finder's event layer")
        precondition(window.level.rawValue < NSWindow.Level.normal.rawValue, "desktop panel covers normal application windows")

        let dragRegion = DesktopPanelDragRegion.DragView(frame: NSRect(x: 36, y: 278, width: 608, height: 22))
        window.contentView?.addSubview(dragRegion)
        precondition(dragRegion.acceptsFirstMouse(for: nil), "inactive panel requires an extra click before dragging")
        precondition(window.contentView?.hitTest(NSPoint(x: 100, y: 290)) === dragRegion, "drag region does not receive header mouse events")
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 100, y: 290), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1
        )!
        dragRegion.mouseDown(with: event)
        precondition(window.forwardedEvent === event, "header does not forward the original mouse event to native window dragging")
        window.close()
        print("Desktop panel mouse routing and window-level probe passed.")
    }
}

@MainActor
private final class DragProbeWindow: DesktopGlassWindow {
    var forwardedEvent: NSEvent?
    override func performDrag(with event: NSEvent) { forwardedEvent = event }
}

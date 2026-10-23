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
private final class DragProbeWindow: NSWindow {
    var forwardedEvent: NSEvent?
    override func performDrag(with event: NSEvent) { forwardedEvent = event }
}

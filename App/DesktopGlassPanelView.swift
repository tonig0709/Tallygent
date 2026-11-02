import AppKit
import CoreGraphics
import SwiftUI

struct DesktopGlassPanelView: View {
    static let windowID = "desktop-glass-panel"

    @ObservedObject var server: QuotaMonitor
    @ObservedObject private var insights: InsightsStore
    @AppStorage(DesktopPanelMode.defaultsKey) private var modeRaw = DesktopPanelMode.large.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(GlassSettingKeys.surfaceStyle) private var surfaceStyleRaw = GlassSurfaceStyle.tinted.rawValue
    @AppStorage(GlassSettingKeys.appearance) private var appearanceRaw = GlassAppearanceMode.dark.rawValue
    @AppStorage(GlassSettingKeys.opacity) private var glassOpacity = WidgetGlassOpacity.defaultValue
    @AppStorage(GlassSettingKeys.edgeStrength) private var edgeStrength = 0.55
    @AppStorage(GlassSettingKeys.pointerHighlightIntensity) private var pointerHighlightIntensity = 1.0
    @AppStorage(GlassSettingKeys.elasticity) private var elasticity = 0.15
    @AppStorage(GlassSettingKeys.displacement) private var displacement = 0.35
    @AppStorage(GlassSettingKeys.blurAmount) private var blurAmount = 0.20
    @AppStorage(GlassSettingKeys.saturation) private var saturation = 1.40
    @AppStorage(GlassSettingKeys.dispersion) private var dispersion = 0.08
    @AppStorage(GlassSettingKeys.cornerRadius) private var cornerRadius = 30.0
    @AppStorage(GlassSettingKeys.tone) private var toneRaw = GlassTone.neutral.rawValue
    @AppStorage(GlassSettingKeys.refractionMode) private var refractionModeRaw = GlassRefractionMode.standard.rawValue
    @AppStorage(PanelChartSource.defaultsKey) private var chartSourceRaw = PanelChartSource.sevenDayTokens.rawValue
    @AppStorage(PanelChartStyle.defaultsKey) private var chartStyleRaw = PanelChartStyle.bars.rawValue
    @State private var showsControls = false
    @State private var hoverVector = CGSize.zero
    @State private var isHovering = false
    @State private var showsChrome = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor
    init(server: QuotaMonitor) {
        self.server = server
        self.insights = server.insights
    }

    private var panelSnapshot: UsageSnapshot {
        var value = server.snapshot
        value.appearance = isLight ? .light : .dark
        return value
    }

    private var mode: DesktopPanelMode { DesktopPanelMode(rawValue: modeRaw) ?? .large }

    var body: some View {
        QuotaPanelContent(mode: mode, snapshot: panelSnapshot, glassOpacity: glassOpacity, trend: panelTrend)
            .id(server.service == .claude ? server.snapshot.claudePresentationKey() : "codex")
            .frame(width: mode.size.width, height: mode.size.height)
            .background {
                LiquidGlassSurface(
                    isLight: isLight,
                    opacity: glassOpacity,
                    accent: .blue,
                    cornerRadius: cornerRadius,
                    edgeStrength: edgeStrength,
                    tone: glassTone.color,
                    dispersion: dispersion,
                    elasticity: elasticity,
                    displacement: displacement,
                    blurAmount: blurAmount,
                    saturation: saturation,
                    refractionMode: refractionMode,
                    surfaceStyle: surfaceStyle,
                    hoverVector: reduceMotion ? .zero : hoverVector,
                    isHovering: isHovering,
                    nativeClearBackdropProvided: true,
                    pointerHighlightIntensity: pointerHighlightIntensity
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                    .opacity(showsChrome || showsControls ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .overlay {
                // The content is read-only; native window dragging can cover it all.
                // Controls below remain above this layer and keep their own clicks.
                DesktopPanelDragRegion(cornerRadius: cornerRadius, onPointer: updateHover)
            }
            .overlay(alignment: .topLeading) {
                Button(action: closePanel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isLight ? .black.opacity(0.62) : .white.opacity(0.72))
                .background(.thinMaterial, in: Circle())
                .padding(6)
                .help("关闭桌面玻璃面板")
                .accessibilityLabel("关闭桌面玻璃面板")
                .opacity(showsChrome || showsControls ? 1 : 0)
                .allowsHitTesting(showsChrome || showsControls)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showsControls.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isLight ? .black.opacity(0.62) : .white.opacity(0.72))
                .background(.thinMaterial, in: Circle())
                .padding(12)
                .help("调整桌面玻璃面板")
                .opacity(showsChrome || showsControls ? 1 : 0)
                .allowsHitTesting(showsChrome || showsControls)
                .popover(isPresented: $showsControls, arrowEdge: .bottom) {
                    controls
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showsChrome)
            .onDisappear { showsChrome = false }
            .background(DesktopPanelWindowConfigurator(size: mode.size, clearMaterial: surfaceStyle == .nativeClear, cornerRadius: cornerRadius, blurAmount: blurAmount))
            .ignoresSafeArea()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("桌面玻璃面板")
                .font(.headline)
            Picker("监测服务", selection: Binding(get: { server.service }, set: server.selectService)) {
                ForEach(AgentService.allCases) { Text($0.title).tag($0) }
            }

            ScrollView {
                GlassSettingsView(compact: true, onSettingsChange: server.updateGlassSettings)
            }
            .frame(height: 500)

            HStack {
                Button("立即刷新") { server.refresh() }
                Spacer()
                Button("关闭面板", action: closePanel)
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    private var appearanceMode: GlassAppearanceMode {
        GlassAppearanceMode(rawValue: appearanceRaw) ?? .dark
    }

    private var panelTrend: PanelTrendPresentation {
        .make(report: insights.panelReport, provider: server.service, scope: server.plannerQuota().scope,
              source: PanelChartSource(rawValue: chartSourceRaw) ?? .sevenDayTokens,
              style: PanelChartStyle(rawValue: chartStyleRaw) ?? .bars,
              now: insights.panelReport.generatedAt)
    }

    private func closePanel() {
        showsControls = false
        DesktopPanelController.shared.close()
    }

    private var glassTone: GlassTone {
        GlassTone(rawValue: toneRaw) ?? .neutral
    }

    private var refractionMode: GlassRefractionMode {
        GlassRefractionMode(rawValue: refractionModeRaw) ?? .standard
    }

    private var isLight: Bool {
        surfaceStyle != .nativeClear && appearanceMode.isLight(in: colorScheme)
    }

    private var surfaceStyle: GlassSurfaceStyle { GlassSurfaceStyle(rawValue: surfaceStyleRaw) ?? .tinted }

    private func updateHover(_ location: CGPoint?) {
        if let location {
            showsChrome = Self.isNearEdge(location, size: mode.size)
            isHovering = true
            hoverVector = CGSize(
                width: min(1, max(-1, location.x / mode.size.width * 2 - 1)),
                height: min(1, max(-1, location.y / mode.size.height * 2 - 1))
            )
        } else {
            showsChrome = false
            isHovering = false
            if reduceMotion {
                hoverVector = .zero
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 1)) {
                    hoverVector = .zero
                }
            }
        }
    }

    static func isNearEdge(_ point: CGPoint, size: CGSize) -> Bool {
        let edge: CGFloat = 40
        return CGRect(origin: .zero, size: size).contains(point) &&
            (point.x < edge || point.y < edge || point.x >= size.width - edge || point.y >= size.height - edge)
    }
}

// Use AppKit's native window drag loop; SwiftUI content is not a window background.
struct DesktopPanelDragRegion: NSViewRepresentable {
    var cornerRadius: Double = 30
    var onPointer: ((CGPoint?) -> Void)? = nil

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.cornerRadius = cornerRadius
        view.onPointer = onPointer
        return view
    }
    func updateNSView(_ view: DragView, context: Context) {
        view.cornerRadius = cornerRadius
        view.onPointer = onPointer
    }

    final class DragView: NSView {
        var cornerRadius: Double = 30
        var onPointer: ((CGPoint?) -> Void)?
        private var pointerArea: NSTrackingArea?
        override var isFlipped: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let pointerArea { removeTrackingArea(pointerArea) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
            addTrackingArea(area)
            pointerArea = area
        }
        override func mouseMoved(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let outline = RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous).path(in: bounds)
            onPointer?(outline.contains(point) ? point : nil)
        }
        override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
        override func mouseExited(with event: NSEvent) { onPointer?(nil) }
        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            let radius = min(CGFloat(cornerRadius), min(bounds.width, bounds.height) / 2)
            // Transparent rounded corners must not intercept desktop clicks.
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: bounds).contains(local) ? self : nil
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}


struct DesktopPanelWindowConfigurator: NSViewRepresentable {
    var size = DesktopPanelMode.large.size
    var clearMaterial = false
    var cornerRadius: Double = 30
    var blurAmount: Double = 0
    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.configuration = self
        return view
    }

    func updateNSView(_ view: WindowView, context: Context) {
        view.configuration = self
        view.scheduleConfiguration()
    }

    final class WindowView: NSView {
        var configuration: DesktopPanelWindowConfigurator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleConfiguration()
        }

        func scheduleConfiguration() {
            // A chart can mount this view after updateNSView. Apply on attachment
            // too, and read the latest settings rather than a queued stale copy.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.configuration?.configure(window)
            }
        }
    }

    func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        (window.contentView as? DesktopGlassBackdropHost)?.configure(clear: clearMaterial, cornerRadius: cornerRadius, blurAmount: blurAmount)
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Remove title-bar layout as well as paint; the panel subclass provides focus.
        window.styleMask.remove(.titled)
        window.styleMask.insert(.fullSizeContentView)
        if window.frame.size != size {
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            window.contentMinSize = .zero
            window.contentMaxSize = NSSize(width: 10_000, height: 10_000)
            window.setContentSize(size)
            window.setFrameTopLeftPoint(topLeft)
        }
        window.contentMinSize = size
        window.contentMaxSize = size
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        // Stay below ordinary app windows, above Finder's desktop/icon windows.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.invalidateShadow()
    }
}

/// THESIS: Native popover optics, not an opaque light/dark rectangle.
/// OWN-WORLD: The OS owns backdrop blur; one bounded specular field follows input.
/// STORY: Read quota on the real desktop and move the same panel normally.
/// FIRST VIEWPORT: Existing three sizes, content and controls stay unchanged.
/// FORM: A native material root below the hosting view, outside SwiftUI flattening.
final class DesktopGlassBackdropHost: NSView {
    let material = NSVisualEffectView()
    private var opticalRadius: Double = 30
    init(content: NSView) {
        super.init(frame: content.frame)
        for child in [material, content] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
            NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: leadingAnchor), child.trailingAnchor.constraint(equalTo: trailingAnchor),
                                         child.topAnchor.constraint(equalTo: topAnchor), child.bottomAnchor.constraint(equalTo: bottomAnchor)])
        }
    }
    required init?(coder: NSCoder) { return nil }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let outline = RoundedRectangle(cornerRadius: CGFloat(opticalRadius), style: .continuous).path(in: bounds)
        return outline.contains(local) ? super.hitTest(point) : nil
    }
    func configure(clear: Bool, cornerRadius: Double, blurAmount: Double) {
        opticalRadius = min(64, max(10, cornerRadius))
        material.isHidden = !clear
        NativeClearMaterial.configure(material, cornerRadius: cornerRadius, blurAmount: blurAmount)
    }
}

@MainActor
final class DesktopPanelController {
    static let shared = DesktopPanelController()
    private var panel: DesktopGlassWindow?
    var isVisible: Bool { panel?.isVisible == true }

    func show(server: QuotaMonitor) {
        if panel == nil {
            let size = DesktopPanelMode.stored().size
            let window = DesktopGlassWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.title = L("Tallygent 桌面玻璃面板")
            window.identifier = NSUserInterfaceItemIdentifier(DesktopGlassPanelView.windowID)
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.contentView = DesktopGlassBackdropHost(content: NSHostingView(rootView: DesktopGlassPanelView(server: server)))
            if !window.setFrameUsingName(DesktopGlassPanelView.windowID) { window.center() }
            let settings = GlassSettingsSnapshot.load()
            DesktopPanelWindowConfigurator(size: size, clearMaterial: settings.resolvedSurfaceStyle == .nativeClear, cornerRadius: settings.cornerRadius, blurAmount: settings.blurAmount).configure(window)
            window.setFrameAutosaveName(DesktopGlassPanelView.windowID)
            panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

class DesktopGlassWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

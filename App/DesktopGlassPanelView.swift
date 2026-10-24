import AppKit
import CoreGraphics
import SwiftUI

struct DesktopGlassPanelView: View {
    static let windowID = "desktop-glass-panel"

    @ObservedObject var server: QuotaMonitor
    @AppStorage(DesktopPanelMode.defaultsKey) private var modeRaw = DesktopPanelMode.large.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(GlassSettingKeys.appearance) private var appearanceRaw = GlassAppearanceMode.dark.rawValue
    @AppStorage(GlassSettingKeys.opacity) private var glassOpacity = WidgetGlassOpacity.defaultValue
    @AppStorage(GlassSettingKeys.edgeStrength) private var edgeStrength = 0.55
    @AppStorage(GlassSettingKeys.elasticity) private var elasticity = 0.15
    @AppStorage(GlassSettingKeys.displacement) private var displacement = 0.35
    @AppStorage(GlassSettingKeys.blurAmount) private var blurAmount = 0.20
    @AppStorage(GlassSettingKeys.saturation) private var saturation = 1.40
    @AppStorage(GlassSettingKeys.dispersion) private var dispersion = 0.08
    @AppStorage(GlassSettingKeys.cornerRadius) private var cornerRadius = 30.0
    @AppStorage(GlassSettingKeys.tone) private var toneRaw = GlassTone.neutral.rawValue
    @AppStorage(GlassSettingKeys.refractionMode) private var refractionModeRaw = GlassRefractionMode.standard.rawValue
    @State private var showsControls = false
    @State private var hoverVector = CGSize.zero
    @State private var isHovering = false
    @State private var showsChrome = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var panelSnapshot: UsageSnapshot {
        var value = server.snapshot
        value.appearance = isLight ? .light : .dark
        return value
    }

    private var mode: DesktopPanelMode { DesktopPanelMode(rawValue: modeRaw) ?? .large }

    var body: some View {
        QuotaPanelContent(mode: mode, snapshot: panelSnapshot, glassOpacity: glassOpacity)
            .id(server.service == .claude ? server.snapshot.claudePresentationKey() : "codex")
            .frame(width: mode.size.width, height: mode.size.height)
            .background {
                DesktopGlassSurface(
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
                    hoverVector: hoverVector,
                    isHovering: isHovering
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
                DesktopPanelDragRegion(cornerRadius: cornerRadius)
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
            .onContinuousHover(perform: updateHover)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showsChrome)
            .onDisappear { showsChrome = false }
            .background(DesktopPanelWindowConfigurator(size: mode.size))
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
        appearanceMode.isLight(in: colorScheme)
    }

    private func updateHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            showsChrome = Self.isNearEdge(location, size: mode.size)
            isHovering = true
            hoverVector = CGSize(
                width: min(1, max(-1, location.x / mode.size.width * 2 - 1)),
                height: min(1, max(-1, location.y / mode.size.height * 2 - 1))
            )
        case .ended:
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

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.cornerRadius = cornerRadius
        return view
    }
    func updateNSView(_ view: DragView, context: Context) {
        view.cornerRadius = cornerRadius
    }

    final class DragView: NSView {
        var cornerRadius: Double = 30
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

private struct DesktopGlassSurface: View {
    let isLight: Bool
    let opacity: Double
    let accent: Color
    let cornerRadius: Double
    let edgeStrength: Double
    let tone: Color
    let dispersion: Double
    let elasticity: Double
    let displacement: Double
    let blurAmount: Double
    let saturation: Double
    let refractionMode: GlassRefractionMode
    let hoverVector: CGSize
    let isHovering: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resolvedOpacity: Double {
        reduceTransparency ? 1 : WidgetGlassOpacity.clamped(opacity)
    }

    private var filmOpacity: Double {
        if isLight {
            return 0.12 + WidgetGlassOpacity.normalized(resolvedOpacity) * 0.68
        }
        return WidgetGlassOpacity.darkFilmOpacity(resolvedOpacity)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
    }

    private var filmColor: Color {
        (isLight ? Color.white : Color.black).opacity(filmOpacity)
    }

    private var outerBorder: Color {
        isLight
            ? .white.opacity(0.48 + edgeStrength * 0.42)
            : .white.opacity(0.12 + edgeStrength * 0.22)
    }

    private var innerBorder: Color {
        isLight ? accent.opacity(0.18) : .white.opacity(0.09)
    }

    private var borderWidth: CGFloat {
        CGFloat(0.65 + edgeStrength * 0.75 + displacement * 1.25)
    }

    private var highlightOpacity: Double {
        (isLight ? 0.46 : 0.1) + edgeStrength * 0.24
    }

    private var highlightCenter: UnitPoint {
        UnitPoint(
            x: min(1, max(0, 0.5 + hoverVector.width * 0.5)),
            y: min(1, max(0, 0.5 + hoverVector.height * 0.5))
        )
    }

    private var motionStrength: CGFloat {
        reduceMotion ? 0 : CGFloat(min(1, max(0, elasticity)))
    }

    private var highlightStart: UnitPoint {
        UnitPoint(x: min(1, max(0, 0.5 - hoverVector.width * 0.5)), y: min(1, max(0, 0.5 - hoverVector.height * 0.5)))
    }

    private var highlightEnd: UnitPoint {
        UnitPoint(x: min(1, max(0, 0.5 + hoverVector.width * 0.5)), y: min(1, max(0, 0.5 + hoverVector.height * 0.5)))
    }

    private var directionalHighlight: some View {
        ZStack {
            shape.strokeBorder(
                LinearGradient(
                    colors: [.clear, .white.opacity(isLight ? 0.96 : 0.68), .clear],
                    startPoint: highlightStart,
                    endPoint: highlightEnd
                ),
                lineWidth: CGFloat(1.4 + edgeStrength * 1.8 + displacement * 2)
            )
            .blendMode(.screen)
            shape.strokeBorder(
                RadialGradient(
                    colors: [.white.opacity(isLight ? 0.82 : 0.48), .clear],
                    center: highlightCenter,
                    startRadius: 0,
                    endRadius: 180
                ),
                lineWidth: CGFloat(1 + displacement * 3)
            )
            .blendMode(.overlay)
        }
        .opacity(isHovering ? 1 : 0)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    private var chromaticEdge: some View {
        let offset = CGFloat(optics.edgeOffset)
        return ZStack {
            shape.inset(by: offset + CGFloat(optics.edgeWidth) / 2)
                .strokeBorder(.red.opacity(optics.edgeOpacity), lineWidth: CGFloat(optics.edgeWidth))
                .offset(x: -offset, y: offset * 0.4)
            shape.inset(by: offset + CGFloat(optics.edgeWidth) / 2)
                .strokeBorder(.cyan.opacity(optics.edgeOpacity), lineWidth: CGFloat(optics.edgeWidth))
                .offset(x: offset, y: -offset * 0.4)
        }
        .allowsHitTesting(false)
    }

    var body: some View {
        ZStack {
            DesktopVisualEffectView(isLight: isLight)
            shape.fill(filmColor)
            shape.fill(frostColor)
            shape.fill(tone.opacity(toneOpacity))
            borderLayer
            topHighlight
            directionalHighlight
            restingRefraction
            chromaticEdge
            elasticHighlight
        }
    }

    private var frostColor: Color {
        // Public macOS materials own backdrop blur. This controls visible frosting,
        // not a fictitious blur radius, and leaves fully opaque dark glass black.
        (isLight ? Color.white : Color(white: 0.28))
            .opacity(optics.frostOpacity * (1 - WidgetGlassOpacity.normalized(resolvedOpacity)))
    }

    private var optics: GlassOptics { GlassOptics(blurAmount: blurAmount, dispersion: dispersion) }

    private var toneOpacity: Double { 0.035 * saturation }

    private var elasticHighlight: some View {
        VStack {
            HStack {
                Capsule()
                    .fill(.white.opacity((isLight ? 0.30 : 0.16) + elasticity * 0.34))
                    .frame(width: CGFloat(42 + elasticity * 118), height: CGFloat(1 + elasticity * 4.5))
                    .blur(radius: CGFloat(elasticity * 1.2))
                    .offset(x: hoverVector.width * motionStrength * 16, y: hoverVector.height * motionStrength * 8)
                    .padding(.leading, CGFloat(18 + displacement * 10))
                    .padding(.top, CGFloat(1.2 + displacement * 2.8))
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    private var borderLayer: some View {
        ZStack {
            shape.strokeBorder(outerBorder, lineWidth: 0.65 + CGFloat(edgeStrength) * 1.35)
            shape.inset(by: 1.2 + displacement * 5.2)
                .strokeBorder(innerBorder.opacity(0.65 + displacement * 0.35), lineWidth: 0.5 + displacement * 2.5)
        }
    }

    private var topHighlight: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(highlightOpacity))
                .frame(height: 0.75)
                .padding(.horizontal, 36)
                .padding(.top, 1)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var restingRefraction: some View {
        switch refractionMode {
        case .standard:
            shape.inset(by: CGFloat(1 + displacement * 4)).strokeBorder(
                LinearGradient(colors: [.white.opacity(0.16 + displacement * 0.48), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: CGFloat(1 + displacement * 3.2)
            )
        case .polar:
            shape.inset(by: CGFloat(1 + displacement * 4)).strokeBorder(
                AngularGradient(colors: [.white.opacity(0.20 + displacement * 0.52), .clear, accent.opacity(0.16 * saturation), .clear], center: .center),
                lineWidth: CGFloat(1.2 + displacement * 4)
            )
        case .prominent:
            shape.inset(by: CGFloat(1 + displacement * 4)).strokeBorder(
                LinearGradient(colors: [.white.opacity(0.30 + displacement * 0.58), accent.opacity(0.20 * saturation), .clear, .black.opacity(0.10 + displacement * 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: CGFloat(1.8 + displacement * 5)
            )
        }
    }
}

private struct DesktopVisualEffectView: NSViewRepresentable {
    let isLight: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)
    }
}

struct DesktopPanelWindowConfigurator: NSViewRepresentable {
    var size = DesktopPanelMode.large.size
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false
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
            window.title = "Tallygent 桌面玻璃面板"
            window.identifier = NSUserInterfaceItemIdentifier(DesktopGlassPanelView.windowID)
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.contentView = NSHostingView(rootView: DesktopGlassPanelView(server: server))
            if !window.setFrameUsingName(DesktopGlassPanelView.windowID) { window.center() }
            DesktopPanelWindowConfigurator(size: size).configure(window)
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

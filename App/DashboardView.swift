import SwiftUI

struct DashboardView: View {
    @ObservedObject var server: CodexAppServer
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
    @State private var showsGlassInspector = true
    @AppStorage(DesktopPanelMode.defaultsKey) private var modeRaw = DesktopPanelMode.large.rawValue
    @State private var selectedMode: DesktopPanelMode? = .stored()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("桌面面板").font(.title2.weight(.semibold))
                    Text("左右滑动选择 · 桌面仅显示一个面板")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { select(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("上一个面板")
                    .disabled(mode == .small)
                Button { select(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("下一个面板")
                    .disabled(mode == .large)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(DesktopPanelMode.allCases) { page in
                        QuotaPanelContent(mode: page, snapshot: previewSnapshot, glassOpacity: glassOpacity)
                            .frame(width: page.size.width, height: page.size.height)
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
                                    refractionMode: refractionMode
                                )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous))
                            .frame(width: 680, height: 300)
                            .id(page)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selectedMode)
            .frame(width: 680, height: 300)

            HStack(spacing: 16) {
                ForEach(DesktopPanelMode.allCases) { page in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1)) {
                            selectedMode = page
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Circle().fill(mode == page ? Color.accentColor : .secondary.opacity(0.25))
                                .frame(width: 6, height: 6)
                            Text(page.title).font(.caption.weight(mode == page ? .semibold : .regular))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == page ? .isSelected : [])
                }
            }

            HStack(spacing: 12) {
                Label(statusText, systemImage: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.callout.weight(.medium))
                Spacer()

                Button("玻璃设置", systemImage: "slider.horizontal.3") {
                    showsGlassInspector.toggle()
                }
                Button("桌面玻璃面板") {
                    DesktopPanelController.shared.show(server: server)
                }
                .help("打开一个独立透明、不会改变其他图标外观的桌面面板")
                Button("刷新") { server.refresh() }
                    .disabled(server.state == .connecting)
                if case .disconnected = server.state {
                    Button("连接 Codex") { server.connect() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(24)
        .frame(minWidth: 730, minHeight: 400)
        .inspector(isPresented: $showsGlassInspector) {
            ScrollView {
                GlassSettingsView(compact: false, onSettingsChange: server.updateGlassSettings)
            }
                .padding(20)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 340)
        }
        .task { server.connect() }
        .onChange(of: selectedMode) { _, value in
            if let value { modeRaw = value.rawValue }
        }
        .onChange(of: modeRaw) { _, _ in selectedMode = mode }
    }

    private var mode: DesktopPanelMode { DesktopPanelMode(rawValue: modeRaw) ?? .large }

    private func select(_ offset: Int) {
        let modes = DesktopPanelMode.allCases
        guard let index = modes.firstIndex(of: mode), modes.indices.contains(index + offset) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1)) {
            selectedMode = modes[index + offset]
        }
    }

    private var appearanceMode: GlassAppearanceMode {
        GlassAppearanceMode(rawValue: appearanceRaw) ?? .dark
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

    private var previewSnapshot: UsageSnapshot {
        var value = server.snapshot
        value.appearance = isLight ? .light : .dark
        return value
    }

    private var statusText: String {
        switch server.state {
        case .disconnected: "尚未连接"
        case .connecting: "正在连接 Codex…"
        case .signingIn: "请在浏览器完成登录"
        case .connected(let email): email.map { "已连接 · \($0)" } ?? "已连接"
        case .failed(let message): message
        }
    }

    private var statusIcon: String {
        switch server.state {
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "circle.dotted"
        }
    }

    private var statusColor: Color {
        switch server.state {
        case .connected: .green
        case .failed: .red
        default: .secondary
        }
    }
}

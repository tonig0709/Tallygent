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

    var body: some View {
        VStack(spacing: 20) {
            QuotaWidgetView(snapshot: previewSnapshot, glassOpacity: glassOpacity)
                .frame(width: 680, height: 300)
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

            HStack(spacing: 12) {
                Label(statusText, systemImage: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.callout.weight(.medium))
                Spacer()

                Button("修复小组件") { WidgetRepairService.repair() }
                    .help("重新登记并刷新桌面小组件")
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

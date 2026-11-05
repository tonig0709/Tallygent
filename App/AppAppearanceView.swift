import SwiftUI
import AppKit

enum AppUIRole { case monitor, insights, planner }
enum AppActionKind { case primary, secondary }

private struct AppUISettingsKey: EnvironmentKey { static let defaultValue = AppUISettings.standard }
extension EnvironmentValues {
    var appUISettings: AppUISettings {
        get { self[AppUISettingsKey.self] }
        set { self[AppUISettingsKey.self] = newValue.sanitized }
    }
}

extension AppUISettings {
    var colorScheme: ColorScheme? {
        switch appearance { case .system: nil; case .light: .light; case .dark: .dark }
    }
    var primaryColor: Color { Self.color(palette.primaryRGB) }
    var secondaryColor: Color { Self.color(palette.secondaryRGB) }
    func accent(for role: AppUIRole) -> Color {
        let rgb: Int
        switch role { case .monitor: rgb = palette.primaryRGB; case .insights: rgb = 0x08756B; case .planner: rgb = palette.secondaryRGB }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let lift = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.38 : 0.0
            func channel(_ shift: Int) -> Double {
                let value = Double((rgb >> shift) & 255) / 255
                return value + (1 - value) * lift
            }
            return NSColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: 1)
        })
    }
    static func color(_ rgb: Int) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

/// One button family across the app; no timers, cursor capture or WebView.
struct AppActionStyle: ButtonStyle {
    var kind: AppActionKind = .secondary
    var role: AppUIRole = .monitor
    func makeBody(configuration: Configuration) -> some View {
        StyledAction(configuration: configuration, kind: kind, role: role)
    }
    private struct StyledAction: View {
        let configuration: ButtonStyleConfiguration
        let kind: AppActionKind
        let role: AppUIRole
        @Environment(\.appUISettings) private var ui
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorSchemeContrast) private var contrast
        @State private var hovered = false
        private var moving: Bool { enabled && !reduceMotion && ui.motionIntensity > 0 }
        var body: some View {
            let radius = max(8, ui.cornerRadius - 3)
            let accent = ui.accent(for: role)
            configuration.label
                .font(.callout.weight(.medium))
                .padding(.horizontal, ui.isCompact ? 12 : 15)
                .padding(.vertical, ui.isCompact ? 7 : 9)
                .foregroundStyle(kind == .primary ? Color.white : Color.primary)
                .background {
                    if kind == .primary {
                        LinearGradient(colors: ui.buttonTreatment == .gradient
                                       ? [ui.primaryColor, ui.secondaryColor] : [ui.primaryColor, ui.primaryColor],
                                       startPoint: .leading, endPoint: .trailing)
                    } else { accent.opacity(contrast == .increased ? 0.18 : 0.08) }
                }
                .overlay {
                    if hovered && enabled && ui.hoverHighlights && ui.motionIntensity > 0 {
                        LinearGradient(colors: [.white.opacity(0.07 * ui.motionIntensity), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(kind == .primary ? Color.white.opacity(configuration.isPressed ? 0.6 : 0.16) : accent.opacity(configuration.isPressed ? 0.65 : 0.22), lineWidth: configuration.isPressed ? 2 : 1)
                }
                .scaleEffect(configuration.isPressed && moving ? 1 - 0.025 * ui.motionIntensity : 1)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .onHover { hovered = $0 }
                .animation(moving ? .easeOut(duration: 0.16) : nil, value: hovered)
                .animation(moving ? .easeOut(duration: 0.12) : nil, value: configuration.isPressed)
        }
    }
}

private struct AppSectionSurface: ViewModifier {
    var role: AppUIRole
    @Environment(\.appUISettings) private var ui
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .padding(ui.isCompact ? 14 : 20)
            .background {
                RoundedRectangle(cornerRadius: ui.cornerRadius, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.045) : Color.primary.opacity(0.025))
            }
            .overlay {
                RoundedRectangle(cornerRadius: ui.cornerRadius, style: .continuous)
                    .strokeBorder(ui.accent(for: role).opacity(0.16), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
extension View {
    func appSectionSurface(role: AppUIRole) -> some View { modifier(AppSectionSurface(role: role)) }
}

struct AppAppearanceSettingsView: View {
    @AppStorage(AppUISettings.defaultsKey) private var data = Data()
    private var settings: AppUISettings { .decode(data) }
    private func binding<Value>(_ path: WritableKeyPath<AppUISettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: path] }, set: { value in
            var updated = settings; updated[keyPath: path] = value; data = updated.encoded
        })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L("应用外观"), systemImage: "paintpalette").font(.title2.weight(.semibold))
                    Text(L("仅调整 App 主界面；不会更改桌面面板、玻璃参数或额度颜色。"))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                preview
                HStack {
                    Button(L("安静")) { var value = AppUISettings.standard; value.buttonTreatment = .solid; value.motionIntensity = 0; value.hoverHighlights = false; data = value.encoded }
                    Button(L("多彩")) { data = AppUISettings.standard.encoded }
                    Button(L("鲜明")) { var value = AppUISettings.standard; value.palette = .iris; value.motionIntensity = 0.8; data = value.encoded }
                }.buttonStyle(AppActionStyle())
                AdaptivePicker("应用主题", id: "appUI.appearance", selection: binding(\.appearance)) {
                    Text(L("跟随系统")).tag(AppUIAppearance.system)
                    Text(L("浅色")).tag(AppUIAppearance.light)
                    Text(L("深色")).tag(AppUIAppearance.dark)
                }
                AdaptivePicker("主色方案", id: "appUI.palette", selection: binding(\.palette)) {
                    Text(L("海蓝")).tag(AppUIPalette.ocean)
                    Text(L("鸢紫")).tag(AppUIPalette.iris)
                    Text(L("薄荷")).tag(AppUIPalette.mint)
                    Text(L("玫瑰")).tag(AppUIPalette.rose)
                }
                AdaptivePicker("按钮外观", id: "appUI.buttons", selection: binding(\.buttonTreatment)) {
                    Text(L("双色渐变")).tag(AppUIButtonTreatment.gradient)
                    Text(L("纯色")).tag(AppUIButtonTreatment.solid)
                }
                AdaptivePicker("界面密度", id: "appUI.density", selection: binding(\.density)) {
                    Text(L("舒适")).tag(AppUIDensity.comfortable)
                    Text(L("紧凑")).tag(AppUIDensity.compact)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(LF("内容圆角 %lld", Int64(settings.cornerRadius.rounded())))
                    Slider(value: binding(\.cornerRadius), in: 8...16, step: 1).accessibilityLabel(L("内容圆角"))
                    Text(LF("动效强度 %lld%%", Int64((settings.motionIntensity * 100).rounded())))
                    Slider(value: binding(\.motionIntensity), in: 0...1, step: 0.05).accessibilityLabel(L("动效强度"))
                    Text(L("0% 关闭装饰动效；始终尊重系统“减少动态效果”。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(L("悬停高光"), isOn: binding(\.hoverHighlights))
                HStack {
                    Text(L("更改即时生效并保存在本机。" )).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("恢复应用外观默认值")) { data = AppUISettings.standard.encoded }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 560, idealHeight: 700)
        .environment(\.appUISettings, settings)
        .tint(settings.accent(for: .monitor))
        .preferredColorScheme(settings.colorScheme)
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("实时外观预览"), systemImage: "rectangle.3.group").font(.headline)
            Text(L("按钮、间距和内容圆角与主界面使用相同设置。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L("主要操作")) {}.buttonStyle(AppActionStyle(kind: .primary))
                Button(L("次要操作")) {}.buttonStyle(AppActionStyle())
            }
        }.frame(maxWidth: .infinity, alignment: .leading).appSectionSurface(role: .monitor)
    }
}

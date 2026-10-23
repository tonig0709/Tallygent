import SwiftUI

enum GlassSettingKeys {
    static let appearance = "glassAppearanceMode"
    static let opacity = "desktopPanelGlassOpacity"
    static let edgeStrength = "glassEdgeStrength"
    static let elasticity = "glassElasticity"
    static let displacement = "glassDisplacement"
    static let blurAmount = "glassBlurAmount"
    static let saturation = "glassSaturation"
    static let dispersion = "glassDispersion"
    static let cornerRadius = "glassCornerRadius"
    static let tone = "glassTone"
    static let refractionMode = "glassRefractionMode"
}

enum GlassAppearanceMode: String, CaseIterable, Identifiable {
    case automatic, dark, light

    var id: Self { self }
    var title: String {
        switch self {
        case .automatic: "自动"
        case .dark: "深色"
        case .light: "浅色"
        }
    }

    func isLight(in colorScheme: ColorScheme) -> Bool {
        switch self {
        case .automatic: colorScheme == .light
        case .dark: false
        case .light: true
        }
    }
}

enum GlassTone: String, CaseIterable, Identifiable {
    case cool, neutral, warm

    var id: Self { self }
    var title: String {
        switch self {
        case .cool: "冷"
        case .neutral: "中性"
        case .warm: "暖"
        }
    }
    var color: Color {
        switch self {
        case .cool: Color(red: 0.35, green: 0.58, blue: 1)
        case .neutral: .clear
        case .warm: Color(red: 1, green: 0.56, blue: 0.26)
        }
    }
}

extension GlassRefractionMode {
    var title: String {
        switch self {
        case .standard: "标准"
        case .polar: "环形"
        case .prominent: "鲜明"
        }
    }
}

enum GlassSettingsSnapshot {
    static func load(defaults: UserDefaults = .standard) -> GlassRenderSettings {
        let appearanceMode = GlassAppearanceMode(
            rawValue: defaults.string(forKey: GlassSettingKeys.appearance) ?? GlassAppearanceMode.dark.rawValue
        ) ?? .dark
        let appearance: WidgetAppearance = appearanceMode == .light ? .light : .dark
        let double = { (key: String, fallback: Double) in
            defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
        }
        return GlassRenderSettings(
            appearance: appearance,
            opacity: double(GlassSettingKeys.opacity, WidgetGlassOpacity.defaultValue),
            edgeStrength: double(GlassSettingKeys.edgeStrength, 0.55),
            elasticity: double(GlassSettingKeys.elasticity, 0.15),
            displacement: double(GlassSettingKeys.displacement, 0.35),
            blurAmount: double(GlassSettingKeys.blurAmount, 0.20),
            saturation: double(GlassSettingKeys.saturation, 1.40),
            dispersion: double(GlassSettingKeys.dispersion, 0.08),
            cornerRadius: double(GlassSettingKeys.cornerRadius, 30),
            tone: defaults.string(forKey: GlassSettingKeys.tone) ?? GlassTone.neutral.rawValue,
            refractionMode: GlassRefractionMode(
                rawValue: defaults.string(forKey: GlassSettingKeys.refractionMode) ?? GlassRefractionMode.standard.rawValue
            ) ?? .standard
        ).sanitized
    }
}

private enum GlassPreset: String, CaseIterable, Identifiable {
    case clear, standard, vivid, custom

    var id: Self { self }
    var title: String {
        switch self {
        case .clear: "清透"
        case .standard: "标准"
        case .vivid: "鲜明"
        case .custom: "自定"
        }
    }
}

struct GlassSettingsView: View {
    let compact: Bool
    var onSettingsChange: (GlassRenderSettings) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(GlassSettingKeys.appearance) private var appearanceRaw = GlassAppearanceMode.dark.rawValue
    @AppStorage(GlassSettingKeys.opacity) private var opacity = WidgetGlassOpacity.defaultValue
    @AppStorage(GlassSettingKeys.edgeStrength) private var edgeStrength = 0.55
    @AppStorage(GlassSettingKeys.elasticity) private var elasticity = 0.15
    @AppStorage(GlassSettingKeys.displacement) private var displacement = 0.35
    @AppStorage(GlassSettingKeys.blurAmount) private var blurAmount = 0.20
    @AppStorage(GlassSettingKeys.saturation) private var saturation = 1.40
    @AppStorage(GlassSettingKeys.dispersion) private var dispersion = 0.08
    @AppStorage(GlassSettingKeys.cornerRadius) private var cornerRadius = 30.0
    @AppStorage(GlassSettingKeys.tone) private var toneRaw = GlassTone.neutral.rawValue
    @AppStorage(GlassSettingKeys.refractionMode) private var refractionModeRaw = GlassRefractionMode.standard.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 18) {
            if !compact {
                Text("玻璃外观")
                    .font(.title3.weight(.semibold))
                Text("三种桌面面板共用这些参数；将指针移入预览可查看高光与弹性。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GlassOpticsPreview(settings: currentSettings, tone: tone.wrappedValue.color)

            Picker("预设", selection: preset) {
                ForEach(GlassPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                        .disabled(preset == .custom)
                }
            }
            .pickerStyle(.segmented)

            Picker("外观", selection: appearance) {
                ForEach(GlassAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            controlSection("基础") {
                slider("不透明度", value: $opacity, range: WidgetGlassOpacity.minimum...WidgetGlassOpacity.maximum, format: .percent)
                slider("边缘强度", value: $edgeStrength, range: 0...1, format: .percent)
                slider("弹性高光", value: $elasticity, range: 0...1, format: .percent)
                slider("光学圆角", value: $cornerRadius, range: 10...64, format: .number)
            }

            controlSection("高级设置") {
                Picker("折射模式", selection: refractionMode) {
                    ForEach(GlassRefractionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                slider("折射位移", value: $displacement, range: 0...1, format: .percent)
                slider("磨砂", value: $blurAmount, range: 0...1, format: .percent)
                slider("色彩增益", value: $saturation, range: 1...2.2, format: .multiplier)
                slider("色散", value: $dispersion, range: 0...0.30, format: .percent)

                Picker("玻璃色调", selection: tone) {
                    ForEach(GlassTone.allCases) { tone in
                        Text(tone.title).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
            }

            Button("恢复默认值") { apply(.standard) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .onAppear { onSettingsChange(currentSettings) }
        .onChange(of: currentSettings) { onSettingsChange($0) }
    }

    @ViewBuilder
    private func controlSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private enum ValueFormat { case percent, number, multiplier }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: ValueFormat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                switch format {
                case .percent:
                    Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                case .number:
                    Text(value.wrappedValue, format: .number.precision(.fractionLength(0)))
                case .multiplier:
                    Text("×\(value.wrappedValue, format: .number.precision(.fractionLength(2)))")
                }
            }
            .monospacedDigit()
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }

    private var currentSettings: GlassRenderSettings {
        GlassRenderSettings(
            appearance: isLight ? .light : .dark,
            opacity: opacity,
            edgeStrength: edgeStrength,
            elasticity: elasticity,
            displacement: displacement,
            blurAmount: blurAmount,
            saturation: saturation,
            dispersion: dispersion,
            cornerRadius: cornerRadius,
            tone: toneRaw,
            refractionMode: refractionMode.wrappedValue
        ).sanitized
    }

    private var isLight: Bool { appearance.wrappedValue.isLight(in: colorScheme) }

    private var appearance: Binding<GlassAppearanceMode> {
        Binding(
            get: { GlassAppearanceMode(rawValue: appearanceRaw) ?? .dark },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    private var tone: Binding<GlassTone> {
        Binding(
            get: { GlassTone(rawValue: toneRaw) ?? .neutral },
            set: { toneRaw = $0.rawValue }
        )
    }

    private var refractionMode: Binding<GlassRefractionMode> {
        Binding(
            get: { GlassRefractionMode(rawValue: refractionModeRaw) ?? .standard },
            set: { refractionModeRaw = $0.rawValue }
        )
    }

    private var preset: Binding<GlassPreset> {
        Binding(
            get: {
                if matches(opacity: 0.35, edge: 0.42, elasticity: 0.08, displacement: 0.18, blur: 0.08, saturation: 1.15, dispersion: 0.03, radius: 24, tone: .neutral, mode: .standard) { return .clear }
                if matches(opacity: 0.86, edge: 0.55, elasticity: 0.15, displacement: 0.35, blur: 0.20, saturation: 1.40, dispersion: 0.08, radius: 30, tone: .neutral, mode: .standard) { return .standard }
                if matches(opacity: 0.72, edge: 0.90, elasticity: 0.55, displacement: 0.72, blur: 0.32, saturation: 1.75, dispersion: 0.18, radius: 42, tone: .cool, mode: .prominent) { return .vivid }
                return .custom
            },
            set: { apply($0) }
        )
    }

    private func matches(opacity expectedOpacity: Double, edge: Double, elasticity expectedElasticity: Double, displacement expectedDisplacement: Double, blur: Double, saturation expectedSaturation: Double, dispersion expectedDispersion: Double, radius: Double, tone: GlassTone, mode: GlassRefractionMode) -> Bool {
        abs(opacity - expectedOpacity) < 0.005 &&
            abs(edgeStrength - edge) < 0.005 &&
            abs(elasticity - expectedElasticity) < 0.005 &&
            abs(displacement - expectedDisplacement) < 0.005 &&
            abs(blurAmount - blur) < 0.005 &&
            abs(saturation - expectedSaturation) < 0.005 &&
            abs(dispersion - expectedDispersion) < 0.005 &&
            abs(cornerRadius - radius) < 0.005 &&
            toneRaw == tone.rawValue && refractionModeRaw == mode.rawValue
    }

    private func apply(_ preset: GlassPreset) {
        let settings: GlassRenderSettings
        switch preset {
        case .clear:
            settings = GlassRenderSettings(opacity: 0.35, edgeStrength: 0.42, elasticity: 0.08, displacement: 0.18, blurAmount: 0.08, saturation: 1.15, dispersion: 0.03, cornerRadius: 24)
        case .standard:
            settings = .standard
        case .vivid:
            settings = GlassRenderSettings(opacity: 0.72, edgeStrength: 0.90, elasticity: 0.55, displacement: 0.72, blurAmount: 0.32, saturation: 1.75, dispersion: 0.18, cornerRadius: 42, tone: GlassTone.cool.rawValue, refractionMode: .prominent)
        case .custom:
            return
        }
        opacity = settings.opacity
        edgeStrength = settings.edgeStrength
        elasticity = settings.elasticity
        displacement = settings.displacement
        blurAmount = settings.blurAmount
        saturation = settings.saturation
        dispersion = settings.dispersion
        cornerRadius = settings.cornerRadius
        toneRaw = settings.tone
        refractionModeRaw = settings.refractionMode.rawValue
    }
}

private struct GlassOpticsPreview: View {
    let settings: GlassRenderSettings
    let tone: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pointer = CGSize.zero
    @State private var hovering = false

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: CGFloat(settings.cornerRadius), style: .continuous)
            ZStack {
                LiquidGlassSurface(
                    isLight: settings.appearance == .light,
                    opacity: settings.opacity,
                    accent: .blue,
                    cornerRadius: settings.cornerRadius,
                    edgeStrength: settings.edgeStrength,
                    tone: tone,
                    dispersion: settings.dispersion,
                    elasticity: settings.elasticity,
                    displacement: settings.displacement,
                    blurAmount: settings.blurAmount,
                    saturation: settings.saturation,
                    refractionMode: settings.refractionMode
                )
                shape
                    .strokeBorder(
                        RadialGradient(
                            colors: [.white.opacity(hovering ? 0.82 : 0), .clear],
                            center: highlightCenter,
                            startRadius: 0,
                            endRadius: 96
                        ),
                        lineWidth: 2.2 + settings.displacement * 4 + settings.elasticity * 3
                    )
                    .offset(x: pointer.width * settings.elasticity * 8, y: pointer.height * settings.elasticity * 6)

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("LIQUID GLASS")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                }
                .foregroundStyle(settings.appearance == .light ? .black.opacity(0.72) : .white.opacity(0.84))
            }
            .clipShape(shape)
            .contentShape(shape)
            .onContinuousHover { phase in update(phase, size: proxy.size) }
        }
        .frame(height: 88)
    }

    private var highlightCenter: UnitPoint {
        UnitPoint(x: 0.5 + pointer.width * 0.5, y: 0.5 + pointer.height * 0.5)
    }

    private func update(_ phase: HoverPhase, size: CGSize) {
        switch phase {
        case .active(let location):
            hovering = true
            pointer = CGSize(
                width: min(1, max(-1, location.x / max(1, size.width) * 2 - 1)),
                height: min(1, max(-1, location.y / max(1, size.height) * 2 - 1))
            )
        case .ended:
            hovering = false
            if reduceMotion { pointer = .zero }
            else {
                withAnimation(.spring(response: 0.35, dampingFraction: 1)) { pointer = .zero }
            }
        }
    }
}

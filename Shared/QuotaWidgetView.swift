import Charts
import SwiftUI

public enum DesktopPanelMode: String, CaseIterable, Identifiable {
    case small, medium, large

    public static let defaultsKey = "desktopPanelMode"
    public var id: Self { self }
    public var title: String {
        switch self {
        case .small: "小型 · 双圆环"
        case .medium: "中型 · 双额度"
        case .large: "大型 · 额度与趋势"
        }
    }

    // Match the previous macOS widget footprint and its 16-point grid gap.
    // Values are logical points, never Retina pixels; the large panel is unchanged.
    public var size: CGSize {
        switch self {
        case .small: CGSize(width: 164, height: 164)
        case .medium: CGSize(width: 344, height: 164)
        case .large: CGSize(width: 680, height: 300)
        }
    }

    public static func stored(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .large
    }
}

public struct QuotaPanelContent: View {
    public let mode: DesktopPanelMode
    public let snapshot: UsageSnapshot
    public let glassOpacity: Double

    public init(mode: DesktopPanelMode, snapshot: UsageSnapshot, glassOpacity: Double) {
        self.mode = mode
        self.snapshot = snapshot
        self.glassOpacity = glassOpacity
    }

    public var body: some View {
        switch mode {
        case .small: QuotaRingWidgetView(snapshot: snapshot, glassOpacity: glassOpacity)
        case .medium: QuotaMediumPanelView(snapshot: snapshot)
        case .large: QuotaWidgetView(snapshot: snapshot, glassOpacity: glassOpacity)
        }
    }
}

private struct QuotaMediumPanelView: View {
    let snapshot: UsageSnapshot
    private var isLight: Bool { snapshot.resolvedAppearance == .light }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image("CodexMark")
                    .resizable().scaledToFit().frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text("Codex").font(.headline.weight(.semibold)).tracking(-0.3)
            }
            quotaBar("5h额度", window: snapshot.fiveHour)
            quotaBar("周额度", window: snapshot.weekly)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(isLight ? Color(red: 0.08, green: 0.1, blue: 0.14) : .white)
        .accessibilityElement(children: .contain)
    }

    private func quotaBar(_ title: String, window: UsageWindow?) -> some View {
        let remaining = window?.remainingPercent
        let color: Color = switch QuotaLevel(remainingPercent: remaining ?? 0) {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        }
        return VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(remaining.map { "\($0)%" } ?? "—")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit().tracking(-0.6)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(isLight ? .black.opacity(0.09) : .white.opacity(0.14))
                    Capsule().fill(color.gradient)
                        .frame(width: proxy.size.width * CGFloat(remaining ?? 0) / 100)
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(remaining.map { "剩余 \($0)%" } ?? "等待账户数据")")
    }
}

public struct QuotaWidgetView: View {
    public let snapshot: UsageSnapshot
    public let glassOpacity: Double

    public init(snapshot: UsageSnapshot, glassOpacity: Double = WidgetGlassOpacity.defaultValue) {
        self.snapshot = snapshot
        self.glassOpacity = WidgetGlassOpacity.clamped(glassOpacity)
    }

    private var isLight: Bool { snapshot.resolvedAppearance == .light }
    private var primaryText: Color { isLight ? Color(red: 0.08, green: 0.1, blue: 0.14) : .white }
    private var secondaryText: Color { isLight ? .black.opacity(0.52) : .white.opacity(0.56) }
    private var trackColor: Color { isLight ? .black.opacity(0.09) : .white.opacity(0.14) }
    private var gridColor: Color { isLight ? .black.opacity(0.08) : .white.opacity(0.1) }
    private var chartColor: Color { isLight ? .indigo : Color(red: 0.32, green: 0.58, blue: 1) }

    public var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image("CodexMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                Text("Codex")
                    .font(.title2.weight(.semibold))
                    .tracking(-0.4)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("已同步")
                    Text(snapshot.updatedAt, style: .time)
                        .monospacedDigit()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(trackColor, in: Capsule())
            }

            HStack(alignment: .bottom, spacing: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    quotaSection(title: "5h额度", window: snapshot.fiveHour)
                    quotaSection(title: "周额度", window: snapshot.weekly)
                }
                .frame(maxWidth: 244)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("近 7 天趋势").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("单位 M").font(.caption2).foregroundStyle(secondaryText)
                    }
                    Chart(snapshot.dailyUsage) { point in
                        BarMark(
                            x: .value("日期", shortDate(point.startDate)),
                            y: .value("Tokens (M)", point.millions)
                        )
                        .foregroundStyle(chartColor.gradient)
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7)) {
                            AxisValueLabel().foregroundStyle(secondaryText)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine().foregroundStyle(gridColor)
                            AxisValueLabel().foregroundStyle(secondaryText)
                        }
                    }
                    .accessibilityLabel("近七天 Codex Token 用量")
                }
            }
        }
        .padding(22)
        .foregroundStyle(primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func quotaSection(title: String, window: UsageWindow?) -> some View {
        let remaining = window?.remainingPercent ?? 0
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("\(remaining)%")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .tracking(-1.1)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(trackColor)
                    Capsule()
                        .fill(quotaColor(for: remaining).gradient)
                        .frame(width: proxy.size.width * CGFloat(remaining) / 100)
                }
            }
            .frame(height: 9)

            Label(resetText(for: window), systemImage: "clock.arrow.circlepath")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(secondaryText)
        }
    }

    private func quotaColor(for remaining: Int) -> Color {
        switch QuotaLevel(remainingPercent: remaining) {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private func resetText(for window: UsageWindow?) -> String {
        guard let date = window?.resetsAt else { return "等待账户数据" }
        return "\(date.formatted(date: .numeric, time: .shortened)) 重置"
    }

    private func shortDate(_ value: String) -> String {
        String(value.suffix(5)).replacingOccurrences(of: "-", with: "/")
    }
}

public struct QuotaRingWidgetView: View {
    public let snapshot: UsageSnapshot
    public let glassOpacity: Double

    public init(snapshot: UsageSnapshot, glassOpacity: Double = WidgetGlassOpacity.defaultValue) {
        self.snapshot = snapshot
        self.glassOpacity = WidgetGlassOpacity.clamped(glassOpacity)
    }

    private var isLight: Bool { snapshot.resolvedAppearance == .light }
    private var primaryText: Color { isLight ? Color(red: 0.08, green: 0.1, blue: 0.14) : .white }
    private var trackColor: Color { isLight ? .black.opacity(0.09) : .white.opacity(0.14) }

    public var body: some View {
        HStack(spacing: 12) {
            quotaRing(title: "5h", window: snapshot.fiveHour)
            quotaRing(title: "周", window: snapshot.weekly)
        }
        .padding(12)
        .foregroundStyle(primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func quotaRing(title: String, window: UsageWindow?) -> some View {
        let remaining = window?.remainingPercent ?? 0
        return VStack(spacing: 7) {
            ZStack {
                Circle().stroke(trackColor, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / 100)
                    .stroke(quotaColor(for: remaining).gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image("CodexMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            .frame(width: 58, height: 58)

            Text("\(title) \(remaining)%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Codex \(title)额度剩余 \(remaining)%")
    }

    private func quotaColor(for remaining: Int) -> Color {
        switch QuotaLevel(remainingPercent: remaining) {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

public struct LiquidGlassSurface: View {
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

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var resolvedOpacity: Double { reduceTransparency ? 1 : WidgetGlassOpacity.clamped(opacity) }
    private var darkFilmOpacity: Double { WidgetGlassOpacity.darkFilmOpacity(resolvedOpacity) }
    private var darkGlassTintOpacity: Double { WidgetGlassOpacity.darkGlassTintOpacity(resolvedOpacity) }

    public init(
        isLight: Bool,
        opacity: Double,
        accent: Color,
        cornerRadius: Double = 30,
        edgeStrength: Double = 0.55,
        tone: Color = .clear,
        dispersion: Double = 0,
        elasticity: Double = 0.15,
        displacement: Double = 0.35,
        blurAmount: Double = 0.20,
        saturation: Double = 1.40,
        refractionMode: GlassRefractionMode = .standard
    ) {
        self.isLight = isLight
        self.opacity = opacity
        self.accent = accent
        self.cornerRadius = min(64, max(10, cornerRadius))
        self.edgeStrength = min(1, max(0, edgeStrength))
        self.tone = tone
        self.dispersion = min(0.30, max(0, dispersion))
        self.elasticity = min(1, max(0, elasticity))
        self.displacement = min(1, max(0, displacement))
        self.blurAmount = min(1, max(0, blurAmount))
        self.saturation = min(2.2, max(1, saturation))
        self.refractionMode = refractionMode
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
        surfaceLayer
            .overlay { shape.fill(frostColor) }
            .overlay { shape.fill(tone.opacity(toneOpacity)) }
            .overlay {
                shape
                    .strokeBorder(outerBorder, lineWidth: rimWidth)
                    .overlay {
                        shape.inset(by: rimInset)
                            .strokeBorder(innerBorder, lineWidth: innerRimWidth)
                    }
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(.white.opacity((isLight ? 0.42 : 0.08) + edgeStrength * 0.24))
                    .frame(height: 0.75)
                    .padding(.horizontal, 36)
                    .padding(.top, 1)
            }
            .overlay { chromaticEdge(shape: shape) }
            .overlay { refractionHighlight(shape: shape) }
            .overlay(alignment: .topLeading) { elasticHighlight }
    }

    @ViewBuilder
    private var surfaceLayer: some View {
        if isLight {
            RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
                .fill(Color(red: 0.93, green: 0.96, blue: 1).opacity(resolvedOpacity))
        } else {
            darkSurface
        }
    }

    @ViewBuilder
    private var darkSurface: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
                .fill(.clear)
                .glassEffect(
                    .clear.tint(.black.opacity(darkGlassTintOpacity)),
                    in: RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
                        .fill(.black.opacity(darkFilmOpacity))
                }
        } else {
            fallbackDarkSurface
        }
#else
        fallbackDarkSurface
#endif
    }

    private var fallbackDarkSurface: some View {
        RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
            .fill(.black.opacity(resolvedOpacity))
    }

    private var outerBorder: Color {
        isLight ? .white.opacity(0.48 + edgeStrength * 0.42) : .white.opacity(0.12 + edgeStrength * 0.22)
    }

    private var innerBorder: Color {
        isLight ? accent.opacity(0.12 + (saturation - 1) * 0.14) : .white.opacity(0.07 + displacement * 0.07)
    }

    private var rimWidth: CGFloat {
        CGFloat(0.65 + edgeStrength * 1.35)
    }

    private var rimInset: CGFloat { CGFloat(1.2 + displacement * 5.2) }
    private var innerRimWidth: CGFloat { CGFloat(0.5 + displacement * 2.5) }

    private var frostColor: Color {
        (isLight ? Color.white : Color.black).opacity(blurAmount * (isLight ? 0.28 : 0.16))
    }

    private var toneOpacity: Double {
        0.035 * saturation
    }

    private var elasticHighlight: some View {
        Capsule()
            .fill(.white.opacity((isLight ? 0.30 : 0.16) + elasticity * 0.34))
            .frame(width: CGFloat(42 + elasticity * 118), height: CGFloat(1 + elasticity * 4.5))
            .blur(radius: CGFloat(elasticity * 1.2))
            .padding(.leading, CGFloat(18 + displacement * 10))
            .padding(.top, CGFloat(1.2 + displacement * 2.8))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func refractionHighlight(shape: RoundedRectangle) -> some View {
        switch refractionMode {
        case .standard:
            shape.inset(by: CGFloat(1 + displacement * 4)).strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.16 + displacement * 0.48), .clear, .white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: CGFloat(1 + displacement * 3.2)
            )
        case .polar:
            shape.inset(by: CGFloat(1 + displacement * 4)).strokeBorder(
                AngularGradient(
                    colors: [.white.opacity(0.20 + displacement * 0.52), .clear, accent.opacity(0.16 * saturation), .clear, .white.opacity(0.20 + displacement * 0.52)],
                    center: .center
                ),
                lineWidth: CGFloat(1.2 + displacement * 4)
            )
        case .prominent:
            shape.inset(by: CGFloat(1 + displacement * 4)).strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.30 + displacement * 0.58), accent.opacity(0.20 * saturation), .clear, .black.opacity(0.10 + displacement * 0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: CGFloat(1.8 + displacement * 5)
            )
        }
    }

    private func chromaticEdge(shape: RoundedRectangle) -> some View {
        let offset = CGFloat(dispersion * 3)
        return ZStack {
            shape
                .strokeBorder(.red.opacity(dispersion * 0.18), lineWidth: 0.65)
                .offset(x: -offset)
            shape
                .strokeBorder(.cyan.opacity(dispersion * 0.18), lineWidth: 0.65)
                .offset(x: offset)
        }
    }
}

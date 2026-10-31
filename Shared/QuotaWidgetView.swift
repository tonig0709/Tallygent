import Charts
import SwiftUI

private struct ServiceMark: View {
    let service: AgentService
    var body: some View {
        Group {
            if service == .codex {
                Image("CodexMark").resizable().scaledToFit()
            } else {
                Image(systemName: "terminal.fill").resizable().scaledToFit()
                    .padding(3).foregroundStyle(.orange)
            }
        }
        .accessibilityHidden(true)
    }
}

public enum DesktopPanelMode: String, CaseIterable, Identifiable {
    case small, medium, large

    public static let defaultsKey = "desktopPanelMode"
    public var id: Self { self }
    public var title: String {
        switch self {
        case .small: L("小型 · 双圆环")
        case .medium: L("中型 · 双额度")
        case .large: L("大型 · 额度与趋势")
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
    public let trend: PanelTrendPresentation?

    public init(mode: DesktopPanelMode, snapshot: UsageSnapshot, glassOpacity: Double,
                trend: PanelTrendPresentation? = nil) {
        self.mode = mode
        self.snapshot = snapshot
        self.glassOpacity = glassOpacity
        self.trend = trend
    }

    public var body: some View {
        switch mode {
        case .small: QuotaRingWidgetView(snapshot: snapshot, glassOpacity: glassOpacity)
        case .medium: QuotaMediumPanelView(snapshot: snapshot)
        case .large: QuotaWidgetView(snapshot: snapshot, glassOpacity: glassOpacity, trend: trend)
        }
    }
}

private struct QuotaMediumPanelView: View {
    let snapshot: UsageSnapshot
    private var isLight: Bool { snapshot.resolvedAppearance == .light }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ServiceMark(service: snapshot.resolvedService).frame(width: 22, height: 22)
                Text(snapshot.resolvedService.title).font(.headline.weight(.semibold)).tracking(-0.3)
                if snapshot.resolvedService == .claude {
                    Spacer()
                    Text(snapshot.statusLabel(at: .now)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            quotaBar(L("5h额度"), window: snapshot.fiveHour)
            quotaBar(L("周额度"), window: snapshot.weekly)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(isLight ? Color(red: 0.08, green: 0.1, blue: 0.14) : .white)
        .accessibilityElement(children: .contain)
        .help(snapshot.resolvedService == .claude ? L("实验性 · Claude Code 会话记录；不代表后台实时查询") : L("Codex 账户额度"))
    }

    private func quotaBar(_ title: String, window: UsageWindow?) -> some View {
        let remaining = snapshot.displayWindow(window)?.remainingPercent
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
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit().tracking(-0.6)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(isLight ? .black.opacity(0.09) : .white.opacity(0.14))
                    Capsule().fill(color.gradient)
                        .frame(width: proxy.size.width * CGFloat(remaining ?? 0) / 100)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LF("%@，%@", title, remaining.map { LF("剩余 %lld%%", $0) } ?? L("等待账户数据")))
    }
}

public struct QuotaWidgetView: View {
    public let snapshot: UsageSnapshot
    public let glassOpacity: Double
    public let trend: PanelTrendPresentation?

    public init(snapshot: UsageSnapshot, glassOpacity: Double = WidgetGlassOpacity.defaultValue,
                trend: PanelTrendPresentation? = nil) {
        self.snapshot = snapshot
        self.glassOpacity = WidgetGlassOpacity.clamped(glassOpacity)
        self.trend = trend
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
                ServiceMark(service: snapshot.resolvedService)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                Text(snapshot.resolvedService.title)
                    .font(.title2.weight(.semibold))
                    .tracking(-0.4)
                Spacer()
                HStack(spacing: 6) {
                    // Keep the clock independent of account polling and snapshot timestamps.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack(spacing: 6) {
                            Circle().fill(snapshot.statusLabel(at: .now) == L("已同步") ? .green : .orange)
                                .frame(width: 6, height: 6)
                            Text(snapshot.statusLabel(at: .now))
                            Text(Date(), format: .dateTime.hour().minute().second())
                                .monospacedDigit()
                                .accessibilityLabel(L("Mac 系统时间"))
                        }
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(trackColor, in: Capsule())
                .help(snapshot.hasQuota ? LF("系统时钟每秒更新；最近接收数据：%@", snapshot.lastReceivedAt.formatted(date: .abbreviated, time: .standard)) : L("等待所选服务提供额度数据"))
            }

            HStack(alignment: .bottom, spacing: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    quotaSection(title: L("5h额度"), window: snapshot.fiveHour)
                    quotaSection(title: L("周额度"), window: snapshot.weekly)
                }
                .frame(maxWidth: 244)

                VStack(alignment: .leading, spacing: 5) {
                    if let trend, trend.source.hours != nil {
                        PanelTrendView(presentation: trend, isLight: isLight,
                                       provider: snapshot.resolvedService).equatable()
                    } else if snapshot.resolvedService == .claude {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(L("Claude Code · 实验性"), systemImage: "flask")
                                .font(.subheadline.weight(.semibold))
                            Text(L("此接入提供会话额度记录，尚无可靠的七日 Token 历史。"))
                            Text(LF("最近接收：%@", snapshot.hasQuota ? snapshot.lastReceivedAt.formatted(date: .abbreviated, time: .shortened) : L("等待会话数据")))
                        }
                        .font(.caption).foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    } else {
                    HStack {
                        Text(L("近 7 天趋势")).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(L("Token（百万）")).font(.caption2).foregroundStyle(secondaryText)
                    }
                    Chart(snapshot.dailyUsage) { point in
                        if trend?.style == .line {
                            LineMark(x: .value(L("日期"), shortDate(point.startDate)),
                                     y: .value("Tokens (M)", point.millions))
                                .interpolationMethod(.linear)
                                .foregroundStyle(chartColor)
                            PointMark(x: .value(L("日期"), shortDate(point.startDate)),
                                      y: .value("Tokens (M)", point.millions))
                                .symbolSize(12)
                                .foregroundStyle(chartColor)
                        } else {
                        BarMark(
                            x: .value(L("日期"), shortDate(point.startDate)),
                            y: .value("Tokens (M)", point.millions)
                        )
                        .foregroundStyle(chartColor.gradient)
                        .cornerRadius(3)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: true))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7)) {
                            AxisValueLabel().foregroundStyle(secondaryText)
                        }
                    }
                    .chartXAxisLabel(position: .bottom, alignment: .trailing) {
                        Text(L("日期（月/日）")).font(.caption2).foregroundStyle(secondaryText)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine().foregroundStyle(gridColor)
                            AxisValueLabel().foregroundStyle(secondaryText)
                        }
                    }
                    .accessibilityLabel(L("近七天 Codex Token 用量，横轴为日期（月/日），纵轴单位为百万 Token"))
                    }
                }
            }
        }
        .padding(22)
        .foregroundStyle(primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func quotaSection(title: String, window: UsageWindow?) -> some View {
        let remaining = snapshot.displayWindow(window)?.remainingPercent
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Spacer()
                Text(remaining.map { "\($0)%" } ?? "—")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .tracking(-1.1)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(trackColor)
                    Capsule()
                        .fill(quotaColor(for: remaining ?? 0).gradient)
                        .frame(width: proxy.size.width * CGFloat(remaining ?? 0) / 100)
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
        if snapshot.resolvedService == .claude, window != nil, snapshot.displayWindow(window) == nil {
            return L("已到重置时间，等待会话更新")
        }
        guard let date = window?.resetsAt else { return L("等待账户数据") }
        return LF("%@ 重置", date.formatted(date: .numeric, time: .shortened))
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
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                quotaRing(title: "5h", window: snapshot.fiveHour)
                quotaRing(title: L("周"), window: snapshot.weekly)
            }
            if snapshot.resolvedService == .claude {
                Text("Claude · \(snapshot.statusLabel(at: .now))").font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .foregroundStyle(primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func quotaRing(title: String, window: UsageWindow?) -> some View {
        let remaining = snapshot.displayWindow(window)?.remainingPercent
        return VStack(spacing: 7) {
            ZStack {
                Circle().stroke(trackColor, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(remaining ?? 0) / 100)
                    .stroke(quotaColor(for: remaining ?? 0).gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                ServiceMark(service: snapshot.resolvedService)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            .frame(width: 58, height: 58)

            Text("\(title) \(remaining.map { "\($0)%" } ?? "—")")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LF("%@ %@额度，%@", snapshot.resolvedService.title, title, remaining.map { LF("剩余 %lld%%", $0) } ?? L("等待数据")))
        .help(snapshot.resolvedService == .claude ? L("实验性 · 会话记录，不代表后台实时查询") : L("Codex 账户额度"))
    }

    private func quotaColor(for remaining: Int) -> Color {
        switch QuotaLevel(remainingPercent: remaining) {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

/// A specular reflection stays on the glass contour; only its light field moves.
public struct GlassRimHighlight: View {
    private let isLight: Bool
    private let cornerRadius: Double
    private let elasticity: Double
    private let displacement: Double
    private let hoverVector: CGSize

    public init(isLight: Bool, cornerRadius: Double, elasticity: Double, displacement: Double,
                hoverVector: CGSize = .zero) {
        self.isLight = isLight
        self.cornerRadius = cornerRadius.isFinite ? min(64, max(0, cornerRadius)) : 30
        self.elasticity = elasticity.isFinite ? min(1, max(0, elasticity)) : 0
        self.displacement = displacement.isFinite ? min(1, max(0, displacement)) : 0
        self.hoverVector = CGSize(
            width: hoverVector.width.isFinite ? min(1, max(-1, hoverVector.width)) : 0,
            height: hoverVector.height.isFinite ? min(1, max(-1, hoverVector.height)) : 0
        )
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
            .strokeBorder(
                RadialGradient(
                    colors: [.white.opacity((isLight ? 0.20 : 0.10) + elasticity * (isLight ? 0.64 : 0.56)), .clear],
                    center: UnitPoint(
                        x: min(1, max(0, 0.22 + Double(hoverVector.width) * elasticity * 0.45)),
                        y: min(1, max(0, 0.06 + Double(hoverVector.height) * elasticity * 0.65))
                    ),
                    startRadius: 0,
                    endRadius: CGFloat(120 + elasticity * 120 + displacement * 40)
                ),
                lineWidth: CGFloat(0.8 + elasticity * 1.7 + displacement * 0.2)
            )
            .allowsHitTesting(false)
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
    private var optics: GlassOptics { GlassOptics(blurAmount: blurAmount, dispersion: dispersion) }
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
                .environment(\.colorScheme, .dark)
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
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
                    .fill(.black.opacity(darkFilmOpacity))
            }
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
        // Haze density, not a private or simulated backdrop blur radius.
        (isLight ? Color.white : Color(white: 0.28))
            .opacity(optics.frostOpacity * (1 - WidgetGlassOpacity.normalized(resolvedOpacity)))
    }

    private var toneOpacity: Double {
        0.035 * saturation
    }

    private var elasticHighlight: some View {
        GlassRimHighlight(isLight: isLight, cornerRadius: cornerRadius,
                          elasticity: elasticity, displacement: displacement)
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
        let offset = CGFloat(optics.edgeOffset)
        let width = CGFloat(optics.edgeWidth)
        let rim = shape.inset(by: offset + width / 2)
        return ZStack {
            rim
                .strokeBorder(.red.opacity(optics.edgeOpacity), lineWidth: width)
                .offset(x: -offset, y: offset * 0.4)
            rim
                .strokeBorder(.cyan.opacity(optics.edgeOpacity), lineWidth: width)
                .offset(x: offset, y: -offset * 0.4)
        }
    }
}

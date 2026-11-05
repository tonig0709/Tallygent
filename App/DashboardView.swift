import SwiftUI

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case monitor, insights, planner
    var id: Self { self }
    var title: String {
        switch self { case .monitor: L("额度与面板"); case .insights: L("Insights"); case .planner: L("Planner") }
    }
}

enum DashboardLayout {
    static let minimumWidth: CGFloat = 760
    static let minimumHeight: CGFloat = 620
    static let inspectorWidth: CGFloat = 300
    static func hasInlineInspector(width: CGFloat) -> Bool { width >= 1_080 }
    static func previewScale(width: CGFloat) -> CGFloat { min(1, max(0.1, width / 680)) }
}

@MainActor
struct DashboardView: View {
    @ObservedObject var server: QuotaMonitor
    @ObservedObject private var insights: InsightsStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppUISettings.defaultsKey) private var appUIData = Data()
    private var appUI: AppUISettings { .decode(appUIData) }
    @AppStorage(GlassSettingKeys.appearance) private var appearanceRaw = GlassAppearanceMode.dark.rawValue
    @AppStorage(GlassSettingKeys.surfaceStyle) private var surfaceStyleRaw = GlassSurfaceStyle.tinted.rawValue
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
    @State private var showsGlassInspector = true
    @State private var showsGlassSheet = false
    @State var section = WorkspaceSection.monitor
    @ObservedObject var planner: PlannerStore
    private let onGalleryLayout: ((DesktopPanelMode, CGRect) -> Void)?
    private let onControlLayout: ((String, CGRect, CGSize) -> Void)?
    @AppStorage(DesktopPanelMode.defaultsKey) private var modeRaw = DesktopPanelMode.large.rawValue
    @State private var selectedMode: DesktopPanelMode?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(server: QuotaMonitor, planner: PlannerStore? = nil, section: WorkspaceSection = .monitor,
         onGalleryLayout: ((DesktopPanelMode, CGRect) -> Void)? = nil,
         onControlLayout: ((String, CGRect, CGSize) -> Void)? = nil) {
        self.server = server
        self.insights = server.insights
        self.planner = planner ?? PlannerStore()
        self.onGalleryLayout = onGalleryLayout
        self.onControlLayout = onControlLayout
        _section = State(initialValue: section)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        workspacePicker
                        Spacer(minLength: 16)
                        appAppearanceLink
                    }
                    VStack(alignment: .leading, spacing: 10) { workspacePicker; appAppearanceLink }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .controlLayoutContainer("workspace.toolbar.container")
                .padding(.horizontal, appUI.spacing).padding(.vertical, appUI.isCompact ? 10 : 16)
                Divider()
                ZStack {
                    HStack(spacing: 0) {
                        ScrollView(.vertical) {
                            monitorContent(wide: DashboardLayout.hasInlineInspector(width: geometry.size.width))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if showsGlassInspector && DashboardLayout.hasInlineInspector(width: geometry.size.width) {
                            Divider()
                            ScrollView {
                                GlassSettingsView(compact: false, onSettingsChange: server.updateGlassSettings)
                                    .padding(20)
                                    .environment(\.colorScheme, colorScheme)
                            }
                            .frame(width: DashboardLayout.inspectorWidth)
                            .background(.primary.opacity(0.025))
                        }
                    }
                    .opacity(section == .monitor ? 1 : 0)
                    .allowsHitTesting(section == .monitor)
                    .accessibilityHidden(section != .monitor)
                    .disabled(section != .monitor)
                    PlannerView(server: server, store: planner, isActive: section == .planner)
                        .opacity(section == .planner ? 1 : 0)
                        .allowsHitTesting(section == .planner)
                        .accessibilityHidden(section != .planner)
                        .disabled(section != .planner)
                    if section == .insights {
                        InsightsView(server: server, store: server.insights)
                    }
                }
            }
            .background(.background)
            .environment(\.appUISettings, appUI)
            .environment(\.colorScheme, appUI.colorScheme ?? colorScheme)
        }
        .coordinateSpace(name: ControlLayoutSpace.name)
        .environment(\.recordsControlLayout, onControlLayout != nil)
        .onPreferenceChange(ControlLayoutPreference.self) { records in
            guard let onControlLayout else { return }
            for (id, record) in records {
                if let frame = record.frame, let ideal = record.idealSize { onControlLayout(id, frame, ideal) }
            }
        }
        .frame(minWidth: DashboardLayout.minimumWidth, minHeight: DashboardLayout.minimumHeight)
        .sheet(isPresented: $showsGlassSheet) {
            VStack(spacing: 0) {
                HStack { Text("玻璃设置").font(.headline); Spacer(); Button("完成") { showsGlassSheet = false } }
                    .padding(20)
                Divider()
                ScrollView { GlassSettingsView(compact: false, onSettingsChange: server.updateGlassSettings).padding(20) }
            }
            .frame(width: 380, height: 600)
            .environment(\.colorScheme, colorScheme)
        }
        .task { await server.connect(); await planner.load() }
        .onChange(of: selectedMode) { _, value in
            if let value { modeRaw = value.rawValue }
        }
        .onChange(of: modeRaw) { _, _ in selectedMode = mode }
    }

    private func monitorContent(wide: Bool) -> some View {
        let trend = panelTrend
        return VStack(spacing: 20) {
            monitorStatus(wide: wide)
            VStack(alignment: .leading, spacing: 8) {
                Text("监测服务").fixedSize().controlLayoutProbe("monitor.service.label")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { serviceButtons }.fixedSize()
                    VStack(alignment: .leading, spacing: 10) { serviceButtons }
                }
                .controlLayoutContainer("monitor.service.picker.container")
                if server.service == .claude { Text("本地会话接入").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .controlLayoutContainer("monitor.service.container")
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
            GeometryReader { geometry in
              ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(DesktopPanelMode.allCases) { page in
                            QuotaPanelContent(mode: page, snapshot: previewSnapshot, glassOpacity: glassOpacity,
                                              trend: trend)
                                .id(server.service == .claude ? server.snapshot.claudePresentationKey() : "codex")
                                .frame(width: page.size.width, height: page.size.height)
                                .background {
                                GlassPreviewSurface(settings: GlassRenderSettings(appearance: isLight ? .light : .dark, opacity: glassOpacity,
                                    edgeStrength: edgeStrength, elasticity: elasticity, displacement: displacement, blurAmount: blurAmount,
                                    saturation: saturation, dispersion: dispersion, cornerRadius: cornerRadius, tone: toneRaw,
                                    refractionMode: refractionMode, surfaceStyle: surfaceStyle,
                                    pointerHighlightIntensity: pointerHighlightIntensity), tone: glassTone.color)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous))
                                .scaleEffect(DashboardLayout.previewScale(width: geometry.size.width))
                                .frame(width: geometry.size.width, height: 300)
                                .background {
                                    if let onGalleryLayout {
                                        GeometryReader { pageGeometry in
                                            let frame = pageGeometry.frame(in: .named("panel-gallery"))
                                            Color.clear
                                                .onAppear { onGalleryLayout(page, frame) }
                                                .onChange(of: frame) { _, value in onGalleryLayout(page, value) }
                                        }
                                    }
                                }
                                .id(page)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .coordinateSpace(name: "panel-gallery")
                .scrollPosition(id: $selectedMode)
                .onAppear {
                    selectedMode = mode
                    proxy.scrollTo(mode, anchor: .center)
                }
                .onChange(of: geometry.size.width) { _, _ in proxy.scrollTo(mode, anchor: .center) }
              }
            }
            .frame(height: 300)
            .environment(\.colorScheme, colorScheme)

            HStack(spacing: 16) {
                ForEach(DesktopPanelMode.allCases) { page in
                    Button {
                        withAnimation(reduceMotion || appUI.motionIntensity == 0 ? nil : .spring(response: 0.35, dampingFraction: 1)) {
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

            if server.service == .claude {
                VStack(alignment: .leading, spacing: 8) {
                    Text("需要 Claude Code 提供订阅额度。会话退出后保留记录，过期窗口显示待更新。仅绑定一个会话，不读取登录凭证。")
                    HStack {
                        Button("启用本地接入") { server.enableClaudeBridge() }
                        Button("移除接入") { server.removeClaudeBridge() }
                        Button("重新绑定会话") { server.resetClaudeSession() }
                    }.buttonStyle(AppActionStyle())
                    if let message = server.connectionMessage { Text(message).textSelection(.enabled) }
                }
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(appUI.spacing)
        .frame(maxWidth: .infinity)
        .controlLayoutContainer("monitor.content.container")
    }

    @ViewBuilder private var serviceButtons: some View {
        ForEach(AgentService.allCases) { service in
            Button { server.selectService(service) } label: {
                Label(service == .claude ? L("Claude Code · 实验性") : service.title,
                      systemImage: service == .codex ? "terminal" : "bubble.left.and.bubble.right")
            }
            .buttonStyle(AppActionStyle(kind: server.service == service ? .primary : .secondary))
            .accessibilityAddTraits(server.service == service ? .isSelected : [])
        }
    }

    private func monitorStatus(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
                Label(statusText, systemImage: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .controlLayoutProbe("monitor.status")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { monitorActions(wide: wide) }.fixedSize()
                    VStack(alignment: .leading, spacing: 8) { monitorActions(wide: wide) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .controlLayoutContainer("monitor.actions.container")
            }
        .appSectionSurface(role: .monitor)
    }

    private var workspacePicker: some View {
        HStack(spacing: 12) {
            Text("工作区").fixedSize().controlLayoutProbe("workspace.label")
            AdaptivePicker("工作区", id: "workspace.choice", selection: $section, showsTitle: false) {
                ForEach(WorkspaceSection.allCases) { section in
                    Label(section.title, systemImage: section == .monitor ? "gauge.with.dots.needle.50percent" : section == .insights ? "chart.xyaxis.line" : "checklist")
                        .tag(section)
                }
            }
            .tint(appUI.primaryColor)
        }
        .controlLayoutContainer("workspace.container")
    }

    private var appAppearanceLink: some View {
        SettingsLink { Label(L("应用外观"), systemImage: "paintpalette") }
            .buttonStyle(AppActionStyle())
    }

    @ViewBuilder
    private func monitorActions(wide: Bool) -> some View {
        Button("玻璃设置", systemImage: "slider.horizontal.3") {
            if wide { showsGlassInspector.toggle() } else { showsGlassSheet = true }
        }
        .buttonStyle(AppActionStyle())
        Button("桌面玻璃面板") { DesktopPanelController.shared.show(server: server) }
            .help("打开一个独立透明、不会改变其他图标外观的桌面面板")
            .buttonStyle(AppActionStyle())
        Button(server.isRefreshing ? L("正在刷新…") : L("刷新")) { server.refresh() }
            .disabled(server.isRefreshing || server.state == .connecting)
            .buttonStyle(AppActionStyle(kind: .primary))
        if server.service == .codex, case .disconnected = server.state {
            Button("连接 Codex") { Task { await server.connect() } }.buttonStyle(.borderedProminent)
        }
    }

    private var mode: DesktopPanelMode { DesktopPanelMode(rawValue: modeRaw) ?? .large }

    private var panelTrend: PanelTrendPresentation {
        .make(report: insights.panelReport, provider: server.service, scope: server.plannerQuota().scope,
              source: PanelChartSource(rawValue: chartSourceRaw) ?? .sevenDayTokens,
              style: PanelChartStyle(rawValue: chartStyleRaw) ?? .bars,
              now: insights.panelReport.generatedAt)
    }

    private func select(_ offset: Int) {
        let modes = DesktopPanelMode.allCases
        guard let index = modes.firstIndex(of: mode), modes.indices.contains(index + offset) else { return }
        withAnimation(reduceMotion || appUI.motionIntensity == 0 ? nil : .spring(response: 0.35, dampingFraction: 1)) {
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
        surfaceStyle != .nativeClear && appearanceMode.isLight(in: colorScheme)
    }

    private var surfaceStyle: GlassSurfaceStyle { GlassSurfaceStyle(rawValue: surfaceStyleRaw) ?? .tinted }

    private var previewSnapshot: UsageSnapshot {
        var value = server.snapshot
        value.appearance = isLight ? .light : .dark
        return value
    }

    private var statusText: String {
        if server.isRefreshing { return L("正在读取账户最新额度…") }
        if server.service == .claude {
            if case .failed(let message) = server.state { return message }
            return server.snapshot.hasQuota
                ? "\(server.snapshot.statusLabel(at: .now)) · \(server.snapshot.lastReceivedAt.formatted(date: .abbreviated, time: .standard))"
                : L("等待 Claude Code 会话数据")
        }
        return switch server.state {
        case .disconnected: L("尚未连接")
        case .connecting: L("正在连接 Codex…")
        case .signingIn: L("请在浏览器完成登录")
        case .connected(let email): "\(email.map { LF("已连接 · %@", $0) } ?? L("已连接"))\n\(LF("最近读取：%@", server.snapshot.lastReceivedAt.formatted(date: .abbreviated, time: .standard)))"
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
        case .connected: server.service == .claude ? .orange : .green
        case .failed: .red
        default: .secondary
        }
    }
}

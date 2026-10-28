import SwiftUI
import Charts
import UniformTypeIdentifiers

/// Operate: extend the native workspace, keep current evidence beside every estimate.
/// Existing system type/controls remain the visual authority; desktop glass is untouched.
@MainActor
struct InsightsView: View {
    @ObservedObject var server: QuotaMonitor
    @ObservedObject var store: InsightsStore
    @State private var showsClear = false
    @State private var showsExporter = false
    @State private var document = ObservationDocument(data: Data())

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 20) {
                            heading.fixedSize(horizontal: true, vertical: true)
                            Spacer(minLength: 0)
                            rangePicker.fixedSize(horizontal: true, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 16) { heading; rangePicker }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .controlLayoutContainer("insights.header.container")
                    HStack {
                        Button("重新读取历史", systemImage: "arrow.clockwise") { Task { await store.reload(force: true) } }
                            .disabled(store.isLoading)
                        if store.isLoading { ProgressView().controlSize(.small) }
                        Spacer()
                        Menu("导出记录") {
                            Button("导出当前范围") { export(allHistory: false) }
                            Button("导出全部 30 天") { export(allHistory: true) }
                        }
                        Button("清空历史", role: .destructive) { showsClear = true }
                            .disabled(store.isLoading)
                    }
                    if let message = store.message {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if store.observations.count >= ObservationHistory.maximumDisplayRows {
                        Text("当前显示最近 20,000 条观测，可能未覆盖整个所选范围；更早的 30 天原始记录仍可导出。")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    ForEach(AgentService.allCases) { provider in
                        providerSection(provider, wide: geometry.size.width >= 940)
                        Divider()
                    }
                    resetTimeline
                    evaluation
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("低额度与预计重置提醒", isOn: Binding(get: { store.notificationsEnabled }, set: { value in
                            Task { await store.setNotifications(value) }
                        }))
                        .disabled(store.isConfiguringNotifications)
                        Text("默认关闭。启用后仅提醒新发生的降至 20% 及以下变化，重置时间仅作预计；App 需保持运行。首次启用不补发旧提醒。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("本机保留 30 天；不保存提示词、对话、代码或登录凭据。订阅比例不是 Token 或费用；文件权限限制不等于加密。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .controlLayoutContainer("insights.content.container")
            }
        }
        .confirmationDialog("清空本机的额度观测历史？", isPresented: $showsClear) {
            Button("清空历史", role: .destructive) { Task { await store.clear() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("不会清除账户、玻璃设置或 Planner 任务记录；操作不可撤销，可先导出。")
        }
        .fileExporter(isPresented: $showsExporter, document: document, contentType: .json,
                      defaultFilename: "Tallygent-observations") { result in
            Task { @MainActor in store.exportFinished(result) }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("用量与节奏").font(.title2.weight(.semibold))
            Text("只分析真实收到的额度。历史从启用后积累，不补造过去的数据。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rangePicker: some View {
        AdaptivePicker("历史范围", id: "insights.range",
                       selection: Binding(get: { store.range }, set: store.selectRange),
                       showsTitle: false, prefersSegments: false) {
            ForEach(InsightsRange.allCases) { Text($0.title).tag($0) }
        }
        .frame(idealWidth: 160, maxWidth: 240, alignment: .leading)
    }

    private func providerSection(_ provider: AgentService, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(provider == .claude ? "Claude Code · 实验性" : provider.title).font(.headline)
                Spacer()
                Toggle(provider == .codex ? "连续记录" : "记录接入事件", isOn: Binding(
                    get: { provider == .codex ? server.codexCollectionEnabled : server.claudeCollectionEnabled },
                    set: { enabled in Task { await server.setCollection(provider, enabled: enabled) } }
                )).toggleStyle(.switch).controlSize(.small)
                    .disabled(server.isConfiguringCollection)
            }
            Text(provider == .codex
                 ? "记录开启后，切换到其他服务仍继续采集。暂停记录不妨碍手动查看当前 Codex 额度。"
                 : "只记录已启用桥接收到的会话事件；未运行 Claude Code 时不会主动查询订阅服务器。")
                .font(.caption).foregroundStyle(.secondary)
            let windows = store.report.windows.filter { $0.provider == provider }
            if wide {
                HStack(alignment: .top, spacing: 32) { ForEach(windows) { window($0) } }
            } else {
                VStack(alignment: .leading, spacing: 24) { ForEach(windows) { window($0) } }
            }
        }
    }

    private func window(_ value: UsageWindowInsight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(value.title).font(.headline)
                Spacer()
                Text(value.currentRemainingPercent.map { value.isFresh ? "\($0)% 剩余" : "上次 \($0)%" } ?? "当前未知")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(quotaColor(value.isFresh ? value.currentRemainingPercent : nil))
            }
            if let latest = value.latest {
                Text("最近收到 \(latest.receivedAt.formatted(date: .abbreviated, time: .standard)) · \(value.isFresh ? "新鲜" : "较旧或不可用")")
                    .font(.caption).foregroundStyle(.secondary)
                Text(value.scopeLabel).font(.caption).foregroundStyle(.secondary)
                Text(latest.source == .codexRateLimits ? "来源：Codex 额度响应" : "来源：Claude Code statusLine 被动事件")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !value.history.isEmpty {
                let showsDates = value.history.first.map { first in
                    !Calendar.current.isDate(first.date, inSameDayAs: value.history.last?.date ?? first.date)
                } ?? false
                Chart(chartPoints(value.history)) { point in
                    LineMark(x: .value("收到时间", point.date), y: .value("剩余比例", point.remainingPercent),
                             series: .value("连续观测区段", point.segmentID))
                        .foregroundStyle(value.provider == .codex ? Color.blue : Color.orange)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: showsDates ? UsageChartAxis.localDateTime : UsageChartAxis.localTime)
                    }
                }
                .chartXAxisLabel(position: .bottom, alignment: .trailing) {
                    Text("观测时间（本地）")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: UsageChartAxis.remainingPercent)
                    }
                }
                .chartYAxisLabel(position: .leading) {
                    Text("剩余额度（%）").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(height: 120)
                .accessibilityLabel("\(value.provider.title) \(value.title) 剩余额度历史，横轴为本地时间或日期，纵轴为剩余额度百分比，重置和缺口处分段")
                if value.history.count > 720 {
                    Text("图形已抽样；速度分析仍使用全部已加载观测。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("尚无连续观测。开启记录并使用对应服务后，这里会逐步形成历史。")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 10)
            }
            Text("\(value.sampleCount) 次观测 · 当前连续区段 \(value.segmentSamples) 次")
                .font(.caption).foregroundStyle(.secondary)
            if let rate = value.ratePerHour {
                Text("近期消耗 \(rate.formatted(.number.precision(.fractionLength(1)))) 个百分点 / 小时")
                    .font(.callout)
            }
            if let estimate = value.forecast {
                Text("按近期节奏，预计 \(estimate.earliest.formatted(date: .abbreviated, time: .shortened))–\(estimate.latest.formatted(date: .abbreviated, time: .shortened)) 耗尽")
                    .font(.callout.weight(.medium))
                ForEach(estimate.assumptions, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            } else {
                Text(value.unavailableReason ?? "暂无法估计耗尽时间")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resetTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("重置时间轴").font(.headline)
            if store.report.resetTimeline.isEmpty {
                Text("尚无可用的未来重置时间。缺失不会被当作已重置。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(store.report.resetTimeline) { event in
                HStack {
                    Text("\(event.provider.title) · \(event.title)")
                    Spacer()
                    Text(event.resetsAt, format: .dateTime.month().day().hour().minute())
                        .monospacedDigit()
                    Text(event.isFresh ? "预计" : "旧记录 · 待确认").foregroundStyle(.secondary)
                }.font(.callout)
            }
            Text(store.report.pacingExplanation).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var evaluation: some View {
        let value = store.report.backtest
        return VStack(alignment: .leading, spacing: 8) {
            Text("规则回放").font(.headline)
            Text("\(value.horizonMinutes) 分钟后比例回放：\(value.evaluatedCount) / \(value.attemptedCount) 个可比较点；其余暂不可估计。")
                .font(.callout)
            if let error = value.meanAbsoluteErrorPercentagePoints,
               let baseline = value.baselineMeanAbsoluteErrorPercentagePoints {
                Text("平均绝对误差 \(error.formatted(.number.precision(.fractionLength(1)))) 个百分点；保持上次值基线 \(baseline.formatted(.number.precision(.fractionLength(1)))) 个百分点。")
                    .font(.callout)
            }
            Text(value.explanation).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func quotaColor(_ percent: Int?) -> Color {
        guard let percent else { return .secondary }
        return percent >= 60 ? .green : (percent >= 30 ? .orange : .red)
    }

    private func export(allHistory: Bool) {
        Task {
            if let data = await store.export(allHistory: allHistory) {
                document = ObservationDocument(data: data)
                showsExporter = true
            }
        }
    }

    private func chartPoints(_ values: [UsageHistoryPoint]) -> [UsageHistoryPoint] {
        // ponytail: a bounded display sample; analysis and export retain all loaded raw observations.
        guard values.count > 720 else { return values }
        let step = Int(ceil(Double(values.count) / 720))
        return values.enumerated().compactMap { index, value in
            index % step == 0 || index == values.count - 1 ? value : nil
        }
    }
}

private struct ObservationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

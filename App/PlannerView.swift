import AppKit
import SwiftUI

// THESIS: A local decision aid, not an execution console. OWN-WORLD: native controls,
// semantic surfaces and Tallygent spacing. STORY: describe, compare, copy, record feedback.
// FIRST VIEWPORT: task and preference precede one explainable recommendation.
// FORM: existing workspace extension; compact widths keep one readable column.
struct PlannerView: View {
    @ObservedObject var server: QuotaMonitor
    @ObservedObject var store: PlannerStore
    @State private var taskText = ""
    @State private var context = ""
    @State private var profile = PlannerProfile()
    @State private var preference = PlannerPreference.balanced
    @AppStorage("plannerSafetyReserve") private var reserve = 10
    @State private var savesTitle = false
    @State private var advice: PlannerAdvice?
    @State private var override: PlannerConfiguration?
    @State private var manualModel: PlannerModel?
    @State private var manualIdentifier = ""
    @State private var manualEfforts = ""
    @State private var manualRole = PlannerModelRole.unknown
    @State private var feedback: PlannerTaskRecord?
    @State private var confirmsClear = false
    @State private var notice: String?

    private var models: [PlannerModel] {
        server.models.filter { $0.provider == server.service } + [manualModel].compactMap { $0 }.filter { $0.provider == server.service }
    }

    private var effectiveProfile: PlannerProfile {
        var value = profile
        if PlannerProfile.classify(taskText + " " + context).risk == .high {
            value.risk = .high
            value.signals = ["检测到安全或关键业务信号，保留高风险护栏"]
        }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                composer
                if let advice { recommendation(advice) }
                catalog
                history
                Text("仅提供建议与本地记录：不发送任务内容、不修改项目或 Codex 设置、不启动付费任务。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await store.load(); if server.service == .codex { server.refreshModelCatalog() } }
        .onChange(of: server.service) { _, _ in
            advice = nil; override = nil
            if server.service == .codex { server.refreshModelCatalog() }
        }
        .onChange(of: server.models) { _, _ in if advice != nil { recommend() } }
        .onChange(of: server.snapshot) { _, _ in if advice != nil { recommend() } }
        .onChange(of: profile) { _, _ in if advice != nil { recommend() } }
        .onChange(of: preference) { _, _ in if advice != nil { recommend() } }
        .onChange(of: reserve) { _, _ in if advice != nil { recommend() } }
        .onChange(of: store.records) { _, _ in if advice != nil { recommend() } }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if advice != nil { recommend() }
        }
        .sheet(item: $feedback) { record in PlannerFeedbackView(record: record, store: store, quota: { server.plannerQuota() }) }
        .confirmationDialog("清空全部本地任务记录？此操作不影响额度与面板设置。", isPresented: $confirmsClear) {
            Button("清空任务记录", role: .destructive) { Task { await store.clear() } }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("下一项任务，用什么配置？").font(.title2.weight(.semibold))
                Text("先解释选择，再积累你自己的反馈。不会替你执行任务。")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Picker("建议来源", selection: Binding(get: { server.service }, set: server.selectService)) {
                ForEach(AgentService.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 180)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("任务描述").font(.headline)
            TextEditor(text: $taskText)
                .font(.body).frame(height: 82).padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if taskText.isEmpty {
                        Text("例如：修复偶发的登录崩溃，并补充回归测试")
                            .foregroundStyle(.secondary).padding(12).allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("任务描述，仅在本地分析")
                .onChange(of: taskText) { _, value in
                    taskText = String(value.prefix(8_000)); advice = nil; override = nil
                }
            HStack {
                Picker("任务类别", selection: $profile.category) {
                    ForEach(PlannerCategory.allCases.filter { $0 != .automatic }) { Text($0.title).tag($0) }
                }
                Button("本地自动识别") { profile = PlannerProfile.classify(taskText + " " + context) }
                Spacer()
                Toggle("紧急", isOn: $profile.urgent).toggleStyle(.checkbox)
            }
            DisclosureGroup("任务特征与背景（可选，可覆盖自动识别）") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("补充背景（不保存）", text: $context)
                        .onChange(of: context) { _, value in context = String(value.prefix(2_000)); advice = nil }
                    HStack(spacing: 20) {
                        levelPicker("规模", value: $profile.complexity, size: true)
                        levelPicker("不确定性", value: $profile.uncertainty)
                        levelPicker("风险", value: $profile.risk)
                    }
                    Text("安全、认证和关键业务关键词始终保留高风险护栏。高 effort 不等于保证成功。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            Picker("优化偏好", selection: $preference) {
                ForEach(PlannerPreference.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Stepper("每个窗口保留 \(reserve)%", value: $reserve, in: 0...50, step: 5)
                    .fixedSize()
                Spacer()
                Button("生成建议") {
                    if profile.signals.isEmpty {
                        let inferred = PlannerProfile.classify(taskText + " " + context)
                        if profile == PlannerProfile() { profile = inferred }
                    }
                    override = nil; recommend()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func levelPicker(_ title: String, value: Binding<PlannerLevel>, size: Bool = false) -> some View {
        Picker(title, selection: value) {
            ForEach(PlannerLevel.allCases) { Text(size ? $0.sizeTitle : $0.title).tag($0) }
        }
    }

    private func recommendation(_ advice: PlannerAdvice) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(advice.shouldWait ? "建议先等待 / 保留额度" : "配置建议").font(.headline)
                Spacer()
                Text(advice.evidence).font(.caption).foregroundStyle(.secondary)
            }
            if let selected = advice.recommended {
                HStack(alignment: .firstTextBaseline) {
                    Text(selected.model.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                    Text(selected.effort).font(.title3).foregroundStyle(.secondary)
                    Spacer()
                }
                Text("\(selected.model.source) · \(selected.model.discoveredAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(advice.reasons.enumerated()), id: \.offset) { _, reason in
                    Text(reason).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup("比较替代项 / 手动覆盖") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(advice.alternatives) { alternative in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(alternative.model.name) · \(alternative.effort)")
                                    Text("\(alternative.model.role.title)方向；未测量实际质量、速度或节省比例。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("采用") { override = alternative; recommend() }
                            }
                        }
                        Picker("模型", selection: Binding(get: { selected.model.id }, set: { id in
                            if let model = models.first(where: { $0.id == id }) {
                                override = PlannerConfiguration(model: model, effort: model.defaultEffort); recommend()
                            }
                        })) {
                            ForEach(models) { Text($0.name).tag($0.id) }
                        }
                        Picker("推理强度", selection: Binding(get: { selected.effort }, set: {
                            override = PlannerConfiguration(model: selected.model, effort: $0); recommend()
                        })) {
                            ForEach(selected.model.efforts, id: \.self) { Text($0).tag($0) }
                        }
                        Button("恢复规则建议") { override = nil; recommend() }
                    }.padding(.top, 10)
                }
                quotaReadout
                VStack(alignment: .leading, spacing: 8) {
                    Text("边界与缺失信息").font(.subheadline.weight(.medium))
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(advice.warnings.enumerated()), id: \.offset) { _, warning in
                            Label(warning, systemImage: "info.circle").font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.foregroundStyle(.secondary).padding(.top, 8)
                }
                Toggle("保存任务短标题到本机（默认不保存描述或背景）", isOn: $savesTitle)
                    .font(.caption)
                HStack {
                    Button("复制配置") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(selected.copyText, forType: .string)
                        notice = "已复制模型与 effort；请自行在 \(selected.model.provider.title) 中应用。"
                    }
                    Button("保存为计划") { save(selected, start: false) }
                        .disabled(!store.isLoaded || store.isSaving || store.records.count >= 500)
                    Button("标记开始") { save(selected, start: true) }
                        .disabled(!store.isLoaded || store.isSaving || store.records.count >= 500)
                    Spacer()
                }
            } else {
                ForEach(Array(advice.warnings.enumerated()), id: \.offset) { _, warning in Text(warning).foregroundStyle(.secondary) }
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(20)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private var quotaReadout: some View {
        let quota = server.plannerQuota()
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(quota.windows) { window in
                HStack {
                    Text(window.title)
                    Text("剩余 \(window.remainingPercent)%").fontWeight(.medium)
                    Spacer()
                    if let reset = window.resetsAt { Text("重置 \(reset.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary) }
                }.font(.callout)
            }
            Text("\(quota.source) · 接收 \(quota.receivedAt == .distantPast ? "暂无" : quota.receivedAt.formatted(date: .abbreviated, time: .standard))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var catalog: some View {
        DisclosureGroup("模型目录与手动配置") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(server.service == .codex ? server.modelCatalogMessage : "Claude 暂无已接入的动态模型目录；仅支持明确标注的手动配置。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if server.service == .codex {
                        Button(server.isLoadingModels ? "读取中…" : "刷新目录") { server.refreshModelCatalog() }
                            .disabled(server.isLoadingModels)
                    }
                }
                Text("目录不做推理调用，也不证明账户已获授权。手动配置需要你确认型号与支持的 effort。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("手动采用目录默认配置") {
                    if let model = models.first(where: \.isDefault) ?? models.first {
                        override = PlannerConfiguration(model: model, effort: model.defaultEffort)
                        recommend()
                    }
                }.disabled(models.isEmpty)
                TextField("模型 ID（必须来自你已确认的本机配置）", text: $manualIdentifier)
                TextField("支持的 effort，用逗号分隔；第一项为默认档", text: $manualEfforts)
                Picker("角色（用户声明）", selection: $manualRole) {
                    ForEach(PlannerModelRole.allCases) { Text($0.title).tag($0) }
                }
                Button("采用手动目录（本次运行）") {
                    let efforts = manualEfforts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    let model = PlannerModel(provider: server.service, identifier: manualIdentifier.trimmingCharacters(in: .whitespaces),
                                             name: manualIdentifier.trimmingCharacters(in: .whitespaces), detail: "用户手动配置；能力未核验", efforts: efforts,
                                             defaultEffort: efforts.first ?? "", isDefault: false, role: manualRole,
                                             source: "用户声明，未核验", discoveredAt: .now, manuallyConfigured: true)
                    guard model.isValid, !server.models.contains(where: { $0.id == model.id }) else {
                        notice = "模型 ID / effort 无效或与当前目录重复。"; return
                    }
                    manualModel = model
                    override = PlannerConfiguration(model: model, effort: model.defaultEffort)
                    recommend()
                }
                if let manualModel { Text("已加入：\(manualModel.name)（未核验）").font(.caption).foregroundStyle(.secondary) }
                if advice == nil, let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }.padding(.top, 12)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("计划与反馈").font(.headline)
                Spacer()
                Text("\(store.records.count) / 500 条 · 仅本机").font(.caption).foregroundStyle(.secondary)
                Button("清空", role: .destructive) { confirmsClear = true }
                    .disabled(store.isSaving)
            }
            if let error = store.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled) }
            if let chosen = advice?.recommended {
                let summary = PlannerEngine.summary(records: store.records, profile: effectiveProfile, configuration: chosen, scope: server.plannerQuota().scope)
                if summary.evaluated >= 5 {
                    Text("同类配置：\(summary.evaluated) 条已评估，完成 \(summary.succeeded) 条，存在失败/返工/较多重试 \(summary.adverse) 条。")
                        .font(.callout).foregroundStyle(.secondary)
                    if let tokens = summary.medianReportedTokens {
                        Text("用户填报 Token 中位数 \(tokens)；不等同于额度消耗，也不用于未来预算保证。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if store.records.isEmpty {
                Text("还没有任务记录。先保存计划或标记开始；至少 5 条同类人工反馈后才参与规则校准。期间账户变化不等于该任务消耗。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(store.records) { record in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(record.configuration.model.identifier) · \(record.configuration.effort) · \(record.profile.category.title)")
                            Text(record.attribution).foregroundStyle(.secondary)
                            Text("重试 \(record.retries) · \(record.verification.title)\(record.manualRework ? " · 有手工返工" : "")")
                            if let tokens = record.tokens { Text("填报 Token：输入 \(tokens.input)，输出 \(tokens.output)；\(tokens.source)") }
                            HStack {
                                if record.outcome == .planned {
                                    Button("标记开始") { Task { await store.start(record.id, quota: server.plannerQuota()) } }
                                        .disabled(record.configuration.model.provider != server.service)
                                }
                                if [.running, .interrupted].contains(record.outcome) {
                                    Button("记录结果") { feedback = record }
                                }
                                Spacer()
                                Button("删除记录", role: .destructive) { Task { await store.delete(record.id) } }
                            }.disabled(store.isSaving)
                        }.font(.caption).padding(.top, 8)
                    } label: {
                        HStack {
                            Text(record.title ?? "\(record.profile.category.title) · \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            Spacer()
                            Text(record.outcome.title).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
            }
        }
    }

    private func recommend() {
        advice = PlannerEngine.advise(profile: effectiveProfile, preference: preference, models: models,
                                       quota: server.plannerQuota(), reserve: reserve, records: store.records, override: override)
    }

    private func save(_ configuration: PlannerConfiguration, start: Bool) {
        Task {
            if await store.saveTask(profile: effectiveProfile, preference: preference, configuration: configuration,
                                    title: savesTitle ? taskText : nil, quota: server.plannerQuota(), start: start) {
                notice = start ? "已标记开始；请在 \(configuration.model.provider.title) 中手动执行，结束后记录结果。" : "计划已保存；未启动任务。"
            }
        }
    }
}

private struct PlannerFeedbackView: View {
    let record: PlannerTaskRecord
    @ObservedObject var store: PlannerStore
    let quota: () -> PlannerQuota
    @Environment(\.dismiss) private var dismiss
    @State private var outcome = PlannerOutcome.notEvaluated
    @State private var retries = 0
    @State private var quality = 0
    @State private var rework = false
    @State private var verification = PlannerVerification.notRun
    @State private var inputTokens = ""
    @State private var outputTokens = ""

    private var tokens: PlannerTokenUsage? {
        guard !inputTokens.isEmpty || !outputTokens.isEmpty,
              let input = Int64(inputTokens), let output = Int64(outputTokens) else { return nil }
        let value = PlannerTokenUsage(input: input, output: output)
        return value.isValid ? value : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("记录任务结果").font(.title2.weight(.semibold))
            Form {
                Picker("结果", selection: $outcome) {
                    ForEach([PlannerOutcome.succeeded, .partial, .failed, .notEvaluated]) { Text($0.title).tag($0) }
                }
                Picker("质量反馈", selection: $quality) {
                    Text("未评价").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0) / 5").tag($0) }
                }
                Stepper("重试 \(retries) 次", value: $retries, in: 0...20)
                Toggle("需要手工返工", isOn: $rework)
                Picker("测试 / 验证", selection: $verification) {
                    ForEach(PlannerVerification.allCases) { Text($0.title).tag($0) }
                }
                TextField("输入 Token（可选，需与输出一起填）", text: $inputTokens)
                TextField("输出 Token（可选）", text: $outputTokens)
            }
            Text("Token 为你的填报值，不自动当成可信成本。起止账户额度可能含并发、其他设备或重置，不用于精确成本校准。")
                .font(.caption).foregroundStyle(.secondary)
            if let error = store.error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存反馈") {
                    Task {
                        await store.complete(record.id, outcome: outcome, quota: quota(), retries: retries,
                                             quality: quality == 0 ? nil : quality, rework: rework, verification: verification, tokens: tokens)
                        if store.error == nil { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isSaving || ((!inputTokens.isEmpty || !outputTokens.isEmpty) && tokens == nil))
            }
        }.padding(24).frame(width: 480)
    }
}

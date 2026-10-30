import Foundation

public enum PlannerCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, routine, ui, feature, debugging, refactor, architecture, review, other
    public var id: Self { self }
    public var title: String {
        switch self {
        case .automatic: L("自动识别")
        case .routine: L("日常修改")
        case .ui: L("界面开发")
        case .feature: L("功能实现")
        case .debugging: L("排查 Bug")
        case .refactor: L("代码重构")
        case .architecture: L("架构设计")
        case .review: L("测试与审查")
        case .other: L("其他")
        }
    }
}

public enum PlannerLevel: Int, Codable, CaseIterable, Identifiable, Sendable {
    case low, medium, high
    public var id: Self { self }
    public var title: String { [L("低"), L("中"), L("高")][rawValue] }
    public var sizeTitle: String { [L("小"), L("中"), L("大")][rawValue] }
}

public enum PlannerPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case quality, balanced, efficiency
    public var id: Self { self }
    public var title: String {
        switch self { case .quality: L("质量优先"); case .balanced: L("平衡"); case .efficiency: L("效率优先") }
    }
}

/// Ordinal task requirements, not benchmark scores. Unmatched dimensions stay unknown.
public struct PlannerTaskDimensions: Codable, Equatable, Sendable {
    public var scope: PlannerLevel?
    public var integration: PlannerLevel?
    public var context: PlannerLevel?
    public var verification: PlannerLevel?
    public var decomposable: Bool
    /// A detected test requirement, not evidence that tests exist, pass, or catch every failure.
    public var automatedVerification: Bool
    public var confidence: PlannerLevel

    public init(scope: PlannerLevel? = nil, integration: PlannerLevel? = nil, context: PlannerLevel? = nil,
                verification: PlannerLevel? = nil, decomposable: Bool = false,
                automatedVerification: Bool = false, confidence: PlannerLevel = .low) {
        self.scope = scope; self.integration = integration; self.context = context
        self.verification = verification; self.decomposable = decomposable
        self.automatedVerification = automatedVerification; self.confidence = confidence
    }
}

public struct PlannerProfile: Codable, Equatable, Sendable {
    public var category: PlannerCategory
    public var complexity: PlannerLevel
    public var uncertainty: PlannerLevel
    public var risk: PlannerLevel
    public var urgent: Bool
    public var signals: [String]
    /// Optional so existing schema-1 feedback records remain readable without invented requirements.
    public var dimensions: PlannerTaskDimensions?

    public init(category: PlannerCategory = .feature, complexity: PlannerLevel = .medium,
                uncertainty: PlannerLevel = .medium, risk: PlannerLevel = .low,
                urgent: Bool = false, signals: [String] = [], dimensions: PlannerTaskDimensions? = nil) {
        self.category = category; self.complexity = complexity; self.uncertainty = uncertainty
        self.risk = risk; self.urgent = urgent; self.signals = signals
        self.dimensions = dimensions
    }

    public static func classify(_ text: String) -> Self {
        // Bound work at the same limit as the composer; never persist matched task fragments.
        let bounded = String(text.prefix(10_000))
        let text = (bounded.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? bounded).lowercased()
        func contains(_ words: [String]) -> Bool {
            words.contains { word in
                if word.unicodeScalars.contains(where: { $0.value > 127 }) { return text.contains(word) }
                // ASCII word boundaries also work for English terms embedded in Chinese text.
                return text.range(of: "(?<![a-z0-9_])" + NSRegularExpression.escapedPattern(for: word) + "(?![a-z0-9_])",
                                  options: .regularExpression) != nil
            }
        }
        let category: PlannerCategory
        if contains(["架构", "architecture", "architectural", "分布式", "系统设计", "system design"]) { category = .architecture }
        else if contains(["bug", "bugs", "崩溃", "debug", "debugging", "crash", "crashes", "报错", "排查", "故障"]) { category = .debugging }
        else if contains(["重构", "refactor", "refactoring"]) { category = .refactor }
        else if contains(["ui", "界面", "布局", "样式", "窗口", "layout", "css", "accessibility"]) { category = .ui }
        else if contains(["文案", "拼写", "typo", "typos", "rename", "改名", "注释", "格式", "翻译", "documentation", "translate", "format", "formatting"]) { category = .routine }
        else if contains(["功能", "feature", "implement", "实现", "开发"]) { category = .feature }
        else if contains(["测试", "审查", "test", "tests", "testing", "review", "audit", "分析", "analysis", "analyze"]) { category = .review }
        else if contains(["增加", "add"]) { category = .feature }
        else { category = .other }
        let sensitive = contains(["安全", "密钥", "认证", "授权", "登录", "支付", "隐私", "生产数据", "删除数据", "security", "auth", "authentication", "authorization", "login", "payment", "payments", "credential", "credentials", "privacy", "data loss", "数据库迁移", "database migration"])
        let wideScope = category == .architecture || contains(["跨模块", "多文件", "全仓库", "整个代码库", "cross-module", "multi-file", "multi file", "multiple files", "repository-wide", "entire codebase", "whole repository"])
        let isolated = contains(["单文件", "一个文件", "单函数", "小范围", "孤立", "single-file", "single file", "one file", "single function", "isolated"])
        let integrationHeavy = contains(["跨服务", "多服务", "分布式", "数据库迁移", "协议兼容", "cross-service", "multi-service", "distributed", "database migration", "protocol compatibility"])
        let integration = integrationHeavy || contains(["集成", "依赖", "接口", "integration", "dependency", "dependencies", "api"])
        let longContext = contains(["长上下文", "全仓库分析", "大型代码库", "long-context", "long context", "large codebase", "codebase analysis", "entire codebase", "whole repository"])
        let large = wideScope || integrationHeavy || longContext || contains(["迁移", "复杂", "并发", "migration", "concurrency", "complex"])
        let uncertain = contains(["未知", "偶发", "无法复现", "不确定", "根因", "unknown", "intermittent", "root cause", "cannot reproduce"])
        let vague = category == .other || contains(["优化一下", "看着办", "不明确", "未指定", "未说明", "make it better", "improve it", "fix it", "something wrong", "unspecified", "underspecified", "ambiguous", "unclear requirements"])
        let automatedVerification = contains(["单元测试", "回归测试", "自动化测试", "测试套件", "unit test", "unit tests", "regression test", "regression tests", "automated tests", "test suite"])
        let complexVerification = sensitive || uncertain || contains(["端到端", "模糊测试", "形式验证", "end-to-end", "fuzzing", "formal verification"])
        let decomposable = contains(["分阶段", "独立子任务", "独立模块", "staged", "stages", "independent tasks", "independent components", "step by step"])
        let urgent = contains(["紧急", "立即", "urgent", "asap", "hotfix"])
        let dimensions = PlannerTaskDimensions(
            scope: wideScope ? .high : (isolated || category == .routine ? .low : nil),
            integration: integrationHeavy ? .high : (integration ? .medium : nil),
            context: longContext ? .high : (isolated ? .low : nil),
            verification: complexVerification ? .high : (automatedVerification ? .medium : nil),
            decomposable: decomposable, automatedVerification: automatedVerification,
            confidence: vague || uncertain ? .low : .medium
        )
        var signals = [L("本地关键词规则；未扫描项目或发送任务文本")]
        signals.append(L("任务特征按范围、集成、上下文与验证需求分别识别；未命中维度保持未知。"))
        if category == .other { signals.append(L("未识别明确任务类型；请补充目标、范围和验收标准。")) }
        if large { signals.append(L("检测到跨模块、迁移、并发或架构信号，按高复杂度处理。")) }
        if uncertain { signals.append(L("检测到根因或复现不确定性，保留更深入的推理。")) }
        if vague { signals.append(L("需求或验收条件不明确；分类证据较弱，建议先澄清。")) }
        if longContext { signals.append(L("检测到长上下文需求；描述长度本身不决定任务难度。")) }
        if automatedVerification { signals.append(L("检测到可重复的自动化验证信号；不代表测试已经通过。")) }
        if decomposable { signals.append(L("检测到可拆分的阶段信号；是否值得分阶段仍需比较协调开销。")) }
        if sensitive { signals.append(L("检测到安全或关键业务信号")) }
        if urgent { signals.append(L("检测到紧急信号；紧急程度不降低复杂度或风险底线。")) }
        return Self(category: category, complexity: large ? .high : (isolated || category == .routine ? .low : .medium),
                    uncertainty: uncertain || vague ? .high : (isolated || category == .routine ? .low : .medium),
                    risk: sensitive ? .high : .low, urgent: urgent, signals: signals, dimensions: dimensions)
    }

    public static func resolved(_ text: String, previous: Self, manual: Bool) -> Self {
        guard !manual else { return previous }
        return classify(text)
    }
}

public enum PlannerModelRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case unknown, efficient, balanced, quality
    public var id: Self { self }
    public var title: String {
        switch self { case .unknown: L("未标注"); case .efficient: L("偏效率"); case .balanced: L("通用"); case .quality: L("偏复杂任务") }
    }
}

public struct PlannerModel: Codable, Equatable, Identifiable, Sendable {
    public var id: String { provider.rawValue + ":" + identifier }
    public var provider: AgentService
    public var identifier: String
    public var name: String
    public var detail: String
    public var efforts: [String]
    public var defaultEffort: String
    public var isDefault: Bool
    public var role: PlannerModelRole
    public var source: String
    public var discoveredAt: Date
    public var manuallyConfigured: Bool

    public var isValid: Bool {
        Self.safeIdentifier(identifier) && !name.isEmpty && name.count <= 160 && !efforts.isEmpty && efforts.count <= 16
            && Set(efforts).count == efforts.count && efforts.allSatisfy(Self.safeIdentifier) && efforts.contains(defaultEffort)
    }

    public static func safeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 160 && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:/")).contains($0)
        }
    }

    public static func merged(live: [Self], manual: Self?, provider: AgentService, at date: Date = .now) -> [Self] {
        let valid = live.filter { $0.provider == provider && $0.isValid && date.timeIntervalSince($0.discoveredAt) <= 1_800 && date >= $0.discoveredAt.addingTimeInterval(-5) }
        // Conflicting entries cannot safely define a single Picker/configuration contract.
        let current = Dictionary(grouping: valid, by: \.id).values.compactMap { entries -> Self? in
            let authoritative = entries.filter { !$0.manuallyConfigured }
            let choices = authoritative.isEmpty ? entries : authoritative
            guard let first = choices.first, choices.allSatisfy({ $0 == first }) else { return nil }
            return first
        }.sorted { $0.id < $1.id }
        guard let manual, manual.isValid, manual.manuallyConfigured, manual.provider == provider,
              !current.contains(where: { $0.id == manual.id }) else { return current }
        return (current + [manual]).sorted { $0.id < $1.id }
    }

    /// The local catalog is a picker contract, not a successful inference entitlement check.
    public static func parsePage(_ object: [String: Any], at date: Date) throws -> (models: [Self], cursor: String?) {
        guard let result = object["result"] as? [String: Any], let entries = result["data"] as? [[String: Any]], entries.count <= 200 else {
            throw PlannerError.invalidCatalog
        }
        let models = entries.compactMap { entry -> Self? in
            if let modalities = entry["inputModalities"] as? [String], !modalities.contains("text") { return nil }
            guard entry["hidden"] as? Bool != true, entry["available"] as? Bool != false,
                  let identifier = entry["model"] as? String,
                  let name = entry["displayName"] as? String,
                  let supported = entry["supportedReasoningEfforts"] as? [[String: Any]],
                  let defaultEffort = entry["defaultReasoningEffort"] as? String else { return nil }
            let efforts = supported.compactMap { $0["reasoningEffort"] as? String }
            let detail = String((entry["description"] as? String ?? "").prefix(600))
            let lower = detail.lowercased()
            let role: PlannerModelRole
            if ["most capable", "most powerful", "demanding", "最强", "复杂任务"].contains(where: lower.contains) { role = .quality }
            else if ["fast", "efficient", "lightweight", "快速", "高效"].contains(where: lower.contains) { role = .efficient }
            else if entry["isDefault"] as? Bool == true { role = .balanced }
            else { role = .unknown }
            let model = Self(provider: .codex, identifier: identifier, name: String(name.prefix(160)), detail: detail,
                             efforts: Array(Set(efforts)).sorted { (effortRank($0), $0) < (effortRank($1), $1) },
                             defaultEffort: defaultEffort, isDefault: entry["isDefault"] as? Bool ?? false,
                             role: role, source: "Codex app-server · model/list", discoveredAt: date, manuallyConfigured: false)
            return model.isValid ? model : nil
        }
        if let value = result["nextCursor"], !(value is NSNull), !(value is String) { throw PlannerError.invalidCatalog }
        return (models, result["nextCursor"] as? String)
    }

    public static func effortRank(_ value: String) -> Int {
        ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"].firstIndex(of: value) ?? 99
    }
}

public struct PlannerConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var model: PlannerModel
    public var effort: String
    public var id: String { model.id + ":" + effort }
    public var isValid: Bool { model.isValid && model.efforts.contains(effort) }
    public var copyText: String {
        model.provider == .codex ? "model = \"\(model.identifier)\"\nmodel_reasoning_effort = \"\(effort)\""
            : LF("Provider: %@\nModel: %@\nReasoning effort: %@\nUser-declared configuration; apply manually.", model.provider.title, model.identifier, effort)
    }
}

public struct PlannerQuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var remainingPercent: Int
    public var resetsAt: Date?
    public var durationMinutes: Int? = nil

    public var isValid: Bool {
        guard (0...100).contains(remainingPercent), resetsAt?.timeIntervalSince1970.isFinite != false else { return false }
        switch id {
        case "fiveHour": return durationMinutes == nil || durationMinutes == 300
        case "weekly": return durationMinutes == nil || durationMinutes == 10_080
        default: return false
        }
    }
}

public enum PlannerQuotaStatus: Sendable { case available, wait, unknown }

public struct PlannerQuotaAssessment: Sendable {
    public var status: PlannerQuotaStatus
    /// Minimum remaining percentage after the reserve; never a task cost estimate.
    public var usablePercent: Int?
    /// A reserve is a user policy, not a provider-imposed limit.
    public var providerExhausted: Bool = false
}

public struct PlannerQuota: Codable, Equatable, Sendable {
    public var provider: AgentService
    public var scope: String?
    public var source: String
    public var receivedAt: Date
    public var windows: [PlannerQuotaWindow]
    public var connected: Bool

    public func isFresh(at date: Date) -> Bool {
        let age = date.timeIntervalSince(receivedAt)
        return connected && age >= -5 && age <= (provider == .codex ? 120 : 300)
    }

    public func warnings(reserve: Int, at date: Date) -> [String] {
        let reserve = min(100, max(0, reserve))
        guard !windows.isEmpty else { return [L("额度数据缺失；本建议未通过额度校验。")] }
        var warnings: [String] = []
        if !hasValidWindows { warnings.append(L("额度窗口重复、百分比或周期无效；本建议未通过额度校验。")) }
        if !isFresh(at: date) { warnings.append(L("额度记录较旧或来源未连接；请刷新后再判断可用量。")) }
        for (id, title) in [("fiveHour", L("5h 额度")), ("weekly", L("周额度"))] where !windows.contains(where: { $0.id == id }) {
            warnings.append(LF("来源未提供%@窗口，无法校验该约束；不能仅凭另一个窗口判断可运行。", title))
        }
        for window in windows {
            guard window.isValid else { continue }
            if let reset = window.resetsAt, reset <= date {
                warnings.append(LF("%@已到重置点，等待来源确认新周期。", L(window.title)))
            } else if window.remainingPercent <= reserve {
                warnings.append(LF("%@剩余 %lld%% ≤ 保留量 %lld%%：建议等待或手动调整预算。", L(window.title), window.remainingPercent, reserve))
            } else if window.remainingPercent < 30 {
                warnings.append(LF("%@仅剩 %lld%%；不能只看另一个较充足的窗口。", L(window.title), window.remainingPercent))
            }
            if window.resetsAt == nil { warnings.append(LF("%@缺少重置时间，当前周期有效性未知。", L(window.title))) }
        }
        if scope == nil { warnings.append(L("账户/会话范围未知，不能把本次额度变化归因给任务。")) }
        warnings.append(L("任务预计额度消耗未知；百分比不是可用 Token 数，也不保证任务可完成。"))
        return warnings
    }

    public func shouldWait(reserve: Int, at date: Date) -> Bool {
        assessment(reserve: reserve, at: date).status == .wait
    }

    public var hasValidWindows: Bool {
        !windows.isEmpty && windows.allSatisfy(\.isValid) && Set(windows.map(\.id)).count == windows.count
    }

    public func assessment(reserve: Int, at date: Date) -> PlannerQuotaAssessment {
        guard isFresh(at: date), hasValidWindows else { return .init(status: .unknown, usablePercent: nil) }
        let reserve = min(100, max(0, reserve))
        let current = windows.filter { $0.resetsAt.map { $0 > date } == true }
        // A known exhausted window blocks work even when another constraint is missing.
        if current.contains(where: { $0.remainingPercent == 0 }) {
            return .init(status: .wait, usablePercent: 0, providerExhausted: true)
        }
        if current.contains(where: { $0.remainingPercent <= reserve }) { return .init(status: .wait, usablePercent: 0) }
        guard current.count == windows.count, Set(current.map(\.id)) == Set(["fiveHour", "weekly"]) else {
            return .init(status: .unknown, usablePercent: nil)
        }
        return .init(status: .available, usablePercent: current.map { $0.remainingPercent - reserve }.min())
    }
}

public enum PlannerOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned, running, succeeded, partial, failed, notEvaluated, interrupted
    public var id: Self { self }
    public var title: String {
        switch self {
        case .planned: L("待开始"); case .running: L("进行中"); case .succeeded: L("完成"); case .partial: L("部分完成")
        case .failed: L("失败"); case .notEvaluated: L("未评估"); case .interrupted: L("中断待确认")
        }
    }
    public var isEvaluated: Bool { [.succeeded, .partial, .failed].contains(self) }
}

public enum PlannerVerification: String, Codable, CaseIterable, Identifiable, Sendable {
    case notRun, passed, failed
    public var id: Self { self }
    public var title: String { switch self { case .notRun: L("未验证"); case .passed: L("验证通过"); case .failed: L("验证失败") } }
}

public struct PlannerTokenUsage: Codable, Equatable, Sendable {
    public var input: Int64
    public var output: Int64
    public var source: String = "用户填报，未自动核验"
    public var total: Int64 { input + output }
    public var isValid: Bool { input >= 0 && output >= 0 && input <= 1_000_000_000 && output <= 1_000_000_000 }
}

public struct PlannerTaskRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    // Raw task text is not stored by default. A short label is explicitly opt-in.
    public var title: String?
    public var profile: PlannerProfile
    public var preference: PlannerPreference
    public var configuration: PlannerConfiguration
    public var createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var before: PlannerQuota?
    public var after: PlannerQuota?
    public var outcome: PlannerOutcome = .planned
    public var retries: Int = 0
    public var quality: Int?
    public var manualRework: Bool = false
    public var verification: PlannerVerification = .notRun
    public var tokens: PlannerTokenUsage?

    public var attribution: String {
        guard let before, let after, let startedAt, let completedAt else { return L("无完整执行区间") }
        guard startedAt <= completedAt, before.hasValidWindows, after.hasValidWindows,
              Set(before.windows.map(\.id)) == Set(after.windows.map(\.id)) else { return L("跨重置或窗口变化，不可归因") }
        guard before.provider == configuration.model.provider, before.provider == after.provider,
              let scope = before.scope, !scope.isEmpty, after.scope == scope else { return L("账户或会话范围变化/未知") }
        guard before.isFresh(at: startedAt), after.isFresh(at: completedAt) else { return L("起止额度记录过期") }
        for window in before.windows {
            guard let end = after.windows.first(where: { $0.id == window.id }), let reset = window.resetsAt,
                  end.resetsAt == reset, end.durationMinutes == window.durationMinutes,
                  reset > completedAt, end.remainingPercent <= window.remainingPercent else {
                return L("跨重置或窗口变化，不可归因")
            }
        }
        return L("期间账户变化；并发/其他设备未隔离，不用于额度成本预测")
    }

    public var isValid: Bool {
        configuration.isValid && (0...20).contains(retries) && (quality == nil || (1...5).contains(quality!))
            && (tokens == nil || tokens!.isValid) && (title?.utf8.count ?? 0) <= 1_000
    }
}

public struct PlannerHistorySummary: Sendable {
    public var evaluated: Int
    public var succeeded: Int
    public var adverse: Int
    public var medianReportedTokens: Int64?
    public var tokenEstimate: PlannerTokenEstimate?
    public var verifiedCompletions: Int = 0
    public var completionTokens: PlannerTokenEstimate? = nil
    public var minimumSamples: Int = 5
    public var discourages: Bool { evaluated >= minimumSamples && adverse * 5 >= evaluated * 2 }
}

/// Observed user-reported totals, not provider billing or an isolated task cost model.
public struct PlannerTokenEstimate: Sendable {
    public var sampleCount: Int
    public var median: Int64
    public var lower: Int64
    public var upper: Int64
}

public enum PlannerDecision: Sendable {
    case configuration, wait, needsInformation, unavailable
    public var title: String {
        switch self {
        case .configuration: L("规则配置建议")
        case .wait: L("建议先等待 / 保留额度")
        case .needsInformation: L("信息不足，请补充或刷新")
        case .unavailable: L("暂无合适配置，请刷新目录或手动确认")
        }
    }
}

public struct PlannerAdvice: Sendable {
    public var recommended: PlannerConfiguration?
    public var alternatives: [PlannerConfiguration]
    public var reasons: [String]
    public var warnings: [String]
    public var evidence: String
    public var shouldWait: Bool
    public var decision: PlannerDecision
    /// Qualitative evidence strength, deliberately capped at medium until benchmarked.
    public var confidence: PlannerLevel
    public var quotaAssessment: PlannerQuotaAssessment
    public var tokenEstimate: PlannerTokenEstimate?
    public var evaluations: [PlannerCandidateEvaluation] = []
    public var quotaPressure: Double? = nil
    public var qualitySatisfied: Bool = false
    public var policyVersion: Int = PlannerPolicy.version
}

/// Versioned ordinal policy; no dollar prices, model benchmarks or learned probabilities.
public struct PlannerPolicy: Sendable {
    public static let version = 2
    public let minimumSamples: Int
    public let feedbackMaximumAgeDays: Int
    public let maximumPressure: Double
    public init(minimumSamples: Int = 5, feedbackMaximumAgeDays: Int = 90, maximumPressure: Double = 4) {
        self.minimumSamples = min(100, max(5, minimumSamples))
        self.feedbackMaximumAgeDays = min(365, max(1, feedbackMaximumAgeDays))
        self.maximumPressure = maximumPressure.isFinite ? min(10, max(1, maximumPressure)) : 4
    }
}

/// An account-window pace, not a model price or task-cost measurement.
public struct PlannerQuotaPace: Sendable {
    public var provider: AgentService
    public var scope: String?
    public var windowID: String
    public var receivedAt: Date
    public var resetsAt: Date?
    public var remainingPercent: Int
    public var ratePerHour: Double
    public var samples: Int
    public var observedSpan: TimeInterval
    public init(provider: AgentService, scope: String?, windowID: String, receivedAt: Date, resetsAt: Date?,
                remainingPercent: Int, ratePerHour: Double, samples: Int, observedSpan: TimeInterval) {
        self.provider = provider; self.scope = scope; self.windowID = windowID; self.receivedAt = receivedAt
        self.resetsAt = resetsAt; self.remainingPercent = remainingPercent; self.ratePerHour = ratePerHour
        self.samples = samples; self.observedSpan = observedSpan
    }
}

public struct PlannerCandidateEvaluation: Sendable {
    public var configuration: PlannerConfiguration
    public var qualitySatisfied: Bool
    /// Descriptive-role tier only; nil means unknown, never zero capability/cost.
    public var ordinalResourceTier: Int?
    public var completionTokens: PlannerTokenEstimate?
    public var feedbackSamples: Int
    /// Smoothed self-report frequency, not a calibrated probability of future failure.
    public var adverseBurden: Double?
}

public enum PlannerEngine {
    public static func summary(records: [PlannerTaskRecord], profile: PlannerProfile,
                               configuration: PlannerConfiguration, scope: String?, at date: Date = .now,
                               policy: PlannerPolicy = PlannerPolicy()) -> PlannerHistorySummary {
        // Identical duplicates count once; contradictory copies of an ID provide no safe evidence.
        let unique = Dictionary(grouping: records, by: \.id).values.compactMap { values -> PlannerTaskRecord? in
            guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
            return first
        }
        let relevant = unique.filter {
            $0.isValid && $0.configuration.id == configuration.id && $0.profile.category == profile.category
                && $0.profile.complexity == profile.complexity && $0.profile.risk == profile.risk
                && $0.profile.uncertainty == profile.uncertainty && $0.outcome.isEvaluated
                && scope?.isEmpty == false && $0.before?.scope == scope && $0.after?.scope == scope
                && $0.before?.provider == configuration.model.provider && $0.after?.provider == configuration.model.provider
                && $0.startedAt != nil && $0.completedAt != nil && $0.createdAt <= $0.startedAt!
                && $0.startedAt! <= $0.completedAt! && $0.completedAt! <= date
                && $0.completedAt! >= date.addingTimeInterval(-Double(policy.feedbackMaximumAgeDays) * 86_400)
                && $0.profile.dimensions == profile.dimensions
        }
        let totals = relevant.compactMap { $0.tokens?.isValid == true ? $0.tokens?.total : nil }.sorted()
        func estimate(_ values: [Int64]) -> PlannerTokenEstimate? {
            let sorted = values.sorted()
            guard sorted.count >= policy.minimumSamples else { return nil }
            return .init(sampleCount: sorted.count, median: (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2,
                         lower: sorted.first!, upper: sorted.last!)
        }
        let reported = estimate(totals)
        let completed = relevant.filter { $0.outcome == .succeeded && $0.verification == .passed && !$0.manualRework }
        return PlannerHistorySummary(evaluated: relevant.count, succeeded: relevant.filter { $0.outcome == .succeeded }.count,
                                     adverse: relevant.filter { $0.outcome != .succeeded || $0.manualRework || $0.verification == .failed || $0.retries > 1 || ($0.quality ?? 5) <= 2 }.count,
                                     medianReportedTokens: reported?.median, tokenEstimate: reported,
                                     verifiedCompletions: completed.count,
                                     completionTokens: estimate(completed.compactMap { $0.tokens?.total }),
                                     minimumSamples: policy.minimumSamples)
    }

    /// Pure local entry point. A future text-analysis provider may propose a profile,
    /// but must still pass this engine's catalog, effort and quota validation.
    public static func advise(task: String, previous: PlannerProfile = PlannerProfile(), manual: Bool = false, urgent: Bool? = nil,
                              preference: PlannerPreference, models: [PlannerModel], quota: PlannerQuota,
                              reserve: Int, records: [PlannerTaskRecord], override: PlannerConfiguration? = nil,
                              at date: Date = .now, pacing: [PlannerQuotaPace] = [],
                              policy: PlannerPolicy = PlannerPolicy()) -> PlannerAdvice {
        var profile = PlannerProfile.resolved(task, previous: previous, manual: manual)
        let automatic = PlannerProfile.classify(task)
        profile.urgent = urgent ?? automatic.urgent
        if automatic.risk == .high { profile.risk = .high }
        var advice = advise(profile: profile, preference: preference, models: models, quota: quota,
                            reserve: reserve, records: records, override: override, at: date, pacing: pacing, policy: policy)
        if task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            advice.recommended = nil; advice.alternatives = []; advice.tokenEstimate = nil
            advice.evaluations = []; advice.qualitySatisfied = false
            advice.decision = .needsInformation; advice.confidence = .low
            advice.warnings.insert(L("尚未填写任务描述；此时只能查看配置，不能评估适配性或保存任务。"), at: 0)
        }
        return advice
    }

    public static func advise(profile: PlannerProfile, preference: PlannerPreference, models: [PlannerModel],
                              quota: PlannerQuota, reserve: Int, records: [PlannerTaskRecord],
                              override: PlannerConfiguration? = nil, at date: Date = .now,
                              pacing: [PlannerQuotaPace] = [], policy: PlannerPolicy = PlannerPolicy()) -> PlannerAdvice {
        let reserve = min(100, max(0, reserve))
        let available = PlannerModel.merged(live: models, manual: nil, provider: quota.provider, at: date)
        let conservative = profile.risk == .high || profile.uncertainty == .high || profile.complexity == .high
        let minimumRank = conservative ? 4 : (profile.complexity == .low ? 2 : 3)
        let desiredRank = conservative || preference == .quality ? 4 : minimumRank
        let desiredRole: PlannerModelRole = conservative || preference == .quality ? .quality : (preference == .efficiency || profile.urgent ? .efficient : .balanced)
        let quotaAssessment = quota.assessment(reserve: reserve, at: date)
        let pressure = quotaPressure(quota: quota, reserve: reserve, pacing: pacing, at: date, policy: policy)
        let saving = preference == .efficiency || (preference == .balanced && (pressure ?? 1) > 1)
        let minimumRole = conservative || preference == .quality ? 2 : (profile.complexity == .low ? 0 : 1)
        func tier(_ role: PlannerModelRole) -> Int? {
            switch role { case .efficient: 0; case .balanced: 1; case .quality: 2; case .unknown: nil }
        }
        func qualitySatisfied(_ item: PlannerConfiguration) -> Bool {
            tier(item.model.role).map { $0 >= minimumRole } == true
                && (minimumRank..<99).contains(PlannerModel.effortRank(item.effort))
        }
        var warnings = quota.warnings(reserve: reserve, at: date)
        var reasons = [LF("%@ · 规模%@ · 不确定性%@ · 风险%@。", profile.category.title, profile.complexity.sizeTitle, profile.uncertainty.title, profile.risk.title),
                       L("模型角色仅依据目录描述或用户配置；没有测量过的模型质量、速度和额度价格不作精确比较。")]
        reasons += profile.signals
        func roleRank(_ role: PlannerModelRole) -> Int {
            let order: [PlannerModelRole]
            switch desiredRole {
            case .quality: order = [.quality, .balanced, .unknown, .efficient]
            case .efficient: order = [.efficient, .balanced, .unknown, .quality]
            default: order = [.balanced, .quality, .unknown, .efficient]
            }
            return order.firstIndex(of: role)!
        }
        // Enumerate real combinations, not a hard-coded list of model names or efforts.
        let candidates = available.flatMap { model -> [PlannerConfiguration] in
            let efforts = model.efforts.filter { (minimumRank..<99).contains(PlannerModel.effortRank($0)) }
            return efforts.map { PlannerConfiguration(model: model, effort: $0) }
        }
        let summaries = Dictionary(uniqueKeysWithValues: candidates.map {
            ($0.id, summary(records: records, profile: profile, configuration: $0, scope: quota.scope, at: date, policy: policy))
        })
        let feasible = candidates.filter(qualitySatisfied)
        let pool = feasible.isEmpty ? candidates : feasible
        // Higher effort is not assumed to improve quality. Prefer the nearest sufficient
        // supported effort per model; do not evade bad feedback by escalating it blindly.
        let nearest = Dictionary(grouping: pool, by: { $0.model.id }).values.compactMap { values in
            values.min { (abs(PlannerModel.effortRank($0.effort) - desiredRank), PlannerModel.effortRank($0.effort), $0.id)
                < (abs(PlannerModel.effortRank($1.effort) - desiredRank), PlannerModel.effortRank($1.effort), $1.id) }
        }
        // Choose a common unit for the WHOLE comparison. Pairwise missing-cost fallbacks
        // can create non-transitive A<B<C<A orderings; unknown must never become free.
        let comparableCosts = !nearest.isEmpty && nearest.allSatisfy { summaries[$0.id]?.completionTokens != nil }
        let comparableFeedback = !nearest.isEmpty && nearest.allSatisfy { (summaries[$0.id]?.evaluated ?? 0) >= policy.minimumSamples }
        func score(_ item: PlannerConfiguration) -> [Double] {
            let history = summaries[item.id]!
            let adverse = comparableFeedback ? Double(history.adverse + 1) / Double(history.evaluated + 2) : 0
            let resource = comparableCosts ? Double(history.completionTokens!.median) : Double(tier(item.model.role) ?? 3)
            return [qualitySatisfied(item) ? 0 : 1,
                 conservative && item.model.role == .efficient ? 1 : 0,
                 Double(abs(PlannerModel.effortRank(item.effort) - desiredRank)),
                 history.discourages ? 1 : 0,
                 Double(saving ? 0 : roleRank(item.model.role)),
                 saving ? resource : 0,
                 adverse,
                 Double(roleRank(item.model.role)),
                 item.model.manuallyConfigured ? 1 : 0,
                 item.model.isDefault ? 0 : 1,
                 Double(PlannerModel.effortRank(item.effort))]
        }
        let ranked = nearest.sorted { left, right in
            let ls = score(left), rs = score(right)
            return ls == rs ? left.id < right.id : ls.lexicographicallyPrecedes(rs)
        }
        var chosen = ranked.first
        var manualChoice = false
        if let override {
            if let current = available.first(where: { $0.id == override.model.id && $0.efforts.contains(override.effort) }), override.isValid {
                chosen = PlannerConfiguration(model: current, effort: override.effort)
                manualChoice = true
                reasons.append(L("用户手动选择；没有自动修改 Codex 的模型设置。"))
                if PlannerModel.effortRank(override.effort) == 99 { warnings.append(L("此 effort 的推理深度语义未知，只保留你的手动选择，不作资源或质量判断。")) }
                if PlannerModel.effortRank(override.effort) < minimumRank {
                    warnings.append(L("手动配置低于此任务的保守推理建议；高风险约束仍需你确认。"))
                }
            } else { warnings.append(L("手动配置已不在当前目录或不支持此 effort，未采用。")) }
        }
        guard let chosen else {
            return PlannerAdvice(recommended: nil, alternatives: [], reasons: reasons,
                                 warnings: [L("没有新鲜且支持所需 effort 的模型目录。请刷新目录，或手动填入已确认的模型配置。")] + warnings,
                                 evidence: L("信息不足"), shouldWait: quotaAssessment.status == .wait,
                                 decision: .unavailable, confidence: .low, quotaAssessment: quotaAssessment, tokenEstimate: nil)
        }
        reasons.append(LF("选择 %@：%@；%@只作规则取舍，不代表性能保证。", chosen.model.name, chosen.model.isDefault ? L("本机目录的默认候选") : chosen.model.role.title, preference.title))
        reasons.append(LF("选择 %@：在该模型实际支持的档位中匹配任务需求；复杂任务不默认使用最高档。", chosen.effort))
        if conservative { reasons.append(L("复杂度、风险或不确定性较高，效率和紧急偏好不会降低推理底线。")) }
        let qualityMet = qualitySatisfied(chosen)
        if !qualityMet {
            warnings.append(L("当前配置未满足启发式质量底线；这是需确认的取舍，不是等价替代。"))
        }
        if quotaAssessment.status == .wait {
            warnings.append(quotaAssessment.providerExhausted ? L("来源确认至少一个当前窗口已耗尽；切换模型不会获得独立额度池。")
                            : L("等待来自你设置的保留量策略，并非来源禁止运行；可手动调整保留量。"))
        }
        if let pressure {
            reasons.append(LF("条件额度压力 ×%.2f：仅假设近期观测速度延续；共享窗口取最大压力，不相加。", pressure))
        } else {
            warnings.append(L("缺少同范围、同周期的新鲜消耗速度；额度压力未知，沿用保守规则。"))
        }
        reasons.append(comparableCosts ? L("资源比较仅用足量同类已验证完成任务的自报 Token 总量；不保证含全部重试和验证成本，不换算订阅百分比。")
                       : L("缺少所有候选可比的完成成本；仅按描述角色作序数取舍，不声称更省额度。"))
        if conservative {
            reasons.append(L("此任务采用直接充分配置；没有证据证明先试弱模型再重做更划算。"))
        } else if profile.dimensions?.automatedVerification == true {
            reasons.append(L("先运行可重复验证，再按结果人工重评；重试、升级和验证成本未知，不宣称级联更省。"))
        }
        if profile.dimensions?.context == .high {
            warnings.append(L("检测到长上下文需求，但目录未确认上下文上限；请先验证容量，不能保证兼容。"))
        }
        if profile.dimensions?.decomposable == true {
            warnings.append(L("任务可能分阶段，但尚无协调开销与收益证据；暂不增加多模型阶段。"))
        }
        let roleFallback = chosen.model.role != desiredRole
        if roleFallback { warnings.append(L("所需角色未成为首选，已按能力角色、反馈和合法推理档位选择备选；需人工确认适配性。")) }
        if available.count < models.count { warnings.append(L("无效、过期、跨来源或重复冲突的目录条目已排除。")) }
        let history = summaries[chosen.id] ?? summary(records: records, profile: profile, configuration: chosen, scope: quota.scope, at: date, policy: policy)
        let discouragedCount = summaries.values.filter(\.discourages).count
        if discouragedCount > 0 { reasons.append(L("同类本地反馈不佳的配置已降序；比较条件包括模型、effort、任务特征和账户范围。")) }
        if history.evaluated >= policy.minimumSamples { reasons.append(LF("此配置有 %lld 条同类人工反馈，其中完成 %lld 条；不是验证过的成功概率。", history.evaluated, history.succeeded)) }
        else { warnings.append(LF("同类反馈不足 %lld 条，不预测成本、成功率或可完成任务数。", Int64(policy.minimumSamples))) }
        if history.discourages { warnings.append(L("此配置的同类反馈存在较多失败、重试或返工；建议人工比较替代项。")) }
        if chosen.model.manuallyConfigured { warnings.append(L("此模型由用户手动配置，可用性及能力未经本机目录核验。")) }
        let alternatives = Array(ranked.filter { $0.id != chosen.id }.prefix(2))
        let confidence: PlannerLevel = manualChoice || chosen.model.manuallyConfigured || roleFallback || history.discourages || !qualityMet
            || history.evaluated < policy.minimumSamples
            || quotaAssessment.status != .available || quota.scope?.isEmpty != false
            || profile.dimensions?.context == .high || profile.dimensions?.confidence == .low
            || [.other, .automatic].contains(profile.category) ? .low : .medium
        reasons.append(L("置信度为规则证据的定性等级，尚未经过任务基准校准，不是成功概率。"))
        return PlannerAdvice(recommended: chosen, alternatives: alternatives, reasons: reasons, warnings: warnings,
                             evidence: history.evaluated >= policy.minimumSamples ? L("本地反馈校准 · 非成功保证") : L("规则建议 · 历史不足"),
                             shouldWait: quotaAssessment.status == .wait,
                             decision: quotaAssessment.status == .wait ? .wait : (quotaAssessment.status == .unknown || !qualityMet || profile.dimensions?.context == .high || [.other, .automatic].contains(profile.category) ? .needsInformation : .configuration),
                             confidence: confidence, quotaAssessment: quotaAssessment, tokenEstimate: history.tokenEstimate,
                             evaluations: candidates.sorted { $0.id < $1.id }.map { item in
                                 let data = summaries[item.id]!
                                 return PlannerCandidateEvaluation(configuration: item, qualitySatisfied: qualitySatisfied(item),
                                     ordinalResourceTier: tier(item.model.role), completionTokens: data.completionTokens,
                                     feedbackSamples: data.evaluated,
                                     adverseBurden: data.evaluated >= policy.minimumSamples ? Double(data.adverse + 1) / Double(data.evaluated + 2) : nil)
                             }, quotaPressure: pressure, qualitySatisfied: qualityMet)
    }

    public static func quotaPressure(quota: PlannerQuota, reserve: Int, pacing: [PlannerQuotaPace],
                                     at date: Date, policy: PlannerPolicy = PlannerPolicy()) -> Double? {
        guard quota.isFresh(at: date), quota.hasValidWindows, let scope = quota.scope, !scope.isEmpty else { return nil }
        let reserve = min(100, max(0, reserve))
        let values = quota.windows.compactMap { window -> Double? in
            // Conflicting duplicate pace records are not resolved by input order.
            let entries = pacing.filter { $0.provider == quota.provider && $0.scope == scope && $0.windowID == window.id }
            guard entries.count == 1, let value = entries.first, let reset = window.resetsAt, reset > date,
                  value.resetsAt == reset, value.remainingPercent == window.remainingPercent,
                  value.receivedAt <= quota.receivedAt.addingTimeInterval(5),
                  date.timeIntervalSince(value.receivedAt) >= -5,
                  date.timeIntervalSince(value.receivedAt) <= (quota.provider == .codex ? 120 : 300),
                  value.samples >= 4, value.observedSpan.isFinite, (300...3_600).contains(value.observedSpan),
                  value.ratePerHour.isFinite, value.ratePerHour > 0,
                  value.ratePerHour * value.observedSpan / 3_600 >= 3 else { return nil }
            let projected = value.ratePerHour * reset.timeIntervalSince(date) / 3_600
            guard projected.isFinite else { return nil }
            // A conditional scarcity multiplier, not a depletion forecast or a price.
            return min(policy.maximumPressure, max(1, projected / Double(max(1, window.remainingPercent - reserve))))
        }
        return values.max()
    }
}

public enum PlannerError: LocalizedError {
    case invalidCatalog, invalidHistory, futureSchema
    public var errorDescription: String? {
        switch self {
        case .invalidCatalog: L("模型目录格式无法识别，请刷新或使用明确标注的手动配置。")
        case .invalidHistory: L("任务记录损坏或不符合边界；原文件已保留，未覆盖。")
        case .futureSchema: L("任务记录来自更新版本；为避免数据丢失，当前版本不会写入。")
        }
    }
}

/// A small, versioned local file; no daemon, cloud sync, raw prompts, or project contents.
public enum PlannerPersistence {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexQuota/planner-history.json")
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var records: [PlannerTaskRecord]
    }

    public static func load(from url: URL) throws -> [PlannerTaskRecord] {
        guard let data = try ClaudeBridgeFiles.readIfPresent(url, maximumBytes: 2_097_152) else { return [] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PlannerError.invalidHistory }
        let version = object["schemaVersion"] as? Int ?? 0
        guard version <= 1 else { throw PlannerError.futureSchema }
        guard version >= 0, let recordsData = try? JSONSerialization.data(withJSONObject: object["records"] as Any),
              let records = try? JSONDecoder().decode([PlannerTaskRecord].self, from: recordsData),
              records.count <= 500, records.allSatisfy(\.isValid), Set(records.map(\.id)).count == records.count else { throw PlannerError.invalidHistory }
        return records
    }

    public static func save(_ records: [PlannerTaskRecord], to url: URL, replacingInvalidFile: Bool = false) throws {
        guard records.count <= 500, records.allSatisfy(\.isValid), Set(records.map(\.id)).count == records.count else { throw PlannerError.invalidHistory }
        try ClaudeBridgeFiles.withLock(for: url) {
            if !replacingInvalidFile { _ = try load(from: url) }
            let data = try JSONEncoder().encode(Envelope(schemaVersion: 1, records: records))
            guard data.count <= 2_097_152 else { throw PlannerError.invalidHistory }
            try ClaudeBridgeFiles.write(data, to: url)
        }
    }
}

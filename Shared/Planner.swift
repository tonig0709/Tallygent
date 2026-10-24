import Foundation

public enum PlannerCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, routine, ui, feature, debugging, refactor, architecture, review, other
    public var id: Self { self }
    public var title: String {
        switch self {
        case .automatic: "自动识别"
        case .routine: "日常修改"
        case .ui: "界面开发"
        case .feature: "功能实现"
        case .debugging: "排查 Bug"
        case .refactor: "代码重构"
        case .architecture: "架构设计"
        case .review: "测试与审查"
        case .other: "其他"
        }
    }
}

public enum PlannerLevel: Int, Codable, CaseIterable, Identifiable, Sendable {
    case low, medium, high
    public var id: Self { self }
    public var title: String { ["低", "中", "高"][rawValue] }
    public var sizeTitle: String { ["小", "中", "大"][rawValue] }
}

public enum PlannerPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case quality, balanced, efficiency
    public var id: Self { self }
    public var title: String {
        switch self { case .quality: "质量优先"; case .balanced: "平衡"; case .efficiency: "效率优先" }
    }
}

public struct PlannerProfile: Codable, Equatable, Sendable {
    public var category: PlannerCategory
    public var complexity: PlannerLevel
    public var uncertainty: PlannerLevel
    public var risk: PlannerLevel
    public var urgent: Bool
    public var signals: [String]

    public init(category: PlannerCategory = .feature, complexity: PlannerLevel = .medium,
                uncertainty: PlannerLevel = .medium, risk: PlannerLevel = .low,
                urgent: Bool = false, signals: [String] = []) {
        self.category = category; self.complexity = complexity; self.uncertainty = uncertainty
        self.risk = risk; self.urgent = urgent; self.signals = signals
    }

    public static func classify(_ text: String) -> Self {
        let text = text.lowercased()
        func contains(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        let category: PlannerCategory
        if contains(["架构", "architecture", "分布式", "系统设计"]) { category = .architecture }
        else if contains(["bug", "崩溃", "debug", "报错", "排查"]) { category = .debugging }
        else if contains(["重构", "refactor"]) { category = .refactor }
        else if contains(["测试", "审查", "test", "review"]) { category = .review }
        else if contains(["ui", "界面", "布局", "样式", "窗口"]) { category = .ui }
        else if contains(["文案", "拼写", "typo", "rename", "改名", "注释", "格式"]) { category = .routine }
        else if contains(["功能", "feature", "实现", "增加", "开发"]) { category = .feature }
        else { category = .other }
        let sensitive = contains(["安全", "密钥", "认证", "支付", "隐私", "security", "auth", "payment", "credential", "数据库迁移"])
        let large = category == .architecture || contains(["跨模块", "迁移", "复杂", "多文件", "distributed"])
        let uncertain = contains(["未知", "偶发", "无法复现", "不确定", "unknown", "intermittent"])
        return Self(category: category, complexity: large ? .high : (category == .routine ? .low : .medium),
                    uncertainty: uncertain ? .high : (category == .routine ? .low : .medium),
                    risk: sensitive ? .high : .low,
                    signals: ["本地关键词规则；未扫描项目或发送任务文本"] + (sensitive ? ["检测到安全或关键业务信号"] : []))
    }
}

public enum PlannerModelRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case unknown, efficient, balanced, quality
    public var id: Self { self }
    public var title: String {
        switch self { case .unknown: "未标注"; case .efficient: "偏效率"; case .balanced: "通用"; case .quality: "偏复杂任务" }
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
        Self.safeIdentifier(identifier) && !name.isEmpty && !efforts.isEmpty
            && efforts.allSatisfy(Self.safeIdentifier) && efforts.contains(defaultEffort)
    }

    public static func safeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 160 && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:/")).contains($0)
        }
    }

    /// The local catalog is a picker contract, not a successful inference entitlement check.
    public static func parsePage(_ object: [String: Any], at date: Date) throws -> (models: [Self], cursor: String?) {
        guard let result = object["result"] as? [String: Any], let entries = result["data"] as? [[String: Any]], entries.count <= 200 else {
            throw PlannerError.invalidCatalog
        }
        let models = entries.compactMap { entry -> Self? in
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
                             efforts: Array(Set(efforts)).sorted { effortRank($0) < effortRank($1) },
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
            : "Provider: \(model.provider.title)\nModel: \(model.identifier)\nReasoning effort: \(effort)\nUser-declared configuration; apply manually."
    }
}

public struct PlannerQuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var remainingPercent: Int
    public var resetsAt: Date?
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
        guard !windows.isEmpty else { return ["额度数据缺失；本建议未通过额度校验。"] }
        var warnings: [String] = []
        if !isFresh(at: date) { warnings.append("额度记录较旧或来源未连接；请刷新后再判断可用量。") }
        for window in windows {
            if let reset = window.resetsAt, reset <= date {
                warnings.append("\(window.title)已到重置点，等待来源确认新周期。")
            } else if window.remainingPercent <= reserve {
                warnings.append("\(window.title)剩余 \(window.remainingPercent)% ≤ 保留量 \(reserve)%：建议等待或手动调整预算。")
            } else if window.remainingPercent < 30 {
                warnings.append("\(window.title)仅剩 \(window.remainingPercent)%；不能只看另一个较充足的窗口。")
            }
        }
        if scope == nil { warnings.append("账户/会话范围未知，不能把本次额度变化归因给任务。") }
        warnings.append("任务预计额度消耗未知；百分比不是可用 Token 数，也不保证任务可完成。")
        return warnings
    }

    public func shouldWait(reserve: Int, at date: Date) -> Bool {
        isFresh(at: date) && windows.contains { ($0.resetsAt == nil || $0.resetsAt! > date) && $0.remainingPercent <= reserve }
    }
}

public enum PlannerOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned, running, succeeded, partial, failed, notEvaluated, interrupted
    public var id: Self { self }
    public var title: String {
        switch self {
        case .planned: "待开始"; case .running: "进行中"; case .succeeded: "完成"; case .partial: "部分完成"
        case .failed: "失败"; case .notEvaluated: "未评估"; case .interrupted: "中断待确认"
        }
    }
    public var isEvaluated: Bool { [.succeeded, .partial, .failed].contains(self) }
}

public enum PlannerVerification: String, Codable, CaseIterable, Identifiable, Sendable {
    case notRun, passed, failed
    public var id: Self { self }
    public var title: String { switch self { case .notRun: "未验证"; case .passed: "验证通过"; case .failed: "验证失败" } }
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
        guard let before, let after, let startedAt, let completedAt else { return "无完整执行区间" }
        guard before.provider == after.provider, let scope = before.scope, after.scope == scope else { return "账户或会话范围变化/未知" }
        guard before.isFresh(at: startedAt), after.isFresh(at: completedAt) else { return "起止额度记录过期" }
        for window in before.windows {
            guard let end = after.windows.first(where: { $0.id == window.id }), let reset = window.resetsAt,
                  end.resetsAt == reset, reset > completedAt, end.remainingPercent <= window.remainingPercent else {
                return "跨重置或窗口变化，不可归因"
            }
        }
        return "期间账户变化；并发/其他设备未隔离，不用于额度成本预测"
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
    public var discourages: Bool { evaluated >= 5 && adverse * 5 >= evaluated * 2 }
}

public struct PlannerAdvice: Sendable {
    public var recommended: PlannerConfiguration?
    public var alternatives: [PlannerConfiguration]
    public var reasons: [String]
    public var warnings: [String]
    public var evidence: String
    public var shouldWait: Bool
}

public enum PlannerEngine {
    public static func summary(records: [PlannerTaskRecord], profile: PlannerProfile,
                               configuration: PlannerConfiguration, scope: String?) -> PlannerHistorySummary {
        let relevant = records.filter {
            $0.configuration.id == configuration.id && $0.profile.category == profile.category
                && $0.profile.complexity == profile.complexity && $0.profile.risk == profile.risk
                && $0.profile.uncertainty == profile.uncertainty && $0.outcome.isEvaluated
                && scope != nil && $0.before?.scope == scope && $0.after?.scope == scope
        }
        let totals = relevant.compactMap { $0.tokens?.isValid == true ? $0.tokens?.total : nil }.sorted()
        return PlannerHistorySummary(evaluated: relevant.count, succeeded: relevant.filter { $0.outcome == .succeeded }.count,
                                     adverse: relevant.filter { $0.outcome != .succeeded || $0.manualRework || $0.verification == .failed || $0.retries > 1 || ($0.quality ?? 5) <= 2 }.count,
                                     medianReportedTokens: totals.count >= 5 ? totals[totals.count / 2] : nil)
    }

    public static func advise(profile: PlannerProfile, preference: PlannerPreference, models: [PlannerModel],
                              quota: PlannerQuota, reserve: Int, records: [PlannerTaskRecord],
                              override: PlannerConfiguration? = nil, at date: Date = .now) -> PlannerAdvice {
        let reserve = min(50, max(0, reserve))
        let available = models.filter { $0.provider == quota.provider && $0.isValid && date.timeIntervalSince($0.discoveredAt) <= 1_800 && date >= $0.discoveredAt.addingTimeInterval(-5) }
        let conservative = profile.risk == .high || profile.uncertainty == .high
        let minimumRank = conservative ? 4 : (profile.complexity == .low ? 2 : 3)
        let desiredRank = conservative || profile.complexity == .high || preference == .quality ? 4 : minimumRank
        let desiredRole: PlannerModelRole = conservative || preference == .quality ? .quality : (preference == .efficiency || profile.urgent ? .efficient : .balanced)
        var warnings = quota.warnings(reserve: reserve, at: date)
        var reasons = ["\(profile.category.title) · 规模\(profile.complexity.sizeTitle) · 不确定性\(profile.uncertainty.title) · 风险\(profile.risk.title)。",
                       "模型角色仅依据目录描述或用户配置；没有测量过的模型质量、速度和额度价格不作精确比较。"]
        func configuration(_ model: PlannerModel, target: Int) -> PlannerConfiguration? {
            let options = model.efforts.filter { PlannerModel.effortRank($0) < 99 && PlannerModel.effortRank($0) >= minimumRank }
            guard let effort = options.min(by: {
                let left = abs(PlannerModel.effortRank($0) - target), right = abs(PlannerModel.effortRank($1) - target)
                return left == right ? PlannerModel.effortRank($0) < PlannerModel.effortRank($1) : left < right
            }) else { return nil }
            return PlannerConfiguration(model: model, effort: effort)
        }
        var candidates = available.compactMap { configuration($0, target: desiredRank) }
        candidates.sort { left, right in
            let lh = summary(records: records, profile: profile, configuration: left, scope: quota.scope).discourages
            let rh = summary(records: records, profile: profile, configuration: right, scope: quota.scope).discourages
            if lh != rh { return !lh }
            if (left.model.role == desiredRole) != (right.model.role == desiredRole) { return left.model.role == desiredRole }
            if left.model.isDefault != right.model.isDefault { return left.model.isDefault }
            return left.model.identifier < right.model.identifier
        }
        var chosen = candidates.first
        if let override {
            if available.contains(where: { $0.id == override.model.id && $0.efforts.contains(override.effort) }) && override.isValid {
                chosen = override
                reasons.append("用户手动选择；没有自动修改 Codex 的模型设置。")
                if PlannerModel.effortRank(override.effort) < minimumRank {
                    warnings.append("手动配置低于此任务的保守推理建议；高风险约束仍需你确认。")
                }
            } else { warnings.append("手动配置已不在当前目录或不支持此 effort，未采用。") }
        }
        guard let chosen else {
            return PlannerAdvice(recommended: nil, alternatives: [], reasons: reasons,
                                 warnings: ["没有新鲜且支持所需 effort 的模型目录。请刷新目录，或手动填入已确认的模型配置。"] + warnings,
                                 evidence: "信息不足", shouldWait: quota.shouldWait(reserve: reserve, at: date))
        }
        reasons.append("选择 \(chosen.model.name)：\(chosen.model.isDefault ? "本机目录的默认候选" : chosen.model.role.title)；\(preference.title)只作规则取舍，不代表性能保证。")
        reasons.append("选择 \(chosen.effort)：在该模型实际支持的档位中匹配任务需求；复杂任务不默认使用最高档。")
        if conservative { reasons.append("风险或不确定性较高，效率偏好不会自动降低质量底线。") }
        let history = summary(records: records, profile: profile, configuration: chosen, scope: quota.scope)
        let discouragedCount = candidates.filter { summary(records: records, profile: profile, configuration: $0, scope: quota.scope).discourages }.count
        if discouragedCount > 0 { reasons.append("同类本地反馈不佳的配置已降序；比较条件包括模型、effort、任务特征和账户范围。") }
        if history.evaluated >= 5 { reasons.append("此配置有 \(history.evaluated) 条同类人工反馈，其中完成 \(history.succeeded) 条；不是验证过的成功概率。") }
        else { warnings.append("同类反馈不足 5 条，不预测成本、成功率或可完成任务数。") }
        if history.discourages { warnings.append("此配置的同类反馈存在较多失败、重试或返工；建议人工比较替代项。") }
        if chosen.model.manuallyConfigured { warnings.append("此模型由用户手动配置，可用性及能力未经本机目录核验。") }
        var alternatives: [PlannerConfiguration] = []
        for target in [minimumRank, 4] {
            for model in available.sorted(by: { ($0.role == (target == 4 ? .quality : .efficient) ? 0 : 1, $0.identifier) < ($1.role == (target == 4 ? .quality : .efficient) ? 0 : 1, $1.identifier) }) {
                if let item = configuration(model, target: target), item.id != chosen.id, !alternatives.contains(where: { $0.id == item.id }) {
                    alternatives.append(item); break
                }
            }
        }
        return PlannerAdvice(recommended: chosen, alternatives: alternatives, reasons: reasons, warnings: warnings,
                             evidence: history.evaluated >= 5 ? "本地反馈校准 · 非成功保证" : "规则建议 · 历史不足",
                             shouldWait: quota.shouldWait(reserve: reserve, at: date))
    }
}

public enum PlannerError: LocalizedError {
    case invalidCatalog, invalidHistory, futureSchema
    public var errorDescription: String? {
        switch self {
        case .invalidCatalog: "模型目录格式无法识别，请刷新或使用明确标注的手动配置。"
        case .invalidHistory: "任务记录损坏或不符合边界；原文件已保留，未覆盖。"
        case .futureSchema: "任务记录来自更新版本；为避免数据丢失，当前版本不会写入。"
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

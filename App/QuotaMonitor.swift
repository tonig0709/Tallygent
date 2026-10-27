import Combine
import Foundation
import CryptoKit

/// Owns provider selection. Providers never write into each other's cache.
@MainActor
final class QuotaMonitor: ObservableObject {
    typealias State = CodexAppServer.State
    @Published private(set) var service: AgentService
    @Published private(set) var state: State = .disconnected
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var connectionMessage: String?
    @Published private(set) var models: [PlannerModel] = []
    @Published private(set) var modelCatalogMessage = "尚未读取本机模型目录"
    @Published private(set) var isLoadingModels = false
    @Published private(set) var codexCollectionEnabled: Bool
    @Published private(set) var claudeCollectionEnabled: Bool
    @Published private(set) var isConfiguringCollection = true
    let insights: InsightsStore

    private let codex: CodexAppServer
    private let defaults: UserDefaults
    private let claudeURL: URL
    private let now: () -> Date
    private var claudeRecord: ClaudeStatuslineRecord?
    private var claudeError: String?
    private var lastClaudePresentationKey: String?
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var started = false
    private var collectorsReady = false

    init(codex: CodexAppServer? = nil, defaults: UserDefaults = .standard,
         claudeURL: URL = ClaudeStatuslineStore.defaultURL, insights: InsightsStore? = nil,
         now: @escaping () -> Date = { .now }) {
        let codex = codex ?? CodexAppServer()
        self.codex = codex
        self.defaults = defaults
        self.claudeURL = claudeURL
        self.now = now
        let selectedService = AgentService(rawValue: defaults.string(forKey: "selectedAgentService") ?? "") ?? .codex
        service = selectedService
        codexCollectionEnabled = defaults.object(forKey: "monitor.collectCodex") as? Bool ?? (selectedService == .codex)
        claudeCollectionEnabled = defaults.object(forKey: "monitor.collectClaude") as? Bool ?? true
        self.insights = insights ?? InsightsStore(url: claudeURL.deletingLastPathComponent().appendingPathComponent("observations.sqlite"), defaults: defaults, now: now)
        defaults.set(codexCollectionEnabled, forKey: "monitor.collectCodex")
        defaults.set(claudeCollectionEnabled, forKey: "monitor.collectClaude")
        codex.onQuotaObservation = { [weak self] rows in
            guard let self, self.codexCollectionEnabled else { return }
            self.insights.record(rows)
        }
        codex.$models.assign(to: &$models)
        codex.$modelCatalogMessage.assign(to: &$modelCatalogMessage)
        codex.$isLoadingModels.assign(to: &$isLoadingModels)
        codex.$snapshot.combineLatest(codex.$state).sink { [weak self] value, state in
            guard let self, self.service == .codex else { return }
            self.snapshot = value
            self.state = state
        }.store(in: &subscriptions)
        readClaude()
        publishSelection()
    }

    func selectService(_ value: AgentService) {
        guard service != value else { return }
        service = value
        defaults.set(value.rawValue, forKey: "selectedAgentService")
        connectionMessage = nil
        readClaude()
        publishSelection()
        if collectorsReady && value == .codex { codex.connect() }
        else if collectorsReady && !codexCollectionEnabled { codex.disconnect() }
    }

    func connect() async {
        guard !started else { return }
        started = true
        let configured = await insights.initializeCollection(codex: codexCollectionEnabled, claude: claudeCollectionEnabled)
        codexCollectionEnabled = configured && insights.collection[.codex] == true
        claudeCollectionEnabled = configured && insights.collection[.claude] == true
        if configured {
            defaults.set(codexCollectionEnabled, forKey: "monitor.collectCodex")
            defaults.set(claudeCollectionEnabled, forKey: "monitor.collectClaude")
        }
        collectorsReady = true
        isConfiguringCollection = false
        if codexCollectionEnabled || service == .codex { codex.connect() }
        readClaude()
        await insights.reload(force: true)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.readClaude()
                await self.insights.reload()
            }
        }
    }

    func refresh() {
        if service == .codex { codex.refresh() }
        else { readClaude() }
    }

    func refreshModelCatalog() { codex.refreshModelCatalog() }

    /// Monitoring choices survive display changes; choosing a card is not starting another owner.
    func setCollection(_ provider: AgentService, enabled: Bool) async {
        guard !isConfiguringCollection else { return }
        isConfiguringCollection = true
        defer { isConfiguringCollection = false }
        guard await insights.setCollection(provider, enabled: enabled) else { return }
        if provider == .codex {
            codexCollectionEnabled = enabled
            defaults.set(enabled, forKey: "monitor.collectCodex")
            if started {
                if enabled { codex.connect() }
                else if service != .codex { codex.disconnect() }
            }
        } else {
            claudeCollectionEnabled = enabled
            defaults.set(enabled, forKey: "monitor.collectClaude")
        }
    }

    func plannerQuota() -> PlannerQuota {
        let scope: String?
        if service == .codex, let email = snapshot.email {
            scope = SHA256.hash(data: Data(email.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        } else { scope = service == .claude ? claudeRecord?.sessionFingerprint : nil }
        let windows = [("fiveHour", "5h 额度", snapshot.fiveHour), ("weekly", "周额度", snapshot.weekly)].compactMap { id, title, window -> PlannerQuotaWindow? in
            guard let window else { return nil }
            return PlannerQuotaWindow(id: id, title: title, remainingPercent: window.remainingPercent,
                                      resetsAt: window.resetsAt, durationMinutes: window.windowDurationMinutes)
        }
        let connected: Bool
        if case .connected = state { connected = true } else { connected = false }
        return PlannerQuota(provider: service, scope: scope,
                            source: service == .codex ? "Codex account/rateLimits/read" : "Claude Code statusLine（被动接收）",
                            receivedAt: snapshot.lastReceivedAt, windows: windows, connected: connected)
    }

    func updateGlassSettings(_ settings: GlassRenderSettings) {
        codex.updateGlassSettings(settings)
        publishSelection()
    }

    func enableClaudeBridge() {
        do {
            guard let executable = Bundle.main.executableURL else { return }
            try ClaudeBridgeSetup.install(executableURL: executable)
            connectionMessage = "接入已启用；请开启 Claude Code 会话。首次接收后绑定该会话。"
        } catch {
            connectionMessage = error.localizedDescription
        }
    }

    func removeClaudeBridge() {
        do {
            try ClaudeBridgeSetup.remove()
            connectionMessage = "已移除本应用的状态栏接入；最后记录仍保留。"
        } catch {
            connectionMessage = error.localizedDescription
        }
    }

    func resetClaudeSession() {
        do {
            try ClaudeStatuslineStore.reset(at: claudeURL)
            claudeRecord = nil
            claudeError = nil
            connectionMessage = "已清除 Claude 会话记录；下一次有效数据将绑定新会话。"
            publishSelection()
        } catch {
            connectionMessage = error.localizedDescription
        }
    }

    private func readClaude() {
        do {
            let record = try ClaudeStatuslineStore.load(from: claudeURL)
            let presentationChanged = service == .claude &&
                snapshot.claudePresentationKey(at: now()) != lastClaudePresentationKey
            guard record != claudeRecord || claudeError != nil || presentationChanged else { return }
            claudeError = nil
            claudeRecord = record
            if service == .claude { publishSelection() }
        } catch {
            claudeError = "无法读取 Claude 会话记录，请重新绑定会话。"
            if service == .claude { state = .failed(claudeError!) }
        }
    }

    private func publishSelection() {
        if service == .codex {
            snapshot = codex.snapshot
            state = codex.state
        } else {
            let date = claudeRecord?.receivedAt ?? .distantPast
            snapshot = UsageSnapshot(
                fiveHour: claudeRecord?.fiveHour, weekly: claudeRecord?.weekly,
                glassSettings: codex.snapshot.glassSettings,
                updatedAt: date, service: .claude, receivedAt: claudeRecord?.receivedAt
            )
            state = claudeError.map(State.failed) ?? (snapshot.hasQuota ? .connected(nil) : .disconnected)
            lastClaudePresentationKey = snapshot.claudePresentationKey(at: now())
        }
    }
}

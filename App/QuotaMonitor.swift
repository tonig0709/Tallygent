import Combine
import Foundation

/// Owns provider selection. Providers never write into each other's cache.
@MainActor
final class QuotaMonitor: ObservableObject {
    typealias State = CodexAppServer.State
    @Published private(set) var service: AgentService
    @Published private(set) var state: State = .disconnected
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var connectionMessage: String?

    private let codex: CodexAppServer
    private let defaults: UserDefaults
    private let claudeURL: URL
    private var claudeRecord: ClaudeStatuslineRecord?
    private var claudeError: String?
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var started = false

    init(codex: CodexAppServer? = nil, defaults: UserDefaults = .standard,
         claudeURL: URL = ClaudeStatuslineStore.defaultURL) {
        let codex = codex ?? CodexAppServer()
        self.codex = codex
        self.defaults = defaults
        self.claudeURL = claudeURL
        service = AgentService(rawValue: defaults.string(forKey: "selectedAgentService") ?? "") ?? .codex
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
        if started && value == .codex { codex.connect() }
    }

    func connect() {
        guard !started else { return }
        started = true
        if service == .codex { codex.connect() }
        readClaude()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.readClaude() }
        }
    }

    func refresh() {
        if service == .codex { codex.refresh() }
        else { readClaude() }
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
            guard record != claudeRecord || claudeError != nil else { return }
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
        }
    }
}

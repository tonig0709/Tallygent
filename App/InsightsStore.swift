import Combine
import Foundation
import UserNotifications

enum InsightsRange: Int, CaseIterable, Identifiable {
    case hour = 1, day = 24, week = 168, month = 720
    var id: Self { self }
    var title: String {
        switch self { case .hour: "近 1 小时"; case .day: "近 24 小时"; case .week: "近 7 天"; case .month: "近 30 天" }
    }
}

private actor ObservationIO {
    let url: URL
    init(url: URL) { self.url = url }
    func append(_ values: [QuotaObservation], now: Date) throws { try ObservationHistory.append(values, at: url, now: now) }
    func load(since: Date, now: Date) throws -> ([QuotaObservation], UsageInsightsReport, UsageInsightsReport, [QuotaObservation]) {
        let panelSince = now.addingTimeInterval(-24 * 3_600)
        let values = try ObservationHistory.load(from: url, since: min(since, panelSince), now: now)
        let selected = values.filter { $0.receivedAt >= since }
        let report = UsageInsights.analyze(observations: selected, now: now)
        let panelValues = values.filter { $0.receivedAt >= panelSince }
        let panelReport = since == panelSince ? report : UsageInsights.analyze(observations: panelValues, now: now)
        return (selected, report, panelReport, panelValues)
    }
    func setEnabled(_ provider: AgentService, _ enabled: Bool) throws {
        try ObservationHistory.setCollectionEnabled(provider, enabled: enabled, at: url)
    }
    func enabled(_ provider: AgentService) throws -> Bool { try ObservationHistory.isCollectionEnabled(provider, at: url) }
    func initialize(codex: Bool, claude: Bool) throws -> [AgentService: Bool] {
        [.codex: try ObservationHistory.initializeCollection(.codex, defaultEnabled: codex, at: url),
         .claude: try ObservationHistory.initializeCollection(.claude, defaultEnabled: claude, at: url)]
    }
    func clear(now: Date) throws { try ObservationHistory.clear(at: url, now: now) }
    func export(since: Date?, now: Date) throws -> Data { try ObservationHistory.export(from: url, since: since, now: now) }
}

/// The App owns presentation; the bridge writes directly to the same transactional history.
@MainActor
final class InsightsStore: ObservableObject {
    @Published private(set) var observations: [QuotaObservation] = []
    @Published private(set) var report = UsageInsights.analyze(observations: [], now: .now)
    /// Independent 24h presentation cache; changing the Insights range must not truncate the placed panel.
    @Published private(set) var panelReport = UsageInsights.analyze(observations: [], now: .now)
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    @Published private(set) var range = InsightsRange.day
    @Published private(set) var collection: [AgentService: Bool] = [.codex: true, .claude: true]
    @Published private(set) var notificationsEnabled = false
    @Published private(set) var isConfiguringNotifications = false
    private let io: ObservationIO
    private let defaults: UserDefaults
    private let now: () -> Date
    private var lastRead = Date.distantPast
    private var reloadQueued = false
    private var panelObservations: [QuotaObservation] = []
    private var alertState: UsageAlertState

    init(url: URL = ObservationHistory.defaultURL, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = { .now }) {
        io = ObservationIO(url: url)
        self.defaults = defaults
        self.now = now
        notificationsEnabled = defaults.bool(forKey: "insights.notificationsEnabled")
        if let data = defaults.data(forKey: "insights.alertState"), data.count < 65_536,
           let state = try? JSONDecoder().decode(UsageAlertState.self, from: data) { alertState = state }
        else { alertState = UsageAlertState() }
    }

    func record(_ values: [QuotaObservation]) {
        Task {
            do { try await io.append(values, now: now()); await reload(force: true) }
            catch { message = error.localizedDescription }
        }
    }

    func selectRange(_ value: InsightsRange) {
        guard value != range else { return }
        range = value
        Task { await reload(force: true) }
    }

    func initializeCollection(codex: Bool, claude: Bool) async -> Bool {
        do {
            collection = try await io.initialize(codex: codex, claude: claude)
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func reload(force: Bool = false) async {
        let elapsed = now().timeIntervalSince(lastRead)
        guard force || elapsed >= 15 || elapsed < 0 else { return }
        if isLoading { reloadQueued = true; return }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadQueued = false
            let requestedRange = range
            let date = now()
            lastRead = date
            do {
                let result = try await io.load(since: date.addingTimeInterval(-Double(requestedRange.rawValue) * 3_600), now: date)
                for provider in AgentService.allCases { collection[provider] = try await io.enabled(provider) }
                if requestedRange == range {
                    observations = result.0
                    report = result.1
                    panelReport = result.2
                    panelObservations = result.3
                    message = nil
                    deliverAlerts(at: date)
                } else { reloadQueued = true }
            } catch {
                report = UsageInsights.analyze(observations: observations, now: date)
                // Re-evaluate expiry without turning a failed history read into a fresh source observation.
                panelReport = UsageInsights.analyze(observations: panelObservations, now: date)
                message = error.localizedDescription
            }
        } while reloadQueued
    }

    @discardableResult
    func setCollection(_ provider: AgentService, enabled: Bool) async -> Bool {
        do {
            try await io.setEnabled(provider, enabled)
            collection[provider] = enabled
            message = nil
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func clear() async {
        do {
            try await io.clear(now: now())
            observations = []
            panelObservations = []
            panelReport = UsageInsights.analyze(observations: [], now: now())
            alertState = UsageAlertState()
            defaults.removeObject(forKey: "insights.alertState")
            await reload(force: true)
        } catch { message = error.localizedDescription }
    }

    func export(allHistory: Bool = true) async -> Data? {
        let date = now()
        do { return try await io.export(since: allHistory ? nil : date.addingTimeInterval(-Double(range.rawValue) * 3_600), now: date) }
        catch { message = error.localizedDescription; return nil }
    }

    func exportFinished(_ result: Result<URL, Error>) {
        guard case .failure(let error) = result else { return }
        let value = error as NSError
        guard value.domain != NSCocoaErrorDomain || value.code != NSUserCancelledError else { return }
        message = "未能保存导出文件。请检查目标文件夹的权限和可用磁盘空间后重试。"
    }

    func setNotifications(_ enabled: Bool) async {
        guard !isConfiguringNotifications else { return }
        isConfiguringNotifications = true
        defer { isConfiguringNotifications = false }
        if enabled {
            do {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else {
                    message = "未获得通知许可；可在系统设置的“通知”中允许 Tallygent。"
                    return
                }
            } catch { message = "无法启用通知，请检查系统通知设置。"; return }
        }
        notificationsEnabled = enabled
        defaults.set(enabled, forKey: "insights.notificationsEnabled")
        alertState = UsageAlertState()
        deliverAlerts(at: now())
    }

    private func deliverAlerts(at date: Date) {
        let events = alertState.evaluate(report: report, enabled: notificationsEnabled, now: date)
        if let data = try? JSONEncoder().encode(alertState), data.count < 65_536 { defaults.set(data, forKey: "insights.alertState") }
        guard notificationsEnabled else { return }
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { _ in }
        }
    }
}

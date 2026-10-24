import AppKit
import Combine
import Foundation
import Network

private final class SnapshotServer: @unchecked Sendable {
    static let port: NWEndpoint.Port = 48_193

    private let queue = DispatchQueue(label: "dev.codexquota.snapshot")
    private var listener: NWListener?

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    private func startOnQueue() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: Self.port)
        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters)
        } catch {
            retry()
            return
        }
        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            guard let self, let newListener, self.listener === newListener else { return }
            switch state {
            case .failed, .cancelled:
                self.listener = nil
                self.retry()
            default:
                break
            }
        }
        newListener.newConnectionHandler = { [queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) }
                let valid = request?.hasPrefix("GET /snapshot HTTP/1.") == true
                var snapshot = SnapshotStore.load()
                snapshot.email = nil
                snapshot.plan = nil
                let body = valid ? ((try? JSONEncoder().encode(snapshot)) ?? Data()) : Data()
                let status = valid ? "200 OK" : "404 Not Found"
                var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(body)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener = newListener
        newListener.start(queue: queue)
    }

    private func retry() {
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.startOnQueue()
        }
    }
}

@MainActor
final class CodexAppServer: ObservableObject {
    enum State: Equatable {
        case disconnected
        case connecting
        case signingIn
        case connected(String?)
        case failed(String)
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var models: [PlannerModel] = []
    @Published private(set) var modelCatalogMessage = "尚未读取本机模型目录"
    @Published private(set) var isLoadingModels = false

    private struct PendingRefresh {
        let rateLimitRequestID: Int
        let usageRequestID: Int
        var rateLimits: RateLimitWindows?
        var dailyUsage: [DailyUsage]?
    }

    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var refreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var pendingRefresh: PendingRefresh?
    private var refreshQueued = false
    private var refreshTimeout: DispatchWorkItem?
    private var nextRequestID = 3
    private var initialized = false
    private var wantsModels = false
    private var modelRequestID: Int?
    private var catalogBuffer: [PlannerModel] = []
    private var catalogCursors = Set<String>()
    private var modelTimeout: DispatchWorkItem?
    private let snapshotServer = SnapshotServer()

    init() {
        var initialSnapshot = SnapshotStore.load()
        initialSnapshot.service = .codex
        initialSnapshot.glassSettings = GlassSettingsSnapshot.load()
        snapshot = initialSnapshot
        SnapshotStore.save(initialSnapshot)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func connect() {
        snapshotServer.start()
        guard process == nil else { refresh() ; return }
        guard let executable = findCodex() else {
            state = .failed("未找到 Codex CLI。请先安装 Codex 或 ChatGPT for Mac。")
            finishModelCatalog(error: "未找到本机 Codex，无法读取目录；可使用手动配置。")
            return
        }

        state = .connecting
        initialized = false
        models = []
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] task in
            let status = task.terminationStatus
            Task { @MainActor [weak self] in
                self?.process = nil
                self?.input = nil
                self?.refreshTimeout?.cancel()
                self?.refreshTimeout = nil
                self?.pendingRefresh = nil
                self?.refreshQueued = false
                self?.initialized = false
                self?.finishModelCatalog(error: "Codex 已断开，目录未刷新")
                if status != 0 {
                    self?.state = .failed("Codex app-server 已退出（\(status)）")
                }
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consume(data) }
        }

        do {
            try process.run()
            self.process = process
            input = stdin.fileHandleForWriting
            send(method: "initialize", id: 0, params: [
                "clientInfo": [
                    "name": "codex_quota_widget",
                    "title": "Tallygent",
                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
                ]
            ])
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func disconnect() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTimeout?.cancel()
        refreshTimeout = nil
        pendingRefresh = nil
        refreshQueued = false
        input?.closeFile()
        process?.terminate()
        process = nil
        input = nil
        state = .disconnected
        initialized = false
        finishModelCatalog(error: "Codex 已断开，目录未刷新")
    }

    func refreshModelCatalog() {
        guard !isLoadingModels else { return }
        wantsModels = true
        guard process != nil else { connect(); return }
        guard initialized else { return }
        catalogBuffer = []; catalogCursors = []
        requestModelsPage(cursor: nil)
    }

    private func requestModelsPage(cursor: String?) {
        isLoadingModels = true
        modelCatalogMessage = "正在读取本机 model/list…"
        let id = nextRequestID
        nextRequestID += 1
        modelRequestID = id
        var params: [String: Any] = ["limit": 100, "includeHidden": false]
        if let cursor { params["cursor"] = cursor }
        send(method: "model/list", id: id, params: params)
        modelTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.finishModelCatalog(error: "模型目录读取超时；额度同步不受影响，可重试或手动配置。") }
        modelTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }

    private func finishModelCatalog(error: String? = nil) {
        modelTimeout?.cancel(); modelTimeout = nil; modelRequestID = nil
        isLoadingModels = false
        wantsModels = false
        if let error { modelCatalogMessage = error }
        else {
            models = catalogBuffer
            modelCatalogMessage = "本机 model/list · \(models.count) 个可选模型 · 实际推理权限未验证"
        }
        catalogBuffer = []
    }

    func refresh() {
        guard process != nil else { connect(); return }
        guard initialized else { refreshQueued = true; return }
        if case .failed = state {
            state = .connecting
            requestAccount()
            return
        }
        guard pendingRefresh == nil else {
            refreshQueued = true
            return
        }

        beginRefresh()
    }

    private func beginRefresh() {
        let rateLimitRequestID = nextRequestID
        let usageRequestID = nextRequestID + 1
        nextRequestID += 2
        pendingRefresh = PendingRefresh(
            rateLimitRequestID: rateLimitRequestID,
            usageRequestID: usageRequestID
        )
        send(method: "account/rateLimits/read", id: rateLimitRequestID)
        send(method: "account/usage/read", id: usageRequestID)

        let timeout = DispatchWorkItem { [weak self] in
            self?.finishPendingRefresh(
                rateLimitRequestID: rateLimitRequestID,
                usageRequestID: usageRequestID,
                allowPartial: true
            )
        }
        refreshTimeout?.cancel()
        refreshTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
    }

    func setAppearance(_ appearance: WidgetAppearance) {
        guard snapshot.resolvedAppearance != appearance else { return }
        snapshot.appearance = appearance
        persist(markDataRefresh: false)
    }

    func updateGlassSettings(_ settings: GlassRenderSettings) {
        let settings = settings.sanitized
        guard snapshot.glassSettings != settings else { return }
        snapshot.glassSettings = settings
        snapshot.appearance = settings.appearance
        SnapshotStore.save(snapshot)
        snapshotServer.start()
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            let payload = Data(line)
            handle(payload)
        }
    }

    private func handle(_ data: Data) {
        guard let object = try? AppServerParser.object(from: data) else { return }

        if let method = object["method"] as? String {
            if method == "account/login/completed" {
                let success = (object["params"] as? [String: Any])?["success"] as? Bool ?? false
                success ? requestAccount() : (state = .failed("Codex 登录未完成"))
            } else if method == "account/rateLimits/updated" {
                refresh()
            } else if method == "account/updated" {
                requestAccount()
            }
            return
        }

        guard let id = (object["id"] as? NSNumber)?.intValue else { return }
        if id == modelRequestID {
            do {
                let page = try PlannerModel.parsePage(object, at: .now)
                catalogBuffer += page.models
                guard catalogBuffer.count <= 1_000, Set(catalogBuffer.map(\.id)).count == catalogBuffer.count else { throw PlannerError.invalidCatalog }
                if let cursor = page.cursor {
                    guard catalogCursors.count < 10, catalogCursors.insert(cursor).inserted else { throw PlannerError.invalidCatalog }
                    requestModelsPage(cursor: cursor)
                } else { finishModelCatalog() }
            } catch { finishModelCatalog(error: error.localizedDescription) }
            return
        }
        switch id {
        case 0:
            send(method: "initialized")
            initialized = true
            if wantsModels { refreshModelCatalog() }
            requestAccount()
        case 1:
            handleAccount(object)
        case 2:
            if let url = AppServerParser.authURL(from: object) {
                state = .signingIn
                NSWorkspace.shared.open(url)
            }
        default:
            guard var pending = pendingRefresh else { return }
            if id == pending.rateLimitRequestID, let rateLimits = try? AppServerParser.rateLimitWindows(from: object) {
                pending.rateLimits = rateLimits
            } else if id == pending.usageRequestID, let usage = try? AppServerParser.dailyUsage(from: object) {
                pending.dailyUsage = usage
            } else {
                return
            }
            pendingRefresh = pending
            commitPendingRefreshIfReady()
        }
    }

    private func requestAccount() {
        send(method: "account/read", id: 1, params: ["refreshToken": false])
    }

    private func handleAccount(_ object: [String: Any]) {
        guard let account = try? AppServerParser.account(from: object) else {
            let message = (object["error"] as? [String: Any])?["message"] as? String
            state = .failed(message.map { "无法读取 Codex 账户：\($0)" } ?? "无法读取 Codex 账户，请重试")
            return
        }
        if account.isLoggedIn {
            if snapshot.email != account.email { models = [] }
            snapshot.email = account.email
            snapshot.plan = account.plan
            state = .connected(account.email)
            persist(markDataRefresh: false)
            refresh()
        } else {
            state = .signingIn
            send(method: "account/login/start", id: 2, params: [
                "type": "chatgpt",
                "useHostedLoginSuccessPage": true,
                "appBrand": "codex"
            ])
        }
    }

    private func persist(markDataRefresh: Bool) {
        if markDataRefresh { snapshot.updatedAt = .now }
        SnapshotStore.save(snapshot)
        snapshotServer.start()
    }

    private func commitPendingRefreshIfReady() {
        guard let pending = pendingRefresh,
              pending.rateLimits != nil,
              pending.dailyUsage != nil
        else { return }
        finishPendingRefresh(
            rateLimitRequestID: pending.rateLimitRequestID,
            usageRequestID: pending.usageRequestID,
            allowPartial: false
        )
    }

    private func finishPendingRefresh(
        rateLimitRequestID: Int,
        usageRequestID: Int,
        allowPartial: Bool
    ) {
        guard let pending = pendingRefresh,
              pending.rateLimitRequestID == rateLimitRequestID,
              pending.usageRequestID == usageRequestID,
              allowPartial || (pending.rateLimits != nil && pending.dailyUsage != nil)
        else { return }

        pendingRefresh = nil
        refreshTimeout?.cancel()
        refreshTimeout = nil

        var snapshotChanged = false
        if let rateLimits = pending.rateLimits {
            // A successful read can confirm unchanged values. Keep this separate
            // from updatedAt, which tracks actual data changes and disk writes.
            snapshot.receivedAt = .now
            if rateLimits.fiveHour != snapshot.fiveHour {
                snapshot.fiveHour = rateLimits.fiveHour
                snapshotChanged = true
            }
            if rateLimits.weekly != snapshot.weekly {
                snapshot.weekly = rateLimits.weekly
                snapshotChanged = true
            }
        }
        if let dailyUsage = pending.dailyUsage, dailyUsage != snapshot.dailyUsage {
            snapshot.dailyUsage = dailyUsage
            snapshotChanged = true
        }
        if snapshotChanged {
            persist(markDataRefresh: true)
        }

        if refreshQueued {
            refreshQueued = false
            beginRefresh()
        }
    }

    private func send(method: String, id: Int? = nil, params: [String: Any]? = nil) {
        var message: [String: Any] = ["method": method]
        if let id { message["id"] = id }
        if let params { message["params"] = params }
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        do { try input?.write(contentsOf: data) }
        catch { state = .failed(error.localizedDescription) }
    }

    private func findCodex() -> URL? {
        let environment = ProcessInfo.processInfo.environment["CODEX_BINARY"]
        let paths = [
            environment,
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ].compactMap { $0 }
        return paths.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}

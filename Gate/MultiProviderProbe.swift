import Combine
import Foundation
import Darwin

// A process-free Codex stand-in lets the production coordinator be exercised
// without account credentials, a listener, installed apps, or persistent defaults.
@MainActor
final class CodexAppServer: ObservableObject {
    enum State: Equatable {
        case disconnected, connecting, signingIn, connected(String?), failed(String)
    }
    @Published var state: State = .disconnected
    @Published var snapshot: UsageSnapshot = .empty
    @Published var models: [PlannerModel] = []
    @Published var modelCatalogMessage = "test"
    @Published var isLoadingModels = false
    private(set) var connectCount = 0
    private(set) var refreshCount = 0
    func connect() { connectCount += 1; state = .connected(nil) }
    func refresh() { refreshCount += 1 }
    func refreshModelCatalog() {}
    func updateGlassSettings(_ settings: GlassRenderSettings) {
        snapshot.glassSettings = settings.sanitized
    }
}

private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

private struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct MultiProviderProbe {
    private static let receivedAt = Date(timeIntervalSince1970: 1_780_000_000)

    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw ProbeFailure(description: "Pass an isolated scratch directory")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .appendingPathComponent("provider-files", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        try parserAndStore(at: root)
        try setup(at: root)
        try presentation()
        try coordinator(at: root)
        print("Agent provider probe passed: parser, private cache, reversible setup, selection and freshness.")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw ProbeFailure(description: message) }
    }

    private static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch let failure as ProbeFailure { throw failure }
        catch { return }
        throw ProbeFailure(description: message)
    }

    private static func parse(_ text: String) throws -> ClaudeStatuslineRecord {
        try ClaudeStatuslineParser.parse(Data(text.utf8), receivedAt: receivedAt)
    }

    private static func object(_ url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private static func write(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    }

    private static func parserAndStore(at root: URL) throws {
        let source = #"{"session_id":"session-private-marker","rate_limits":{"five_hour":{"used_percentage":12.6,"resets_at":1780000300},"seven_day":{"used_percentage":0,"resets_at":1780604800}},"transcript_path":"/private/secret-project/transcript.jsonl","cwd":"/private/secret-project","prompt":"secret-prompt-marker","access_token":"secret-token-marker"}"#
        let record = try parse(source)
        try expect(record.fiveHour?.usedPercent == 13 && record.weekly?.remainingPercent == 100,
                   "Decimal and zero usage do not preserve the remaining-quota meaning")
        try expect(record.fiveHour?.windowDurationMinutes == 300 && record.weekly?.windowDurationMinutes == 10_080,
                   "Official rate-limit windows have incorrect durations")
        let full = try parse(#"{"session_id":"full","rate_limits":{"five_hour":{"used_percentage":100}}}"#)
        try expect(full.fiveHour?.remainingPercent == 0 && full.weekly == nil,
                   "Fully used quota or missing window is being presented incorrectly")
        for text in [#"{}"#, #"{"rate_limits":null}"#, #"{"rate_limits":{"five_hour":null,"seven_day":null}}"#] {
            let empty = try parse(text)
            try expect(empty.fiveHour == nil && empty.weekly == nil, "Absent quota was invented as zero usage")
        }
        for text in ["{", "[]", #"{"rate_limits":{"five_hour":{"used_percentage":-1}}}"#,
                     #"{"rate_limits":{"five_hour":{"used_percentage":100.1}}}"#,
                     #"{"rate_limits":{"five_hour":{"used_percentage":"10"}}}"#,
                     #"{"rate_limits":{"five_hour":{"used_percentage":null}}}"#,
                     #"{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":-1}}}"#] {
            try rejects("Malformed or out-of-range bridge input was accepted") { _ = try parse(text) }
        }
        try rejects("Unbounded status-line input was accepted") {
            _ = try ClaudeStatuslineParser.parse(Data(repeating: 0x20, count: ClaudeStatuslineParser.maximumInputBytes + 1))
        }

        let url = root.appendingPathComponent("quota.json")
        try ClaudeStatuslineStore.save(try parse("{}"), to: url)
        try expect(try ClaudeStatuslineStore.load(from: url) == nil, "Empty startup input bound a nonexistent session")
        try ClaudeStatuslineStore.save(record, to: url)
        try expect(try ClaudeStatuslineStore.load(from: url) == record, "Quota cache did not round-trip")
        let cache = try Data(contentsOf: url)
        let text = String(decoding: cache, as: UTF8.self)
        for secret in ["session-private-marker", "secret-project", "secret-prompt-marker", "secret-token-marker", "transcript_path", "cwd"] {
            try expect(!text.contains(secret), "Sensitive Claude input crossed the normalized cache boundary")
        }
        let keys = Set(try object(url).keys)
        try expect(keys == Set(["fiveHour", "weekly", "receivedAt", "sessionFingerprint"]),
                   "Bridge cache stores fields beyond the normalized quota contract")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
        try expect(permissions.intValue & 0o777 == 0o600, "Quota cache is not owner-only")
        try rejects("A second session silently replaced the bound session") {
            try ClaudeStatuslineStore.save(full, to: url)
        }
        try rejects("Quota without a session silently replaced the bound session") {
            try ClaudeStatuslineStore.save(try parse(#"{"rate_limits":{"five_hour":{"used_percentage":10}}}"#), to: url)
        }
        let outdated = ClaudeStatuslineRecord(fiveHour: record.fiveHour, weekly: record.weekly,
                                              receivedAt: receivedAt.addingTimeInterval(-1),
                                              sessionFingerprint: record.sessionFingerprint)
        try rejects("A delayed older record replaced fresher quota") { try ClaudeStatuslineStore.save(outdated, to: url) }
        try expect(try Data(contentsOf: url) == cache, "Rejected records modified the last valid cache")
        let missing = try parse(#"{"session_id":"session-private-marker","rate_limits":null}"#)
        try ClaudeStatuslineStore.save(missing, to: url)
        try expect(try Data(contentsOf: url) == cache, "Empty status-line input replaced the last valid record or its timestamp")
        try ClaudeStatuslineStore.reset(at: url)
        try ClaudeStatuslineStore.save(full, to: url)
        try expect(try ClaudeStatuslineStore.load(from: url) == full, "Explicit reset cannot bind a new session")

        let target = root.appendingPathComponent("untouched.json")
        try Data("untouched".utf8).write(to: target)
        let link = root.appendingPathComponent("quota-symlink.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try rejects("Cache followed a symbolic link") { try ClaudeStatuslineStore.save(record, to: link) }
        try expect(try String(contentsOf: target) == "untouched", "Unsafe cache write modified its symlink target")
    }

    private static func setup(at root: URL) throws {
        let settings = root.appendingPathComponent("settings.json")
        let backup = root.appendingPathComponent("settings-backup.json")
        let original: [String: Any] = ["model": "test-model", "env": ["TEST_ONLY": "keep"],
                                       "futureField": ["nested": [1, 2, 3]], "hooks": ["Stop": []]]
        try write(original, to: settings)
        try ClaudeBridgeSetup.install(executableURL: URL(fileURLWithPath: "/bin/echo"), settingsURL: settings, backupURL: backup)
        var installed = try object(settings)
        var unrelated = installed
        unrelated.removeValue(forKey: "statusLine")
        try expect(NSDictionary(dictionary: unrelated).isEqual(to: original), "Setup discarded unknown Claude settings")
        let command = (installed["statusLine"] as? [String: Any])?["command"] as? String
        try expect(command == "'/bin/echo' --claude-statusline-bridge", "Setup installed an unexpected helper command")
        let installedBytes = try Data(contentsOf: settings)
        let backupBytes = try Data(contentsOf: backup)
        try ClaudeBridgeSetup.install(executableURL: URL(fileURLWithPath: "/bin/echo"), settingsURL: settings, backupURL: backup)
        try expect(try Data(contentsOf: settings) == installedBytes && Data(contentsOf: backup) == backupBytes,
                   "Repeated setup overwrote the original recovery data")
        try ClaudeBridgeSetup.install(executableURL: URL(fileURLWithPath: "/bin/cat"), settingsURL: settings, backupURL: backup)
        installed = try object(settings)
        let migratedCommand = (installed["statusLine"] as? [String: Any])?["command"] as? String
        try expect(migratedCommand == "'/bin/cat' --claude-statusline-bridge",
                   "A managed bridge did not migrate to the renamed executable")
        let migratedSettingsBytes = try Data(contentsOf: settings)
        let migratedBackupBytes = try Data(contentsOf: backup)
        try ClaudeBridgeSetup.install(executableURL: URL(fileURLWithPath: "/bin/cat"), settingsURL: settings, backupURL: backup)
        try expect(try Data(contentsOf: settings) == migratedSettingsBytes
                    && Data(contentsOf: backup) == migratedBackupBytes,
                   "Repeated setup after a path migration was not idempotent")
        installed["model"] = "changed-by-user"
        try write(installed, to: settings)
        try ClaudeBridgeSetup.remove(settingsURL: settings, backupURL: backup)
        var expected = original
        expected["model"] = "changed-by-user"
        try expect(NSDictionary(dictionary: try object(settings)).isEqual(to: expected),
                   "Disconnect reverted unrelated settings edited after connection")
        try expect(!FileManager.default.fileExists(atPath: backup.path), "Disconnect retained an active backup")

        let originalBytes = try Data(contentsOf: settings)
        try ClaudeBridgeSetup.install(executableURL: URL(fileURLWithPath: "/bin/echo"), settingsURL: settings, backupURL: backup)
        // Simulate a first-install interruption after the backup, before settings were written.
        try originalBytes.write(to: settings)
        try ClaudeBridgeSetup.remove(settingsURL: settings, backupURL: backup)
        try expect(try Data(contentsOf: settings) == originalBytes && !FileManager.default.fileExists(atPath: backup.path),
                   "Recovering an interrupted install changed original settings or retained its backup")

        var foreign = original
        foreign["statusLine"] = ["type": "command", "command": "do-not-execute-or-overwrite"]
        try write(foreign, to: settings)
        let foreignBytes = try Data(contentsOf: settings)
        try rejects("Setup overwrote an existing status-line command") {
            try ClaudeBridgeSetup.install(executableURL: URL(fileURLWithPath: "/bin/echo"), settingsURL: settings, backupURL: backup)
        }
        try expect(try Data(contentsOf: settings) == foreignBytes, "Rejected setup changed the settings file")
        try expect(!FileManager.default.fileExists(atPath: backup.path), "Rejected setup fabricated a backup")
        try rejects("Removal without our backup changed another status line") {
            try ClaudeBridgeSetup.remove(settingsURL: settings, backupURL: backup)
        }
        try write(original, to: settings)
        try ClaudeBridgeSetup.install(executableURL: URL(fileURLWithPath: "/bin/echo"), settingsURL: settings, backupURL: backup)
        try write(foreign, to: settings)
        try rejects("Disconnect overwrote a replacement third-party status line") {
            try ClaudeBridgeSetup.remove(settingsURL: settings, backupURL: backup)
        }
        try expect(try Data(contentsOf: settings) == foreignBytes && FileManager.default.fileExists(atPath: backup.path),
                   "Refusing external modifications lost the settings or backup")
    }

    private static func presentation() throws {
        let fiveHour = UsageWindow(usedPercent: 25, windowDurationMinutes: 300,
                                   resetsAt: receivedAt.addingTimeInterval(100))
        let weekly = UsageWindow(usedPercent: 70, windowDurationMinutes: 10_080,
                                 resetsAt: receivedAt.addingTimeInterval(700))
        let snapshot = UsageSnapshot(fiveHour: fiveHour, weekly: weekly,
                                     updatedAt: receivedAt, service: .claude, receivedAt: receivedAt)
        let before = receivedAt.addingTimeInterval(99)
        let firstReset = receivedAt.addingTimeInterval(100)
        let lastReset = receivedAt.addingTimeInterval(700)
        try expect(snapshot.displayWindow(fiveHour, at: before) == fiveHour &&
                   snapshot.statusLabel(at: before) == "会话记录", "A current Claude window was hidden")
        try expect(snapshot.displayWindow(fiveHour, at: firstReset) == nil &&
                   snapshot.displayWindow(weekly, at: firstReset) == weekly &&
                   snapshot.statusLabel(at: firstReset) == "部分窗口待更新",
                   "A reset Claude window is still presented as current remaining quota")
        try expect(snapshot.displayWindow(weekly, at: lastReset) == nil &&
                   snapshot.statusLabel(at: lastReset) == "窗口待更新",
                   "Fully expired Claude windows are still presented as usable quota")
        try expect(snapshot.menuSummary(at: before) == "周额度剩余 30%" &&
                   snapshot.menuSummary(at: firstReset) == "周额度剩余 30%" &&
                   snapshot.menuSummary(at: lastReset) == "等待额度数据",
                   "The menu presents expired Claude weekly quota or hides a still-current weekly window")
        var missingWeekly = snapshot
        missingWeekly.weekly = nil
        try expect(missingWeekly.menuSummary(at: before) == "等待额度数据",
                   "The menu invents a weekly percentage from a missing Claude window")
        try expect(snapshot.claudePresentationKey(at: before) != snapshot.claudePresentationKey(at: firstReset) &&
                   snapshot.claudePresentationKey(at: firstReset) != snapshot.claudePresentationKey(at: lastReset),
                   "A reset does not invalidate the unchanged-file presentation")
        try expect(snapshot.claudePresentationKey(at: firstReset) ==
                   snapshot.claudePresentationKey(at: receivedAt.addingTimeInterval(600)),
                   "An unchanged presentation causes unnecessary quota publications")
        var undated = snapshot
        undated.fiveHour?.resetsAt = nil
        undated.weekly?.resetsAt = nil
        try expect(undated.statusLabel(at: receivedAt.addingTimeInterval(300)) == "会话记录" &&
                   undated.statusLabel(at: receivedAt.addingTimeInterval(301)) == "较旧会话记录" &&
                   undated.displayWindow(undated.fiveHour, at: lastReset) != nil,
                   "Receipt age either stays fresh forever or invents a reset without a timestamp")
        try expect(undated.claudePresentationKey(at: receivedAt.addingTimeInterval(300)) !=
                   undated.claudePresentationKey(at: receivedAt.addingTimeInterval(301)),
                   "The receipt-age transition does not invalidate presentation")
        var codex = snapshot
        codex.service = .codex
        try expect(codex.displayWindow(fiveHour, at: lastReset) == fiveHour,
                   "Claude expiry handling changed the established Codex presentation")
        try expect(codex.menuSummary(at: lastReset) == "周额度剩余 30%" &&
                   UsageSnapshot.empty.menuSummary(at: lastReset) == "等待额度数据",
                   "Claude menu expiry changed the established Codex wording or missing-data behavior")
        try expect(snapshot.fiveHour == fiveHour && snapshot.weekly == weekly && snapshot.receivedAt == receivedAt,
                   "Presentation changed the original record or fabricated a refresh")
    }

    @MainActor
    private static func coordinator(at root: URL) throws {
        let defaults = MemoryDefaults()
        try expect(SnapshotStore.load(defaults: defaults) == .empty, "A clean install invents cached quota")
        let url = root.appendingPathComponent("coordinator.json")
        let record = try parse(#"{"session_id":"coordinator","rate_limits":{"five_hour":{"used_percentage":25},"seven_day":{"used_percentage":70}}}"#)
        try ClaudeStatuslineStore.save(record, to: url)
        let codex = CodexAppServer()
        codex.snapshot = UsageSnapshot(fiveHour: .init(usedPercent: 10, windowDurationMinutes: 300, resetsAt: nil),
                                       weekly: .init(usedPercent: 20, windowDurationMinutes: 10_080, resetsAt: nil),
                                       dailyUsage: [.init(startDate: "2026-10-24", tokens: 1_000_000)],
                                       updatedAt: receivedAt.addingTimeInterval(-50), service: .codex)
        let monitor = QuotaMonitor(codex: codex, defaults: defaults, claudeURL: url)
        monitor.connect()
        monitor.connect()
        try expect(codex.connectCount == 1, "Repeated App startup opens duplicate Codex connections")
        monitor.selectService(.claude)
        try expect(monitor.snapshot.resolvedService == .claude && monitor.snapshot.weekly?.usedPercent == 70,
                   "Selecting Claude still publishes Codex quota")
        try expect(monitor.snapshot.dailyUsage.isEmpty && monitor.snapshot.email == nil && monitor.snapshot.plan == nil,
                   "Claude selection inherited fabricated history or another service's identity")
        let quotaDate = monitor.snapshot.updatedAt
        let receivedDate = monitor.snapshot.receivedAt
        monitor.refresh()
        monitor.refresh()
        try expect(monitor.snapshot.updatedAt == quotaDate && monitor.snapshot.receivedAt == receivedDate && codex.refreshCount == 0,
                   "Reading unchanged Claude data pretends it is newly refreshed or queries Codex")
        let glass = GlassRenderSettings(appearance: .light, opacity: 0.4, dispersion: 0.2)
        monitor.updateGlassSettings(glass)
        try expect(monitor.snapshot.glassSettings == glass.sanitized && monitor.snapshot.updatedAt == quotaDate,
                   "Changing glass settings changes Claude quota freshness")
        for value in 30...34 {
            monitor.selectService(.codex)
            codex.snapshot.weekly?.usedPercent = value
            monitor.selectService(.claude)
            codex.snapshot.weekly?.usedPercent = value + 10
            codex.state = .failed("late Codex response")
            try expect(monitor.snapshot.resolvedService == .claude && monitor.snapshot.weekly?.usedPercent == 70,
                       "A late Codex response replaced the selected Claude quota")
            if case .failed = monitor.state { throw ProbeFailure(description: "A Codex failure leaked into Claude connection state") }
        }
        let restored = QuotaMonitor(codex: CodexAppServer(), defaults: defaults, claudeURL: url)
        try expect(restored.service == .claude && restored.snapshot.weekly?.usedPercent == 70,
                   "Service selection did not survive coordinator restart")
        let absent = QuotaMonitor(codex: CodexAppServer(), defaults: defaults,
                                  claudeURL: root.appendingPathComponent("not-connected.json"))
        try expect(!absent.snapshot.hasQuota && absent.snapshot.dailyUsage.isEmpty && absent.state == .disconnected,
                   "An unconnected Claude service invented quota or history")
        try expect(absent.snapshot.statusLabel(at: .now) == "等待数据", "Missing quota is described as synchronized")
        try expect(monitor.snapshot.statusLabel(at: receivedAt.addingTimeInterval(600)) != "已同步",
                   "An old Claude session record is described as live synchronization")

        let expiryURL = root.appendingPathComponent("expiring-coordinator.json")
        let expiring = ClaudeStatuslineRecord(
            fiveHour: .init(usedPercent: 25, windowDurationMinutes: 300, resetsAt: receivedAt.addingTimeInterval(10)),
            weekly: .init(usedPercent: 70, windowDurationMinutes: 10_080, resetsAt: receivedAt.addingTimeInterval(20)),
            receivedAt: receivedAt, sessionFingerprint: record.sessionFingerprint
        )
        try ClaudeStatuslineStore.save(expiring, to: expiryURL)
        let originalBytes = try Data(contentsOf: expiryURL)
        var clock = receivedAt
        let expiryCodex = CodexAppServer()
        let expiryMonitor = QuotaMonitor(codex: expiryCodex, defaults: defaults, claudeURL: expiryURL, now: { clock })
        let rawSnapshot = expiryMonitor.snapshot
        var publications = 0
        let observation = expiryMonitor.$snapshot.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        clock = receivedAt.addingTimeInterval(11)
        expiryMonitor.refresh()
        try expect(publications == 1 && expiryMonitor.snapshot.statusLabel(at: clock) == "部分窗口待更新",
                   "An unchanged file does not notify the desktop at its first reset")
        clock = receivedAt.addingTimeInterval(15)
        expiryMonitor.refresh()
        try expect(publications == 1, "An unchanged Claude presentation publishes on every polling tick")
        clock = receivedAt.addingTimeInterval(21)
        expiryMonitor.refresh()
        try expect(publications == 2 && expiryMonitor.snapshot.statusLabel(at: clock) == "窗口待更新",
                   "The remaining window does not expire without another status-line emission")
        try expect(expiryMonitor.snapshot == rawSnapshot && Data(contentsOf: expiryURL) == originalBytes &&
                   expiryCodex.connectCount == 0 && expiryCodex.refreshCount == 0,
                   "A local expiry changed the raw record, receipt time, or contacted Codex")
    }
}

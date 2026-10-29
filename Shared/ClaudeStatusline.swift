import Foundation
import CryptoKit
import Darwin

/// Only normalized quota fields cross the Claude Code status-line boundary.
public struct ClaudeStatuslineRecord: Codable, Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let weekly: UsageWindow?
    public let receivedAt: Date
    public let sessionFingerprint: String?

    public init(fiveHour: UsageWindow?, weekly: UsageWindow?, receivedAt: Date,
                sessionFingerprint: String?) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.receivedAt = receivedAt
        self.sessionFingerprint = sessionFingerprint
    }
}

public enum ClaudeBridgeError: LocalizedError {
    case oversizedInput, invalidData, sessionUnavailable, differentSession, outdatedRecord, unsafeFile
    case existingStatusLine, changedConfiguration, bridgePathChanged, missingBackup

    public var errorDescription: String? {
        switch self {
        case .oversizedInput: return L("Claude Code 状态栏输入过大。")
        case .invalidData: return L("Claude Code 额度数据无效。")
        case .sessionUnavailable: return L("状态栏未提供会话标识，无法安全关联额度。")
        case .differentSession: return L("检测到另一个 Claude Code 会话。请在 App 中选择“重新绑定会话”后切换。")
        case .outdatedRecord: return L("已忽略延迟到达的旧会话记录。")
        case .unsafeFile: return L("Claude 桥接文件不是安全的普通文件。")
        case .existingStatusLine: return L("已有 Claude Code 状态栏配置。为保留原配置，请先在 Claude Code 中移除现有状态栏，再连接。")
        case .changedConfiguration: return L("Claude Code 状态栏配置已被外部修改；保留原文件，请先检查配置。")
        case .bridgePathChanged: return L("应用的桥接路径已变化。请先移除现有桥接配置，再重新连接。")
        case .missingBackup: return L("没有本应用创建的状态栏备份，未更改 Claude Code 设置。")
        }
    }
}

public enum ClaudeStatuslineParser {
    public static let maximumInputBytes = 1_048_576

    public static func parse(_ data: Data, receivedAt: Date = .now) throws -> ClaudeStatuslineRecord {
        guard data.count <= maximumInputBytes else { throw ClaudeBridgeError.oversizedInput }
        struct Window: Decodable { let used_percentage: Double; let resets_at: Double? }
        struct Limits: Decodable { let five_hour: Window?; let seven_day: Window? }
        struct Input: Decodable { let session_id: String?; let rate_limits: Limits? }
        guard let input = try? JSONDecoder().decode(Input.self, from: data),
              validTime(receivedAt.timeIntervalSince1970) else { throw ClaudeBridgeError.invalidData }

        func window(_ value: Window?, minutes: Int) throws -> UsageWindow? {
            guard let value else { return nil }
            guard value.used_percentage.isFinite, (0...100).contains(value.used_percentage),
                  value.resets_at.map(validTime) ?? true else { throw ClaudeBridgeError.invalidData }
            return UsageWindow(usedPercent: Int(value.used_percentage.rounded()),
                               windowDurationMinutes: minutes,
                               resetsAt: value.resets_at.map(Date.init(timeIntervalSince1970:)))
        }
        let fingerprint: String?
        if let session = input.session_id, !session.isEmpty {
            guard session.utf8.count <= 4_096 else { throw ClaudeBridgeError.invalidData }
            fingerprint = SHA256.hash(data: Data(session.utf8)).map { String(format: "%02x", $0) }.joined()
        } else { fingerprint = nil }
        return try ClaudeStatuslineRecord(fiveHour: window(input.rate_limits?.five_hour, minutes: 300),
                                          weekly: window(input.rate_limits?.seven_day, minutes: 10_080),
                                          receivedAt: receivedAt, sessionFingerprint: fingerprint)
    }

    fileprivate static func validTime(_ value: Double) -> Bool {
        value.isFinite && (0...4_102_444_800).contains(value)
    }
}

public enum ClaudeStatuslineStore {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexQuota", isDirectory: true)
            .appendingPathComponent("claude-usage.json")
    }

    public static func load(from url: URL = defaultURL) throws -> ClaudeStatuslineRecord? {
        guard let data = try ClaudeBridgeFiles.readIfPresent(url, maximumBytes: 16_384) else { return nil }
        guard let record = try? JSONDecoder().decode(ClaudeStatuslineRecord.self, from: data) else {
            throw ClaudeBridgeError.invalidData
        }
        try validate(record)
        return record
    }

    private static func validate(_ record: ClaudeStatuslineRecord) throws {
        if (record.fiveHour != nil || record.weekly != nil) && record.sessionFingerprint == nil {
            throw ClaudeBridgeError.sessionUnavailable
        }
        guard ClaudeStatuslineParser.validTime(record.receivedAt.timeIntervalSince1970),
              record.sessionFingerprint.map({ $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }) ?? true
        else { throw ClaudeBridgeError.invalidData }
        for (window, duration) in [(record.fiveHour, 300), (record.weekly, 10_080)] {
            guard let window else { continue }
            guard (0...100).contains(window.usedPercent),
                  window.windowDurationMinutes == duration,
                  window.resetsAt.map({ ClaudeStatuslineParser.validTime($0.timeIntervalSince1970) }) ?? true
            else { throw ClaudeBridgeError.invalidData }
        }
    }

    public static func save(_ record: ClaudeStatuslineRecord, to url: URL = defaultURL,
                            historyURL: URL? = nil) throws {
        try validate(record)
        // An omitted rate_limits is not proof that the last quota is invalid or refreshed.
        guard record.fiveHour != nil || record.weekly != nil else { return }
        try ClaudeBridgeFiles.withLock(for: url) {
            let existing = try load(from: url)
            if let boundSession = existing?.sessionFingerprint, boundSession != record.sessionFingerprint {
                throw ClaudeBridgeError.differentSession
            }
            if let existing, record.receivedAt < existing.receivedAt { throw ClaudeBridgeError.outdatedRecord }
            // Capture the accepted source event, never GUI cache reads. DB first: if a process
            // stops between the two writes the compatibility cache may lag, but history survives.
            // Replaying this exact normalized receipt is idempotent; fresh receipts remain distinct.
            do {
                let destination = historyURL ?? url.deletingLastPathComponent().appendingPathComponent("observations.sqlite")
                try ObservationHistory.append(QuotaObservation.claude(record), at: destination,
                                              now: record.receivedAt)
            } catch {
                // Static diagnostic only: never print raw input, session IDs or filesystem paths.
                try? FileHandle.standardError.write(contentsOf: Data(L("Tallygent: 本次 Claude 历史未保存；额度缓存仍会更新。\n").utf8))
            }
            try ClaudeBridgeFiles.write(JSONEncoder().encode(record), to: url)
        }
    }

    /// Explicit disconnect only; never silently replace a selected session.
    public static func reset(at url: URL = defaultURL) throws {
        try ClaudeBridgeFiles.withLock(for: url) {
            if try ClaudeBridgeFiles.readIfPresent(url, maximumBytes: 16_384) != nil {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}

public enum ClaudeStatuslineBridge {
    /// Invoke before SwiftUI startup; returning nil means this is a normal App launch.
    public static func runIfRequested(arguments: [String] = CommandLine.arguments,
                                      cacheURL: URL = ClaudeStatuslineStore.defaultURL) -> Int32? {
        guard arguments.dropFirst().first == "--claude-statusline-bridge" else { return nil }
        do {
            var input = Data()
            while let chunk = try FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
                guard input.count + chunk.count <= ClaudeStatuslineParser.maximumInputBytes else {
                    throw ClaudeBridgeError.oversizedInput
                }
                input.append(chunk)
            }
            let record = try ClaudeStatuslineParser.parse(input)
            try ClaudeStatuslineStore.save(record, to: cacheURL)
            let parts = [("5h", record.fiveHour), (L("周"), record.weekly)].compactMap { label, window in
                window.map { LF("%@ 剩余 %lld%%", label, $0.remainingPercent) }
            }
            let output = parts.isEmpty ? L("Claude Code · 暂无额度数据") : "Claude Code · " + parts.joined(separator: " · ")
            try FileHandle.standardOutput.write(contentsOf: Data((output + "\n").utf8))
            return 0
        } catch {
            // Never echo the input: it may contain prompts, project paths or credentials.
            try? FileHandle.standardError.write(contentsOf: Data(("Tallygent: \(error.localizedDescription)\n").utf8))
            return 1
        }
    }
}

/// Native files only: bounded reads, owner-only atomic writes and one cross-process lock.
enum ClaudeBridgeFiles {
    static func readIfPresent(_ url: URL, maximumBytes: Int) throws -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw ClaudeBridgeError.unsafeFile
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_size >= 0, info.st_size <= maximumBytes else { throw ClaudeBridgeError.unsafeFile }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw ClaudeBridgeError.oversizedInput }
        return data
    }

    static func withLock<T>(for url: URL, _ operation: () throws -> T) throws -> T {
        try prepareDirectory(url.deletingLastPathComponent())
        let descriptor = open(url.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ClaudeBridgeError.unsafeFile }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), flock(descriptor, LOCK_EX) == 0 else { throw ClaudeBridgeError.unsafeFile }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    static func write(_ data: Data, to url: URL) throws {
        try prepareDirectory(url.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try readIfPresent(url, maximumBytes: 2_097_152)
        }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".claude-bridge-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ClaudeBridgeError.unsafeFile }
        defer { close(descriptor); try? FileManager.default.removeItem(at: temporary) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        guard fsync(descriptor) == 0, rename(temporary.path, url.path) == 0 else { throw ClaudeBridgeError.unsafeFile }
    }

    private static func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw ClaudeBridgeError.unsafeFile }
    }
}

import CryptoKit
import Darwin
import Dispatch
import Foundation
import SQLite3

public enum ObservationSource: String, Codable, Sendable { case codexRateLimits, claudeStatusLine }
public enum ObservationValidity: String, Codable, Sendable { case valid, unavailable }

/// Source observations, not UI snapshots. No account names, prompts or credentials belong here.
public struct QuotaObservation: Codable, Equatable, Identifiable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let eventID: String
    public let provider: AgentService
    public let accountScope: String?
    public let sessionScope: String?
    public let windowID: String
    public let durationMinutes: Int?
    public let usedPercent: Int?
    public let resetsAt: Date?
    public let source: ObservationSource
    public let receivedAt: Date
    public let providerUpdatedAt: Date?
    public let validity: ObservationValidity
    public let reason: String?
    public let quotaPool: String?

    public init(id: String = UUID().uuidString, eventID: String = UUID().uuidString,
                provider: AgentService, accountScope: String? = nil, sessionScope: String? = nil,
                windowID: String, durationMinutes: Int? = nil, usedPercent: Int? = nil,
                resetsAt: Date? = nil, source: ObservationSource, receivedAt: Date,
                providerUpdatedAt: Date? = nil, validity: ObservationValidity = .valid,
                reason: String? = nil, quotaPool: String? = nil, schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion; self.id = id; self.eventID = eventID
        self.provider = provider; self.accountScope = accountScope; self.sessionScope = sessionScope
        self.windowID = windowID; self.durationMinutes = durationMinutes; self.usedPercent = usedPercent
        self.resetsAt = resetsAt; self.source = source; self.receivedAt = receivedAt
        self.providerUpdatedAt = providerUpdatedAt; self.validity = validity; self.reason = reason
        self.quotaPool = quotaPool
    }

    public static func batch(provider: AgentService, source: ObservationSource, receivedAt: Date,
                             fiveHour: UsageWindow?, weekly: UsageWindow?, accountScope: String? = nil,
                             sessionScope: String? = nil, providerUpdatedAt: Date? = nil,
                             eventID: String? = nil) -> [Self] {
        let rows = [("fiveHour", fiveHour), ("weekly", weekly)].map { key, value in
            Self(id: key, eventID: "", provider: provider, accountScope: accountScope,
                 sessionScope: sessionScope, windowID: key, durationMinutes: value?.windowDurationMinutes,
                 usedPercent: value?.usedPercent, resetsAt: value?.resetsAt, source: source,
                 receivedAt: receivedAt, providerUpdatedAt: providerUpdatedAt,
                 validity: value == nil ? .unavailable : .valid,
                 reason: value == nil ? "windowUnavailable" : nil)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let canonical = (try? encoder.encode(rows)) ?? Data()
        let event = eventID ?? SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        return rows.map {
            Self(id: event + ":" + $0.windowID, eventID: event, provider: $0.provider,
                 accountScope: $0.accountScope, sessionScope: $0.sessionScope, windowID: $0.windowID,
                 durationMinutes: $0.durationMinutes, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt,
                 source: $0.source, receivedAt: $0.receivedAt, providerUpdatedAt: $0.providerUpdatedAt,
                 validity: $0.validity, reason: $0.reason)
        }
    }

    public static func claude(_ record: ClaudeStatuslineRecord) -> [Self] {
        batch(provider: .claude, source: .claudeStatusLine, receivedAt: record.receivedAt,
              fiveHour: record.fiveHour, weekly: record.weekly, sessionScope: record.sessionFingerprint)
    }

    fileprivate func validate() throws {
        func slug(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 160 && value.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 58, 95].contains($0)
            }
        }
        func fingerprint(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        func validDate(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite && (0...4_102_444_800).contains(date.timeIntervalSince1970) }
        guard schemaVersion == 1, slug(id), slug(eventID), slug(windowID),
              accountScope.map(fingerprint) ?? true, sessionScope.map(fingerprint) ?? true,
              quotaPool.map(slug) ?? true, validDate(receivedAt),
              providerUpdatedAt.map(validDate) ?? true, resetsAt.map(validDate) ?? true,
              durationMinutes.map({ (1...525_600).contains($0) }) ?? true,
              (provider == .codex && source == .codexRateLimits) || (provider == .claude && source == .claudeStatusLine)
        else { throw ObservationHistoryError.invalidObservation }
        switch validity {
        case .valid:
            guard let usedPercent, (0...100).contains(usedPercent), reason == nil else { throw ObservationHistoryError.invalidObservation }
        case .unavailable:
            guard usedPercent == nil, reason == "windowUnavailable" else { throw ObservationHistoryError.invalidObservation }
        }
    }
}

public enum ObservationHistoryError: LocalizedError {
    case unsafeFile, invalidObservation, incompatibleSchema, corruptDatabase, databaseBusy, capacity, storageFailure
    public var errorDescription: String? {
        switch self {
        case .unsafeFile: return L("历史文件不是当前用户私有的安全普通文件；未修改原件。")
        case .invalidObservation: return L("观测字段无效，未写入历史。")
        case .incompatibleSchema: return L("历史数据库来自不兼容版本；未覆盖原件。")
        case .corruptDatabase: return L("历史数据库损坏，未覆盖原件；请先导出或保留备份。")
        case .databaseBusy: return L("历史数据库忙；本次历史未保存，额度显示不受影响。")
        case .capacity: return L("历史存储或导出达到安全上限；请缩短导出范围或清理历史。")
        case .storageFailure: return L("无法读写本地额度历史；额度显示不受影响。")
        }
    }
}

/// SQLite serializes the App and short-lived bridge writers; each call owns one bounded connection.
public enum ObservationHistory {
    public static let retentionDays = 30
    public static let maximumDisplayRows = 20_000
    public static let maximumExportBytes = 134_217_728
    private static let maximumDatabaseBytes = 536_870_912
    private static let applicationID: Int32 = 0x54414C59
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private final class LockBudget {
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_500_000_000
    }

    public static var defaultURL: URL {
        ClaudeStatuslineStore.defaultURL.deletingLastPathComponent().appendingPathComponent("observations.sqlite")
    }

    @discardableResult
    public static func append(_ observations: [QuotaObservation], at url: URL = defaultURL, now: Date = .now) throws -> Int {
        guard observations.count <= 64 else { throw ObservationHistoryError.invalidObservation }
        for row in observations { try row.validate() }
        return try withDatabase(at: url, create: true) { db in
            try transaction(db) {
                try prune(db, now: now)
                let statement = try prepare(db, "INSERT OR IGNORE INTO observations(id,event_id,received_at,provider,payload) VALUES(?,?,?,?,?)")
                defer { sqlite3_finalize(statement) }
                var inserted = 0
                for row in observations where row.receivedAt >= cutoff(now) && row.receivedAt <= now.addingTimeInterval(300) {
                    guard try collectionEnabled(db, row.provider) else { continue }
                    let payload = try JSONEncoder().encode(row)
                    guard payload.count <= 4_096 else { throw ObservationHistoryError.invalidObservation }
                    sqlite3_reset(statement); sqlite3_clear_bindings(statement)
                    try bind(row.id, at: 1, to: statement, db: db)
                    try bind(row.eventID, at: 2, to: statement, db: db)
                    try check(sqlite3_bind_double(statement, 3, row.receivedAt.timeIntervalSince1970), db)
                    try bind(row.provider.rawValue, at: 4, to: statement, db: db)
                    try payload.withUnsafeBytes { bytes in
                        try check(sqlite3_bind_blob(statement, 5, bytes.baseAddress, Int32(bytes.count), transient), db)
                    }
                    try stepDone(statement, db)
                    let changes = Int(sqlite3_changes(db))
                    if changes == 0 {
                        let existing = try prepare(db, "SELECT payload,id,event_id,received_at,provider FROM observations WHERE id=?")
                        defer { sqlite3_finalize(existing) }
                        try bind(row.id, at: 1, to: existing, db: db)
                        guard sqlite3_step(existing) == SQLITE_ROW, try decode(existing) == row else {
                            throw ObservationHistoryError.invalidObservation
                        }
                    }
                    inserted += changes
                }
                return inserted
            }
        } ?? 0
    }

    /// Returns the newest bounded slice, ordered chronologically. A full limit may mean older rows were omitted.
    public static func load(from url: URL = defaultURL, since: Date? = nil, now: Date = .now,
                            limit: Int = maximumDisplayRows) throws -> [QuotaObservation] {
        guard (1...100_000).contains(limit) else { throw ObservationHistoryError.capacity }
        return try withDatabase(at: url, create: false) { db in
            try prune(db, now: now)
            let statement = try prepare(db, "SELECT payload,id,event_id,received_at,provider FROM observations WHERE received_at>=? AND received_at<=? ORDER BY received_at DESC,id DESC LIMIT ?")
            defer { sqlite3_finalize(statement) }
            try check(sqlite3_bind_double(statement, 1, max((since ?? cutoff(now)).timeIntervalSince1970, cutoff(now).timeIntervalSince1970)), db)
            try check(sqlite3_bind_double(statement, 2, now.addingTimeInterval(300).timeIntervalSince1970), db)
            try check(sqlite3_bind_int(statement, 3, Int32(limit)), db)
            var result: [QuotaObservation] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW else { try check(status, db); break }
                result.append(try decode(statement))
            }
            return result.reversed()
        } ?? []
    }

    public static func export(from url: URL = defaultURL, since: Date? = nil, now: Date = .now) throws -> Data {
        try withDatabase(at: url, create: false) { db in
            try prune(db, now: now)
            let statement = try prepare(db, "SELECT payload,id,event_id,received_at,provider FROM observations WHERE received_at>=? AND received_at<=? ORDER BY received_at,id")
            defer { sqlite3_finalize(statement) }
            try check(sqlite3_bind_double(statement, 1, max((since ?? cutoff(now)).timeIntervalSince1970, cutoff(now).timeIntervalSince1970)), db)
            try check(sqlite3_bind_double(statement, 2, now.addingTimeInterval(300).timeIntervalSince1970), db)
            var data = Data("{\"schemaVersion\":1,\"observations\":[".utf8), first = true
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW else { try check(status, db); break }
                let row = try decode(statement)
                let payload = try JSONEncoder().encode(row)
                guard data.count + payload.count + 3 <= maximumExportBytes else { throw ObservationHistoryError.capacity }
                if !first { data.append(0x2C) }; first = false
                data.append(payload)
            }
            data.append(contentsOf: [0x5D, 0x7D])
            return data
        } ?? Data("{\"schemaVersion\":1,\"observations\":[]}".utf8)
    }

    /// Explicit clear removes observations only, preserving collection pause controls.
    public static func clear(at url: URL = defaultURL, now: Date = .now) throws {
        _ = try withDatabase(at: url, create: false) { db in
            try execute(db, "DELETE FROM observations")
            // secure_delete clears freed pages; VACUUM bounds a formerly full local file after explicit deletion.
            try execute(db, "VACUUM")
        }
    }

    public static func isCollectionEnabled(_ provider: AgentService, at url: URL = defaultURL) throws -> Bool {
        try withDatabase(at: url, create: false) { try collectionEnabled($0, provider) } ?? true
    }

    /// Legacy defaults seed a missing setting once; the database remains authoritative thereafter.
    public static func initializeCollection(_ provider: AgentService, defaultEnabled: Bool,
                                            at url: URL = defaultURL) throws -> Bool {
        guard let enabled = try withDatabase(at: url, create: true, { db in
            try transaction(db) {
                let statement = try prepare(db, "INSERT OR IGNORE INTO collection_config(provider,enabled) VALUES(?,?)")
                defer { sqlite3_finalize(statement) }
                try bind(provider.rawValue, at: 1, to: statement, db: db)
                try check(sqlite3_bind_int(statement, 2, defaultEnabled ? 1 : 0), db)
                try stepDone(statement, db)
                return try collectionEnabled(db, provider)
            }
        }) else { throw ObservationHistoryError.storageFailure }
        return enabled
    }

    public static func setCollectionEnabled(_ provider: AgentService, enabled: Bool, at url: URL = defaultURL) throws {
        _ = try withDatabase(at: url, create: true) { db in
            let statement = try prepare(db, "INSERT INTO collection_config(provider,enabled) VALUES(?,?) ON CONFLICT(provider) DO UPDATE SET enabled=excluded.enabled")
            defer { sqlite3_finalize(statement) }
            try bind(provider.rawValue, at: 1, to: statement, db: db)
            try check(sqlite3_bind_int(statement, 2, enabled ? 1 : 0), db)
            try stepDone(statement, db)
        }
    }

    private static func cutoff(_ now: Date) -> Date { now.addingTimeInterval(-Double(retentionDays) * 86_400) }

    private static func prune(_ db: OpaquePointer, now: Date) throws {
        let statement = try prepare(db, "DELETE FROM observations WHERE received_at<?")
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_double(statement, 1, cutoff(now).timeIntervalSince1970), db)
        try stepDone(statement, db)
    }

    private static func collectionEnabled(_ db: OpaquePointer, _ provider: AgentService) throws -> Bool {
        let statement = try prepare(db, "SELECT enabled FROM collection_config WHERE provider=?")
        defer { sqlite3_finalize(statement) }
        try bind(provider.rawValue, at: 1, to: statement, db: db)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return true }
        guard status == SQLITE_ROW else { try check(status, db); return false }
        let value = sqlite3_column_int(statement, 0)
        guard value == 0 || value == 1 else { throw ObservationHistoryError.corruptDatabase }
        return value == 1
    }

    private static func withDatabase<T>(at url: URL, create: Bool, _ operation: (OpaquePointer) throws -> T) throws -> T? {
        guard url.isFileURL else { throw ObservationHistoryError.unsafeFile }
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            guard create else { return nil }
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let directory = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw ObservationHistoryError.unsafeFile }
        defer { close(directory) }
        var directoryInfo = stat()
        guard fstat(directory, &directoryInfo) == 0, directoryInfo.st_uid == getuid(),
              fchmod(directory, 0o700) == 0 else { throw ObservationHistoryError.unsafeFile }
        for suffix in ["", "-journal", "-wal", "-shm"] { try validateFile(url.path + suffix) }
        let descriptor = open(url.path, O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (create ? O_CREAT : 0), 0o600)
        guard descriptor >= 0 else {
            if !create && errno == ENOENT { return nil }
            throw ObservationHistoryError.unsafeFile
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_nlink == 1, info.st_size <= maximumDatabaseBytes, fchmod(descriptor, 0o600) == 0 else {
            close(descriptor); throw ObservationHistoryError.unsafeFile
        }
        close(descriptor)
        var pointer: OpaquePointer?
        // /var and /tmp are system aliases on macOS. Resolve ancestors only after opening
        // the final owned directory without following a symlink; keep the filename NOFOLLOW.
        guard let resolvedParent = realpath(parent.path, nil) else { throw ObservationHistoryError.unsafeFile }
        defer { free(resolvedParent) }
        let databasePath = String(cString: resolvedParent) + "/" + url.lastPathComponent
        let openStatus = sqlite3_open_v2(databasePath, &pointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
        guard openStatus == SQLITE_OK, let db = pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw mapError(openStatus)
        }
        let lockBudget = Unmanaged.passRetained(LockBudget())
        defer {
            sqlite3_busy_handler(db, nil, nil)
            sqlite3_close(db)
            lockBudget.release()
        }
        // One monotonic budget for the entire connection, not a fresh timeout
        // for every initialization PRAGMA or transaction statement.
        try check(sqlite3_busy_handler(db, { context, _ in
            guard let context else { return 0 }
            let deadline = Unmanaged<LockBudget>.fromOpaque(context).takeUnretainedValue().deadline
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return 0 }
            usleep(useconds_t(min(10_000, max(1, (deadline - now) / 1_000))))
            return DispatchTime.now().uptimeNanoseconds < deadline ? 1 : 0
        }, lockBudget.toOpaque()), db)
        try execute(db, "PRAGMA trusted_schema=OFF; PRAGMA temp_store=MEMORY")
        let version = try integer(db, "PRAGMA user_version")
        guard version == 0 || version == 1 else { throw ObservationHistoryError.incompatibleSchema }
        let marker = try integer(db, "PRAGMA application_id")
        guard (version == 0 && marker == 0) || marker == applicationID else { throw ObservationHistoryError.incompatibleSchema }
        if version == 0 {
            try transaction(db) {
                let statement = try prepare(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
                defer { sqlite3_finalize(statement) }
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let name = sqlite3_column_text(statement, 0), ["observations", "collection_config"].contains(String(cString: name)) else {
                        throw ObservationHistoryError.incompatibleSchema
                    }
                }
                try execute(db, "CREATE TABLE IF NOT EXISTS observations(id TEXT PRIMARY KEY NOT NULL,event_id TEXT NOT NULL,received_at REAL NOT NULL,provider TEXT NOT NULL,payload BLOB NOT NULL); CREATE INDEX IF NOT EXISTS observations_time ON observations(received_at); CREATE TABLE IF NOT EXISTS collection_config(provider TEXT PRIMARY KEY NOT NULL,enabled INTEGER NOT NULL CHECK(enabled IN (0,1)))")
                try validateColumns(db, table: "observations", expected: ["id", "event_id", "received_at", "provider", "payload"])
                try validateColumns(db, table: "collection_config", expected: ["provider", "enabled"])
                try execute(db, "PRAGMA application_id=\(applicationID); PRAGMA user_version=1")
            }
        }
        let pageSize = try integer(db, "PRAGMA page_size")
        guard pageSize > 0 else { throw ObservationHistoryError.corruptDatabase }
        try execute(db, "PRAGMA journal_mode=DELETE; PRAGMA secure_delete=ON; PRAGMA max_page_count=\(maximumDatabaseBytes / Int(pageSize))")
        let result = try operation(db)
        for suffix in ["", "-journal", "-wal", "-shm"] { try validateFile(url.path + suffix) }
        return result
    }

    private static func validateFile(_ path: String) throws {
        var info = stat()
        if lstat(path, &info) != 0 {
            if errno == ENOENT { return }
            throw ObservationHistoryError.unsafeFile
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1,
              info.st_mode & 0o077 == 0, info.st_size <= maximumDatabaseBytes else { throw ObservationHistoryError.unsafeFile }
    }

    private static func validateColumns(_ db: OpaquePointer, table: String, expected: [String]) throws {
        let statement = try prepare(db, "PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { throw ObservationHistoryError.corruptDatabase }
            columns.append(String(cString: name))
        }
        guard columns == expected else { throw ObservationHistoryError.incompatibleSchema }
    }

    private static func decode(_ statement: OpaquePointer) throws -> QuotaObservation {
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard (1...4_096).contains(count), let bytes = sqlite3_column_blob(statement, 0),
              let value = try? JSONDecoder().decode(QuotaObservation.self, from: Data(bytes: bytes, count: count)) else {
            throw ObservationHistoryError.corruptDatabase
        }
        do { try value.validate() } catch { throw ObservationHistoryError.corruptDatabase }
        if sqlite3_column_count(statement) >= 5 {
            guard let id = sqlite3_column_text(statement, 1), let event = sqlite3_column_text(statement, 2),
                  let provider = sqlite3_column_text(statement, 4), String(cString: id) == value.id,
                  String(cString: event) == value.eventID, String(cString: provider) == value.provider.rawValue,
                  sqlite3_column_double(statement, 3) == value.receivedAt.timeIntervalSince1970 else {
                throw ObservationHistoryError.corruptDatabase
            }
        }
        return value
    }

    private static func transaction<T>(_ db: OpaquePointer, _ operation: () throws -> T) throws -> T {
        try execute(db, "BEGIN IMMEDIATE")
        do { let result = try operation(); try execute(db, "COMMIT"); return result }
        catch { try? execute(db, "ROLLBACK"); throw error }
    }
    private static func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(db, sql, -1, &statement, nil), db)
        guard let statement else { throw ObservationHistoryError.storageFailure }
        return statement
    }
    private static func execute(_ db: OpaquePointer, _ sql: String) throws { try check(sqlite3_exec(db, sql, nil, nil, nil), db) }
    private static func integer(_ db: OpaquePointer, _ sql: String) throws -> Int32 {
        let statement = try prepare(db, sql); defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW else { try check(status, db); throw ObservationHistoryError.corruptDatabase }
        return sqlite3_column_int(statement, 0)
    }
    private static func bind(_ value: String, at index: Int32, to statement: OpaquePointer, db: OpaquePointer) throws {
        try check(sqlite3_bind_text(statement, index, value, -1, transient), db)
    }
    private static func stepDone(_ statement: OpaquePointer, _ db: OpaquePointer) throws {
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE else { try check(status, db); throw ObservationHistoryError.storageFailure }
    }
    private static func check(_ status: Int32, _ db: OpaquePointer) throws {
        guard status == SQLITE_OK else { throw mapError(status) }
    }
    private static func mapError(_ status: Int32) -> ObservationHistoryError {
        switch status & 0xFF {
        case SQLITE_BUSY, SQLITE_LOCKED: return .databaseBusy
        case SQLITE_FULL, SQLITE_TOOBIG: return .capacity
        case SQLITE_CORRUPT, SQLITE_NOTADB: return .corruptDatabase
        default: return .storageFailure
        }
    }
}

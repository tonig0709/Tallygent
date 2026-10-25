import Darwin
import Foundation
import SQLite3

@main
struct ObservationHistoryProbe {
    static let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    static let scope = String(repeating: "a", count: 64)

    static func assert(_ condition: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) {
        do { let result = try condition(); precondition(result, file: file, line: line) }
        catch { fatalError("Unexpected history error: \(error)", file: file, line: line) }
    }

    static func rows(at date: Date, provider: AgentService = .codex, used: Int = 20, event: String? = nil) -> [QuotaObservation] {
        QuotaObservation.batch(provider: provider, source: provider == .codex ? .codexRateLimits : .claudeStatusLine,
                               receivedAt: date, fiveHour: .init(usedPercent: used, windowDurationMinutes: 300,
                                                               resetsAt: epoch.addingTimeInterval(3_600)),
                               weekly: nil, accountScope: provider == .codex ? scope : nil,
                               sessionScope: provider == .claude ? scope : nil, eventID: event)
    }

    static func rejects(_ operation: () throws -> Void) {
        do { try operation(); fatalError("Expected refusal") } catch { }
    }

    static func sql(_ sql: String, at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { fatalError("Fixture open") }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { fatalError("Fixture SQL") }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func main() throws {
        let args = CommandLine.arguments
        if args.count > 1, args[1] == "crash" {
            var db: OpaquePointer?
            guard sqlite3_open(args[2], &db) == SQLITE_OK, let db,
                  sqlite3_exec(db, "PRAGMA cache_size=1; BEGIN IMMEDIATE; DELETE FROM observations", nil, nil, nil) == SQLITE_OK else {
                _exit(74)
            }
            _exit(73) // Deliberately leave an uncommitted write and journal: next open must recover.
        }
        if args.count > 1, args[1] == "writer" {
            let url = URL(fileURLWithPath: args[2]), prefix = args[3]
            for index in 0..<35 {
                try ObservationHistory.append(rows(at: epoch.addingTimeInterval(Double(index)), event: prefix + String(index)), at: url, now: epoch.addingTimeInterval(100))
            }
            return
        }
        let root = URL(fileURLWithPath: args[1], isDirectory: true).appendingPathComponent("observation-history", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = root.appendingPathComponent("observations.sqlite")
        assert(try ObservationHistory.load(from: url, now: epoch).isEmpty)
        let initial = rows(at: epoch)
        assert(try ObservationHistory.append(initial, at: url, now: epoch) == 2)
        assert(try ObservationHistory.append(initial, at: url, now: epoch) == 0)
        // Unchanged values at a genuinely new source receipt must remain a new event.
        let newer = rows(at: epoch.addingTimeInterval(1))
        assert(try ObservationHistory.append(newer, at: url, now: epoch) == 2)
        let all = try ObservationHistory.load(from: url, now: epoch)
        assert(all.count == 4 && all.first?.receivedAt == epoch && all.last?.receivedAt == epoch.addingTimeInterval(1))
        assert(all.filter { $0.validity == .unavailable }.allSatisfy { $0.usedPercent == nil && $0.reason == "windowUnavailable" })
        assert(try ObservationHistory.load(from: url, now: epoch, limit: 1).first?.receivedAt == epoch.addingTimeInterval(1))
        let export = try ObservationHistory.export(from: url, now: epoch)
        assert((try JSONSerialization.jsonObject(with: export) as? [String: Any])?["observations"] is [Any])
        assert(!String(decoding: export, as: UTF8.self).contains("email"))

        let defaultsDB = root.appendingPathComponent("collection-defaults.sqlite")
        assert(try !ObservationHistory.initializeCollection(.codex, defaultEnabled: false, at: defaultsDB))
        assert(try !ObservationHistory.initializeCollection(.codex, defaultEnabled: true, at: defaultsDB))
        assert(try !ObservationHistory.isCollectionEnabled(.codex, at: defaultsDB))
        assert(try ObservationHistory.initializeCollection(.claude, defaultEnabled: true, at: defaultsDB))
        assert(try ObservationHistory.initializeCollection(.claude, defaultEnabled: false, at: defaultsDB))

        try ObservationHistory.setCollectionEnabled(.claude, enabled: false, at: url)
        assert(try !ObservationHistory.isCollectionEnabled(.claude, at: url))
        assert(try ObservationHistory.append(rows(at: epoch, provider: .claude), at: url, now: epoch) == 0)
        try ObservationHistory.clear(at: url)
        assert(try ObservationHistory.load(from: url, now: epoch).isEmpty)
        assert(try !ObservationHistory.isCollectionEnabled(.claude, at: url))
        try ObservationHistory.setCollectionEnabled(.claude, enabled: true, at: url)
        assert(try ObservationHistory.append(rows(at: epoch, provider: .claude), at: url, now: epoch) == 2)
        assert(try ObservationHistory.append(initial, at: url, now: epoch) == 2)
        assert(try ObservationHistory.load(from: url, now: epoch).count == 4)
        // Retention is wall-clock time, not calendar grouping or an invented reconstruction.
        let later = epoch.addingTimeInterval(31 * 86_400)
        assert(try ObservationHistory.append(rows(at: later), at: url, now: later) == 2)
        assert(try ObservationHistory.load(from: url, now: later).count == 2)
        assert(try ObservationHistory.append(initial, at: url, now: later) == 0)
        assert(try ObservationHistory.load(from: url, now: later).count == 2)
        let readOnlyAge = root.appendingPathComponent("retention-on-read.sqlite")
        try ObservationHistory.append(initial, at: readOnlyAge, now: epoch)
        assert(try ObservationHistory.load(from: readOnlyAge, now: later).isEmpty)
        var ageDB: OpaquePointer?, ageStatement: OpaquePointer?
        assert(sqlite3_open(readOnlyAge.path, &ageDB) == SQLITE_OK)
        assert(sqlite3_prepare_v2(ageDB, "SELECT count(*) FROM observations", -1, &ageStatement, nil) == SQLITE_OK)
        assert(sqlite3_step(ageStatement) == SQLITE_ROW && sqlite3_column_int(ageStatement, 0) == 0)
        sqlite3_finalize(ageStatement); sqlite3_close(ageDB)

        let invalid = QuotaObservation(provider: .codex, accountScope: "someone@example.com", windowID: "fiveHour", usedPercent: 10,
                                       source: .codexRateLimits, receivedAt: epoch)
        rejects { try ObservationHistory.append([invalid], at: url, now: epoch) }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        assert((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let link = root.appendingPathComponent("link.sqlite")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        rejects { _ = try ObservationHistory.load(from: link, now: later) }
        let journalLink = root.appendingPathComponent("observations.sqlite-journal")
        try FileManager.default.createSymbolicLink(at: journalLink, withDestinationURL: url)
        rejects { try ObservationHistory.append(rows(at: later.addingTimeInterval(1)), at: url, now: later) }
        try FileManager.default.removeItem(at: journalLink)

        // Future schemas and corrupted files are refused rather than replaced.
        let future = root.appendingPathComponent("future.sqlite")
        try sql("PRAGMA user_version=99; CREATE TABLE keep_me(value TEXT); INSERT INTO keep_me VALUES('preserve')", at: future)
        let futureBefore = try Data(contentsOf: future)
        rejects { try ObservationHistory.append(initial, at: future, now: epoch) }
        assert(try Data(contentsOf: future) == futureBefore)
        let corrupt = root.appendingPathComponent("corrupt.sqlite")
        try Data("not sqlite; preserve this".utf8).write(to: corrupt)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: corrupt.path)
        let corruptBefore = try Data(contentsOf: corrupt)
        rejects { try ObservationHistory.append(initial, at: corrupt, now: epoch) }
        assert(try Data(contentsOf: corrupt) == corruptBefore)
        // A version-0 database with the recognized table can migrate without losing rows.
        let legacy = root.appendingPathComponent("legacy.sqlite")
        try ObservationHistory.append(initial, at: legacy, now: epoch)
        try sql("DROP TABLE collection_config; PRAGMA application_id=0; PRAGMA user_version=0", at: legacy)
        assert(try ObservationHistory.load(from: legacy, now: epoch).count == 2)

        // The bridge stores each accepted event before replacing its compatibility cache.
        let cache = root.appendingPathComponent("claude-cache.json"), bridgeDB = root.appendingPathComponent("bridge.sqlite")
        let record = ClaudeStatuslineRecord(fiveHour: .init(usedPercent: 12, windowDurationMinutes: 300, resetsAt: nil), weekly: nil,
                                           receivedAt: epoch, sessionFingerprint: scope)
        try ClaudeStatuslineStore.save(record, to: cache, historyURL: bridgeDB)
        try ClaudeStatuslineStore.save(record, to: cache, historyURL: bridgeDB)
        assert(try ObservationHistory.load(from: bridgeDB, now: epoch).count == 2)
        _ = try ClaudeStatuslineStore.load(from: cache)
        _ = try ClaudeStatuslineStore.load(from: cache)
        assert(try ObservationHistory.load(from: bridgeDB, now: epoch).count == 2)
        let other = ClaudeStatuslineRecord(fiveHour: record.fiveHour, weekly: nil, receivedAt: epoch.addingTimeInterval(1),
                                          sessionFingerprint: String(repeating: "b", count: 64))
        rejects { try ClaudeStatuslineStore.save(other, to: cache, historyURL: bridgeDB) }
        assert(try ObservationHistory.load(from: bridgeDB, now: epoch).count == 2)
        let delayed = ClaudeStatuslineRecord(fiveHour: record.fiveHour, weekly: nil, receivedAt: epoch.addingTimeInterval(-1), sessionFingerprint: scope)
        rejects { try ClaudeStatuslineStore.save(delayed, to: cache, historyURL: bridgeDB) }
        let fresh = ClaudeStatuslineRecord(fiveHour: record.fiveHour, weekly: nil, receivedAt: epoch.addingTimeInterval(2), sessionFingerprint: scope)
        try ClaudeStatuslineStore.save(fresh, to: cache, historyURL: bridgeDB)
        assert(try ObservationHistory.load(from: bridgeDB, now: epoch).count == 4)
        // A history fault must not make an otherwise accepted current quota disappear.
        let cache2 = root.appendingPathComponent("claude-failed-history.json")
        try ClaudeStatuslineStore.save(record, to: cache2, historyURL: corrupt)
        assert(try ClaudeStatuslineStore.load(from: cache2) == record)

        // Two independent bridge/App-style processes can append without lost observations.
        let concurrent = root.appendingPathComponent("concurrent.sqlite")
        let workers = ["A", "B"].map { prefix -> Process in
            let process = Process(); process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = ["writer", concurrent.path, prefix]; return process
        }
        for process in workers { try process.run() }
        for process in workers { process.waitUntilExit(); assert(process.terminationStatus == 0) }
        assert(try ObservationHistory.load(from: concurrent, now: epoch.addingTimeInterval(100)).count == 140)
        let interrupted = Process(); interrupted.executableURL = URL(fileURLWithPath: args[0])
        interrupted.arguments = ["crash", concurrent.path]
        try interrupted.run(); interrupted.waitUntilExit(); assert(interrupted.terminationStatus == 73)
        assert(try ObservationHistory.load(from: concurrent, now: epoch.addingTimeInterval(100)).count == 140)
        // A competing connection cannot stall monitoring indefinitely.
        var locked: OpaquePointer?
        assert(sqlite3_open(concurrent.path, &locked) == SQLITE_OK)
        assert(sqlite3_exec(locked, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
        let began = Date()
        do {
            _ = try ObservationHistory.append(rows(at: epoch, event: "locked"), at: concurrent, now: epoch)
            fatalError("Expected bounded lock refusal")
        } catch ObservationHistoryError.databaseBusy { }
        assert(Date().timeIntervalSince(began) < 3)
        sqlite3_exec(locked, "ROLLBACK", nil, nil, nil); sqlite3_close(locked)
        print("Observation history: PASS (source receipts, dedup, missing windows, pause,30d retention, privacy, migrations, recovery, concurrent processes)")
    }
}

import Foundation

@main
enum UsageExportProbe {
    static let start = Date(timeIntervalSince1970: 1_780_000_000)
    static let scope = String(repeating: "a", count: 64)

    static func row(_ index: Int, used: Int? = 20, at: Date? = nil, account: String? = scope,
                    validity: ObservationValidity = .valid, reset: Date? = start.addingTimeInterval(14_400),
                    id: String? = nil, pool: String? = nil) -> QuotaObservation {
        QuotaObservation(id: id ?? "row-\(index)", eventID: "event-\(index)", provider: .codex,
            accountScope: account, windowID: "fiveHour", durationMinutes: 300,
            usedPercent: validity == .valid ? used : nil, resetsAt: reset, source: .codexRateLimits,
            receivedAt: at ?? start.addingTimeInterval(Double(index) * 60), validity: validity,
            reason: validity == .unavailable ? "windowUnavailable" : nil, quotaPool: pool)
    }

    static func json(_ rows: [QuotaObservation]) throws -> Data {
        let payload = try JSONEncoder().encode(rows)
        return Data("{\"schemaVersion\":1,\"observations\":".utf8) + payload + Data("}".utf8)
    }

    static func html(_ rows: [QuotaObservation]) throws -> String {
        String(decoding: try UsageExport.convert(json: json(rows), format: .html,
                                               generatedAt: start.addingTimeInterval(7_200)), as: UTF8.self)
    }

    static func count(_ needle: String, in value: String) -> Int { value.components(separatedBy: needle).count - 1 }

    static func main() throws {
        let samples = [row(0), row(1, used: 25), row(2, validity: .unavailable), row(3, used: 30),
                       row(20, used: 35), row(21, used: 5), row(22, used: 10, reset: start.addingTimeInterval(15_000)),
                       row(23, used: 20, account: String(repeating: "b", count: 64))]
        let original = try json(samples)
        let unchangedJSON = try UsageExport.convert(json: original, format: .json, generatedAt: start)
        precondition(unchangedJSON == original,
                     "JSON export no longer preserves the original data/schema")
        let csvData = try UsageExport.convert(json: original, format: .csv, generatedAt: start)
        precondition(csvData.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        let csv = String(decoding: csvData, as: UTF8.self)
        precondition(count("\r\n", in: csv) == samples.count + 1, "CSV lost raw observations")
        precondition(csv.contains("receivedAtUTC") && csv.contains("remainingPercent") && csv.contains("\"80\""))
        precondition(csv.contains("\"unavailable\",\"windowUnavailable\""), "missing values were dropped or filled")
        let unsafe = row(1, id: "  =SUM(1,2)\n\"quoted\"", pool: "</title><script>alert('x')</script>&")
        let unsafeCSV = String(decoding: try UsageExport.convert(json: json([unsafe]), format: .csv, generatedAt: start), as: UTF8.self)
        precondition(unsafeCSV.contains("\"'  =SUM(1,2)\n\"\"quoted\"\"\""), "CSV formula/quote escaping is unsafe")
        let escaped = try html([row(0, account: "<script>attack</script>\"&'")])
        precondition(!escaped.contains("<script>") && escaped.contains("&lt;script&gt;attack&lt;/script&gt;&quot;&amp;&#39;"), "HTML metadata was not escaped")
        let report = try html(samples)
        precondition(count("<section>", in: report) == 2, "different account scopes were merged")
        precondition(count("class=\"plot\"", in: report) == 1 && count("<circle", in: report) == 5,
                     "HTML crossed an unavailable read, long gap, quota increase, reset or account change")
        precondition(report.contains("100%") && report.contains("50%") && report.contains("0%") && report.contains(TimeZone.current.identifier))
        precondition(!report.contains("<script") && !report.contains("https://") && report.contains("Content-Security-Policy"), "HTML export is not standalone/offline")
        let unknown = try html([row(0, account: nil), row(1, account: nil)])
        precondition(!unknown.contains("class=\"plot\"") && count("<circle", in: unknown) == 2, "unknown identities were joined")
        let empty = try html([])
        precondition(empty.contains(L("所选时段暂无观测")) && !empty.contains("<svg"))
        let many = (0..<129).map { index in row(index, account: String(format: "%064x", index)) }
        let bounded = try html(many)
        precondition(count("<section>", in: bounded) == 128 && bounded.contains(L("图表报告最多显示 128 组最近有记录的序列；其余完整记录可导出为 CSV 或 JSON。")), "large HTML report must be bounded and disclose omissions")
        let completeCSV = String(decoding: try UsageExport.convert(json: json(many), format: .csv, generatedAt: start), as: UTF8.self)
        precondition(count("\r\n", in: completeCSV) == 130, "HTML display limits must not truncate CSV")
        let long = (0..<1_000).map { row($0, used: min(100, $0 / 10), at: start.addingTimeInterval(Double($0))) }
        let sampled = try html(long)
        precondition(count("class=\"plot\"", in: sampled) == 1 && count(" L", in: sampled) < 250,
                     "long continuous SVG segments are not sampled")
        if let output = ProcessInfo.processInfo.environment["TALLYGENT_EXPORT_PREVIEW"] {
            try Data(report.utf8).write(to: URL(fileURLWithPath: output), options: .atomic)
        }
        print("Usage export passed: exact JSON, full CSV/escaping, offline SVG axes, missing/reset/account/gap isolation, bounded reports.")
    }
}

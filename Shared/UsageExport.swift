import Foundation

public enum UsageExportFormat: String, CaseIterable, Identifiable, Sendable {
    case html, csv, json
    public var id: Self { self }
    public var fileExtension: String { rawValue }
    public var title: String {
        switch self {
        case .html: L("HTML 图表报告")
        case .csv: L("CSV 表格")
        case .json: L("JSON 原始记录")
        }
    }
}

/// Conversions use the same complete, bounded export as JSON, not the UI's display slice.
public enum UsageExport {
    private struct Envelope: Decodable {
        let schemaVersion: Int
        let observations: [QuotaObservation]
    }

    public static func convert(json: Data, format: UsageExportFormat, generatedAt: Date) throws -> Data {
        guard json.count <= ObservationHistory.maximumExportBytes else { throw ObservationHistoryError.capacity }
        if format == .json { return json }
        let envelope = try JSONDecoder().decode(Envelope.self, from: json)
        guard envelope.schemaVersion == 1 else { throw ObservationHistoryError.incompatibleSchema }
        let rows = envelope.observations
        guard rows.allSatisfy({ $0.schemaVersion == 1 &&
            ($0.usedPercent.map { (0...100).contains($0) } ?? true) &&
            ($0.validity == .valid ? $0.usedPercent != nil : $0.usedPercent == nil)
        }) else { throw ObservationHistoryError.invalidObservation }
        return try format == .csv ? csv(rows) : html(rows, generatedAt: generatedAt)
    }

    private static func append(_ value: String, to data: inout Data) throws {
        let bytes = Data(value.utf8)
        guard bytes.count <= ObservationHistory.maximumExportBytes - data.count else { throw ObservationHistoryError.capacity }
        data.append(bytes)
    }

    private static func csv(_ rows: [QuotaObservation]) throws -> Data {
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func stamp(_ value: Date?) -> String { value.map(date.string) ?? "" }
        var data = Data([0xEF, 0xBB, 0xBF]) // UTF-8 BOM lets spreadsheet apps recognize translated text.
        try append("schemaVersion,id,eventID,provider,accountScope,sessionScope,windowID,durationMinutes,usedPercent,remainingPercent,resetsAtUTC,source,receivedAtUTC,providerUpdatedAtUTC,validity,reason,quotaPool\r\n", to: &data)
        for row in rows {
            let values = [String(row.schemaVersion), row.id, row.eventID, row.provider.rawValue,
                row.accountScope ?? "", row.sessionScope ?? "", row.windowID,
                row.durationMinutes.map(String.init) ?? "", row.usedPercent.map(String.init) ?? "",
                row.usedPercent.map { String(100 - $0) } ?? "", stamp(row.resetsAt), row.source.rawValue,
                stamp(row.receivedAt), stamp(row.providerUpdatedAt), row.validity.rawValue, row.reason ?? "", row.quotaPool ?? ""]
            try append(values.map(csvCell).joined(separator: ",") + "\r\n", to: &data)
        }
        return data
    }

    private static func csvCell(_ value: String) -> String {
        // Quoting alone does not stop spreadsheet formula execution.
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let dangerous = first.map { "=+-@".contains($0) } ?? false
        let protected = dangerous || value.first.map({ "\t\r\n".contains($0) }) == true ? "'" + value : value
        return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func html(_ rows: [QuotaObservation], generatedAt: Date) throws -> Data {
        let date = DateFormatter()
        date.dateStyle = .medium; date.timeStyle = .medium
        var data = Data()
        try append("""
        <!doctype html><html lang="\(escape(Bundle.main.preferredLocalizations.first ?? "en"))"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'none'; base-uri 'none'; form-action 'none'">
        <title>Tallygent — \(escape(L("用量报告")))</title>
        <style>
        :root{color-scheme:light dark;font:16px/1.55 system-ui,-apple-system,sans-serif;background:#f6f7f9;color:#17202b}
        *{box-sizing:border-box}body{max-width:1120px;margin:0 auto;padding:40px 24px}h1{font-size:30px;line-height:1.2;margin:0 0 12px}
        h2{font-size:19px;margin:0 0 8px}p{margin:8px 0}.note,.scope{color:#526174;font-size:14px;overflow-wrap:anywhere}
        header{margin-bottom:32px}section{padding:24px 0;border-top:1px solid #c8d0da;break-inside:avoid}.chart{overflow-x:auto}svg{width:100%;min-width:720px;height:auto;display:block;margin-top:12px}
        .grid{stroke:#b5c0ce;stroke-width:1;opacity:.45}.axis{fill:currentColor;font:12px system-ui,sans-serif}.plot{fill:none;stroke:#1976d2;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}.point{fill:#1976d2}
        footer{border-top:1px solid #c8d0da;margin-top:24px;padding-top:16px}.metadata{display:flex;gap:8px 32px;flex-wrap:wrap}
        @media(prefers-color-scheme:dark){:root{background:#15191f;color:#f2f5f9}.note,.scope{color:#b6c3d3}.plot{stroke:#69a8ff}.point{fill:#69a8ff}}
        @media print{:root{color-scheme:light;background:white;color:#17202b}body{padding:0;font-size:12px}.note,.scope{color:#526174}svg{min-width:0}.chart{overflow:visible}}
        </style></head><body><header><h1>Tallygent · \(escape(L("用量报告")))</h1>
        <div class="metadata"><span>\(escape(L("导出时间"))) · \(escape(date.string(from: generatedAt)))</span><span>\(escape(L("原始记录数"))) · \(rows.count)</span></div>
        <p class="note">\(escape(L("每条曲线按服务、来源、额度窗口及账户或会话范围隔离。空白不代表 0%，不跨重置或缺口连线。")))</p>
        <p class="note">\(escape(L("图表已抽样；CSV 和 JSON 保留完整原始记录。")))</p></header>
        """, to: &data)
        let groups = Dictionary(grouping: rows, by: UsageInsights.seriesKey)
        // ponytail: a readable report is bounded to the 128 most recently seen
        // series; machine-readable formats retain every exported observation.
        let keys = groups.keys.sorted {
            let left = groups[$0]!.last!.receivedAt, right = groups[$1]!.last!.receivedAt
            return left == right ? $0 < $1 : left > right
        }
        if keys.count > 128 {
            try append("<p class=\"note\">\(escape(L("图表报告最多显示 128 组最近有记录的序列；其余完整记录可导出为 CSV 或 JSON。")))</p>", to: &data)
        }
        for key in keys.prefix(128) {
            guard let group = groups[key], let row = group.first else { continue }
            let title = row.windowID == "fiveHour" ? L("5h 额度") : (row.windowID == "weekly" ? L("周额度") : row.windowID)
            let scope = [row.accountScope.map { L("按账户隔离") + " · " + $0 },
                         row.sessionScope.map { (row.accountScope == nil ? L("仅此会话；账户范围未核实") : L("会话记录")) + " · " + $0 }].compactMap { $0 }.joined(separator: " · ")
            let source = row.source == .codexRateLimits ? L("来源：Codex 额度响应") : L("来源：Claude Code statusLine 被动事件")
            let insight = UsageInsights.analyze(observations: group, now: generatedAt).windows.first { $0.provider == row.provider && $0.windowID == row.windowID }
            try append("<section><h2>\(escape(row.provider.title)) · \(escape(title))</h2><p class=\"scope\">\(escape(scope.isEmpty ? L("身份范围未知") : scope))</p><p class=\"note\">\(escape(source))</p>", to: &data)
            if let history = insight?.history, !history.isEmpty {
                try append("<div class=\"chart\">" + chart(history) + "</div>", to: &data)
            } else {
                try append("<p>\(escape(L("所选时段暂无有效观测")))</p>", to: &data)
            }
            try append("</section>", to: &data)
        }
        if rows.isEmpty { try append("<p>\(escape(L("所选时段暂无观测")))</p>", to: &data) }
        try append("""
        <footer><p class="note">\(escape(L("在浏览器中打开即可查看图表；可通过打印保存为 PDF。")))</p>
        <p class="note">\(escape(L("导出文件包含匿名账户或会话指纹，请谨慎分享；导出后不会自动删除。")))</p></footer></body></html>
        """, to: &data)
        return data
    }

    private static func chart(_ history: [UsageHistoryPoint]) -> String {
        let start = history.first!.date
        let end = history.last!.date
        let span = max(60, end.timeIntervalSince(start))
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(span > 48 * 3_600 ? "MMMd" : "MMMdHHmm")
        func number(_ value: Double) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value) }
        func x(_ date: Date) -> String { number(52 + date.timeIntervalSince(start) / span * 880) }
        func y(_ percent: Int) -> String { number(20 + Double(100 - percent) / 100 * 192) }
        var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 960 282\" role=\"img\" aria-label=\"\(escape(L("剩余额度（%）")))\"><text class=\"axis\" x=\"52\" y=\"12\">\(escape(L("剩余额度（%）")))</text>"
        for percent in [0, 50, 100] {
            svg += "<path class=\"grid\" d=\"M52 \(y(percent)) H932\"/><text class=\"axis\" text-anchor=\"end\" x=\"44\" y=\"\(number(24 + Double(100 - percent) / 100 * 192))\">\(percent)%</text>"
        }
        for index in 0...4 {
            let date = start.addingTimeInterval(span * Double(index) / 4)
            let anchor = index == 0 ? "start" : (index == 4 ? "end" : "middle")
            svg += "<text class=\"axis\" x=\"\(x(date))\" y=\"234\" text-anchor=\"\(anchor)\">\(escape(formatter.string(from: date)))</text>"
        }
        // ponytail: bound points within each continuous segment, never connect or
        // drop an entire sparse segment merely to hit one global display limit.
        for segment in Dictionary(grouping: history, by: \.segmentID).values.sorted(by: { $0[0].date < $1[0].date }) {
            let stride = max(1, Int(ceil(Double(segment.count) / 240)))
            let points = segment.enumerated().compactMap { index, point in index % stride == 0 || index == segment.count - 1 ? point : nil }
            if points.count == 1, let point = points.first {
                svg += "<circle class=\"point\" cx=\"\(x(point.date))\" cy=\"\(y(point.remainingPercent))\" r=\"2.8\"/>"
            } else {
                let path = points.enumerated().map { "\($0.offset == 0 ? "M" : "L")\(x($0.element.date)) \(y($0.element.remainingPercent))" }.joined(separator: " ")
                svg += "<path class=\"plot\" d=\"\(path)\"/>"
            }
        }
        svg += "<text class=\"axis\" x=\"52\" y=\"267\">\(escape(L("观测时间（本地）"))) · \(escape(TimeZone.current.identifier))</text></svg>"
        return svg
    }
}

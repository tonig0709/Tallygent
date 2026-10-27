import Foundation
import CoreFoundation

public enum AppServerParserError: Error, Equatable {
    case invalidEnvelope
    case missingRateLimits
}

public struct AccountInfo: Equatable, Sendable {
    public let email: String?
    public let plan: String?
    public let isLoggedIn: Bool
}

public struct RateLimitWindows: Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let weekly: UsageWindow?
}

public enum AppServerParser {
    public static func object(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppServerParserError.invalidEnvelope
        }
        return object
    }

    public static func account(from object: [String: Any]) throws -> AccountInfo {
        guard let result = object["result"] as? [String: Any] else {
            throw AppServerParserError.invalidEnvelope
        }
        guard let account = result["account"] as? [String: Any] else {
            return AccountInfo(email: nil, plan: nil, isLoggedIn: false)
        }
        return AccountInfo(
            email: account["email"] as? String,
            plan: account["planType"] as? String,
            isLoggedIn: true
        )
    }

    public static func rateLimitWindows(from object: [String: Any]) throws -> RateLimitWindows {
        guard object["error"] == nil,
              let result = object["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any]
        else { throw AppServerParserError.missingRateLimits }

        var windows: [Int: UsageWindow] = [:]
        for raw in [limits["primary"], limits["secondary"]] {
            guard let raw, !(raw is NSNull) else { continue }
            guard let value = raw as? [String: Any],
                  let duration = quotaInteger(value["windowDurationMins"]), duration > 0
            else { throw AppServerParserError.invalidEnvelope }
            // A new provider duration is unknown, not another name for weekly quota.
            guard duration == 300 || duration == 10_080 else { continue }
            guard windows[duration] == nil,
                  let used = quotaInteger(value["usedPercent"]), (0...100).contains(used)
            else { throw AppServerParserError.invalidEnvelope }
            var reset: Date?
            if let rawReset = value["resetsAt"], !(rawReset is NSNull) {
                guard let timestamp = quotaInteger(rawReset), (0...4_102_444_800).contains(timestamp)
                else { throw AppServerParserError.invalidEnvelope }
                reset = Date(timeIntervalSince1970: TimeInterval(timestamp))
            }
            windows[duration] = UsageWindow(usedPercent: used, windowDurationMinutes: duration, resetsAt: reset)
        }
        return RateLimitWindows(fiveHour: windows[300], weekly: windows[10_080])
    }

    public static func weeklyWindow(from object: [String: Any]) throws -> UsageWindow {
        guard let weekly = try rateLimitWindows(from: object).weekly else {
            throw AppServerParserError.missingRateLimits
        }
        return weekly
    }

    public static func dailyUsage(from object: [String: Any]) throws -> [DailyUsage] {
        guard let result = object["result"] as? [String: Any] else {
            throw AppServerParserError.invalidEnvelope
        }
        let buckets = result["dailyUsageBuckets"] as? [[String: Any]] ?? []
        return buckets.compactMap { bucket in
            guard let startDate = bucket["startDate"] as? String,
                  let tokens = int64OrNil(bucket["tokens"])
            else { return nil }
            return DailyUsage(startDate: startDate, tokens: tokens)
        }
        .suffix(7)
        .map { $0 }
    }

    public static func authURL(from object: [String: Any]) -> URL? {
        guard let result = object["result"] as? [String: Any],
              let value = result["authUrl"] as? String
        else { return nil }
        return URL(string: value)
    }

    private static func quotaInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, let integer = Int(exactly: number.doubleValue)
        else { return nil }
        return integer
    }

    private static func int64OrNil(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }
}

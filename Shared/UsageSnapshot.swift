import Foundation

public enum AgentService: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, claude
    public var id: Self { self }
    public var title: String { self == .codex ? "Codex" : "Claude Code" }
}

public enum WidgetAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case dark, light

    public var id: Self { self }
    public var title: String { self == .dark ? "深色" : "浅色" }
}

public enum GlassRefractionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, polar, prominent

    public var id: Self { self }
}

/// Shared visual response for the App preview and the native desktop surface.
/// Frost is a haze overlay; macOS owns the actual backdrop blur radius.
public struct GlassOptics: Sendable {
    public let dispersionStrength: Double
    public let edgeOffset: Double
    public let edgeOpacity: Double
    public let edgeWidth: Double
    public let frostOpacity: Double

    public init(blurAmount: Double, dispersion: Double) {
        dispersionStrength = dispersion.isFinite ? min(1, max(0, dispersion / 0.30)) : 0
        edgeOffset = 3 * dispersionStrength
        edgeOpacity = 0.55 * dispersionStrength
        edgeWidth = 0.7 + 1.3 * dispersionStrength
        frostOpacity = 0.45 * (blurAmount.isFinite ? min(1, max(0, blurAmount)) : 0)
    }
}

/// A target-neutral description of the glass surface. The app persists this
/// alongside the quota snapshot; every panel uses the same persisted values.
public struct GlassRenderSettings: Codable, Equatable, Sendable {
    public var appearance: WidgetAppearance
    public var opacity: Double
    public var edgeStrength: Double
    public var elasticity: Double
    public var displacement: Double
    public var blurAmount: Double
    public var saturation: Double
    public var dispersion: Double
    public var cornerRadius: Double
    public var tone: String
    public var refractionMode: GlassRefractionMode

    public init(
        appearance: WidgetAppearance = .dark,
        opacity: Double = WidgetGlassOpacity.defaultValue,
        edgeStrength: Double = 0.55,
        elasticity: Double = 0.15,
        displacement: Double = 0.35,
        blurAmount: Double = 0.20,
        saturation: Double = 1.40,
        dispersion: Double = 0.08,
        cornerRadius: Double = 30,
        tone: String = "neutral",
        refractionMode: GlassRefractionMode = .standard
    ) {
        self.appearance = appearance
        self.opacity = opacity
        self.edgeStrength = edgeStrength
        self.elasticity = elasticity
        self.displacement = displacement
        self.blurAmount = blurAmount
        self.saturation = saturation
        self.dispersion = dispersion
        self.cornerRadius = cornerRadius
        self.tone = tone
        self.refractionMode = refractionMode
    }

    public var sanitized: Self {
        Self(
            appearance: appearance,
            opacity: WidgetGlassOpacity.clamped(opacity),
            edgeStrength: min(1, max(0, edgeStrength)),
            elasticity: min(1, max(0, elasticity)),
            displacement: min(1, max(0, displacement)),
            blurAmount: min(1, max(0, blurAmount)),
            saturation: min(2.2, max(1, saturation)),
            dispersion: min(0.30, max(0, dispersion)),
            cornerRadius: min(64, max(10, cornerRadius)),
            tone: ["cool", "neutral", "warm"].contains(tone) ? tone : "neutral",
            refractionMode: refractionMode
        )
    }

    public static let standard = Self()
}

public struct UsageWindow: Codable, Equatable, Sendable {
    public var usedPercent: Int
    public var windowDurationMinutes: Int?
    public var resetsAt: Date?

    public var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }

    public init(usedPercent: Int, windowDurationMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }
}

public struct DailyUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { startDate }
    public let startDate: String
    public let tokens: Int64

    public init(startDate: String, tokens: Int64) {
        self.startDate = startDate
        self.tokens = tokens
    }

    public var millions: Double { Double(tokens) / 1_000_000 }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var fiveHour: UsageWindow?
    public var weekly: UsageWindow?
    public var dailyUsage: [DailyUsage]
    public var email: String?
    public var plan: String?
    public var appearance: WidgetAppearance?
    public var glassSettings: GlassRenderSettings?
    public var updatedAt: Date
    // Optional fields keep existing Codex caches readable across the upgrade.
    public var service: AgentService?
    public var receivedAt: Date?

    public init(
        fiveHour: UsageWindow? = nil,
        weekly: UsageWindow? = nil,
        dailyUsage: [DailyUsage] = [],
        email: String? = nil,
        plan: String? = nil,
        appearance: WidgetAppearance = .dark,
        glassSettings: GlassRenderSettings? = nil,
        updatedAt: Date = .now,
        service: AgentService? = nil,
        receivedAt: Date? = nil
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.dailyUsage = dailyUsage
        self.email = email
        self.plan = plan
        self.appearance = appearance
        self.glassSettings = glassSettings
        self.updatedAt = updatedAt
        self.service = service
        self.receivedAt = receivedAt
    }

    public var resolvedAppearance: WidgetAppearance { appearance ?? .dark }
    public var resolvedService: AgentService { service ?? .codex }
    public var hasQuota: Bool { fiveHour != nil || weekly != nil }
    public var lastReceivedAt: Date { receivedAt ?? updatedAt }

    public func statusLabel(at now: Date) -> String {
        guard hasQuota else { return "等待数据" }
        if resolvedService == .claude { return "会话记录" }
        return now.timeIntervalSince(lastReceivedAt) > 60 ? "数据待刷新" : "已同步"
    }

    public static let empty = UsageSnapshot(updatedAt: .distantPast)

    public static let placeholder = UsageSnapshot(
        fiveHour: UsageWindow(usedPercent: 18, windowDurationMinutes: 300, resetsAt: nil),
        weekly: UsageWindow(usedPercent: 28, windowDurationMinutes: 10_080, resetsAt: nil),
        dailyUsage: [
            .init(startDate: "Mon", tokens: 12_000_000),
            .init(startDate: "Tue", tokens: 27_000_000),
            .init(startDate: "Wed", tokens: 54_000_000),
            .init(startDate: "Thu", tokens: 21_000_000),
            .init(startDate: "Fri", tokens: 34_000_000),
            .init(startDate: "Sat", tokens: 10_000_000),
            .init(startDate: "Sun", tokens: 13_000_000)
        ]
    )
}

public enum QuotaLevel: Equatable, Sendable {
    case healthy, warning, critical

    public init(remainingPercent: Int) {
        if remainingPercent >= 60 { self = .healthy }
        else if remainingPercent >= 30 { self = .warning }
        else { self = .critical }
    }
}

public enum WidgetGlassOpacity {
    public static let minimum = 0.35
    public static let maximum = 1.0
    public static let defaultValue = 0.86

    public static func clamped(_ value: Double) -> Double {
        min(maximum, max(minimum, value))
    }

    public static func normalized(_ value: Double) -> Double {
        (clamped(value) - minimum) / (maximum - minimum)
    }

    /// The native glass carries refraction; this film controls how close the
    /// dark appearance is to solid black without hiding the wallpaper at the
    /// minimum setting.
    public static func darkFilmOpacity(_ value: Double) -> Double {
        0.08 + pow(normalized(value), 1.15) * 0.86
    }

    public static func darkGlassTintOpacity(_ value: Double) -> Double {
        0.28 + normalized(value) * 0.22
    }
}

public enum SnapshotHTTPClient {
    public static let endpoint = URL(string: "http://127.0.0.1:48193/snapshot")!

    public static func load(from url: URL = endpoint, fallback: UsageSnapshot) async -> UsageSnapshot {
        var safeFallback = fallback
        safeFallback.email = nil
        safeFallback.plan = nil
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              response.mimeType == "application/json",
              var snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        else { return safeFallback }
        snapshot.email = nil
        snapshot.plan = nil
        return snapshot
    }
}

public enum SnapshotStore {
    private static let key = "usageSnapshot"

    public static func load(defaults: UserDefaults = sharedDefaults) -> UsageSnapshot {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        else { return .empty }
        return value
    }

    public static func save(_ snapshot: UsageSnapshot, defaults: UserDefaults = sharedDefaults) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public static var sharedDefaults: UserDefaults {
        .standard
    }
}

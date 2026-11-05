import Foundation

public enum AppUIAppearance: String, Codable, CaseIterable, Sendable { case system, light, dark }
public enum AppUIPalette: String, Codable, CaseIterable, Sendable {
    case ocean, iris, mint, rose
    public var primaryRGB: Int {
        switch self { case .ocean: 0x2459C4; case .iris: 0x6540B8; case .mint: 0x08756B; case .rose: 0xA13670 }
    }
    public var secondaryRGB: Int {
        switch self { case .ocean: 0x4C43B9; case .iris: 0x3558B4; case .mint: 0x2061A6; case .rose: 0x6F45B0 }
    }
}
public enum AppUIButtonTreatment: String, Codable, CaseIterable, Sendable { case gradient, solid }
public enum AppUIDensity: String, Codable, CaseIterable, Sendable { case comfortable, compact }

/// Main-app preferences only. Never included in provider snapshots or panel rendering.
public struct AppUISettings: Codable, Equatable, Sendable {
    public static let defaultsKey = "appUI.appearance.v1"
    public var appearance: AppUIAppearance = .system
    public var palette: AppUIPalette = .ocean
    public var buttonTreatment: AppUIButtonTreatment = .gradient
    public var density: AppUIDensity = .comfortable
    public var cornerRadius: Double = 14
    public var motionIntensity: Double = 0.45
    public var hoverHighlights = true
    public init() {}
    public static let standard = AppUISettings()
    public var sanitized: Self {
        var value = self
        value.cornerRadius = cornerRadius.isFinite ? min(16, max(8, cornerRadius)) : 14
        value.motionIntensity = motionIntensity.isFinite ? min(1, max(0, motionIntensity)) : 0.45
        return value
    }
    public var encoded: Data { (try? JSONEncoder().encode(sanitized)) ?? Data() }
    public static func decode(_ data: Data) -> Self {
        ((try? JSONDecoder().decode(Self.self, from: data)) ?? .standard).sanitized
    }
    public var isCompact: Bool { density == .compact }
    public var spacing: Double { isCompact ? 16 : 24 }
}

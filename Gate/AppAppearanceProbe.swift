import Foundation

/// Pure model/contrast checks: no app launch, listener, account or personal defaults.
@main
enum AppAppearanceProbe {
    static func main() throws {
        let standard = AppUISettings.standard
        precondition(AppUISettings.defaultsKey == "appUI.appearance.v1")
        precondition(standard.appearance == .system && standard.palette == .ocean &&
                     standard.buttonTreatment == .gradient && standard.density == .comfortable &&
                     standard.cornerRadius == 14 && standard.motionIntensity == 0.45 && standard.hoverHighlights)
        precondition(!standard.isCompact && standard.spacing == 24)

        var count = 0
        for appearance in AppUIAppearance.allCases {
            for palette in AppUIPalette.allCases {
                for treatment in AppUIButtonTreatment.allCases {
                    for density in AppUIDensity.allCases {
                        var value = standard
                        value.appearance = appearance; value.palette = palette
                        value.buttonTreatment = treatment; value.density = density
                        value.cornerRadius = 12; value.motionIntensity = 0; value.hoverHighlights = false
                        precondition(AppUISettings.decode(value.encoded) == value,
                                     "appearance preferences lost a valid option during persistence")
                        precondition(value.isCompact == (density == .compact) &&
                                     value.spacing == (density == .compact ? 16 : 24))
                        count += 1
                    }
                }
            }
        }

        for (radius, intensity, expectedRadius, expectedIntensity) in [
            (-100.0, -1.0, 8.0, 0.0), (100.0, 8.0, 16.0, 1.0),
            (Double.nan, Double.infinity, 14.0, 0.45),
            (-Double.infinity, -Double.infinity, 14.0, 0.45)
        ] {
            var value = standard
            value.cornerRadius = radius; value.motionIntensity = intensity
            precondition(value.sanitized.cornerRadius == expectedRadius &&
                         value.sanitized.motionIntensity == expectedIntensity,
                         "untrusted appearance parameters escaped finite bounds")
            precondition(AppUISettings.decode(value.encoded) == value.sanitized,
                         "invalid numeric preference prevented a safe persisted roundtrip")
        }
        for malformed in [Data(), Data("not JSON".utf8), Data("[]".utf8),
                          Data(#"{"appearance":"dark","opacity":0.35,"edgeStrength":1}"#.utf8)] {
            precondition(AppUISettings.decode(malformed) == standard,
                         "unrelated/legacy preferences changed main-app defaults")
        }
        let object = try JSONSerialization.jsonObject(with: standard.encoded) as! [String: Any]
        for (key, badValue) in [("appearance", "sepia"), ("palette", "unknown"),
                                ("motionIntensity", "NaN"), ("buttonTreatment", "neon")] {
            var invalid = object; invalid[key] = badValue
            let invalidData = try JSONSerialization.data(withJSONObject: invalid)
            precondition(AppUISettings.decode(invalidData) == standard,
                         "corrupt appearance data must fall back to the safe default")
        }
        var future = object; future["futureOption"] = "ignored"
        let futureData = try JSONSerialization.data(withJSONObject: future)
        precondition(AppUISettings.decode(futureData) == standard)
        var bounded = object; bounded["cornerRadius"] = 30; bounded["motionIntensity"] = -2
        let clamped = AppUISettings.decode(try JSONSerialization.data(withJSONObject: bounded))
        precondition(clamped.cornerRadius == 16 && clamped.motionIntensity == 0)

        // White primary-action labels must remain readable over the whole gradient.
        for palette in AppUIPalette.allCases {
            let start = rgb(palette.primaryRGB), end = rgb(palette.secondaryRGB)
            for step in 0...20 {
                let mix = Double(step) / 20
                let color = zip(start, end).map { $0.0 * (1 - mix) + $0.1 * mix }
                for sheen in [0.0, 0.07] {
                    let highlighted = color.map { $0 * (1 - sheen) + sheen }
                    precondition(contrastWithWhite(highlighted) >= 4.5,
                                 "primary action gradient/hover has insufficient white-label contrast")
                }
            }
        }
        precondition(contrastWithWhite(rgb(0xBBBBBB)) < 4.5,
                     "contrast checker accepted a known-bad light button")
        print("App appearance model: \(count) option roundtrips, numeric bounds, corrupt/legacy recovery, palette contrast and negative control: PASS")
    }

    private static func rgb(_ value: Int) -> [Double] {
        [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { $0 / 255 }
    }
    private static func contrastWithWhite(_ rgb: [Double]) -> Double {
        let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        return 1.05 / (luminance + 0.05)
    }
}

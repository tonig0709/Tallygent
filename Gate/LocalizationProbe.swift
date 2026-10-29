import Foundation

@main
struct LocalizationProbe {
    static func main() {
        let expected = ProcessInfo.processInfo.environment["TALLYGENT_EXPECT_LANGUAGE"]!
        precondition(Bundle.main.preferredLocalizations.first == expected, "Native system-language selection or English fallback failed")
        let weekly = ["en": "Weekly quota", "zh-Hans": "周额度", "zh-Hant": "每週額度"][expected]!
        precondition(L("周额度") == weekly, "Dynamic text did not use the selected bundle language")
        let formatted = LF("本机 model/list · %lld 个可选模型 · 实际推理权限未验证", Int64(2))
        precondition(formatted.contains("2") && !formatted.contains("%lld"), "Typed localization format was not substituted")
        precondition(L("unregistered-provider-model-id") == "unregistered-provider-model-id", "Unknown identifiers must remain unchanged")
        print("Native localization passed: \(expected), \(weekly)")
    }
}

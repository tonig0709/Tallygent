import Foundation

/// Native bundle localization follows macOS preferred languages (including per-app settings).
/// Source keys remain stable; account data, identifiers and persisted raw values are not translated.
public func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

public func LF(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: L(format), locale: Locale.current, arguments: arguments)
}

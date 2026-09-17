import Foundation

/// User-selectable app language. `.system` preserves the device locale (today's
/// behaviour); the other cases pin the app to one of the six shipped catalogs.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case spanish = "es"
    case japanese = "ja"
    case german = "de"
    case french = "fr"

    // MARK: Public

    /// Locale for SwiftUI's `\.locale` and explicit lookups. `.system` follows
    /// the device; the six pinned cases map to their catalog language.
    public var locale: Locale {
        self == .system ? .current : Locale(identifier: rawValue)
    }
}

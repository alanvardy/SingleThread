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

    /// BCP-47 identifier, or `nil` when following the system.
    public var localeIdentifier: String? {
        self == .system ? nil : rawValue
    }

    /// Picker label. `.system` localizes through the App catalog; the six
    /// language names are endonyms deliberately left out of every catalog so
    /// they render verbatim (cataloging them would also trip
    /// `LocalizationTests`' English-identity guard).
    public var title: LocalizedStringResource {
        switch self {
        case .system: LocalizedStringResource("System", table: "Localizable", bundle: .main)
        case .english: LocalizedStringResource("English")
        case .simplifiedChinese: LocalizedStringResource("简体中文")
        case .spanish: LocalizedStringResource("Español")
        case .japanese: LocalizedStringResource("日本語")
        case .german: LocalizedStringResource("Deutsch")
        case .french: LocalizedStringResource("Français")
        }
    }
}

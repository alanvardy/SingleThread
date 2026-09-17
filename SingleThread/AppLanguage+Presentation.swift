import SingleThreadCore
import SwiftUI

// MARK: - AppLanguage presentation

/// SwiftUI presentation for the Core `AppLanguage`, mirroring `SortOption` /
/// `TextSize` (Core stays presentation- and bundle-free; the app target owns the
/// picker label, which resolves against the App catalog).
extension AppLanguage {
    /// Picker label. `.system` localizes through the App catalog; the six
    /// language names are endonyms deliberately left out of every catalog so
    /// they render verbatim (cataloging them would also trip
    /// `LocalizationTests`' English-identity guard).
    var title: LocalizedStringResource {
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

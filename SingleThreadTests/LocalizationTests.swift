import Foundation
import Testing

/// Validates the string-catalog and InfoPlist.strings resource layer that
/// the localization effort ships:
///
/// - every `.xcstrings` catalog parses and has non-empty English values;
/// - every key resolves a non-empty value in *all six* supported languages;
/// - count-based `%lld` keys carry `variations.plural` with the CLDR-mandated
///   categories in each locale;
/// - every target's `InfoPlist.strings` has the required keys in all six
///   supported languages.
///
/// The catalogs live in the source tree (synchronized folder groups), so
/// `#filePath` of this test file resolves to the checkout's source path; no
/// bundle lookup is needed.
struct LocalizationTests {
    // MARK: Internal

    @Test
    func catalogsParseAndHaveNonEmptyEnglish() throws {
        for (name, url) in Self.catalogs {
            let data = try Data(contentsOf: url)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = try #require(root["strings"] as? [String: Any])
            #expect(!strings.isEmpty, "\(name) catalog has no keys")
            for (key, value) in strings {
                let entry = try #require(value as? [String: Any], "\(name)/\(key) malformed")
                let localizations = try #require(entry["localizations"] as? [String: Any])
                let enEntry = try #require(localizations["en"] as? [String: Any], "\(name)/\(key) missing en")
                if let unit = enEntry["stringUnit"] as? [String: Any] {
                    let enValue = try #require(unit["value"] as? String, "\(name)/\(key) en has no value")
                    #expect(!enValue.isEmpty, "\(name)/\(key) has empty en value")
                } else {
                    // Plural keys carry their English value under variations.plural.
                    let variations = try #require(
                        enEntry["variations"] as? [String: Any],
                        "\(name)/\(key) en has neither stringUnit nor variations")
                    let plural = try #require(
                        variations["plural"] as? [String: Any],
                        "\(name)/\(key) en variations has no plural")
                    #expect(!plural.isEmpty, "\(name)/\(key) en plural has no categories")
                    for (category, variation) in plural {
                        let variant = try #require(
                            variation as? [String: Any],
                            "\(name)/\(key) plural \(category) malformed")
                        let unit = try #require(
                            variant["stringUnit"] as? [String: Any],
                            "\(name)/\(key) plural \(category) has no stringUnit")
                        let value = try #require(
                            unit["value"] as? String,
                            "\(name)/\(key) plural \(category) has no value")
                        #expect(!value.isEmpty, "\(name)/\(key) plural \(category) is empty")
                    }
                }
            }
        }
    }

    /// Every catalog key resolves a non-empty value in *all six* supported
    /// languages — either directly via `stringUnit.value` or across plural
    /// variations for the `%lld` keys.
    @Test
    func catalogsHaveAllSixLanguages() throws {
        for (name, url) in Self.catalogs {
            let data = try Data(contentsOf: url)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = try #require(root["strings"] as? [String: Any])
            for (key, value) in strings {
                let entry = try #require(value as? [String: Any], "\(name)/\(key) malformed")
                let localizations = try #require(entry["localizations"] as? [String: Any])
                for language in Self.languages {
                    let loc = try #require(
                        localizations[language] as? [String: Any],
                        "\(name)/\(key) missing \(language)")
                    #expect(
                        Self.hasNonEmptyValue(loc),
                        "\(name)/\(key) has empty \(language) value")
                }
            }
        }
    }

    /// The `%lld` plural keys carry `variations.plural` in every locale, with a
    /// `one` variant in locales whose CLDR rules distinguish singular/plural
    /// (en/es/de/fr) and `other`-only in zh-Hans/ja.
    @Test
    func pluralKeysCarryPluralVariationsInAllLanguages() throws {
        for (catalogName, keys) in Self.pluralKeys {
            let data = try Data(contentsOf: Self.catalogURL(for: catalogName))
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = try #require(root["strings"] as? [String: Any])
            for key in keys {
                let entry = try #require(
                    strings[key] as? [String: Any],
                    "\(catalogName)/\(key) missing")
                let localizations = try #require(
                    entry["localizations"] as? [String: Any],
                    "\(catalogName)/\(key) has no localizations")
                for language in Self.languages {
                    let loc = try #require(
                        localizations[language] as? [String: Any],
                        "\(key) missing \(language)")
                    let variations = try #require(
                        loc["variations"] as? [String: Any],
                        "\(key)/\(language) missing variations")
                    let plural = try #require(
                        variations["plural"] as? [String: Any],
                        "\(key)/\(language) missing plural")
                    let categories = plural.keys
                    #expect(
                        categories.contains("other"),
                        "\(key)/\(language) should have an other variant, got \(categories)")
                    if Self.pluralLocales.contains(language) {
                        #expect(
                            categories.contains("one"),
                            "\(key)/\(language) should have a one variant, got \(categories)")
                    }
                }
            }
        }
    }

    @Test
    func infoPlistStringsHaveRequiredKeysPerLanguage() throws {
        for (target, keys) in Self.infoPlistTargets {
            for language in Self.languages {
                let filePath = Self.repoRoot
                    .appendingPathComponent(Self.pluralizedTargetPath(target))
                    .appendingPathComponent("\(language).lproj/InfoPlist.strings")
                let data = try Data(contentsOf: filePath)
                let plist = try #require(
                    try PropertyListSerialization.propertyList(from: data, format: nil)
                        as? [String: String])
                for key in keys {
                    let value = try #require(plist[key], "\(target)/\(language) missing \(key)")
                    #expect(!value.isEmpty, "\(target)/\(language) \(key) is empty")
                }
            }
        }
    }

    // MARK: - Regression guard

    /// Every non-English value in the App and Core catalogs must differ from the
    /// English source. Intentional identities (brand names, format strings, and
    /// validated computing cognates) are listed in `excludedIdentities`.
    ///
    /// Watch and Widget catalogs are excluded — research confirms zero
    /// English-identity flags in their 4 / 5 keys.
    @Test
    func nonEnglishValuesDifferFromEnglish() throws {
        for (name, url) in Self.guardedCatalogs {
            let data = try Data(contentsOf: url)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = try #require(root["strings"] as? [String: Any])
            for (key, value) in strings {
                let entry = try #require(value as? [String: Any], "\(name)/\(key) malformed")
                let localizations = try #require(entry["localizations"] as? [String: Any])
                let enEntry = try #require(localizations["en"] as? [String: Any], "\(name)/\(key) missing en")
                for language in Self.nonEnglishLanguages {
                    guard let loc = localizations[language] as? [String: Any] else {
                        continue
                    }
                    if Self.excludedIdentities.contains(ExclusionEntry(catalog: name, key: key)) {
                        continue
                    }
                    if let unit = loc["stringUnit"] as? [String: Any] {
                        let enValue = try Self.englishValue(from: enEntry, key: key, catalog: name)
                        let locValue = try #require(
                            unit["value"] as? String,
                            "\(name)/\(key) \(language) stringUnit has no value")
                        #expect(
                            locValue != enValue,
                            "\(name)/\(key) \(language) value is identical to English: \"\(locValue)\"")
                    } else if let variations = loc["variations"] as? [String: Any],
                              let plural = variations["plural"] as? [String: Any] {
                        let enVariations = try #require(
                            enEntry["variations"] as? [String: Any],
                            "\(name)/\(key) en missing variations for plural comparison")
                        let enPlural = try #require(
                            enVariations["plural"] as? [String: Any],
                            "\(name)/\(key) en missing plural for plural comparison")
                        for (category, variation) in plural {
                            guard let variant = variation as? [String: Any],
                                  let unit = variant["stringUnit"] as? [String: Any],
                                  let locValue = unit["value"] as? String else { continue }
                            guard let enVariant = enPlural[category] as? [String: Any],
                                  let enUnit = enVariant["stringUnit"] as? [String: Any],
                                  let enValue = enUnit["value"] as? String else { continue }
                            #expect(
                                locValue != enValue,
                                "\(name)/\(key) \(language) \(category) identical to English: \"\(locValue)\"")
                        }
                    }
                }
            }
        }
    }

    // MARK: Private

    /// A key identity within a specific catalog.
    private struct ExclusionEntry: Hashable {
        let catalog: String
        let key: String
    }

    /// Locales whose CLDR plural rules distinguish a singular `one` category
    /// from plural `other` for the count-based `%lld` keys.
    private static let pluralLocales = ["en", "es", "de", "fr"]

    /// The count-based keys that must carry `variations.plural`.
    private static let pluralKeys: [(name: String, keys: [String])] = [
        ("Core", [
            "Every %lld days",
            "Every %lld weeks",
            "Every %lld months",
            "Every %lld years"
        ]),
        ("App", ["You have %lld reminders waiting — open SingleThread!"])
    ]

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SingleThreadTests/
        .deletingLastPathComponent() // repo root

    private static let languages = ["en", "zh-Hans", "es", "ja", "de", "fr"]

    private static let catalogs: [(name: String, url: URL)] = [
        ("Core", repoRoot.appendingPathComponent(
            "SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings")),
        ("App", repoRoot.appendingPathComponent("SingleThread/Resources/Localizable.xcstrings")),
        ("Watch", repoRoot.appendingPathComponent("SingleThreadWatch/Resources/Localizable.xcstrings")),
        ("Widget", repoRoot.appendingPathComponent("SingleThreadWidget/Resources/Localizable.xcstrings"))
    ]

    private static let infoPlistTargets: [(name: String, keys: [String])] = [
        ("App", [
            "NSMicrophoneUsageDescription",
            "NSRemindersUsageDescription",
            "NSSpeechRecognitionUsageDescription",
            "CFBundleDisplayName"
        ]),
        ("Watch", ["NSRemindersFullAccessUsageDescription", "CFBundleDisplayName"]),
        ("Widget", ["NSRemindersFullAccessUsageDescription", "CFBundleDisplayName"])
    ]

    /// Catalogs guarded against English-identity translations.
    private static let guardedCatalogs: [(name: String, url: URL)] = [
        catalogs[0], // Core
        catalogs[1] // App
    ]

    /// All non-English languages.
    private static let nonEnglishLanguages = ["zh-Hans", "es", "ja", "de", "fr"]

    /// Keys whose non-English value may be byte-identical to the English source.
    /// Format strings, brand names, and validated computing cognates.
    private static let excludedIdentities: Set<ExclusionEntry> = [
        ExclusionEntry(catalog: "App", key: "%lld%%"),
        ExclusionEntry(catalog: "App", key: "SingleThread"),
        ExclusionEntry(catalog: "App", key: "Copyright 2026 Alan Vardy"),
        // de "System" — standard German computing term, same spelling as English
        ExclusionEntry(catalog: "App", key: "System"),
        // fr "Interface" — standard French computing term, same spelling as English
        ExclusionEntry(catalog: "App", key: "Interface"),
        // fr "Notifications" — standard French UI term, same spelling as English
        ExclusionEntry(catalog: "App", key: "Notifications"),
        // de/fr "Version" — same spelling in German and French
        ExclusionEntry(catalog: "Core", key: "Version %@")
    ]

    // Note: "Medium" stays in both guarded catalogs — App (font-size
    // picker, es "Mediano") and Core (priority level, es "Media") — same
    // English word, different UI contexts and translations. Not an exclusion:
    // both entries are genuinely translated in every locale.

    /// True when the localization entry carries a non-empty translated value,
    /// either directly (`stringUnit`) or across all plural variations.
    private static func hasNonEmptyValue(_ loc: [String: Any]) -> Bool {
        if let unit = loc["stringUnit"] as? [String: Any] {
            if let value = unit["value"] as? String {
                return !value.isEmpty
            }
        }
        if let variations = loc["variations"] as? [String: Any] {
            if let plural = variations["plural"] as? [String: Any] {
                if plural.isEmpty {
                    return false
                }
                for (_, variation) in plural {
                    if let variant = variation as? [String: Any] {
                        if let unit = variant["stringUnit"] as? [String: Any] {
                            if let value = unit["value"] as? String {
                                if value.isEmpty {
                                    return false
                                }
                            } else {
                                return false
                            }
                        } else {
                            return false
                        }
                    } else {
                        return false
                    }
                }
                return true
            }
        }
        return false
    }

    private static func catalogURL(for name: String) -> URL {
        switch name {
        case "Core", "App", "Watch", "Widget":
            catalogs.first { $0.name == name }?.url ?? repoRoot
        default:
            repoRoot
        }
    }

    /// Extracts the English `stringUnit.value` from an en localization entry.
    /// Handles both direct stringUnit keys and keys nested under variations.plural.
    private static func englishValue(from enEntry: [String: Any], key: String, catalog: String) throws -> String {
        if let unit = enEntry["stringUnit"] as? [String: Any] {
            return try #require(
                unit["value"] as? String,
                "\(catalog)/\(key) en stringUnit has no value")
        }
        // For plural-only keys, return the en `other` category value as the canonical form.
        if let variations = enEntry["variations"] as? [String: Any],
           let plural = variations["plural"] as? [String: Any],
           let otherVariant = plural["other"] as? [String: Any],
           let otherUnit = otherVariant["stringUnit"] as? [String: Any] {
            return try #require(
                otherUnit["value"] as? String,
                "\(catalog)/\(key) en plural other has no value")
        }
        throw NSError(
            domain: "LocalizationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(catalog)/\(key) en has no extractable value"])
    }

    // MARK: - Helpers

    private static func pluralizedTargetPath(_ target: String) -> String {
        switch target {
        case "App": "SingleThread"
        case "Watch": "SingleThreadWatch"
        case "Widget": "SingleThreadWidget"
        default: target
        }
    }
}

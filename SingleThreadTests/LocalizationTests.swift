import Foundation
import Testing

/// Validates the string-catalog and InfoPlist.strings resource layer that
/// Phase 1 of the localization effort ships:
///
/// - every `.xcstrings` catalog parses and has non-empty English values;
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

    // MARK: Private

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

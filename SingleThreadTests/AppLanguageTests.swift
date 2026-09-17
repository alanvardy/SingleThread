import SingleThreadCore
import SwiftUI
import Testing

// MARK: - App Language Tests

/// Covers the `AppLanguage` enum, its persisted `AppLanguagePreference` store,
/// the process-wide `AppLocaleState`, and the explicit-locale resolution
/// helpers the language picker relies on.
@MainActor
struct AppLanguageTests {
    @Test
    func languagePreferenceRoundTripsEveryCase() throws {
        let name = "test-applang-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) } // isolated
        let pref = AppLanguagePreference(defaults: suite, key: "appLanguage")
        for language in AppLanguage.allCases {
            pref.setRawValue(language.rawValue)
            #expect(pref.load() == language)
            #expect(pref.rawValue == language.rawValue)
        }
        // `.standard` untouched
        #expect(UserDefaults.standard.object(forKey: "appLanguage") == nil)
    }

    @Test
    func languagePreferenceFallsBackToSystemOnUnknownRawValue() throws {
        let name = "test-applang-bad-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }
        suite.set("klingon", forKey: "appLanguage")
        #expect(AppLanguagePreference(defaults: suite, key: "appLanguage").load() == .system)
    }

    @Test
    func localizedStringResourceResolvesInExplicitLocale() {
        // The one out-of-repo API risk: prove it before anything depends on it.
        let resource = LocalizedStringResource("Skip", table: "Localizable", bundle: Bundle.core)
        #expect(resource.resolved(in: Locale(identifier: "en")) == "Skip")
        #expect(resource.resolved(in: Locale(identifier: "de")) == "Überspringen")
    }

    @Test
    func effectiveLocaleFollowsTheStoredLanguage() throws {
        let name = "test-applang-loc-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }
        AppLanguagePreference(defaults: suite, key: "appLanguage").setRawValue("de")
        let state = AppLocaleState(
            language: AppLanguagePreference(defaults: suite, key: "appLanguage").load(),
            defaults: suite)
        #expect(state.effectiveLocale == Locale(identifier: "de"))
        state.set(.japanese)
        #expect(AppLanguagePreference(defaults: suite, key: "appLanguage").load() == .japanese)
    }

    @Test
    func endonymsRenderVerbatim() {
        // No catalog entry → the key is returned unchanged in every locale.
        #expect(AppLanguage.german.title.resolved(in: Locale(identifier: "ja")) == "Deutsch")
        #expect(AppLanguage.simplifiedChinese.title.resolved(in: Locale(identifier: "en")) == "简体中文")
    }

    @Test
    func systemTitleLocalizesThroughTheCatalog() {
        #expect(AppLanguage.system.title.resolved(in: Locale(identifier: "de")) == "System")
    }

    @Test
    func sharedStringResolvesToEveryShippedLanguage() {
        let expected: [String: String] = [
            "en": "Skip", "zh-Hans": "跳过", "es": "Omitir",
            "ja": "スキップ", "de": "Überspringen", "fr": "Passer"
        ]
        // SharedStrings.skipAction is a resource in Phase 2.
        for (identifier, value) in expected {
            #expect(
                SharedStrings.skipAction.resolved(in: Locale(identifier: identifier)) == value,
                "Skip in \(identifier)")
        }
    }
}

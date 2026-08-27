import Foundation
import SingleThreadCore
import Testing

struct ShowCompletionGlowPreferenceTests {
    @Test
    func missingKeyDefaultsToEnabled() {
        let key = "showcompletionglow-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowCompletionGlowPreference(defaults: .standard, key: key)
        #expect(preference.isEnabled)
    }

    @Test
    func setFalseRoundTrips() {
        let key = "showcompletionglow-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowCompletionGlowPreference(defaults: .standard, key: key)
        preference.set(false)
        #expect(!preference.isEnabled)
    }

    @Test
    func setTrueRoundTrips() {
        let key = "showcompletionglow-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowCompletionGlowPreference(defaults: .standard, key: key)
        preference.set(true)
        #expect(preference.isEnabled)
    }

    @Test
    func missingKeyIsNotFalse() {
        let key = "showcompletionglow-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowCompletionGlowPreference(defaults: .standard, key: key)
        #expect(preference.isEnabled != false)
    }
}

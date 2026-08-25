import Foundation
import SingleThreadCore
import Testing

struct ShowRecurrencePreferenceTests {
    @Test
    func missingKeyDefaultsToEnabled() {
        let key = "showrecurrence-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowRecurrencePreference(defaults: .standard, key: key)
        #expect(preference.isEnabled)
    }

    @Test
    func setFalseRoundTrips() {
        let key = "showrecurrence-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowRecurrencePreference(defaults: .standard, key: key)
        preference.set(false)
        #expect(!preference.isEnabled)
    }

    @Test
    func setTrueRoundTrips() {
        let key = "showrecurrence-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowRecurrencePreference(defaults: .standard, key: key)
        preference.set(true)
        #expect(preference.isEnabled)
    }
}

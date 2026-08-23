import Foundation
import SingleThreadCore
import Testing

struct ShowListPreferenceTests {
    @Test
    func missingKeyDefaultsToDisabled() {
        let key = "showlist-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowListPreference(defaults: .standard, key: key)
        #expect(!preference.isEnabled)
    }

    @Test
    func setTrueRoundTrips() {
        let key = "showlist-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowListPreference(defaults: .standard, key: key)
        preference.set(true)
        #expect(preference.isEnabled)
    }

    @Test
    func setFalseRoundTrips() {
        let key = "showlist-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowListPreference(defaults: .standard, key: key)
        preference.set(false)
        #expect(!preference.isEnabled)
    }
}

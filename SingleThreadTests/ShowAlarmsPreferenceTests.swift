import Foundation
import SingleThreadCore
import Testing

struct ShowAlarmsPreferenceTests {
    @Test
    func missingKeyDefaultsToEnabled() {
        let key = "showalarms-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowAlarmsPreference(defaults: .standard, key: key)
        #expect(preference.isEnabled)
    }

    @Test
    func setFalseRoundTrips() {
        let key = "showalarms-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowAlarmsPreference(defaults: .standard, key: key)
        preference.set(false)
        #expect(!preference.isEnabled)
    }

    @Test
    func setTrueRoundTrips() {
        let key = "showalarms-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowAlarmsPreference(defaults: .standard, key: key)
        preference.set(true)
        #expect(preference.isEnabled)
    }
}

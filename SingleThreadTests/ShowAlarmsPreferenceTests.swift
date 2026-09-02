import Foundation
import SingleThreadCore
import Testing

struct ShowAlarmsPreferenceTests {
    @Test
    func defaultAndRoundTrips() {
        let key = "showalarms-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowAlarmsPreference(defaults: .standard, key: key)
        #expect(preference.isEnabled, "missing key defaults to enabled")
        preference.set(false)
        #expect(!preference.isEnabled, "set(false) round-trips")
        preference.set(true)
        #expect(preference.isEnabled, "set(true) round-trips")
    }
}

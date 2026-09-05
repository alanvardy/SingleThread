import Foundation
import SingleThreadCore
import Testing

struct ShowUndatedRemindersPreferenceTests {
    @Test
    func defaultAndRoundTrips() {
        let key = "showundated-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowUndatedRemindersPreference(defaults: .standard, key: key)
        #expect(!preference.isEnabled, "missing key defaults to false")
        preference.set(true)
        #expect(preference.isEnabled, "set(true) round-trips")
        preference.set(false)
        #expect(!preference.isEnabled, "set(false) round-trips")
    }
}

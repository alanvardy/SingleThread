import Foundation
import SingleThreadCore
import Testing

struct ShowDatePreferenceTests {
    @Test
    func missingKeyDefaultsToEnabled() {
        let key = "showdate-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowDatePreference(defaults: .standard, key: key)
        #expect(preference.isEnabled)
    }

    @Test
    func setFalseRoundTrips() {
        let key = "showdate-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowDatePreference(defaults: .standard, key: key)
        preference.set(false)
        #expect(!preference.isEnabled)
    }

    @Test
    func setTrueRoundTrips() {
        let key = "showdate-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowDatePreference(defaults: .standard, key: key)
        preference.set(true)
        #expect(preference.isEnabled)
    }

    @Test
    func missingKeyIsNotFalse() {
        let key = "showdate-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowDatePreference(defaults: .standard, key: key)
        // A missing key must never read as false (which would hide dates by
        // default). Distinguishes the nil→true default from bool(forKey:).
        #expect(preference.isEnabled != false)
    }
}

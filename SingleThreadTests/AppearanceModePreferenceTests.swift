import Foundation
import SingleThreadCore
import Testing

struct AppearanceModePreferenceTests {
    @Test
    func defaultAndRoundTrips() {
        let key = "appearance-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = AppearanceModePreference(defaults: .standard, key: key)
        #expect(preference.rawValue == "system", "missing key defaults to system")
        preference.setRawValue("dark")
        #expect(preference.rawValue == "dark", "setRawValue(dark) round-trips")
        preference.setRawValue("unknown")
        #expect(preference.rawValue == "system", "unrecognized raw falls back to system")
        preference.setRawValue("light")
        #expect(preference.rawValue == "light", "setRawValue(light) round-trips")
    }
}

import Foundation
import SingleThreadCore
import Testing

struct OrientationPreferenceTests {
    @Test
    func defaultAndRoundTrips() {
        let key = "orientation-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = OrientationPreference(defaults: .standard, key: key)
        #expect(preference.isLandscapeEnabled, "missing key defaults to true")
        preference.setLandscapeEnabled(false)
        #expect(!preference.isLandscapeEnabled, "setLandscapeEnabled(false) round-trips")
        preference.setLandscapeEnabled(true)
        #expect(preference.isLandscapeEnabled, "setLandscapeEnabled(true) round-trips")
    }
}

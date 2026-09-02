import Foundation
import SingleThreadCore
import Testing

struct ShowCompletionGlowPreferenceTests {
    @Test
    func defaultAndRoundTrips() {
        let key = "showcompletionglow-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowCompletionGlowPreference(defaults: .standard, key: key)
        #expect(preference.isEnabled, "missing key defaults to enabled")
        #expect(
            preference.isEnabled != false,
            "missing key must never read as false (bool(forKey:) would hide the glow by default)")
        preference.set(false)
        #expect(!preference.isEnabled, "set(false) round-trips")
        preference.set(true)
        #expect(preference.isEnabled, "set(true) round-trips")
    }
}

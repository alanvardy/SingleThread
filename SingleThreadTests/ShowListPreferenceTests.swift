import Foundation
import SingleThreadCore
import Testing

struct ShowListPreferenceTests {
    @Test
    func defaultAndRoundTripsWithDisabledDefault() {
        let key = "showlist-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowListPreference(defaults: .standard, key: key)
        #expect(
            !preference.isEnabled,
            "absent key defaults to disabled (new feature preserves today's card look)")
        preference.set(true)
        #expect(preference.isEnabled, "set(true) round-trips")
        preference.set(false)
        #expect(!preference.isEnabled, "set(false) round-trips")
    }
}

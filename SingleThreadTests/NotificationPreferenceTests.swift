import Foundation
import SingleThreadCore
import Testing

struct NotificationPreferenceTests {
    @Test
    func defaultAndRoundTrips() {
        let key = "notif-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let enabledKey = key + "-enabled"
        let intervalKey = key + "-interval"
        let preference = NotificationPreference(
            defaults: .standard,
            enabledKey: enabledKey,
            intervalKey: intervalKey)
        #expect(!preference.isEnabled, "missing key defaults to false")
        #expect(preference.intervalHours == 48, "missing key defaults to 48")
        preference.setEnabled(true)
        #expect(preference.isEnabled, "setEnabled(true) round-trips")
        preference.setIntervalHours(24)
        #expect(preference.intervalHours == 24, "setIntervalHours(24) round-trips")
        preference.setIntervalHours(0)
        #expect(preference.intervalHours == 48, "zero falls back to 48")
    }
}

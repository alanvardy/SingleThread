import Foundation
import SingleThreadCore
import Testing

// MARK: - Crash Reporting Preference Tests

struct CrashReportingPreferenceTests {
    @Test
    func absentKeyDefaultsToEnabled() throws {
        let defaults = try #require(UserDefaults(suiteName: "CrashReportingPreferenceTests.absent"))
        defer { defaults.removePersistentDomain(forName: "CrashReportingPreferenceTests.absent") }
        #expect(CrashReportingPreference(defaults: defaults).isEnabled)
    }

    @Test
    func toggleRoundTripsThroughInjectedDefaults() throws {
        let suite = "CrashReportingPreferenceTests.roundTrip"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = CrashReportingPreference(defaults: defaults)

        preference.setEnabled(false)
        #expect(!preference.isEnabled)
        #expect(defaults.object(forKey: CrashReportingPreference.defaultsKey) as? Bool == false)

        preference.setEnabled(true)
        #expect(preference.isEnabled)
    }
}

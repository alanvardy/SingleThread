import EventKit
import Foundation
import SingleThreadCore
import Testing

/// Covers the pure logic extracted from the widget's `NextThingProvider`:
/// per-key preference fallbacks, the timeline refresh interval, and the
/// authorization gate. macOS-safe — EventKit is available in the macOS unit run.
struct NextThingWidgetLogicTests {
    // MARK: Internal

    @Test
    func refreshDateAddsInterval() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        #expect(
            NextThingWidgetLogic.nextRefreshDate(from: base)
                == base.addingTimeInterval(300),
            "the timeline refresh is the fixed 5-minute interval")
    }

    @Test
    func displayPreferencesDefaultPerKeyFallbacks() {
        let preferences = NextThingDisplayPreferences(defaults: makeDefaults())
        #expect(preferences.showsDate, "showDate falls back to true")
        #expect(!preferences.showsList, "showList falls back to false")
        #expect(preferences.showsRecurrence, "showRecurrence falls back to true")
        #expect(preferences.showsAlarms, "showAlarms falls back to true")
    }

    @Test
    func displayPreferencesReadPersistedOverrides() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: BoolPreferenceKey.showDate.rawValue)
        defaults.set(true, forKey: BoolPreferenceKey.showList.rawValue)
        defaults.set(false, forKey: BoolPreferenceKey.showRecurrence.rawValue)
        defaults.set(false, forKey: BoolPreferenceKey.showAlarms.rawValue)

        let preferences = NextThingDisplayPreferences(defaults: defaults)

        #expect(!preferences.showsDate)
        #expect(preferences.showsList)
        #expect(!preferences.showsRecurrence)
        #expect(!preferences.showsAlarms)
    }

    @Test
    func accessDeniedYieldsNoAccess() {
        #expect(
            NextThingWidgetLogic.isAccessGranted(.fullAccess),
            "full access renders the reminder")
        #expect(!NextThingWidgetLogic.isAccessGranted(.denied))
        #expect(!NextThingWidgetLogic.isAccessGranted(.restricted))
        #expect(!NextThingWidgetLogic.isAccessGranted(.notDetermined))
    }

    // MARK: Private

    /// Fresh suite per call, so no cross-test/cross-run persistence leaks.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "NextThingWidgetLogicTests.\(UUID().uuidString)")!
    }
}

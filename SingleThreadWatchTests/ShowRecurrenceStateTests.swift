import Foundation
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

/// Covers the watch "show recurrence" holder: default-on when unset, true/false
/// round-trip, and persistence into `UserDefaults.standard` (where the holder
/// writes). Serialized because every test writes the same real key.
@MainActor
@Suite(.serialized)
struct ShowRecurrenceStateTests {
    // MARK: Internal

    @Test
    func unsetKeyDefaultsToOn() {
        defer { clearKey() }
        UserDefaults.standard.removeObject(forKey: Self.key)
        #expect(
            ShowRecurrenceState().isEnabled,
            "no persisted value means the show-recurrence default-on")
    }

    @Test
    func persistedValueStaysOnInit() {
        defer { clearKey() }
        UserDefaults.standard.set(false, forKey: Self.key)
        #expect(
            !ShowRecurrenceState().isEnabled,
            "an explicitly toggled-off value overrides the default")
    }

    @Test
    func applyRoundTripsTrueAndFalse() {
        defer { clearKey() }
        let state = ShowRecurrenceState()
        state.apply(true)
        #expect(state.isEnabled, "apply republishes true through the state")
        state.apply(false)
        #expect(!state.isEnabled, "apply republishes false through the state")
    }

    @Test
    func applyPersistsToStandardDefaults() {
        defer { clearKey() }
        ShowRecurrenceState().apply(true)
        #expect(
            UserDefaults.standard.bool(forKey: Self.key),
            "apply persists into UserDefaults.standard, where the holder reads")
    }

    // MARK: Private

    private static let key = BoolPreferenceKey.showRecurrence.rawValue

    private func clearKey() {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

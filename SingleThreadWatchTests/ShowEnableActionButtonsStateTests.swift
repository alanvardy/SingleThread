import Foundation
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

/// Covers the watch-side "enable action buttons" state holder: default-on when
/// unset, true/false round-trip, and serialization into `AppGroup.defaults`
/// (falling back to `.standard` where the group is unavailable) so the state
/// survives relaunch and matches where the sync pipeline persists. Serialized
/// because every test writes the same real UserDefaults key.
@MainActor
@Suite(.serialized)
struct ShowEnableActionButtonsStateTests {
    // MARK: Internal

    @Test
    func unsetKeyDefaultsToOn() {
        defer { clearKey() }
        AppGroup.defaults.removeObject(forKey: Self.key)
        let state = ShowEnableActionButtonsState()
        #expect(state.isEnabled, "no persisted value means the new default-on")
    }

    @Test
    func persistedOffStaysOff() {
        defer { clearKey() }
        AppGroup.defaults.set(false, forKey: Self.key)
        #expect(
            !ShowEnableActionButtonsState().isEnabled,
            "an explicitly toggled-off value overrides the default")
    }

    @Test
    func applyRoundTripsTrueAndFalse() {
        defer { clearKey() }
        let state = ShowEnableActionButtonsState()
        state.apply(true)
        #expect(state.isEnabled, "apply republishes true through the state")
        state.apply(false)
        #expect(!state.isEnabled, "apply republishes false through the state")
    }

    @Test
    func applyPersistsToAppGroupDefaults() {
        defer { clearKey() }
        let state = ShowEnableActionButtonsState()
        state.apply(true)
        #expect(
            AppGroup.defaults.bool(forKey: Self.key),
            "apply persists into the App Group suite the sync pipeline uses")
    }

    @Test
    func initReadsPersistedValue() {
        defer { clearKey() }
        AppGroup.defaults.set(true, forKey: Self.key)
        #expect(
            ShowEnableActionButtonsState().isEnabled,
            "initial value comes from the persisted store")
    }

    // MARK: Private

    private static let key = "enableActionButtons"

    /// The state holder writes the App Group suite; `.standard` is cleaned too
    /// because AppGroup falls back to it where the group is unavailable.
    private func clearKey() {
        AppGroup.defaults.removeObject(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

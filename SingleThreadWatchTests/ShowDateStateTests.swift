import Foundation
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

/// Covers the watch "show due date" holder: default-on when unset, true/false
/// round-trip, and persistence into `UserDefaults.standard` (where the holder
/// writes). Serialized because every test writes the same real key.
@MainActor
@Suite(.serialized)
struct ShowDateStateTests {
    // MARK: Internal

    @Test
    func unsetKeyDefaultsToOn() {
        defer { clearKey() }
        UserDefaults.standard.removeObject(forKey: Self.key)
        #expect(
            ShowDateState().isEnabled,
            "no persisted value means the show-date default-on")
    }

    @Test
    func persistedValueStaysOnInit() {
        defer { clearKey() }
        UserDefaults.standard.set(false, forKey: Self.key)
        #expect(
            !ShowDateState().isEnabled,
            "an explicitly toggled-off value overrides the default")
    }

    @Test
    func applyRoundTripsTrueAndFalse() {
        defer { clearKey() }
        let state = ShowDateState()
        state.apply(true)
        #expect(state.isEnabled, "apply republishes true through the state")
        state.apply(false)
        #expect(!state.isEnabled, "apply republishes false through the state")
    }

    @Test
    func applyPersistsToStandardDefaults() {
        defer { clearKey() }
        ShowDateState().apply(true)
        #expect(
            UserDefaults.standard.bool(forKey: Self.key),
            "apply persists into UserDefaults.standard, where the holder reads")
    }

    // MARK: Private

    private static let key = BoolPreferenceKey.showDate.rawValue

    private func clearKey() {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

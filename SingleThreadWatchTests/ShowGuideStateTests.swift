import Foundation
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

/// Covers ShowGuidePreference read/write/round-trip semantics.
/// Serialized because every test writes the real "showGuide" key via
/// `.standard`; running in parallel would race cleanup vs reads.
@MainActor
@Suite(.serialized)
struct ShowGuidePreferenceTests {
    @Test
    func isEnabledReturnsTrueWhenKeyMissing() {
        // Clean start — key absent
        UserDefaults.standard.removeObject(forKey: "showGuide")
        let pref = ShowGuidePreference(defaults: .standard)
        #expect(pref.isEnabled)
    }

    @Test
    func isEnabledReturnsFalseAfterSetFalse() {
        let pref = ShowGuidePreference(defaults: .standard)
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        pref.set(false)
        #expect(!pref.isEnabled)
    }

    @Test
    func isEnabledReturnsTrueAfterSetTrue() {
        let pref = ShowGuidePreference(defaults: .standard)
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        pref.set(false)
        pref.set(true)
        #expect(pref.isEnabled)
    }

    @Test
    func roundTripSurvivesNewInstance() {
        let prefA = ShowGuidePreference(defaults: .standard)
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        prefA.set(false)
        let prefB = ShowGuidePreference(defaults: .standard)
        #expect(!prefB.isEnabled)
    }
}

/// Covers the ShowGuideState holder semantics. Same serialization rationale as
/// the preference suite: it reads/writes the real "showGuide" key via `.standard`.
@MainActor
@Suite(.serialized)
struct ShowGuideStateTests {
    @Test
    func initReadsSeededFalse() {
        UserDefaults.standard.set(false, forKey: "showGuide")
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        let state = ShowGuideState()
        #expect(!state.isEnabled)
    }

    @Test
    func applyPersistsToStandardDefaults() {
        let state = ShowGuideState()
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        state.apply(false)
        #expect(!ShowGuidePreference(defaults: .standard).isEnabled)
    }

    @Test
    func applyRepublishes() {
        let state = ShowGuideState()
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        #expect(state.isEnabled) // default
        state.apply(false)
        #expect(!state.isEnabled)
        state.apply(true)
        #expect(state.isEnabled)
    }
}

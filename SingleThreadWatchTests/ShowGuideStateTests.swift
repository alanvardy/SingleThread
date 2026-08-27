import Foundation
import SingleThreadCore
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

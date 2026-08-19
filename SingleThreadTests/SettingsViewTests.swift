@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - Settings View Tests

@MainActor
struct SettingsViewTests {
    @Test
    func settingsViewContainsAllPreferenceRows() {
        #if os(iOS)
            let view = SettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                allowsLandscape: .constant(true),
                showMicrophoneButton: .constant(true),
                showUndatedReminders: .constant(false),
                excludedProjects: .constant([]),
                availableProjects: ["Work", "Personal"],
                sortOption: .constant(.priority))
        #else
            let view = SettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                showUndatedReminders: .constant(false),
                excludedProjects: .constant([]),
                availableProjects: ["Work", "Personal"],
                sortOption: .constant(.priority))
        #endif

        let bodyDescription = String(describing: view.body)

        // `Form` content (unlike `.sheet` content) is reflected in the
        // body description, so the row labels below are assertable.
        #expect(bodyDescription.contains("Appearance"))
        #expect(bodyDescription.contains("Text Size"))
        #expect(bodyDescription.contains("Sort By"))
        #expect(bodyDescription.contains("Microphone"))
        #expect(bodyDescription.contains("Show Undated"))
        #expect(bodyDescription.contains("Excluded Projects"))
        #expect(bodyDescription.contains("Done"))
        #if os(iOS)
            #expect(bodyDescription.contains("Landscape"))
        #endif
    }
}
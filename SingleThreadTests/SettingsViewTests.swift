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
                enableActionButtons: .constant(true),
                showMicrophoneButton: .constant(true),
                backgroundEnabled: .constant(true),
                backgroundFadePercent: .constant(50),
                backgroundPhotographer: "NEOM",
                showUndatedReminders: .constant(false),
                excludedProjects: .constant([]),
                availableProjects: ["Work", "Personal"],
                sortOption: .constant(.priority),
                showDate: .constant(true),
                showList: .constant(true))
        #else
            let view = SettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                backgroundEnabled: .constant(true),
                backgroundFadePercent: .constant(50),
                backgroundPhotographer: "NEOM",
                showUndatedReminders: .constant(false),
                excludedProjects: .constant([]),
                availableProjects: ["Work", "Personal"],
                sortOption: .constant(.priority),
                showDate: .constant(true),
                showList: .constant(true))
        #endif

        let bodyDescription = String(describing: view.body)

        // `Form` content (unlike `.sheet` content) is reflected in the
        // body description, so the row labels below are assertable.
        #expect(bodyDescription.contains("Appearance"))
        #expect(bodyDescription.contains("Text Size"))
        #expect(bodyDescription.contains("Sort By"))
        #expect(bodyDescription.contains("Microphone"))
        #expect(bodyDescription.contains("Background"))
        #expect(bodyDescription.contains("Background Fade"))
        #expect(bodyDescription.contains("Unsplash"))
        #expect(bodyDescription.contains("Show Undated"))
        #expect(bodyDescription.contains("Show Date"))
        #expect(bodyDescription.contains("Show list"))
        #expect(bodyDescription.contains("Excluded Projects"))
        #expect(bodyDescription.contains("Done"))
        #if os(iOS)
            #expect(bodyDescription.contains("Landscape"))
            #expect(bodyDescription.contains("Enable action buttons"))
        #endif
    }
}

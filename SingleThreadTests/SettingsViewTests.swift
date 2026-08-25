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
                excludedLists: .constant([]),
                availableLists: ["Work", "Personal"],
                sortOption: .constant(.priority),
                showDate: .constant(true),
                showList: .constant(true),
                showRecurrence: .constant(true),
                showAlarms: .constant(true))
        #else
            let view = SettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                backgroundEnabled: .constant(true),
                backgroundFadePercent: .constant(50),
                backgroundPhotographer: "NEOM",
                showUndatedReminders: .constant(false),
                excludedLists: .constant([]),
                availableLists: ["Work", "Personal"],
                sortOption: .constant(.priority),
                showDate: .constant(true),
                showList: .constant(true),
                showRecurrence: .constant(true),
                showAlarms: .constant(true))
        #endif

        let bodyDescription = String(describing: view.body)

        // `Form` content (unlike `.sheet` content) is reflected in the
        // body description, so the row labels below are assertable.
        let commonLabels = [
            "Appearance", "Text Size", "Sort By", "Show microphone", "Background",
            "Background Fade", "Unsplash", "Show undated reminders", "Show date",
            "Show list", "Recurrence indicator", "Reminder alerts", "Excluded Lists",
            "Done"
        ]
        #if os(iOS)
            let expectedLabels = commonLabels + ["Allow landscape", "Show action buttons"]
        #else
            let expectedLabels = commonLabels
        #endif
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }
    }
}

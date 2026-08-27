@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - Settings View Tests

@MainActor
struct SettingsViewTests {
    // MARK: Internal

    @Test
    func settingsViewContainsNavigationLinkLabels() {
        let view = SettingsView(
            bindings: SettingsBindings(),
            backgroundPhotographer: nil,
            backgroundPhotographerURL: nil,
            availableLists: [],
            excludedLists: .constant([]))
        let bodyDescription = String(describing: view.body)

        let expectedLabels = [
            "Interface", "Reminder", "Filtering & Sorting", "Background", "Privacy"
        ]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }
        #expect(bodyDescription.contains("Done"))
    }

    @Test
    func interfaceSettingsViewContainsExpectedRows() {
        #if os(iOS)
            let view = InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                allowsLandscape: .constant(true),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                viewModel: SettingsViewModel())
        #else
            let view = InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                viewModel: SettingsViewModel())
        #endif
        let bodyDescription = String(describing: view.body)

        var expectedLabels = [
            "Appearance", "Text Size", "Show microphone"
        ]
        #if os(iOS)
            expectedLabels += ["Allow landscape", "Show action buttons"]
        #endif
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }
    }

    @Test
    func reminderSettingsViewContainsExpectedRows() {
        let view = ReminderSettingsView(
            showDate: .constant(true),
            showList: .constant(false),
            showRecurrence: .constant(true),
            showAlarms: .constant(true),
            viewModel: SettingsViewModel())
        let bodyDescription = String(describing: view.body)

        let expectedLabels = [
            "Show date", "Show list", "Recurrence indicator", "Reminder alerts"
        ]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }
    }

    @Test
    func filterSortSettingsViewContainsExpectedRows() {
        let view = FilterSortSettingsView(
            sortOption: .constant(.priority),
            showUndatedReminders: .constant(false),
            availableLists: ["Work"],
            excludedLists: .constant([]))
        let bodyDescription = String(describing: view.body)

        let expectedLabels = [
            "Sort By", "Show undated reminders", "Excluded Lists"
        ]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }
    }

    @Test
    func backgroundSettingsViewContainsExpectedRows() {
        let view = BackgroundSettingsView(
            backgroundEnabled: .constant(true),
            backgroundFadePercent: .constant(50),
            backgroundPhotographer: "NEOM",
            backgroundPhotographerURL: Self.sampleURL)
        let bodyDescription = String(describing: view.body)

        let expectedLabels = ["Background", "Background Fade", "Unsplash"]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }
    }

    @Test
    func privacySettingsViewContainsExpectedContent() {
        let view = PrivacySettingsView()
        let bodyDescription = String(describing: view.body)

        let expected = [
            "Privacy",
            "Reminders",
            "Display & Sync Preferences",
            "Skipped & Excluded Lists",
            "Background Image",
            "vardy.cc/unsplash",
            "no analytics"
        ]
        for label in expected {
            #expect(bodyDescription.contains(label), "Expected privacy content to contain \(label)")
        }
    }

    // MARK: Private

    private static let sampleURL = URL(string: "https://unsplash.com/@neom")
}

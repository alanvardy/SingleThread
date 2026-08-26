@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - Settings View Tests

@MainActor
struct SettingsViewTests {
    // MARK: Internal

    @Test
    func interfaceSettingsViewContainsExpectedRows() {
        let view = InterfaceSettingsView(
            bindings: SettingsBindings(),
            viewModel: SettingsViewModel())
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
            bindings: SettingsBindings(),
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
            bindings: SettingsBindings(),
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
            bindings: SettingsBindings(),
            backgroundPhotographer: "NEOM",
            backgroundPhotographerURL: Self.sampleURL)
        let bodyDescription = String(describing: view.body)

        let expectedLabels = ["Background", "Background Fade", "Unsplash"]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }
    }

    // MARK: Private

    private static let sampleURL = URL(string: "https://unsplash.com/@neom")
}

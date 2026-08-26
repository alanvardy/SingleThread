@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - Settings View Tests

@MainActor
struct SettingsViewTests {
    // MARK: Internal

    @Test
    func settingsViewContainsAllPreferenceRows() {
        let view = settingsView()
        let bodyDescription = String(describing: view.body)

        // The root SettingsView now hosts only the group NavigationLinks plus
        // transitional inline rows that Phase 4 removes. Each preference group
        // is covered by its own focused sub-view test below; here we check the
        // Background group that remains inline through the transition.
        let commonLabels = ["Background", "Background Fade", "Unsplash", "Done"]
        for label in commonLabels {
            #expect(bodyDescription.contains(label))
        }
    }

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

    // MARK: Private

    private static let sampleURL = URL(string: "https://unsplash.com/@neom")

    private func settingsView() -> SettingsView {
        SettingsView(
            bindings: SettingsBindings(),
            backgroundPhotographer: "NEOM",
            backgroundPhotographerURL: Self.sampleURL,
            availableLists: ["Work", "Personal"],
            excludedLists: .constant([]))
    }
}

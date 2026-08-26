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

        // `Form` content (unlike `.sheet` content) is reflected in the
        // body description, so the row labels below are assertable.
        // Interface labels (Appearance, Text Size, Show microphone) moved to
        // InterfaceSettingsView and are covered by the dedicated focused test.
        let commonLabels = [
            "Sort By", "Background", "Background Fade", "Unsplash",
            "Show undated reminders", "Show date", "Show list",
            "Recurrence indicator", "Reminder alerts", "Excluded Lists", "Done"
        ]
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

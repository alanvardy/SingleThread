@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - Settings View Tests

@MainActor
struct SettingsViewTests {
    // MARK: Internal

    @Test
    func settingsBindingsCarriesShowCompletionGlow() {
        let bag = SettingsBindings()
        #expect(bag.showCompletionGlow) // default enabled
        let off = SettingsBindings(showCompletionGlow: false)
        #expect(!off.showCompletionGlow) // explicit false round-trips
    }

    @Test
    func settingsViewContainsNavigationLinkLabels() {
        let view = SettingsView(
            bindings: SettingsBindings(),
            backgroundImage: BackgroundImageStore(),
            availableLists: [],
            excludedLists: .constant([]))
        let bodyDescription = String(describing: view.body)

        let expectedLabels = [
            "Interface", "Reminder", "Filtering & Sorting", "Background", "Privacy", "About"
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
            showCompletionGlow: .constant(true),
            viewModel: SettingsViewModel())
        let bodyDescription = String(describing: view.body)

        let expectedLabels = [
            "Show date", "Show list", "Recurrence indicator", "Reminder alerts", "Completion glow"
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
    func backgroundSettingsViewContainsExpectedRows() async {
        let store = await makeSeededStore()
        let view = BackgroundSettingsView(
            backgroundEnabled: .constant(true),
            backgroundFadePercent: .constant(50),
            backgroundImage: store)
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
            "vardy.cc",
            "no analytics"
        ]
        for label in expected {
            #expect(bodyDescription.contains(label), "Expected privacy content to contain \(label)")
        }
    }

    // MARK: Private

    /// Builds a store whose fetch pipeline has already populated a photo and
    /// its attribution, so the background footer renders the Unsplash credit.
    private func makeSeededStore() async -> BackgroundImageStore {
        let fetcher = SeededFetcher()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = BackgroundImageStore(client: fetcher, directory: directory)
        await store.refreshIfNeeded()
        return store
    }
}

/// Serves the store's endpoint payload and photo so tests can seed a populated
/// store without touching the network.
private final class SeededFetcher: BackgroundImageFetching, @unchecked Sendable {
    // MARK: Internal

    func fetchData(from url: URL) async throws -> Data {
        if url == Self.endpoint {
            let json = "{\"url\":\"\(Self.imageURL.absoluteString)\",\"photographer\":\"NEOM\","
                + "\"photographer_url\":\"https://unsplash.com/@neom\"}"
            return Data(json.utf8)
        }
        return BackgroundTestFixtures.jpegData
    }

    // MARK: Private

    private static let endpoint = URL(string: "https://vardy.cc/unsplash")!
    private static let imageURL = URL(string: "https://images.unsplash.com/photo-1.jpg")!
}

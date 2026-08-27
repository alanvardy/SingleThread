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
            "vardy.cc/unsplash",
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
    private static let endpoint = URL(string: "https://vardy.cc/unsplash")!
    private static let imageURL = URL(string: "https://images.unsplash.com/photo-1.jpg")!

    func fetchData(from url: URL) async throws -> Data {
        if url == Self.endpoint {
            let json = "{\"url\":\"\(Self.imageURL.absoluteString)\",\"photographer\":\"NEOM\","
                + "\"photographer_url\":\"https://unsplash.com/@neom\"}"
            return Data(json.utf8)
        }
        return Self.jpegData
    }

    /// Smallest valid JPEG (1x1), matching the store's decodability gate.
    private static let jpegData = Data(
        base64Encoded: "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEA"
            + "AKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAA"
            + "ABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAQABAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkK"
            + "C//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYn"
            + "KCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqy"
            + "s7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAAB"
            + "AgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoW"
            + "JDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZ"
            + "mqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwIC"
            + "AwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQE"
            + "BxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQAC"
            + "EQMRAD8A+L6KKK/lM/38P//Z")!
}

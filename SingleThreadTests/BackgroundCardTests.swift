import EventKit
@testable import SingleThread
import SingleThreadCore
import Speech
import SwiftUI
import Testing

#if os(iOS)

    // MARK: - Fake transcriber for background-card tests

    @MainActor
    private final class BackgroundCardFakeTranscriber: SpeechTranscribing {
        // MARK: Lifecycle

        init(authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized) {
            self.authorizationStatus = authorizationStatus
        }

        // MARK: Internal

        private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus

        func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
            authorizationStatus
        }

        func transcribe(
            onPartialResult _: @escaping @MainActor (String) -> Void) async throws -> String {
            ""
        }
    }

    // MARK: - Background Card Tests

    /// Whether the reminder card renders see-through over the photo is decided by
    /// `ContentViewModel.backgroundDisplayed`; the visual result itself (transparent
    /// row chrome, text plate color) can't be distinguished through reflected body
    /// descriptions (`_ConditionalContent` names include both branches), so these
    /// tests verify the gate decision directly — same rationale as
    /// `ActionButtonTests`. The rendered look is verified manually / in review.
    @MainActor
    @Suite(.serialized)
    struct BackgroundCardTests {
        // MARK: Internal

        // MARK: Tests

        @Test
        func displayedWhenToggleOnAndPhotoStored() async throws {
            #expect(try await gate(toggleOn: true, withPhoto: true))
        }

        @Test
        func hiddenWhenToggleOff() async throws {
            let displayed = try await gate(toggleOn: false, withPhoto: true)
            #expect(!displayed)
        }

        @Test
        func hiddenWhenNoPhotoStored() async throws {
            let displayed = try await gate(toggleOn: true, withPhoto: false)
            #expect(!displayed)
        }

        /// Regression test for VAR-703: toggling "Show date" in Settings re-evaluates
        /// `SingleThreadApp.body` which re-creates `ContentView`. If `BackgroundImageStore`
        /// isn't owned in the App (like `ReminderStore` is), a fresh default instance with
        /// `nil` imageData replaces the loaded one and the background disappears.
        @Test
        func backgroundSurvivesViewModelConstruction() async throws {
            let key = "backgroundEnabled"
            UserDefaults.standard.set(true, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let seeded = try seededBackgroundImage()
            await seeded.refreshIfNeeded(maxAge: 3600)
            #expect(seeded.imageData != nil, "seeded store should load")

            // A ContentViewModel constructed with the same (loaded) BackgroundImageStore
            // must still report the background as displayed — this is what happens when
            // the App (which owns the store) builds a fresh view model around it.
            let viewModel = makeViewModel(backgroundImage: seeded)
            #expect(viewModel.backgroundDisplayed, "Background should survive view-model construction")
        }

        // MARK: Private

        /// Smallest valid JPEG (1×1 pixel), passes the store's decodability gate.
        private static let jpegData = Data(
            base64Encoded: "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAA"
                + "ABAAEAAKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAA"
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

        // MARK: Helpers

        private func makeViewModel(backgroundImage: BackgroundImageStore) -> ContentViewModel {
            ContentViewModel(
                store: storeWithReminder(),
                backgroundImage: backgroundImage,
                speechTranscriber: BackgroundCardFakeTranscriber())
        }

        /// Sets up the toggle + photo state, builds the view model, reads the gate once,
        /// THEN removes the toggle key — reading after cleanup would see the
        /// `@AppStorage` default (true), not the value under test.
        private func gate(toggleOn: Bool, withPhoto: Bool) async throws -> Bool {
            let key = "backgroundEnabled"
            UserDefaults.standard.set(toggleOn, forKey: key)

            let backgroundImage: BackgroundImageStore
            if withPhoto {
                backgroundImage = try seededBackgroundImage()
                // Loads the stored bytes into observable state; the fresh sidecar
                // means this never touches the network.
                await backgroundImage.refreshIfNeeded(maxAge: 3600)
                #expect(backgroundImage.imageData != nil, "seeded store should load")
            } else {
                backgroundImage = BackgroundImageStore(
                    directory: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString))
            }
            let viewModel = makeViewModel(backgroundImage: backgroundImage)
            let result = viewModel.backgroundDisplayed
            UserDefaults.standard.removeObject(forKey: key)
            return result
        }

        /// A store whose Application-Support-like directory already holds a valid
        /// photo + freshly-fetched sidecar, i.e. what a successful fetch leaves on disk.
        private func seededBackgroundImage() throws -> BackgroundImageStore {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = BackgroundImageStore(directory: directory)
            try Self.jpegData.write(to: store.imageURL)
            let fetchedAt = ISO8601DateFormatter().string(from: Date())
            let metadata = #"{"photographer":"NEOM","fetchedAt":"\#(fetchedAt)"}"#
            try Data(metadata.utf8).write(to: store.metadataURL, options: .atomic)
            return store
        }

        /// Construction only — never saved through EventKit.
        private func storeWithReminder() -> ReminderStore {
            let eventStore = EKEventStore()
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = "Buy groceries"
            return ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
        }
    }
#endif

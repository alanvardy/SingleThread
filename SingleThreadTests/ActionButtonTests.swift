import EventKit
@testable import SingleThread
import SingleThreadCore
import Speech
import SwiftUI
import Testing

#if os(iOS)

    import UIKit

    // MARK: - Action Button Tests

    /// The cluster is a runtime `_ConditionalContent` branch, so `String(describing:
    /// view.body)` cannot distinguish it (both branches appear in the reflected type
    /// names and SwiftUI never reflects accessibility labels). These tests therefore
    /// verify the gate decision (`ContentViewModel.showsActionButtons`) directly — the
    /// seam exists exactly for this — while the rendered cluster is exercised by the
    /// UI tests (`ActionButtonsUITests` in Phase 3).
    @MainActor
    struct ActionButtonTests {
        // MARK: Internal

        // MARK: Tests

        @Test
        func buttonsShowWhenToggleOnAndReminderVisible() {
            let key = "enableActionButtons"
            UserDefaults.standard.set(true, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let viewModel = makeViewModel(store: storeWithReminder())
            #expect(viewModel.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenToggleOff() {
            let key = "enableActionButtons"
            UserDefaults.standard.set(false, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let viewModel = makeViewModel(store: storeWithReminder())
            #expect(!viewModel.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenNoVisibleReminder() {
            // Toggle on, but an empty store -> no visible reminder -> plain mic.
            let key = "enableActionButtons"
            UserDefaults.standard.set(true, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            let viewModel = makeViewModel(store: store)
            #expect(!viewModel.showsActionButtons)
        }

        @Test
        func accentColorsUsedWhenNoBackgroundDisplayed() {
            // Toggle off -> no photo layer -> accent glyphs (green/orange).
            let key = "backgroundEnabled"
            UserDefaults.standard.set(false, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let viewModel = makeViewModel(store: storeWithReminder())
            #expect(viewModel.actionButtonsUseAccentColors)
        }

        @Test
        func neutralGlyphWhenBackgroundDisplayed() async throws {
            // Toggle on + a valid stored photo -> accent colors suppressed so the
            // neutral scheme-adaptive glyph stays legible over the photo.
            let key = "backgroundEnabled"
            UserDefaults.standard.set(true, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let backgroundImage = try seededBackgroundImage()
            await backgroundImage.refreshIfNeeded(maxAge: 3600)
            #expect(backgroundImage.imageData != nil)

            let viewModel = makeViewModel(store: storeWithReminder(), backgroundImage: backgroundImage)
            #expect(viewModel.backgroundDisplayed)
            #expect(!viewModel.actionButtonsUseAccentColors)
        }

        @Test
        func buttonsHiddenWhenAllSkipped() {
            // Toggle on, but every reminder skipped -> visibleReminders empty.
            let key = "enableActionButtons"
            UserDefaults.standard.set(true, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            // Construction only — never saved through EventKit.
            let eventStore = EKEventStore()
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = "Buy groceries"
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [reminder.calendarItemIdentifier],
                authorizationStatus: .fullAccess)
            let viewModel = makeViewModel(store: store)
            #expect(!viewModel.showsActionButtons)
        }

        // MARK: Private

        /// Smallest valid 1×1 PNG, passes the store's decodability gate.
        private static func makePNGData() throws -> Data {
            let size = CGSize(width: 1, height: 1)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { context in
                UIColor.systemGreen.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            guard let data = image.pngData() else {
                throw URLError(.cannotDecodeContentData)
            }
            return data
        }

        // MARK: Helpers

        private func makeViewModel(
            store: ReminderStore,
            backgroundImage: BackgroundImageStore = BackgroundImageStore()) -> ContentViewModel {
            ContentViewModel(
                store: store,
                backgroundImage: backgroundImage,
                speechTranscriber: ActionButtonFakeTranscriber())
        }

        /// A store whose Application-Support-like directory already holds a valid
        /// photo + freshly-fetched sidecar, i.e. what a successful fetch leaves on disk.
        private func seededBackgroundImage() throws -> BackgroundImageStore {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = BackgroundImageStore(directory: directory)
            try Self.makePNGData().write(to: store.imageURL)
            let fetchedAt = ISO8601DateFormatter().string(from: Date())
            let metadata = #"{"photographer":"Test","fetchedAt":"\#(fetchedAt)"}"#
            try Data(metadata.utf8).write(to: store.metadataURL, options: .atomic)
            return store
        }

        /// A prepopulated store with one visible reminder; never touches EventKit.
        /// Construction only — never saved through EventKit.
        private func storeWithReminder() -> ReminderStore {
            let eventStore = EKEventStore()
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = "Buy groceries"
            reminder.priority = 5
            return ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
        }
    }

    // MARK: - Fake transcriber

    /// Pattern copied from `MicrophoneToggleTests`; that file's fake transcriber is
    /// private to its own source file, so it is not reusable here.
    @MainActor
    private final class ActionButtonFakeTranscriber: SpeechTranscribing {
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
#endif

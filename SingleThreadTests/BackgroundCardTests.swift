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

    /// Whether the reminder card's row chrome is see-through is decided by
    /// `ContentViewModel.rowChromeBackground`; the visual result itself (transparent
    /// row chrome, text plate color) can't be distinguished through reflected body
    /// descriptions (`_ConditionalContent` names include both branches), so these
    /// tests verify the seam decision directly — same rationale as
    /// `ActionButtonTests`. The rendered look is verified manually / in review.
    @MainActor
    @Suite(.serialized)
    struct BackgroundCardTests {
        // MARK: Internal

        // MARK: Tests

        /// Regression guard for the row-background seam: the row chrome is always
        /// clear so the photo (or `systemBackground`) shows through on every device.
        @Test
        func rowBackgroundClearWithPhotoStored() async throws {
            let viewModel = try await makeViewModel(toggleOn: true, withPhoto: true)
            #expect(viewModel.rowChromeBackground == Color.clear)
        }

        /// Sad path: row chrome stays clear with no photo and the gate closed — the exact
        /// state that previously fell back to the opaque system row default on iPad.
        @Test
        func rowBackgroundClearWithoutPhoto() async throws {
            let viewModel = try await makeViewModel(toggleOn: false, withPhoto: false)
            #expect(viewModel.rowChromeBackground == Color.clear)
        }

        /// The card plate behind the text is off-white in light mode so the text stays
        /// readable over the wallpaper. The rendered paint can't be asserted headlessly,
        /// so the decision is asserted directly.
        @Test
        func plateFillOffWhiteInLightMode() {
            let fill = ReminderCardView.plateFill(for: .light)
            #expect(fill == Color(red: 0.96, green: 0.95, blue: 0.94))
        }

        /// The card plate is black in dark mode for contrast.
        @Test
        func plateFillBlackInDarkMode() {
            #expect(ReminderCardView.plateFill(for: .dark) == Color.black)
        }

        /// The empty-state plate's corner radius must match the card plate (10pt)
        /// so they share visual rhythm. The rendered shape can't be asserted
        /// headlessly — tests assert this decision instead.
        @Test
        func emptyStateCornerRadiusMatchesCardPlate() {
            #expect(ReminderCardView.emptyStateCornerRadius == 10)
        }

        // MARK: Private

        // MARK: Helpers

        private func makeViewModel(backgroundImage: BackgroundImageStore) -> ContentViewModel {
            ContentViewModel(
                store: storeWithReminder(),
                backgroundImage: backgroundImage,
                speechTranscriber: BackgroundCardFakeTranscriber())
        }

        /// Sets up the toggle + photo state, builds the view model (the row seam is
        /// always clear regardless of state), then removes the toggle key again.
        private func makeViewModel(toggleOn: Bool, withPhoto: Bool) async throws -> ContentViewModel {
            let key = "backgroundEnabled"
            UserDefaults.standard.set(toggleOn, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let backgroundImage: BackgroundImageStore
            if withPhoto {
                backgroundImage = try seededBackgroundImage()
                await backgroundImage.refreshIfNeeded(maxAge: 3600)
                #expect(backgroundImage.imageData != nil, "seeded store should load")
            } else {
                backgroundImage = BackgroundImageStore(
                    directory: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString))
            }
            return makeViewModel(backgroundImage: backgroundImage)
        }

        /// A store whose Application-Support-like directory already holds a valid
        /// photo + freshly-fetched sidecar, i.e. what a successful fetch leaves on disk.
        private func seededBackgroundImage() throws -> BackgroundImageStore {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = BackgroundImageStore(directory: directory)
            try BackgroundTestFixtures.jpegData.write(to: store.imageURL)
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

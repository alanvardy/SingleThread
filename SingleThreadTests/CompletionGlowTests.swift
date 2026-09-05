import EventKit
@testable import SingleThread
import SingleThreadCore
import Speech
import SwiftUI
import Testing

// MARK: - CompletionGlow state machine

/// Serialized so these small timing-sensitive tests never interleave with
/// each other on the main actor (mirrors `ReminderStoreTests`).
@MainActor
@Suite(.serialized)
struct CompletionGlowTests {
    @Test
    func glowStateMachine() {
        let glow = CompletionGlow()
        #expect(!glow.isActive, "glow starts inactive")
        glow.trigger()
        #expect(glow.isActive, "trigger sets the glow active")
        glow.trigger()
        #expect(glow.isActive, "a second trigger must not synchronously clear the glow")
    }

    @Test
    func glowAutoDismissesAfterDuration() async {
        let glow = CompletionGlow()
        glow.duration = 0.05
        glow.trigger()
        #expect(glow.isActive)

        // Poll for up to ~2s for the glow to clear. Polling is robust against
        // slow executors: we wait for the invariant rather than asserting at a
        // fixed wall-clock deadline.
        for _ in 0 ..< 100 {
            if !glow.isActive {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(!glow.isActive)
    }
}

// MARK: - ContentViewModel wiring

@MainActor
@Suite(.serialized)
struct CompletionGlowViewModelTests {
    // MARK: Internal

    @Test
    func glowTriggersOnSuccessfulCompletion() async {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Buy groceries"
        let viewModel = makeViewModel(reminders: [reminder])

        await viewModel.completeCurrentReminder()

        // Deterministic: `trigger()` runs synchronously at the end of
        // `completeCurrentReminder()`, before the auto-dismiss task can fire.
        #expect(viewModel.completionGlow.isActive)
    }

    @Test
    func glowStaysInactiveWhenNothingToComplete() async {
        let viewModel = makeViewModel(reminders: [])
        await viewModel.completeCurrentReminder()
        #expect(!viewModel.completionGlow.isActive)
    }

    @Test
    func glowStaysInactiveWhenAllSkipped() async {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Buy groceries"
        let viewModel = makeViewModel(
            reminders: [reminder],
            skippedIDs: [reminder.calendarItemIdentifier])
        await viewModel.completeCurrentReminder()
        #expect(!viewModel.completionGlow.isActive)
    }

    @Test
    func glowStaysInactiveWhenPreferenceDisabled() async {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Buy groceries"
        let disabled = BoolPreferenceStore(
            defaults: .standard, key: "glow-disabled-\(UUID().uuidString)", fallback: true)
        disabled.set(false)
        let viewModel = makeViewModel(reminders: [reminder], showCompletionGlow: disabled)
        await viewModel.completeCurrentReminder()
        #expect(!viewModel.completionGlow.isActive)
    }

    @Test
    func glowTriggersWhenPreferenceEnabled() async {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Buy groceries"
        let enabled = BoolPreferenceStore(defaults: .standard, key: "glow-enabled-\(UUID().uuidString)", fallback: true)
        enabled.set(true)
        let viewModel = makeViewModel(reminders: [reminder], showCompletionGlow: enabled)
        await viewModel.completeCurrentReminder()
        #expect(viewModel.completionGlow.isActive)
    }

    // MARK: Private

    private func makeViewModel(
        reminders: [EKReminder],
        skippedIDs: Set<String> = [],
        showCompletionGlow: BoolPreferenceStore = BoolPreferenceStore(
            key: BoolPreferenceKey.showCompletionGlow.rawValue,
            fallback: true)) -> ContentViewModel {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: .fullAccess)
        return ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: GlowFakeTranscriber(),
            showCompletionGlow: showCompletionGlow)
    }
}

// MARK: - Fake transcriber

/// Keeps `ContentViewModel` construction off the real speech recognizer,
/// mirroring the fake in `ActionButtonTests` (private there, so not reusable).
@MainActor
private final class GlowFakeTranscriber: SpeechTranscribing {
    private(set) var authorizationStatus = SFSpeechRecognizerAuthorizationStatus.authorized

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        authorizationStatus
    }

    func transcribe(
        onPartialResult _: @escaping @MainActor (String) -> Void) async throws -> String {
        ""
    }
}

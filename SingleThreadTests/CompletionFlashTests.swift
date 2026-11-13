import EventKit
@testable import SingleThread
import SingleThreadCore
import Speech
import Testing

// MARK: - CompletionFlash state machine

/// Serialized so these small timing-sensitive tests never interleave with
/// each other on the main actor (mirrors `CompletionGlowTests`).
@MainActor
@Suite(.serialized)
struct CompletionFlashTests {
    @Test
    func flashStateMachine() {
        let flash = CompletionFlash()
        #expect(!flash.isActive, "flash starts inactive")
        flash.trigger()
        #expect(flash.isActive, "trigger sets the flash active")
        flash.trigger()
        #expect(flash.isActive, "a second trigger must not synchronously clear the flash")
    }

    @Test
    func flashAutoDismissesAfterDuration() async {
        let flash = CompletionFlash()
        flash.duration = 0.05
        flash.trigger()
        #expect(flash.isActive)

        // Poll for up to ~2s rather than asserting at a fixed wall-clock
        // deadline, so a slow executor cannot make this flaky.
        for _ in 0 ..< 100 {
            if !flash.isActive {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(!flash.isActive)
    }

    @Test
    func defaultDurationMatchesDictationCheckmark() {
        #expect(CompletionFlash().duration == CreationFeedback.displayDuration)
    }
}

// MARK: - ContentViewModel wiring

@MainActor
@Suite(.serialized)
struct CompletionFlashViewModelTests {
    // MARK: Internal

    @Test
    func flashTriggersOnSuccessfulCompletion() async {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Buy groceries"
        let viewModel = makeViewModel(reminders: [reminder])

        await viewModel.completeCurrentReminder()

        // Deterministic: `trigger()` runs synchronously at the end of
        // `completeCurrentReminder()`, before the auto-dismiss task can fire.
        #expect(viewModel.completionFlash.isActive)
    }

    @Test
    func flashStaysInactiveWhenNothingToComplete() async {
        let viewModel = makeViewModel(reminders: [])
        await viewModel.completeCurrentReminder()
        #expect(!viewModel.completionFlash.isActive)
    }

    // MARK: Private

    private func makeViewModel(reminders: [EKReminder]) -> ContentViewModel {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: reminders,
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        return ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: TestFakeTranscriber())
    }
}

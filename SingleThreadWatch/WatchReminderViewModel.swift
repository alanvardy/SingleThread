import EventKit
import SingleThreadCore
import SwiftUI

/// Holds the watch reminder card's presentation state and its refresh flow,
/// moving the `@State` vars and the inline `refresh()` out of the view.
@MainActor
@Observable
final class WatchReminderViewModel {
    // MARK: Lifecycle

    init(
        store: ReminderStore,
        showDateState: ShowDateState,
        showRecurrenceState: ShowRecurrenceState,
        showAlarmsState: ShowAlarmsState,
        showListState: ShowListState,
        showCompletionGlowState: ShowCompletionGlowState,
        entitlementState: EntitlementState,
        showEnableActionButtonsState: ShowEnableActionButtonsState) {
        self.store = store
        self.showDateState = showDateState
        self.showRecurrenceState = showRecurrenceState
        self.showAlarmsState = showAlarmsState
        self.showListState = showListState
        self.showCompletionGlowState = showCompletionGlowState
        self.entitlementState = entitlementState
        self.showEnableActionButtonsState = showEnableActionButtonsState
        // 6th-skip nudge: surface the in-card banner and track the dialog state.
        store.onSkipNudgeRequested = { [weak self] identifier in
            self?.nudgeIdentifier = identifier
        }
    }

    // MARK: Internal

    let store: ReminderStore
    let showDateState: ShowDateState
    let showRecurrenceState: ShowRecurrenceState
    let showAlarmsState: ShowAlarmsState
    let showListState: ShowListState
    let showCompletionGlowState: ShowCompletionGlowState
    let entitlementState: EntitlementState
    let showEnableActionButtonsState: ShowEnableActionButtonsState

    /// Drives the brief full-screen green flash after a successful completion.
    let completionGlow = CompletionGlow()

    var isRefreshing = false

    /// Identifier of the reminder that just crossed the 6-skip threshold. Drives
    /// the in-card nudge banner; cleared on delete/dismiss/refresh.
    var nudgeIdentifier: String?

    /// Drives the Delete confirmation dialog presented when the nudge banner is
    /// tapped.
    var isShowingNudgeDialog = false

    /// Drives the three-action menu (Skip / Reschedule / Delete) presented from
    /// the Skip button when the action-buttons toggle is synced ON.
    var isShowingActionMenu = false

    /// Drives the Reschedule sheet presented from the action menu.
    var isShowingRescheduleSheet = false

    /// The reschedule date picker's selection (defaults to tomorrow).
    var rescheduleDate = Date().addingTimeInterval(86400)

    /// When `true`, the completion glow is playing out and the card should
    /// stay visible as a "ghost" even though the store is already empty.
    var isShowingCompletionTransition = false

    /// Snapshot of the reminder that was on screen when Complete was tapped.
    /// Rendered during the transition so the card doesn't vanish mid-glow.
    var transitionReminder: EKReminder?

    /// Extra hold time beyond `completionGlow.duration` before the ghost card
    /// is cleared. Test-configurable so unit tests can run near-instantly.
    var completionTransitionBuffer: TimeInterval = 0.5

    func task() async {
        await store.start()
    }

    /// Completes the visible reminder, captures a snapshot for the ghost card,
    /// and triggers the glow. Holds the card visible for the full glow + buffer,
    /// then relinquishes to the normal state branches — the next reminder (if
    /// any) or the empty/done state.
    /// True when `identifier` is the reminder that just crossed the 6-skip
    /// threshold, so the view renders the nudge banner on its card.
    func isNudged(_ identifier: String) -> Bool {
        nudgeIdentifier == identifier
    }

    func completeCurrentReminder() async {
        guard !isShowingCompletionTransition else { return }
        transitionReminder = store.visibleReminders.first
        if await store.completeCurrentReminder(),
           showCompletionGlowState.isEnabled {
            isShowingCompletionTransition = true
            completionGlow.trigger()
            let delay = completionGlow.duration + completionTransitionBuffer
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self else { return }
                // Clear unconditionally: the store already reflects the
                // completion (next reminder or empty), so the normal branches
                // render the correct state once the glow has faded. Gating on
                // `visibleReminders.isEmpty` would keep the ghost card — and its
                // dead buttons — stuck on screen whenever another reminder
                // survived the completion.
                isShowingCompletionTransition = false
                transitionReminder = nil
            }
        } else {
            transitionReminder = nil
        }
    }

    /// A tap on the reminder card refreshes the list directly (no dialog),
    /// pruning skip state without un-skipping a still-visible window. Inherits
    /// `refresh`'s `guard !isRefreshing` re-entrancy absorption — no new state.
    func cardTapped() async {
        await refresh(clearSkipped: store.allSkipped)
    }

    func refresh(clearSkipped: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let startedAt = Date()
        await store.reload(clearSkipped: clearSkipped)
        let remaining = MinimumDisplayDuration.remainingSleep(
            elapsed: Date().timeIntervalSince(startedAt),
            minimum: Self.refreshMinimumDisplayDuration)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        isRefreshing = false
    }

    // MARK: Private

    /// The refresh spinner stays visible for at least this long so brief
    /// EventKit fetches still read as a refresh.
    private static let refreshMinimumDisplayDuration: TimeInterval = 1
}

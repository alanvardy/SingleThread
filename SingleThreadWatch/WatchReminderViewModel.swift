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
        showAlarmsState: ShowAlarmsState) {
        self.store = store
        self.showDateState = showDateState
        self.showRecurrenceState = showRecurrenceState
        self.showAlarmsState = showAlarmsState
    }

    // MARK: Internal

    let store: ReminderStore
    let showDateState: ShowDateState
    let showRecurrenceState: ShowRecurrenceState
    let showAlarmsState: ShowAlarmsState

    var isRefreshing = false
    var isShowingRefreshConfirmation = false

    func task() async {
        await store.start()
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

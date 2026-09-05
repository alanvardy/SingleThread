import EventKit
import SingleThreadCore
import Speech
import SwiftUI

/// Owns the reminder-list screen's presentation logic: determines which
/// empty state to show, whether the background / action-buttons gates are
/// open, and delegates dictation to its child ``DictationViewModel``.
@MainActor
@Observable
final class ContentViewModel {
    // MARK: Lifecycle

    init(
        store: ReminderStore,
        backgroundImage: BackgroundImageStore,
        speechTranscriber: any SpeechTranscribing,
        showCompletionGlow: BoolPreferenceStore = BoolPreferenceStore(
            key: BoolPreferenceKey.showCompletionGlow.rawValue,
            fallback: true),
        urlOpener: (any URLOpening)? = nil) {
        self.store = store
        self.backgroundImage = backgroundImage
        self.showCompletionGlow = showCompletionGlow
        self.urlOpener = urlOpener ?? SystemURLOpener.noop
        dictation = DictationViewModel(speechTranscriber: speechTranscriber, store: store)
        store.onSkipNudgeRequested = { [weak self] identifier in
            self?.nudgeIdentifier = identifier
        }
    }

    // MARK: Internal

    /// Copy + icon describing why the reminder list has nothing to show.
    struct EmptyStateCopy {
        let title: String
        let systemImage: String
        let description: String
    }

    let store: ReminderStore
    let backgroundImage: BackgroundImageStore
    let dictation: DictationViewModel
    let urlOpener: any URLOpening

    /// Identifier of the reminder that just crossed the 6-skip threshold.
    /// Drives the in-card banner. Cleared on act or dismiss. Single owner —
    /// ContentViewModel, not AppViewModel.
    var nudgeIdentifier: String?

    /// Drives the brief full-screen green flash after a successful completion.
    let completionGlow = CompletionGlow()

    /// True while `refreshManual()` is running, so the button can show a
    /// disabled/spinner state and re-entrant taps are dropped. Matches the
    /// watch pattern (`WatchReminderViewModel.isRefreshing`).
    var isRefreshing = false

    #if os(iOS)
        /// Whether the Complete/Skip cluster replaces the plain mic in the bottom
        /// bar: the toggle must be on AND a visible reminder must exist. Readable
        /// outside a live view (unit-test seam); inside the app it reads the live
        /// `@AppStorage` value.
        var showsActionButtons: Bool {
            UserDefaults.standard.bool(forKey: "enableActionButtons")
                && store.visibleReminders.first != nil
        }
    #endif

    /// Row chrome is always clear so the photo (or `systemBackground` when none is
    /// shown) shows through on every device. Extracted because the rendered paint
    /// can't be asserted headlessly — tests assert this decision instead.
    var rowChromeBackground: Color {
        .clear
    }

    /// The last URL recorded by the `--url-opener-spy` UI-test seam, exposed so
    /// the view never needs to know the concrete `URLOpeningSpy` type. Always
    /// nil in production, where the opener is a `SystemURLOpener`.
    var lastOpenedURLForUITesting: String? {
        (urlOpener as? URLOpeningSpy)?.lastOpenedURL?.absoluteString
    }

    static func emptyStateCopy(hasHidden: Bool) -> EmptyStateCopy {
        if hasHidden {
            return EmptyStateCopy(
                title: String(localized: "Nothing due", table: "Localizable", bundle: .main),
                systemImage: "calendar",
                description: String(
                    localized: "Only today's and overdue reminders show here — pull to refresh.",
                    table: "Localizable",
                    bundle: .main))
        }
        return EmptyStateCopy(
            title: SharedStrings.noReminders,
            systemImage: "checklist",
            description: String(
                localized: "You don't have any reminders yet.",
                table: "Localizable",
                bundle: .main))
    }

    static func allDoneStateCopy() -> EmptyStateCopy {
        EmptyStateCopy(
            title: SharedStrings.allDone,
            systemImage: "checkmark.circle",
            description: String(
                localized: "Pull to refresh to see all your reminders again.",
                table: "Localizable",
                bundle: .main))
    }

    // MARK: - Task / onChange reactions

    func task(showUndatedReminders: Bool) async {
        store.showsUndatedReminders = showUndatedReminders
        await store.start()
        await backgroundImage.refreshIfNeeded()
    }

    func handleShowUndatedReminders(_ value: Bool) {
        store.showsUndatedReminders = value
        Task { await store.reload() }
    }

    func handleSortOption(_ option: SortOption) {
        store.setSortOption(option)
    }

    func handleAppearanceMode(_ mode: AppearanceMode) {
        #if os(iOS)
            AppDelegate.applyAppearance(mode)
        #elseif os(macOS)
            MacAppDelegate.applyAppearance(mode)
        #endif
    }

    // MARK: - Store mutation forwarding

    /// Forwards to ``ReminderStore/completeCurrentReminder()`` so the view
    /// never reaches through to the model for mutations. On success, triggers
    /// the completion glow for positive visual feedback.
    func completeCurrentReminder() async {
        if await store.completeCurrentReminder(), showCompletionGlow.isEnabled {
            completionGlow.trigger()
        }
    }

    func skipCurrentReminder() {
        store.skipCurrentReminder()
    }

    func deleteCurrentReminder() async {
        await store.deleteCurrentReminder()
    }

    /// Forwards to ``ReminderStore/undoLastCompletion()``.
    /// No glow trigger — the reappearing reminder is its own feedback.
    func undoLastCompletion() async {
        await store.undoLastCompletion()
    }

    func reload(clearSkipped: Bool = false) async {
        await store.reload(clearSkipped: clearSkipped)
    }

    /// Manual refresh entry point for the macOS button. Guards against re-entrant
    /// taps, toggles `isRefreshing`, and holds the spinner for at least the
    /// minimum display duration so the user sees the feedback.
    func refreshManual() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let startedAt = Date()
        await store.reload(clearSkipped: store.allSkipped)
        let elapsed = Date().timeIntervalSince(startedAt)
        try? await Task.sleep(
            for: .seconds(MinimumDisplayDuration.remainingSleep(elapsed: elapsed, minimum: 1)))
    }

    func setExcludedListTitles(_ titles: Set<String>) {
        store.setExcludedListTitles(titles)
    }

    // MARK: - Deep linking

    /// Opens the given reminder in Apple's Reminders app via the injected
    /// ``urlOpener``. Building the deep link here (rather than in the view) keeps
    /// the URL construction unit-testable. No-op when the reminder has no
    /// identifier.
    func openInReminders(_ reminder: EKReminder) {
        openInReminders(identifier: reminder.calendarItemIdentifier)
    }

    /// Identifier-based deep link, shared with the skip-nudge sheet (which
    /// holds only the nudged identifier, not an `EKReminder`). No-op for an
    /// empty identifier.
    func openInReminders(identifier: String) {
        guard let url = ReminderDeepLink.url(forReminderIdentifier: identifier)
        else { return }
        urlOpener.open(url)
    }

    // MARK: - Skip nudge

    /// True when `identifier`'s card should show the skip-nudge banner.
    func isNudged(_ identifier: String) -> Bool {
        nudgeIdentifier == identifier
    }

    /// Clears the nudge banner (dismiss without acting).
    func dismissNudge() {
        nudgeIdentifier = nil
    }

    /// Deletes the nudged reminder and clears the banner.
    func deleteNudgedReminder() async {
        guard let identifier = nudgeIdentifier else { return }
        await store.deleteReminder(identifier: identifier)
        nudgeIdentifier = nil
    }

    /// Reschedules the nudged reminder to a new due date, clearing the banner on
    /// success. Returns whether the reschedule applied.
    @discardableResult
    func rescheduleNudgedReminder(to due: DateComponents) async -> Bool {
        guard let identifier = nudgeIdentifier else { return false }
        let succeeded = await store.rescheduleReminder(identifier: identifier, to: due)
        if succeeded {
            nudgeIdentifier = nil
        }
        return succeeded
    }

    // MARK: Private

    /// Preference read at trigger time so a settings toggle takes effect
    /// without rebuilding the view model.
    private let showCompletionGlow: BoolPreferenceStore
}

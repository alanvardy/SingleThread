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
        speechTranscriber: any SpeechTranscribing) {
        self.store = store
        self.backgroundImage = backgroundImage
        dictation = DictationViewModel(speechTranscriber: speechTranscriber, store: store)
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

    #if os(iOS)
        /// Whether the Complete/Skip cluster replaces the plain mic in the bottom
        /// bar: the toggle must be on AND a visible reminder must exist. Readable
        /// outside a live view (unit-test seam); inside the app it reads the live
        /// `@AppStorage` value.
        var showsActionButtons: Bool {
            UserDefaults.standard.bool(forKey: "enableActionButtons")
                && store.visibleReminders.first != nil
        }

        /// Whether the Complete/Skip buttons render their accent glyph colors
        /// (green/orange). True only when no background photo is on screen — over
        /// a photo the neutral scheme-adaptive glyph stays legible. Readable
        /// outside a live view (unit-test seam).
        var actionButtonsUseAccentColors: Bool {
            !backgroundDisplayed
        }
    #endif

    /// See-through reminder-card gate: true while a background photo is actually
    /// on screen. Row chrome clears and the card text sits on its own plate.
    var backgroundDisplayed: Bool {
        UserDefaults.standard.bool(forKey: "backgroundEnabled")
            && backgroundImage.imageData != nil
    }

    static func emptyStateCopy(hasHidden: Bool) -> EmptyStateCopy {
        if hasHidden {
            return EmptyStateCopy(
                title: "Nothing due",
                systemImage: "calendar",
                description: "Only today's and overdue reminders show here — pull to refresh.")
        }
        return EmptyStateCopy(
            title: "No Reminders",
            systemImage: "checklist",
            description: "You don't have any reminders yet.")
    }

    static func allDoneStateCopy() -> EmptyStateCopy {
        EmptyStateCopy(
            title: "All Done",
            systemImage: "checkmark.circle",
            description: "Pull to refresh to see all your reminders again.")
    }

    // MARK: - Task / onChange reactions

    func task(showUndatedReminders: Bool) async {
        store.showsUndatedReminders = showUndatedReminders
        await store.start()
        await backgroundImage.refreshIfNeeded(maxAge: 3600)
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
    /// never reaches through to the model for mutations.
    func completeCurrentReminder() async {
        await store.completeCurrentReminder()
    }

    func skipCurrentReminder() {
        store.skipCurrentReminder()
    }

    func deleteCurrentReminder() async {
        await store.deleteCurrentReminder()
    }

    func reload(clearSkipped: Bool = false) async {
        await store.reload(clearSkipped: clearSkipped)
    }

    func setExcludedListTitles(_ titles: Set<String>) {
        store.setExcludedListTitles(titles)
    }

    // MARK: Private
}

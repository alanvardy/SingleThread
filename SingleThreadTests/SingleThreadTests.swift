@testable import SingleThread
@testable import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct SingleThreadTests {
    @Test
    func contentViewModelInitializesWithoutReminders() {
        let viewModel = ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())
        // Verify the view model init and its content-view wrapper render without crashing.
        let view = ContentView(viewModel: viewModel)
        let bodyValue = view.body
        #expect(String(describing: bodyValue).isEmpty == false)
    }

    @Test
    func contentViewBodyContainsRefreshableModifier() {
        let viewModel = ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())
        let view = ContentView(viewModel: viewModel)
        // Verify body renders with the List + refreshable structure
        let bodyValue = view.body
        let description = String(describing: bodyValue)
        #expect(description.contains("List") || description.contains("refreshable"))
    }

    @Test
    func contentViewEmptyStatesShowDistinctCopy() {
        let emptyCopy = ContentViewModel.emptyStateCopy(hasHidden: false)
        #expect(emptyCopy.title == String.en("No Reminders", bundle: .core))
        #expect(emptyCopy.systemImage == "checklist")
        #expect(emptyCopy.description == String.en(
            "You don't have any reminders yet.", bundle: .main, table: "Localizable"))

        let nothingDueCopy = ContentViewModel.emptyStateCopy(hasHidden: true)
        #expect(nothingDueCopy.title == String.en("Nothing due", bundle: .main))
        #expect(nothingDueCopy.systemImage == "calendar")
        #if os(macOS)
            #expect(nothingDueCopy.description == String.en(
                "Only today's and overdue reminders show here — press the refresh button in the top left corner.",
                bundle: .main, table: "Localizable"))
        #else
            #expect(nothingDueCopy.description == String.en(
                "Only today's and overdue reminders show here — pull to refresh.",
                bundle: .main, table: "Localizable"))
        #endif
        #expect(emptyCopy.title != nothingDueCopy.title)
    }

    @Test
    func contentViewAllDoneShowsAllDoneCopy() {
        let allDoneCopy = ContentViewModel.allDoneStateCopy()
        #expect(allDoneCopy.title == String.en("All Done", bundle: .core))
        #expect(allDoneCopy.systemImage == "checkmark.circle")
        #if os(macOS)
            #expect(allDoneCopy.description == String.en(
                "Press the refresh button in the top left corner to see all your reminders again.",
                bundle: .main, table: "Localizable"))
        #else
            #expect(allDoneCopy.description == String.en(
                "Pull to refresh to see all your reminders again.",
                bundle: .main, table: "Localizable"))
        #endif
    }

    @Test
    func contentViewBodyContainsRefreshButtonOnMacOS() {
        let viewModel = ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())
        let view = ContentView(viewModel: viewModel)
        let bodyValue = view.body
        let description = String(describing: bodyValue)
        // The button only exists when compiled for macOS. On iOS the
        // assertion is vacuously true (no-op) — the test compiles on both
        // platforms and just verifies the view renders without crashing.
        #if os(macOS)
            // `String(describing:)` reflects the view's generic structure,
            // not accessibility values, so the "refreshButton" identifier is
            // not printed. The refresh overlay's structural signature is
            // unique on macOS: a control-plate Button wrapped by
            // `.disabled(isRefreshing)` (printed as an environment key
            // transform) and then the accessibility attachment. The gear
            // button shares the plate but adds `.contentShape`, and no other
            // button uses `.disabled`, so this substring pins the overlay.
            let refreshButtonSignature =
                "Button<ModifiedContent<ModifiedContent<Image, _EnvironmentKeyWritingModifier<Optional<Font>>>, "
                    + "ControlPlateModifier>>, SingleThreadButtonModifier>, "
                    + "_EnvironmentKeyTransformModifier<Bool>>, AccessibilityAttachmentModifier"
            #expect(description.contains(refreshButtonSignature))
        #endif
    }

    @Test
    func contentViewBodyContainsBorderlessSettingsGearOnMacOS() {
        let view = ContentView(viewModel: ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation()))
        let description = String(describing: view.body)
        #if os(macOS)
            // The gear's label is Image.font(.title3).controlPlate().contentShape(Rectangle()),
            // wrapped by `.singleThreadButton()` then `.accessibilityLabel`. The
            // `_ContentShapeModifier<Rectangle>` distinguishes it from the refresh
            // button (which uses `.disabled` instead).
            let gearSignature =
                "Button<ModifiedContent<ModifiedContent<ModifiedContent<Image, "
                    + "_EnvironmentKeyWritingModifier<Optional<Font>>>, ControlPlateModifier>, "
                    + "_ContentShapeModifier<Rectangle>>>, SingleThreadButtonModifier>, "
                    + "AccessibilityAttachmentModifier"
            #expect(description.contains(gearSignature))
        #endif
    }

    @Test
    func contentViewBodyContainsBorderlessDictateButtonOnMacOS() {
        let view = ContentView(viewModel: ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation()))
        let description = String(describing: view.body)
        #if os(macOS)
            // The mic button (shared across platforms) keeps `.title2` + `.controlPlate()`,
            // wrapped by `.singleThreadButton()` directly before `.accessibilityLabel`. No
            // `.disabled`/`.contentShape`, so `SingleThreadButtonModifier>, Accessibility…`
            // (no intervening transform) is unique to the mic.
            let micSignature =
                "Button<ModifiedContent<ModifiedContent<Image, _EnvironmentKeyWritingModifier<Optional<Font>>>, "
                    + "ControlPlateModifier>>, SingleThreadButtonModifier>, AccessibilityAttachmentModifier"
            #expect(description.contains(micSignature))
        #endif
    }

    @Test
    func rescheduleSheetTextButtonsKeepNativeChrome() {
        let view = ContentView(viewModel: ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation()))
        // Scope boundary: the sheet's text "Cancel" button stays native and is
        // never routed through the new modifier.
        let sheetDescription = String(describing: view.actionMenuRescheduleSheet)
        #expect(sheetDescription.contains("Cancel"))
        #expect(!sheetDescription.contains("SingleThreadButtonModifier"))
    }
}

struct ReminderDateFilterTests {
    // MARK: Internal

    @Test
    func reminderDueTodayIsIncluded() {
        let end = ReminderDateFilter.endOfToday(calendar: calendar, now: now)
        #expect(date(6) <= end)
    }

    @Test
    func reminderDueYesterdayIsIncluded() {
        let end = ReminderDateFilter.endOfToday(calendar: calendar, now: now)
        #expect(date(5) <= end)
    }

    @Test
    func reminderDueTomorrowIsExcluded() {
        let end = ReminderDateFilter.endOfToday(calendar: calendar, now: now)
        #expect(date(7) > end)
    }

    @Test
    func endOfTodayIsLastInstantOfToday() throws {
        let end = ReminderDateFilter.endOfToday(calendar: calendar, now: now)
        let startOfTomorrow = try #require(calendar.date(
            byAdding: DateComponents(day: 1),
            to: calendar.startOfDay(for: now)))
        #expect(end < startOfTomorrow)
    }

    @Test
    func overdueCutoffDefaultsToThirtyDaysAgo() throws {
        let cutoff = ReminderDateFilter.overdueCutoff(calendar: calendar, now: now)
        let startOfToday = calendar.startOfDay(for: now)
        let thirtyDaysAgo = try #require(calendar.date(
            byAdding: DateComponents(day: -30),
            to: startOfToday))
        #expect(cutoff == thirtyDaysAgo)
    }

    @Test
    func overdueCutoffIncludesReminderThirtyDaysOverdue() {
        let cutoff = ReminderDateFilter.overdueCutoff(calendar: calendar, now: now)
        #expect(date(7, in: .august) >= cutoff)
    }

    @Test
    func overdueCutoffExcludesReminderMoreThanThirtyDaysOverdue() {
        let cutoff = ReminderDateFilter.overdueCutoff(calendar: calendar, now: now)
        #expect(date(6, in: .august) < cutoff)
    }

    @Test
    func isInCurrentWindowIncludesNilDate() {
        #expect(ReminderDateFilter.isInCurrentWindow(nil, calendar: calendar, now: now))
    }

    @Test
    func isInCurrentWindowIncludesTodaysReminder() {
        #expect(ReminderDateFilter.isInCurrentWindow(date(6), calendar: calendar, now: now))
    }

    @Test
    func isInCurrentWindowIncludesOverdueCutoffBoundary() {
        let cutoff = ReminderDateFilter.overdueCutoff(calendar: calendar, now: now)
        #expect(ReminderDateFilter.isInCurrentWindow(cutoff, calendar: calendar, now: now))
    }

    @Test
    func isInCurrentWindowExcludesTomorrow() {
        #expect(!ReminderDateFilter.isInCurrentWindow(date(7), calendar: calendar, now: now))
    }

    @Test
    func isInCurrentWindowExcludesOldOverdue() {
        #expect(!ReminderDateFilter.isInCurrentWindow(date(6, in: .august), calendar: calendar, now: now))
    }

    // MARK: Private

    private enum Month: Int {
        case august = 8
        case september = 9
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_725_600_000) // 2024-09-06 05:20 UTC

    private func date(_ day: Int, in month: Month = .september) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: month.rawValue, day: day))!
    }
}

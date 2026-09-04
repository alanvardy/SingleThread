import Foundation
import SingleThreadCore
import Testing

struct NextThingSummaryTests {
    // MARK: Internal

    // MARK: Happy path

    @Test
    func reminderWithDateProducesInlinePrefixAndDetail() {
        let summary = NextThingSummary.summarize(
            .reminder(reminder()), showsDate: true, showsList: false,
            showsRecurrence: false, showsAlarms: false)
        #expect(summary.status == .next)
        #expect(summary.inlineText.hasPrefix("› "))
        #expect(summary.rectangularTitle == "Buy groceries")
        #expect(summary.rectangularDetail != nil) // due-date string present
    }

    @Test
    func reminderWithoutShowsDateOmitsDetail() {
        let summary = NextThingSummary.summarize(
            .reminder(reminder()), showsDate: false, showsList: false,
            showsRecurrence: false, showsAlarms: false)
        #expect(summary.rectangularDetail == nil)
    }

    // MARK: Sad / edge

    @Test
    func emptyWithHiddenMirrorsNothingDueWord() {
        let summary = NextThingSummary.summarize(
            .empty(hasHidden: true), showsDate: true, showsList: true,
            showsRecurrence: true, showsAlarms: true)
        #expect(summary.status == .empty)
        #expect(summary.rectangularTitle == SharedStrings.nothingDueRightNow)
        #expect(summary.symbolName == "checklist")
    }

    @Test
    func emptyWithoutHiddenMirrorsNoRemindersWord() {
        let summary = NextThingSummary.summarize(
            .empty(hasHidden: false), showsDate: true, showsList: true,
            showsRecurrence: true, showsAlarms: true)
        #expect(summary.rectangularTitle == SharedStrings.noRemindersYet)
    }

    @Test
    func allDoneProducesCheckmarkGlyph() {
        let summary = NextThingSummary.summarize(
            .allDone, showsDate: true, showsList: true,
            showsRecurrence: true, showsAlarms: true)
        #expect(summary.status == .allDone)
        #expect(summary.symbolName == "checkmark.circle")
        #expect(summary.rectangularTitle == SharedStrings.allDone)
    }

    @Test
    func noAccessProducesLockGlyph() {
        let summary = NextThingSummary.summarize(
            .noAccess, showsDate: true, showsList: true,
            showsRecurrence: true, showsAlarms: true)
        #expect(summary.status == .noAccess)
        #expect(summary.symbolName == "lock.shield")
        #expect(summary.rectangularTitle == SharedStrings.remindersAccess)
    }

    // MARK: Glyph mapping

    @Test
    func priorityMarkerMapsToExclamationSymbol() {
        let summary = NextThingSummary.summarize(
            .reminder(reminder(priorityMarker: "!!")), showsDate: false,
            showsList: false, showsRecurrence: false, showsAlarms: false)
        #expect(summary.symbolName == "exclamationmark.2")
    }

    @Test
    func noPriorityMapsToGenericGlyph() {
        let summary = NextThingSummary.summarize(
            .reminder(reminder(priorityMarker: "")), showsDate: false,
            showsList: false, showsRecurrence: false, showsAlarms: false)
        #expect(summary.symbolName == "list.bullet")
    }

    // MARK: Show-flag matrix

    @Test
    func listAndRecurrenceBitsAreGatedByShowFlags() {
        let base = reminder(listName: "Groceries", hasRecurrence: true, recurrenceSummary: "Weekly")
        let onSummary = NextThingSummary.summarize(
            .reminder(base), showsDate: false, showsList: true,
            showsRecurrence: true, showsAlarms: false)
        #expect(onSummary.rectangularDetail?.contains("Groceries") == true)
        #expect(onSummary.rectangularDetail?.contains("Weekly") == true)

        let offSummary = NextThingSummary.summarize(
            .reminder(base), showsDate: false, showsList: false,
            showsRecurrence: false, showsAlarms: false)
        #expect(offSummary.rectangularDetail == nil)
    }

    @Test
    func alarmBitIsGatedByShowsAlarms() {
        let withAlarm = reminder(hasAlarms: true)
        let onSummary = NextThingSummary.summarize(
            .reminder(withAlarm), showsDate: false, showsList: false,
            showsRecurrence: false, showsAlarms: true)
        #expect(onSummary.rectangularDetail == SharedStrings.alert)
        let offSummary = NextThingSummary.summarize(
            .reminder(withAlarm), showsDate: false, showsList: false,
            showsRecurrence: false, showsAlarms: false)
        #expect(offSummary.rectangularDetail == nil)
    }

    // MARK: Private

    // MARK: Helpers

    private func reminder(
        title: String = "Buy groceries",
        dueDate: Date? = Date(timeIntervalSince1970: 1_800_000_000),
        priorityMarker: String = "",
        listName: String? = nil,
        hasRecurrence: Bool = false,
        recurrenceSummary: String? = nil,
        hasAlarms: Bool = false) -> ReminderDisplay {
        ReminderDisplay(
            title: title,
            dueDate: dueDate,
            priorityMarker: priorityMarker,
            listName: listName,
            hasRecurrence: hasRecurrence,
            recurrenceSummary: recurrenceSummary,
            hasAlarms: hasAlarms)
    }
}

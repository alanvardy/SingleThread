import Foundation

/// Resolved "next thing" state fed to `NextThingSummary`. Mirrors the widget's
/// `NextThingEntry.State` so the mapping in `NextThingWidgetView` is mechanical.
/// Distinct from the widget type because this lives in `SingleThreadCore` and
/// must not depend on WidgetKit.
public enum NextThingState: Equatable, Sendable {
    case noAccess
    case empty(hasHidden: Bool)
    case allDone
    case reminder(ReminderDisplay)
}

/// Compact, family-agnostic strings + glyph consumed by the accessory views.
/// Pure formatting only — never reads EventKit / App Group itself.
public struct NextThingSummary: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case next, allDone, empty, noAccess
    }

    public let status: Status
    public let inlineText: String // accessoryInline: "› Buy groceries" / "All Done" / …
    public let rectangularTitle: String
    public let rectangularDetail: String? // due date / list / recurrence / alert, gated by show flags
    public let symbolName: String // reminder priority glyph, else per-status glyph
}

extension NextThingSummary {
    public static func summarize(
        _ state: NextThingState,
        showsDate: Bool,
        showsList: Bool,
        showsRecurrence: Bool,
        showsAlarms: Bool) -> NextThingSummary {
        switch state {
        case .noAccess:
            return NextThingSummary(
                status: .noAccess,
                inlineText: SharedStrings.remindersAccess,
                rectangularTitle: SharedStrings.remindersAccess,
                rectangularDetail: nil,
                symbolName: "lock.shield")
        case let .empty(hasHidden):
            let word = hasHidden ? SharedStrings.nothingDueRightNow : SharedStrings.noRemindersYet
            return NextThingSummary(
                status: .empty,
                inlineText: word,
                rectangularTitle: word,
                rectangularDetail: nil,
                symbolName: "checklist")
        case .allDone:
            return NextThingSummary(
                status: .allDone,
                inlineText: SharedStrings.allDone,
                rectangularTitle: SharedStrings.allDone,
                rectangularDetail: nil,
                symbolName: "checkmark.circle")
        case let .reminder(display):
            let title = String(display.titleAttributed.characters) // backtick-stripped plain title
            return NextThingSummary(
                status: .next,
                inlineText: "› \(title)",
                rectangularTitle: title,
                rectangularDetail: detail(
                    for: display,
                    showsDate: showsDate,
                    showsList: showsList,
                    showsRecurrence: showsRecurrence,
                    showsAlarms: showsAlarms),
                symbolName: symbol(for: display))
        }
    }

    // MARK: Private

    private static func detail(
        for display: ReminderDisplay,
        showsDate: Bool,
        showsList: Bool,
        showsRecurrence: Bool,
        showsAlarms: Bool) -> String? {
        var parts: [String] = []
        if showsDate, let dueDate = display.dueDate {
            parts.append(detailDateFormat.format(dueDate))
        }
        if showsList, let listName = display.listName, !listName.isEmpty {
            parts.append(listName)
        }
        if showsRecurrence, display.hasRecurrence {
            parts.append(display.recurrenceSummary ?? SharedStrings.repeats)
        }
        if showsAlarms, display.hasAlarms {
            parts.append(SharedStrings.alert)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func symbol(for display: ReminderDisplay) -> String {
        switch ReminderPriority.level(forMarker: display.priorityMarker) {
        case .high: "exclamationmark.3"
        case .medium: "exclamationmark.2"
        case .low: "exclamationmark"
        case nil: "list.bullet"
        }
    }

    /// Date-only, locale-relative formatter. Date components are omitted so a
    /// reminder whose due date has no meaningful time renders without a
    /// spurious "12:00 AM". Unit tests assert gate behavior, not exact strings
    /// (formatting output is locale-dependent).
    private static let detailDateFormat = Date.FormatStyle(date: .abbreviated, time: .omitted)
}

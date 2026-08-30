import EventKit
import Foundation

/// Parses a `--seed '<json>'` launch argument into an in-memory store
/// configuration driven by UI tests.
///
/// JSON schema (whitespace-insensitive):
/// ```json
/// {
///   "reminders": [
///     {"title":"Buy groceries","priority":5,"notes":"milk"},
///     {"title":"Call mom","priority":1}
///   ],
///   "calendars": ["Groceries"],
///   "excludedLists": ["Work"],
///   "completionCount": 3,      // optional, defaults to 0
///   "isEntitled": true          // optional, defaults to false
/// }
/// ```
public struct UITestingSeed {
    // MARK: Public

    public let reminders: [EKReminder]
    public let calendars: [EKCalendar]
    public let excludedListTitles: Set<String>
    public let completionCount: Int
    public let isEntitled: Bool

    /// Reads an optional `--seed '<json>'` launch argument and decodes it.
    /// Returns `nil` when the argument is absent or malformed.
    public static func fromLaunchArguments(_ arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--seed"),
              index + 1 < arguments.count,
              let data = arguments[index + 1].data(using: .utf8),
              let payload = try? JSONDecoder().decode(SeedPayload.self, from: data)
        else {
            return nil
        }
        return payload.materialize()
    }

    /// Clears the persisted UserDefaults keys the app reads on launch so each
    /// seeded UI test starts from a clean slate (no leaked skips, exclusions,
    /// sort, or show-date state from a previous test run).
    public static func resetPersistedState() {
        for key in persistedKeys {
            AppGroup.defaults.removeObject(forKey: key)
        }
        for key in persistedKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: Private

    private static let persistedKeys = [
        "skippedReminderIdentifiers",
        "excludedListTitles",
        "showDate",
        "showList",
        "showRecurrence",
        "showAlarms",
        "showCompletionGlow",
        "showUndatedReminders",
        "sortOption",
        "completionCount",
        "isEntitled",
        "enableActionButtons",
        "showMicrophoneButton",
        "showSwipePrompt",
        "showUndoButton",
        "backgroundEnabled",
        "backgroundFadePercent",
        "backgroundPinned",
        "allowsLandscape",
        "textSize",
        "appearanceMode"
    ]
}

// MARK: - Codable payload

private struct SeedPayload: Codable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        // Defaults do not make the synthesized `decode` optional, so absent
        // `calendars`/`excludedLists` keys would throw keyNotFound. Use
        // decodeIfPresent so a seed omitting them still parses.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reminders = try container.decode([ReminderSeed].self, forKey: .reminders)
        calendars = try container.decodeIfPresent([String].self, forKey: .calendars) ?? []
        excludedLists = try container.decodeIfPresent([String].self, forKey: .excludedLists) ?? []
        completionCount = try container.decodeIfPresent(Int.self, forKey: .completionCount) ?? 0
        isEntitled = try container.decodeIfPresent(Bool.self, forKey: .isEntitled) ?? false
    }

    // MARK: Internal

    struct ReminderSeed: Codable {
        var title: String
        var notes: String?
        var priority: Int?
    }

    var reminders: [ReminderSeed]
    var calendars: [String] = []
    var excludedLists: [String] = []
    var completionCount: Int = 0
    var isEntitled: Bool = false

    func materialize() -> UITestingSeed {
        let eventStore = EKEventStore()
        let createdCalendars = calendars.map { title in
            let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
            calendar.title = title
            return calendar
        }
        let defaultCalendar = createdCalendars.first
        let createdReminders = reminders.map { seed in
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = seed.title
            reminder.notes = seed.notes
            if let priority = seed.priority {
                reminder.priority = priority
            }
            reminder.calendar = defaultCalendar
            return reminder
        }
        return UITestingSeed(
            reminders: createdReminders,
            calendars: createdCalendars,
            excludedListTitles: Set(excludedLists),
            completionCount: completionCount,
            isEntitled: isEntitled)
    }

    // MARK: Private

    /// Explicit keys pin the wire format: renaming the property alone would
    /// otherwise silently change the decoded JSON key.
    private enum CodingKeys: String, CodingKey {
        case reminders, calendars
        case excludedLists
        case completionCount, isEntitled
    }
}

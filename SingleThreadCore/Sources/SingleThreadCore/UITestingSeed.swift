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
///   "skipCounts": {"Buy groceries": 5},  // optional, title-keyed, defaults to {}
///   "isEntitled": true,         // optional, defaults to false
///   "hasHidden": true,          // optional, defaults to false; only meaningful
///                               // with an empty "reminders" array
///   "entitlementUnresolved": true  // optional, defaults to false; when true,
///                                  // the entitlement store starts unresolved
///                                  // so the pre-resolution render is testable
/// }
/// ```
///
/// `completionCount` is written verbatim (unclamped) by the app's `--seed`
/// seam: production only ever writes `count + 1`, `max(0, count - 1)`, or `0`
/// (see ``CompletionCounterStore``), yet the seed accepts any `Int` so UI tests
/// can stage the free-tier gate scenarios (99 = near-cap, 100 = gated) that
/// production never produces.
public struct UITestingSeed {
    // MARK: Public

    public let reminders: [EKReminder]
    public let calendars: [EKCalendar]
    public let excludedListTitles: Set<String>
    public let completionCount: Int
    /// Title-keyed skip counts, resolved to identifier-keyed on materialization
    /// (identifiers aren't stable until `calendarItemIdentifier` is generated).
    public let skipCountsByIdentifier: [String: Int]
    public let isEntitled: Bool
    public let hasHidden: Bool
    public let entitlementUnresolved: Bool

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
        SkippedReminderStore.defaultsKey,
        SkipCountStore.defaultsKey,
        ExcludedListStore.defaultsKey,
        ShowDatePreference.defaultsKey,
        ShowListPreference.defaultsKey,
        ShowRecurrencePreference.defaultsKey,
        ShowAlarmsPreference.defaultsKey,
        ShowCompletionGlowPreference.defaultsKey,
        ShowUndatedRemindersPreference.defaultsKey,
        SortOption.defaultsKey,
        CompletionCounterStore.defaultsKey,
        "isEntitled", // in-memory, no store type
        "enableActionButtons", // Stage 3/6: replace with store constant
        "showMicrophoneButton", // cosmetic, no store type
        "showSwipePrompt", // cosmetic, no store type
        "showUndoButton", // cosmetic, no store type
        "backgroundEnabled", // cosmetic, no store type
        "backgroundFadePercent", // cosmetic, no store type
        "backgroundPinned", // cosmetic, no store type
        "allowsLandscape", // Stage 3: replace with store constant
        "textSize", // cosmetic, no store type
        "appearanceMode", // Stage 3: replace with store constant
        "notificationsEnabled", // Stage 3: replace with store constant
        "notificationIntervalHours" // Stage 3: replace with store constant
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
        skipCounts = try container.decodeIfPresent([String: Int].self, forKey: .skipCounts) ?? [:]
        isEntitled = try container.decodeIfPresent(Bool.self, forKey: .isEntitled) ?? false
        hasHidden = try container.decodeIfPresent(Bool.self, forKey: .hasHidden) ?? false
        entitlementUnresolved = try container.decodeIfPresent(Bool.self, forKey: .entitlementUnresolved) ?? false
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
    var skipCounts: [String: Int] = [:]
    var isEntitled: Bool = false
    var hasHidden: Bool = false
    var entitlementUnresolved: Bool = false

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
        // Resolve title-keyed wire counts to identifier-keyed (identifiers are
        // generated at materialization, so the JSON can't key by identifier).
        var countsByIdentifier: [String: Int] = [:]
        for reminder in createdReminders {
            guard let title = reminder.title, let count = skipCounts[title] else { continue }
            countsByIdentifier[reminder.calendarItemIdentifier] = count
        }
        return UITestingSeed(
            reminders: createdReminders,
            calendars: createdCalendars,
            excludedListTitles: Set(excludedLists),
            completionCount: completionCount,
            skipCountsByIdentifier: countsByIdentifier,
            isEntitled: isEntitled,
            hasHidden: hasHidden,
            entitlementUnresolved: entitlementUnresolved)
    }

    // MARK: Private

    /// Explicit keys pin the wire format: renaming the property alone would
    /// otherwise silently change the decoded JSON key.
    private enum CodingKeys: String, CodingKey {
        case reminders, calendars
        case excludedLists
        case completionCount, isEntitled, hasHidden
        case skipCounts
        case entitlementUnresolved
    }
}

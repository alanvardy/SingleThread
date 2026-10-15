import Foundation

/// The demo reminder the watch `--ui-testing` seam renders, parsed as a value so
/// the copy is unit-testable without launching the app.
///
/// Exists for the App Store screenshot harness. The phone seeds localized copy
/// through `--seed`, but the watch builds its store from launch arguments and
/// had no equivalent, so every watch capture showed the hardcoded English
/// "Buy groceries" no matter the interface language.
struct WatchDemoReminder: Equatable {
    // MARK: Internal

    /// Copy used whenever the matching seam is absent.
    static let sample = Self(
        title: "Buy groceries",
        notes: "Don't forget the milk",
        isEmpty: false)

    let title: String
    let notes: String?
    /// `--ui-testing-empty` renders the empty store ("No Reminders") instead of a
    /// card. No other watch seam reaches that state: `--ui-testing` always seeds
    /// one reminder.
    let isEmpty: Bool

    static func fromLaunchArguments(
        _ arguments: [String] = ProcessInfo.processInfo.arguments)
        -> Self {
        Self(
            title: value(of: titleFlag, in: arguments) ?? sample.title,
            notes: notes(from: arguments),
            isEmpty: arguments.contains(emptyFlag))
    }

    // MARK: Private

    private static let titleFlag = "--ui-testing-title"
    private static let notesFlag = "--ui-testing-notes"
    private static let emptyFlag = "--ui-testing-empty"

    /// An explicitly empty `--ui-testing-notes ""` means "no notes" (`nil`) so a
    /// capture can show a title-only card; absent the flag the sample notes stay.
    private static func notes(from arguments: [String]) -> String? {
        guard let raw = value(of: notesFlag, in: arguments) else {
            return sample.notes
        }
        return raw.isEmpty ? nil : raw
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}

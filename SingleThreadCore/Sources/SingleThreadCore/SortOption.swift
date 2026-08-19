import Foundation

/// The user's preferred ordering for reminder display, persisted in the App
/// Group under ``defaultsKey``. Mirrors `ReminderPriority` (pure Core logic,
/// no SwiftUI); presentation lives in the app target.
public enum SortOption: String, CaseIterable, Sendable {
    /// Today's compound order: priority rank → due date → title.
    case priority
    /// Due date soonest-first (dated before undated) → title.
    case dueDate
    /// Case-insensitive title A→Z → due date.
    case title

    // MARK: Public

    /// Single shared key used by `SortOptionStore`, the app's `@AppStorage`,
    /// and nowhere else as a raw literal.
    public static let defaultsKey = "sortOption"
}

/// Persists the sort option in UserDefaults, mirroring `SkippedReminderStore`.
public struct SortOptionStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = SortOption.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Loads the persisted option, falling back to `.priority` when the key is
    /// missing or holds an unrecognized raw value.
    public func load() -> SortOption {
        guard let raw = defaults.string(forKey: key), let option = SortOption(rawValue: raw) else {
            return .priority
        }
        return option
    }

    public func save(_ option: SortOption) {
        defaults.set(option.rawValue, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}

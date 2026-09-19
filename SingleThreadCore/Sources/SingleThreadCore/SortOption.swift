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
    /// On-device AI ranking against the user's freeform rules, falling back to
    /// the `.priority` chain when no ranking is available. Currently disabled:
    /// withheld from ``menuOptions``, so the sort menu does not offer it and
    /// neither the store nor sync will apply it. The case, its persisted raw
    /// value and the ranking path all stay in place so re-enabling it is a
    /// matter of putting `.ai` back in ``menuOptions``.
    case ai

    // MARK: Public

    /// Single shared key used by `SortOptionStore`, the app's `@AppStorage`,
    /// and nowhere else as a raw literal.
    public static let defaultsKey = "sortOption"

    /// The options the sort menu offers, in display order. `.ai` is deliberately
    /// absent while on-device AI sorting is disabled.
    public static let menuOptions: [Self] = [.priority, .dueDate, .title]

    /// Whether this option can be chosen, i.e. is offered by the sort menu. A
    /// disabled option may still be named by a stored or synced raw value, but
    /// nothing may apply it.
    public var isSelectable: Bool {
        Self.menuOptions.contains(self)
    }
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
    /// missing, holds an unrecognized raw value, or names a currently-disabled
    /// option (`.ai`) — a device that had AI sort selected must not keep ranking
    /// while the sort menu no longer offers it.
    public func load() -> SortOption {
        guard let raw = defaults.string(forKey: key),
              let option = SortOption(rawValue: raw),
              option.isSelectable else {
            return .priority
        }
        return option
    }

    /// Persists `option`, substituting `.priority` for a currently-disabled
    /// option so the store never holds a choice the menu cannot offer.
    public func save(_ option: SortOption) {
        defaults.set((option.isSelectable ? option : .priority).rawValue, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}

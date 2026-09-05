import Foundation

/// A user action recorded by a watch widget extension process and later drained
/// by the watch app process (the only WatchConnectivity peer on the watch).
public struct PendingReminderAction: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(kind: Kind, identifier: String) {
        self.kind = kind
        self.identifier = identifier
    }

    // MARK: Public

    public enum Kind: String, Codable, Sendable {
        case complete
        case skip
    }

    public let kind: Kind
    /// `EKReminder.calendarItemIdentifier` of the reminder to complete/skip.
    public let identifier: String
}

/// Single-slot mailbox in `AppGroup.defaults` (real suite on watch once the
/// App Group is registered). Mirrors `SkippedReminderStore`'s shape.
public struct PendingReminderActionStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    // MARK: Public

    public static let key = "pendingReminderAction"

    public func load() -> PendingReminderAction? {
        guard
            let data = defaults.data(forKey: Self.key),
            let action = try? JSONDecoder().decode(PendingReminderAction.self, from: data)
        else { return nil }
        return action
    }

    public func save(_ action: PendingReminderAction) {
        guard let data = try? JSONEncoder().encode(action) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: Private

    private let defaults: UserDefaults
}

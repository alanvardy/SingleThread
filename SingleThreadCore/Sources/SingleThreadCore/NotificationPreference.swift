import Foundation

/// Persists the background-notification preferences in `UserDefaults.standard`.
///
/// Like `OrientationPreference`, the keys live in plain `UserDefaults` (not the
/// App Group) because the schedule is evaluated in the app's background
/// lifecycle paths.
public struct NotificationPreference {
    // MARK: Lifecycle

    public init(
        defaults: UserDefaults = .standard,
        enabledKey: String = enabledDefaultsKey,
        intervalKey: String = intervalDefaultsKey) {
        self.defaults = defaults
        self.enabledKey = enabledKey
        self.intervalKey = intervalKey
    }

    // MARK: Public

    /// Single shared key for the enabled toggle (`@AppStorage`, settings).
    public static let enabledDefaultsKey = "notificationsEnabled"

    /// Single shared key for the interval hours (`@AppStorage`, settings).
    public static let intervalDefaultsKey = "notificationIntervalHours"

    /// Whether background notifications are scheduled. `nil` (missing key) → `false`.
    public var isEnabled: Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }

    /// The interval hours to schedule after, falling back to the 48 h default
    /// when the key is absent or non-positive — mirrors the `bool(forKey:)` /
    /// `integer(forKey:)` + fallback reads `scheduleNotificationIfNeeded()`
    /// used before this type existed.
    public var intervalHours: Int {
        let raw = defaults.integer(forKey: intervalKey)
        return raw > 0 ? raw : 48
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enabledKey)
    }

    public func setIntervalHours(_ hours: Int) {
        defaults.set(hours, forKey: intervalKey)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let enabledKey: String
    private let intervalKey: String
}

import Foundation

/// Persists the appearance-mode raw string in `UserDefaults.standard`.
///
/// Lives in `SingleThreadCore` so the iOS app, macOS app, and (potentially)
/// widget targets can share the key. An absent or unrecognized key resolves to
/// `"system"`.
public struct AppearanceModePreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by `@AppStorage` and `AppearanceMode.load(from:)`.
    public static let defaultsKey = "appearanceMode"

    /// Returns the raw value string (`"system"` | `"light"` | `"dark"`),
    /// falling back to `"system"` for missing/unrecognized keys.
    public var rawValue: String {
        guard let raw = defaults.object(forKey: key) as? String,
              ["system", "light", "dark"].contains(raw)
        else { return "system" }
        return raw
    }

    public func setRawValue(_ raw: String) {
        defaults.set(raw, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}

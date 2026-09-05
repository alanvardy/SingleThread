import Foundation

/// Generic Bool preference store parameterized by key string and absent-value fallback.
/// Replaces six near-identical `Show*Preference` structs.
///
/// - Read via `isEnabled` (uses `object(forKey:) as? Bool ?? fallback` — never `bool(forKey:)`,
///   so nil ≠ explicitly-off).
/// - Write via `set(_:)`.
/// - `defaults:` defaults to `AppGroup.defaults` (like every old struct).
public struct BoolPreferenceStore {
    // MARK: Lifecycle

    public init(
        // swiftlint:disable:next function_default_parameter_at_end
        defaults: UserDefaults = AppGroup.defaults,
        key: String,
        fallback: Bool) {
        self.defaults = defaults
        self.key = key
        self.fallback = fallback
    }

    // MARK: Public

    /// Whether the preference is enabled. Absent key → `fallback`.
    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    public func set(_ value: Bool) {
        defaults.set(value, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
    private let fallback: Bool
}

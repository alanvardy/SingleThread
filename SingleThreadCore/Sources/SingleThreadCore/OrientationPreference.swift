import Foundation

/// Persists the "allow landscape" preference in `UserDefaults.standard`.
///
/// Unlike the App-Group preferences, this key is read at launch by the
/// `AppDelegate` before any SwiftUI view exists (so the persisted lock takes
/// effect without a wrong-orientation flash), hence plain `UserDefaults`
/// rather than the shared suite. An absent key resolves to `true` (landscape
/// enabled by default).
public struct OrientationPreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by `AppDelegate`, `@AppStorage`, and settings.
    public static let defaultsKey = "allowsLandscape"

    /// Whether landscape orientation is enabled. `nil` (missing key) → `true`.
    public var isLandscapeEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func setLandscapeEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}

import SwiftUI

#if os(iOS)
    import UIKit
#endif

// MARK: - AppearanceMode

/// The app's appearance override, persisted in `UserDefaults` via `@AppStorage`.
/// Applied at the window level (`UIWindow.overrideUserInterfaceStyle` on iOS,
/// `NSWindow.appearance` on macOS). `.system` clears the override so the app
/// follows the device.
enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    // MARK: Internal

    #if os(iOS)
        /// The window interface style to force, or the "clear override → follow
        /// device" sentinel for `.system`.
        var windowOverrideStyle: UIUserInterfaceStyle {
            switch self {
            case .system: .unspecified
            case .light: .light
            case .dark: .dark
            }
        }
    #endif

    /// The `ColorScheme` to prefer, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// SF Symbol shown alongside the label in the appearance picker.
    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// Human-readable label shown in the appearance picker.
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Reads the persisted appearance from `UserDefaults`, defaulting to
    /// `.system` for a missing or unknown value. Mirrors `AppDelegate`'s
    /// `allowsLandscape` launch read and `@AppStorage`'s fallback-to-default.
    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.object(forKey: "appearanceMode") as? String,
              let mode = Self(rawValue: rawValue)
        else { return .system }
        return mode
    }
}

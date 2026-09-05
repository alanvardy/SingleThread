import SingleThreadCore
import SwiftUI
#if os(iOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
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

    #if os(macOS)
        /// The `NSAppearance` to force, or `nil` for `.system` (clear override
        /// → follow the system).
        var appKitAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    #endif

    /// The `ColorScheme` to force in a SwiftUI preview (the canvas), or `nil`
    /// for `.system` to follow the device. Previews have no window to override,
    /// so they translate the appearance through this property instead of
    /// `windowOverrideStyle` / `appKitAppearance`.
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
        case .system: String(localized: "System", table: "Localizable", bundle: .main)
        case .light: String(localized: "Light", table: "Localizable", bundle: .main)
        case .dark: String(localized: "Dark", table: "Localizable", bundle: .main)
        }
    }

    /// Reads the persisted appearance from `UserDefaults`, defaulting to
    /// `.system` for a missing or unknown value. Mirrors `AppDelegate`'s
    /// `allowsLandscape` launch read and `@AppStorage`'s fallback-to-default.
    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: AppearanceModePreference(defaults: defaults).rawValue) ?? .system
    }
}

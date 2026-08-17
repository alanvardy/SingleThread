import SwiftUI

// MARK: - AppearanceMode

/// The app's appearance override, persisted in `UserDefaults` via `@AppStorage`.
/// Maps onto `.preferredColorScheme(_:)`, where `.system` produces `nil` so the
/// app follows the device's appearance.
enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    // MARK: Internal

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
}

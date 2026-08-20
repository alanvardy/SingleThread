import SwiftUI

// MARK: - TextSize

/// User-selectable text size preference, persisted in `UserDefaults` via
/// `@AppStorage`. Follows the same `String, CaseIterable` pattern as
/// ``AppearanceMode`` so it slots into the settings menu as a `Picker`.
enum TextSize: String, CaseIterable {
    case system
    case small
    case medium
    case large
    case extraLarge

    // MARK: Internal

    /// The `DynamicTypeSize` to apply, or `nil` to follow the system.
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: nil
        case .small: .small
        case .medium: .medium
        case .large: .xLarge
        case .extraLarge: .xxxLarge
        }
    }

    /// SF Symbol shown alongside the label in the text-size picker.
    var systemImage: String {
        switch self {
        case .system: "textformat.size"
        case .small: "textformat.size.smaller"
        case .medium: "textformat.size"
        case .large: "textformat.size.larger"
        case .extraLarge: "textformat.size.larger"
        }
    }

    /// Human-readable label shown in the text-size picker.
    var title: String {
        switch self {
        case .system: "System"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}

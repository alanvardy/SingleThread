import SingleThreadCore
import SwiftUI

// MARK: - SortOption presentation

/// SwiftUI presentation for the Core `SortOption`, mirroring `AppearanceMode`
/// / `TextSize` (Core stays SwiftUI-free; the app target owns `title`/`systemImage`).
extension SortOption {
    /// Human-readable label shown in the settings picker.
    var title: LocalizedStringResource {
        switch self {
        case .default: LocalizedStringResource("Default", table: "Localizable", bundle: .main)
        case .priority: LocalizedStringResource("Priority", table: "Localizable", bundle: .main)
        case .dueDate: LocalizedStringResource("Due Date", table: "Localizable", bundle: .main)
        case .title: LocalizedStringResource("Title", table: "Localizable", bundle: .main)
        case .ai: LocalizedStringResource("AI", table: "Localizable", bundle: .main)
        }
    }

    /// SF Symbol shown alongside the label in the picker.
    var systemImage: String {
        switch self {
        case .default: "arrow.up.arrow.down"
        case .priority: "exclamationmark.3"
        case .dueDate: "calendar"
        case .title: "textformat.abc"
        case .ai: "sparkles"
        }
    }
}

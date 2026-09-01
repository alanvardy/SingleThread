import SingleThreadCore
import SwiftUI

// MARK: - SortOption presentation

/// SwiftUI presentation for the Core `SortOption`, mirroring `AppearanceMode`
/// / `TextSize` (Core stays SwiftUI-free; the app target owns `title`/`systemImage`).
extension SortOption {
    /// Human-readable label shown in the settings picker.
    var title: String {
        switch self {
        case .priority: String(localized: "Priority", table: "Localizable", bundle: .main)
        case .dueDate: String(localized: "Due Date", table: "Localizable", bundle: .main)
        case .title: String(localized: "Title", table: "Localizable", bundle: .main)
        }
    }

    /// SF Symbol shown alongside the label in the picker.
    var systemImage: String {
        switch self {
        case .priority: "exclamationmark.3"
        case .dueDate: "calendar"
        case .title: "textformat.abc"
        }
    }
}

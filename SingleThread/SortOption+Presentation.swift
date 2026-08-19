import SingleThreadCore
import SwiftUI

// MARK: - SortOption presentation

/// SwiftUI presentation for the Core `SortOption`, mirroring `AppearanceMode`
/// / `TextSize` (Core stays SwiftUI-free; the app target owns `title`/`systemImage`).
extension SortOption {
    /// Human-readable label shown in the settings picker.
    var title: String {
        switch self {
        case .priority: "Priority"
        case .dueDate: "Due Date"
        case .title: "Title"
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

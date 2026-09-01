import SwiftUI

// MARK: - CreationFeedback

/// Transient result of the dictate-and-save flow, shown as a full-color icon
/// bubble above the bottom bar for a beat before clearing itself.
enum CreationFeedback {
    case success
    case failure

    // MARK: Internal

    var systemImage: String {
        switch self {
        case .success: "checkmark"
        case .failure: "xmark"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .success: .green
        case .failure: .red
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .success: String(localized: "Task created", table: "Localizable", bundle: .main)
        case .failure: String(localized: "Task creation failed", table: "Localizable", bundle: .main)
        }
    }
}

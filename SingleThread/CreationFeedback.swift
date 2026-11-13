import SingleThreadCore
import SwiftUI

// MARK: - CreationFeedback

/// Transient result of the dictate-and-save flow, shown as a tinted toolbar
/// icon for a beat before clearing itself.
enum CreationFeedback {
    case success
    case failure

    // MARK: Internal

    /// Seconds the success/failure icon stays visible. Shared with the complete
    /// toolbar item's green flash (``CompletionFlash``) so both confirmations
    /// last the same beat.
    static let displayDuration: TimeInterval = 1.0

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
        case .success: LocalizedStringResource("Task created", table: "Localizable", bundle: .main)
            .resolvedInAppLanguage()
        case .failure: LocalizedStringResource("Task creation failed", table: "Localizable", bundle: .main)
            .resolvedInAppLanguage()
        }
    }
}

import Foundation
import SingleThreadCore

/// Chooses the glyph and accessibility label for the watch's Skip button based
/// on whether tapping it opens the three-action menu or skips the reminder
/// directly. Mirrors the iOS `skipButton` in `ContentView+ActionMenu.swift`;
/// `SwipeRevealPanel` is iOS-only, so the ellipsis symbol name is literal here.
enum WatchSkipButtonAppearance {
    nonisolated static func systemImage(opensActionMenu: Bool) -> String {
        opensActionMenu ? "ellipsis.circle.fill" : "circle.slash"
    }

    nonisolated static func accessibilityLabel(opensActionMenu: Bool) -> LocalizedStringResource {
        opensActionMenu ? SharedStrings.moreAction : SharedStrings.skipReminderAccessibility
    }
}

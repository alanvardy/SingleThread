import SwiftUI

// MARK: - Notifications (iOS)

// Notification scheduling handlers and the UI-test seam overlay. Kept in a
// separate extension so `ContentView`'s own body stays within SwiftLint's
// `type_body_length` budget.
#if os(iOS)
    extension ContentView {
        /// True only for the notifications scheduling UI test; exposes the pending /
        /// last-schedule status strings to the accessibility tree in that mode so an
        /// XCUITest can assert the app's real pending-notification state.
        var isNotificationsUITesting: Bool {
            ProcessInfo.processInfo.arguments.contains("--ui-testing-notifications")
        }

        /// UI-test seam: renders the pending/last-schedule notification status
        /// strings so an XCUITest can read the app's real pending state. Only
        /// ever present in the view hierarchy under `--ui-testing-notifications`
        /// (the call site gates on `isNotificationsUITesting`), so production
        /// and accessibility audits never see it.
        var notificationStatusOverlay: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(appViewModel?.pendingSummary ?? "unset")
                    .accessibilityIdentifier("pendingStatus")
                Text(appViewModel?.lastScheduleSummary ?? "unset")
                    .accessibilityIdentifier("lastScheduleStatus")
            }
            .font(.system(size: 1))
            .allowsHitTesting(false)
            .accessibilityHidden(!isNotificationsUITesting)
        }

        /// Requests notification authorization the first time the user flips the
        /// enable toggle ON, and cancels all pending requests when flipped OFF.
        func handleNotificationsEnabledChange(_ newValue: Bool) {
            if newValue {
                Task { await appViewModel?.requestNotificationPermissionIfNeeded() }
            } else {
                Task { await appViewModel?.cancelNotifications() }
            }
        }
    }
#endif

import EventKit
import SingleThreadCore
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

// MARK: - Skip-nudge sheet (iOS)

// The nudge sheet body (RescheduleSheet + View in Reminders / Delete) splits into
// multiple small @ViewBuilder members so SwiftLint's function-body length
// limit stays satisfied. Kept in a separate extension so `ContentView`'s own
// body stays within SwiftLint's `type_body_length` budget.
#if os(iOS)
    extension ContentView {
        /// The skip-nudge sheet body: the shared reschedule picker plus Delete /
        /// View in Reminders actions. Shown after the user taps the in-card
        /// nudge banner (6th skip).
        var nudgeSheetContent: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    RescheduleSheet(
                        reminder: nudgedReminder,
                        onReschedule: { [weak viewModel] components in
                            guard let viewModel else { return false }
                            return await viewModel.rescheduleNudgedReminder(to: components)
                        },
                        onCancel: { isShowingNudgeSheet = false },
                        nudgeMessage: "This reminder keeps coming back.")
                    nudgeViewInRemindersButton
                    nudgeDeleteButton
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isShowingNudgeSheet = false }
                    }
                }
            }
        }

        /// The reminder being nudged, resolved from the stored identifier so the
        /// sheet can tailor its picker (date-only vs date+time).
        private var nudgedReminder: EKReminder? {
            guard let identifier = viewModel.nudgeIdentifier else { return nil }
            return viewModel.store.visibleReminders.first {
                $0.calendarItemIdentifier == identifier
            }
        }

        /// Opens the nudged reminder in the system Reminders app via its deep link.
        /// Routes through the view model so the `--url-opener-spy` UI-test seam
        /// records and replays the URL (same pattern as the context-menu deep
        /// link), instead of calling `openURL` directly in the view.
        private var nudgeViewInRemindersButton: some View {
            Button {
                if let identifier = viewModel.nudgeIdentifier {
                    viewModel.openInReminders(identifier: identifier)
                    if isURLSpyUITesting {
                        lastOpenedURL = viewModel.lastOpenedURLForUITesting
                    }
                }
                isShowingNudgeSheet = false
            } label: {
                Label("View in Reminders", systemImage: "eye")
            }
            .accessibilityIdentifier("nudgeViewInRemindersButton")
        }

        /// Deletes the nudged reminder and closes the sheet (count resets).
        private var nudgeDeleteButton: some View {
            Button(role: .destructive) {
                Task {
                    await viewModel.deleteNudgedReminder()
                    isShowingNudgeSheet = false
                }
            } label: {
                Label(SharedStrings.deleteAction, systemImage: "trash")
            }
            .accessibilityIdentifier("nudgeDeleteButton")
        }
    }
#endif

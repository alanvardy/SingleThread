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

// The nudge sheet body (Reschedule / View in Reminders / Delete) splits into
// multiple small @ViewBuilder members so SwiftLint's function-body length
// limit stays satisfied. Kept in a separate extension so `ContentView`'s own
// body stays within SwiftLint's `type_body_length` budget.
#if os(iOS)
    extension ContentView {
        /// The skip-nudge sheet body: a reschedule date picker plus Delete / View
        /// in Reminders / Reschedule actions. Shown after the user taps the in-card
        /// nudge banner (6th skip).
        var nudgeSheetContent: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This reminder keeps coming back.")
                        .font(.headline)
                        .accessibilityIdentifier("nudgeSheetTitle")

                    DatePicker(
                        "Reschedule to",
                        selection: $rescheduleDate,
                        displayedComponents: [.date, .hourAndMinute])

                    nudgeRescheduleButton

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

        /// Reschedules the nudged reminder to the picked date, closing the sheet on
        /// success (the banner clears via the view-model hook).
        private var nudgeRescheduleButton: some View {
            Button {
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: rescheduleDate)
                Task {
                    if await viewModel.rescheduleNudgedReminder(to: components) {
                        isShowingNudgeSheet = false
                    }
                }
            } label: {
                Label("Reschedule", systemImage: "calendar")
            }
            .accessibilityIdentifier("nudgeRescheduleButton")
        }

        /// Opens the nudged reminder in the system Reminders app via its deep link.
        private var nudgeViewInRemindersButton: some View {
            Button {
                let identifier = viewModel.nudgeIdentifier
                if let identifier,
                   let url = ReminderDeepLink.url(forReminderIdentifier: identifier) {
                    openURL(url)
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

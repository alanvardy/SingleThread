import EventKit
import SingleThreadCore
import SwiftUI

// MARK: - Action Menu (iOS + macOS)

/// The toggle-gated three-action menu (Skip / Reschedule / Delete) replaces the
/// direct Skip button on the bottom bar when the user enabled the action-buttons
/// toggle. Kept in a sibling extension so `ContentView`'s own body stays within
/// SwiftLint's `type_body_length` budget (same split pattern as
/// `ContentView+iOS.swift`). The toggle-off path is behaviorally identical to
/// the pre-menu app: direct Skip, and on macOS a standalone Delete button.
extension ContentView {
    #if os(iOS)
        /// True when the Skip button should open the three-action menu instead
        /// of skipping directly: the user enabled the toggle, mutation is
        /// allowed, and a reminder is visible. All three gates are required.
        private var showActionMenu: Bool {
            ActionMenuGate.showsActionMenu(
                enableActionButtons: enableActionButtons,
                canMutate: viewModel.store.canMutate,
                hasVisibleReminder: viewModel.store.visibleReminders.first != nil)
        }

        /// The bottom-bar Skip button. When the action menu is gated open, the
        /// tap captures the visible reminder and presents the dialog instead of
        /// skipping directly. Internal (not `private`) so `actionCluster` in
        /// `ContentView.swift` can reference it across files, mirroring the
        /// `ContentView+iOS.swift` extension pattern.
        var skipButton: some View {
            Button {
                if showActionMenu {
                    actionMenuReminder = viewModel.store.visibleReminders.first
                    isShowingActionMenu = true
                } else {
                    viewModel.skipCurrentReminder()
                }
            } label: {
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
                    .controlPlate()
            }
            .accessibilityLabel(SharedStrings.skipReminderAccessibility)
            .accessibilityIdentifier("skipButton")
            .accessibilityAddTraits(.isButton)
            .confirmationDialog("Reminder", isPresented: $isShowingActionMenu) {
                Button(SharedStrings.skipAction) {
                    viewModel.skipCurrentReminder()
                }
                Button("Reschedule") {
                    isShowingActionMenu = false
                    isShowingRescheduleSheet = true
                }
                .accessibilityIdentifier("rescheduleButton")
                Button(SharedStrings.deleteAction, role: .destructive) {
                    Task { await viewModel.deleteCurrentReminder() }
                }
                .accessibilityIdentifier("deleteButton")
            }
        }

        /// The reminder the action menu was opened for; the sheet falls back to
        /// the visible reminder defensively (the dialog and the sheet are
        /// separate presentations, so the capture can be nil).
        private var actionMenuRescheduleReminder: EKReminder? {
            actionMenuReminder ?? viewModel.store.visibleReminders.first
        }
    #endif

    #if os(macOS)
        /// The bottom-bar cluster: Complete, then either the three-action Menu
        /// (toggle ON) or the direct Skip + standalone Delete (toggle OFF).
        /// The toggle lives in iOS Settings and syncs through the App Group;
        /// macOS reads the same suite so a phone-side toggle applies here too.
        var actionButtons: some View {
            HStack(spacing: 32) {
                if macShowActionMenu {
                    macCompleteButton
                    macActionMenu
                } else {
                    macCompleteButton
                    macSkipButton
                    macDeleteButton
                }
            }
            .padding(.bottom, 8)
        }

        private var macShowActionMenu: Bool {
            ActionMenuGate.showsActionMenu(
                enableActionButtons: AppGroup.defaults.bool(forKey: "enableActionButtons"),
                canMutate: viewModel.store.canMutate,
                hasVisibleReminder: viewModel.store.visibleReminders.first != nil)
        }

        private var macCompleteButton: some View {
            Button {
                Task { await viewModel.completeCurrentReminder() }
            } label: {
                Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
            }
            .tint(.green)
            .keyboardShortcut("c", modifiers: [])
            .accessibilityLabel(SharedStrings.completeReminderAccessibility)
            .accessibilityIdentifier("completeButton")
            .accessibilityAddTraits(.isButton)
        }

        private var macActionMenu: some View {
            Menu {
                Button(SharedStrings.skipAction) {
                    viewModel.skipCurrentReminder()
                }
                Button("Reschedule") {
                    isShowingRescheduleSheet = true
                }
                Button(SharedStrings.deleteAction, role: .destructive) {
                    Task { await viewModel.deleteCurrentReminder() }
                }
                .keyboardShortcut(.delete, modifiers: [])
            } label: {
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
                    .font(.title)
            }
            .tint(.orange)
            .keyboardShortcut("s", modifiers: [])
            .accessibilityLabel(SharedStrings.skipReminderAccessibility)
            .accessibilityIdentifier("skipButton")
            .accessibilityAddTraits(.isButton)
        }

        private var macSkipButton: some View {
            Button {
                viewModel.skipCurrentReminder()
            } label: {
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
                    .font(.title)
            }
            .tint(.orange)
            .keyboardShortcut("s", modifiers: [])
            .accessibilityLabel(SharedStrings.skipReminderAccessibility)
            .accessibilityIdentifier("skipButton")
            .accessibilityAddTraits(.isButton)
        }

        private var macDeleteButton: some View {
            Button {
                Task { await viewModel.deleteCurrentReminder() }
            } label: {
                Label(SharedStrings.deleteAction, systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .font(.title)
            }
            .tint(.red)
            .accessibilityLabel(SharedStrings.deleteReminderAccessibility)
            .accessibilityIdentifier("deleteButton")
            .accessibilityAddTraits(.isButton)
        }

        /// The reminder the action menu's reschedule sheet tailors its picker
        /// to. macOS has no captured reminder (the Menu has no tap-through), so
        /// the visible reminder is used directly.
        private var actionMenuRescheduleReminder: EKReminder? {
            viewModel.store.visibleReminders.first
        }
    #endif

    /// The reschedule sheet shared by iOS and macOS, wrapped in a
    /// `NavigationStack` with a Cancel toolbar item (the nudge sheet in
    /// `ContentView+iOS.swift` wraps `RescheduleSheet` the same way).
    var actionMenuRescheduleSheet: some View {
        NavigationStack {
            RescheduleSheet(
                reminder: actionMenuRescheduleReminder,
                onReschedule: { [weak viewModel] components in
                    guard let viewModel,
                          let id = viewModel.store.visibleReminders.first?.calendarItemIdentifier
                    else { return false }
                    return await viewModel.rescheduleReminder(identifier: id, to: components)
                },
                onCancel: { isShowingRescheduleSheet = false },
                nudgeMessage: nil)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isShowingRescheduleSheet = false }
                    }
                }
        }
    }
}

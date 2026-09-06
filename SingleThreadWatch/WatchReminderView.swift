import EventKit
import SingleThreadCore
import SwiftUI

struct WatchReminderView: View {
    // MARK: Lifecycle

    /// Accepts a pre-configured view model (production or preview).
    init(viewModel: WatchReminderViewModel) {
        self.viewModel = viewModel
    }

    /// Pre-populates state for canvas previews.
    init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus,
        hasHidden: Bool = false,
        showDateState: ShowDateState = ShowDateState(),
        showRecurrenceState: ShowRecurrenceState = ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState = ShowAlarmsState(),
        showListState: ShowListState = ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState = ShowCompletionGlowState(),
        entitlementState: EntitlementState = EntitlementState(),
        showEnableActionButtonsState: ShowEnableActionButtonsState = ShowEnableActionButtonsState()) {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: loadsReminders,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: authorizationStatus,
            hasHidden: hasHidden)
        viewModel = WatchReminderViewModel(
            store: store,
            showDateState: showDateState,
            showRecurrenceState: showRecurrenceState,
            showAlarmsState: showAlarmsState,
            showListState: showListState,
            showCompletionGlowState: showCompletionGlowState,
            entitlementState: entitlementState,
            showEnableActionButtonsState: showEnableActionButtonsState)
    }

    // MARK: Internal

    var body: some View {
        Group {
            switch viewModel.store.authorizationStatus {
            case .notDetermined:
                ProgressView(SharedStrings.requestingAccess)
            case .fullAccess:
                reminderContent
            default:
                Text("Enable Reminders access in Settings")
                    .multilineTextAlignment(.center)
            }
        }
        .task {
            await viewModel.task()
        }
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private let viewModel: WatchReminderViewModel

    /// True only for the completion-glow UI test; production always hides the
    /// overlay from accessibility (unchanged behavior for real users).
    private var isGlowUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-glow")
    }

    /// True when the Skip button presents the three-action menu instead of
    /// skipping directly: the phone-side action-buttons toggle is synced ON,
    /// mutation is allowed, and a reminder is visible. All three gates are
    /// required so the toggle-off path is identical to the pre-menu behavior.
    private var canShowActionMenu: Bool {
        viewModel.showEnableActionButtonsState.isEnabled
            && viewModel.store.canMutate
            && viewModel.store.visibleReminders.first != nil
    }

    // MARK: - Content

    private var reminderContent: some View {
        ZStack {
            if viewModel.isShowingCompletionTransition,
               let reminder = viewModel.transitionReminder {
                reminderCard(reminder)
            } else {
                switch viewModel.store.listContent {
                case .noAccess:
                    // Unreachable: `body` diverts non-.fullAccess before this
                    // renders. Required only for exhaustiveness — if auth ever
                    // collapses into the enum, this arm is the footgun to revisit.
                    EmptyView()
                case .allDone:
                    allDoneState
                case let .empty(hasHidden):
                    noRemindersState(hasHidden: hasHidden)
                case .reminder:
                    // `reminderCard` takes an `EKReminder`; don't bind the payload.
                    if let reminder = viewModel.store.visibleReminders.first {
                        reminderCard(reminder)
                    }
                }
            }

            if viewModel.isRefreshing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }
        }
        .overlay {
            if viewModel.completionGlow.isActive {
                completionGlowOverlay
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: viewModel.completionGlow.isActive)
    }

    private var actionButtons: some View {
        HStack {
            Button {
                Task { await viewModel.completeCurrentReminder() }
            } label: {
                Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .tint(.green)
            .accessibilityLabel(SharedStrings.completeReminderAccessibility)
            .accessibilityIdentifier("completeButton")
            .accessibilityAddTraits(.isButton)

            Button {
                if canShowActionMenu {
                    viewModel.isShowingActionMenu = true
                } else {
                    viewModel.store.skipCurrentReminder()
                }
            } label: {
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
            }
            .tint(.orange)
            .accessibilityLabel(SharedStrings.skipReminderAccessibility)
            .accessibilityIdentifier("skipButton")
            .accessibilityAddTraits(.isButton)
        }
    }

    /// Shown in place of the Complete/Skip buttons when the free-tier cap is
    /// exhausted on the phone and the entitlement flag has not synced. The watch
    /// itself has no StoreKit surface, so the user upgrades on the iPhone.
    private var upgradeOniPhonePrompt: some View {
        VStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.headline)
                .accessibilityHidden(true)
            Text("Upgrade on\nyour iPhone")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("upgradePrompt")
        }
        .frame(maxWidth: .infinity)
    }

    private var allDoneState: some View {
        VStack(spacing: 6) {
            Text(SharedStrings.allDone)
                .font(.headline)
                .accessibilityIdentifier("emptyStateTitle")
            refreshButton
        }
    }

    /// Decorative full-screen green flash. Passes touches through and stays out
    /// of the accessibility tree; fades via the `.animation` on `reminderContent`.
    /// During the completion-glow UI test the overlay is exposed to accessibility
    /// so an XCUITest can observe it.
    private var completionGlowOverlay: some View {
        Color.green
            .opacity(0.3)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(!isGlowUITesting)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("completionGlowOverlay")
            .accessibilityLabel(SharedStrings.completionGlow)
            .transition(.opacity)
    }

    private var refreshButton: some View {
        Button("Refresh") {
            Task { await viewModel.refresh(clearSkipped: viewModel.store.allSkipped) }
        }
        .disabled(viewModel.isRefreshing)
        .accessibilityIdentifier("refreshButton")
    }

    /// The three action-menu buttons presented in the Skip confirmation dialog:
    /// Skip, Reschedule (opens the reschedule sheet), and Delete.
    @ViewBuilder private var actionMenuDialogButtons: some View {
        Button(SharedStrings.skipAction) {
            viewModel.store.skipCurrentReminder()
        }
        Button("Reschedule") {
            viewModel.isShowingActionMenu = false
            viewModel.isShowingRescheduleSheet = true
        }
        Button(SharedStrings.deleteAction, role: .destructive) {
            Task { await viewModel.store.deleteCurrentReminder() }
        }
    }

    private func noRemindersState(hasHidden: Bool) -> some View {
        VStack(spacing: 6) {
            Text(SharedStrings.noReminders)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("emptyStateTitle")
            Text(hasHidden ? SharedStrings.nothingDueRightNow : SharedStrings.noRemindersYet)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            refreshButton
        }
    }

    /// The reminder is always scrollable so long titles and notes are never cut off.
    private func reminderCard(_ reminder: EKReminder) -> some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                let display = ReminderDisplay(reminder: reminder)
                reminderDetails(display)
            }
            .onTapGesture {
                Task { await viewModel.refreshFromCardTap() }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                Task { await viewModel.refreshFromCardTap() }
            }
            .accessibilityIdentifier("reminderCard")

            if viewModel.isNudged(reminder.calendarItemIdentifier) {
                Button {
                    viewModel.isShowingNudgeDialog = true
                } label: {
                    Label(SharedStrings.skipNudgeTitle, systemImage: "exclamationmark.bubble")
                        .font(.caption)
                }
                .accessibilityIdentifier("skipNudgeBanner")
                .confirmationDialog(SharedStrings.skipNudgeTitle, isPresented: $viewModel.isShowingNudgeDialog) {
                    Button(SharedStrings.deleteAction, role: .destructive) {
                        Task { await viewModel.store.deleteCurrentReminder() }
                    }
                    .accessibilityIdentifier("nudgeDeleteButton")
                }
            }

            if !viewModel.store.canMutate, !viewModel.entitlementState.isEnabled {
                upgradeOniPhonePrompt
            } else {
                actionButtons
            }
        }
        .padding()
        .confirmationDialog("Reminder", isPresented: $viewModel.isShowingActionMenu) {
            actionMenuDialogButtons
        }
        .sheet(isPresented: $viewModel.isShowingRescheduleSheet) {
            actionMenuRescheduleSheet()
        }
    }

    /// The Reschedule sheet body: a date-only picker plus a confirm button,
    /// wrapped in a NavigationStack with a Cancel toolbar item. Confirming
    /// fires the watch→phone reschedule relay (``ReminderStore`` watchOS
    /// branch → `onRescheduleReminder`). Kept out of `reminderCard` so that
    /// function stays within SwiftLint's 50-line body limit.
    private func actionMenuRescheduleSheet() -> some View {
        @Bindable var viewModel = viewModel
        return NavigationStack {
            VStack(spacing: 12) {
                DatePicker(
                    "Reschedule to",
                    selection: $viewModel.rescheduleDate,
                    displayedComponents: [.date])
                Button("Reschedule") {
                    let components = Calendar.current.dateComponents(
                        [.year, .month, .day],
                        from: viewModel.rescheduleDate)
                    if let id = viewModel.store.visibleReminders.first?.calendarItemIdentifier {
                        Task {
                            await viewModel.store.rescheduleReminder(identifier: id, to: components)
                            viewModel.isShowingRescheduleSheet = false
                        }
                    } else {
                        viewModel.isShowingRescheduleSheet = false
                    }
                }
                .accessibilityIdentifier("rescheduleConfirmButton")
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.isShowingRescheduleSheet = false }
                }
            }
        }
    }

    private func reminderDetails(_ display: ReminderDisplay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let level = ReminderPriority.level(forMarker: display.priorityMarker) {
                    Text(display.priorityMarker)
                        .font(.headline)
                        .foregroundStyle(priorityColor(level))
                        .accessibilityLabel(SharedStrings.priorityAccessibilityLabel(level.displayName))
                        .accessibilityIdentifier("priorityMarker")
                }
                Text(display.titleAttributed)
                    .font(.headline)
            }
            if viewModel.showDateState.isEnabled, let due = display.dueDate {
                Text(due, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if viewModel.showListState.isEnabled, let listName = display.listName {
                Text(listName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if viewModel.showRecurrenceState.isEnabled, display.hasRecurrence {
                Label(display.recurrenceSummary ?? SharedStrings.repeats, systemImage: "repeat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if viewModel.showAlarmsState.isEnabled, display.hasAlarms {
                Label(SharedStrings.alert, systemImage: "bell")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let notesAttr = display.notesAttributed {
                Text(notesAttr)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func priorityColor(_ level: ReminderPriority.Level) -> Color {
        switch level {
        case .low: .green
        case .medium: .yellow
        case .high: .red
        }
    }
}

// MARK: - Previews

/// A single `EKEventStore` kept alive to back the preview reminders. The
/// backing store must outlive the reminders — `EKReminder` holds a weak
/// reference to it, so a deallocated store crashes canvas with SIGTRAP.
private let mockWatchEventStore = EKEventStore()

private let mockWatchReminder: EKReminder = {
    let reminder = EKReminder(eventStore: mockWatchEventStore)
    reminder.title = "Buy groceries"
    reminder.priority = 5
    reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 18, hour: 14, minute: 0)
    reminder.notes = "Don't forget the milk"
    return reminder
}()

private let mockWatchReminderWithCode: EKReminder = {
    let reminder = EKReminder(eventStore: mockWatchEventStore)
    reminder.title = "Use `map` and `filter`"
    reminder.priority = 5
    reminder.notes = "```\nlet x = 1\nlet y = 2\n```"
    return reminder
}()

#Preview("Requesting Access") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .notDetermined)
}

#Preview("Reminder") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [mockWatchReminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
}

#Preview("Code Spans") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [mockWatchReminderWithCode],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
}

#Preview("All Skipped") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [mockWatchReminder],
        skippedIDs: [mockWatchReminder.calendarItemIdentifier],
        authorizationStatus: .fullAccess)
}

#Preview("No Reminders") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
}

#Preview("Nothing Due") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .fullAccess,
        hasHidden: true)
}

#Preview("No Access") {
    WatchReminderView(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .denied)
}

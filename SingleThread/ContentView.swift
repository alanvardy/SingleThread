// The settings bag plumbing and (Phase 4) undo overlay keep this file above
// the `file_length` warning threshold (650) and the `type_body_length`
// threshold (500); the value drives the entire single-screen UI so the view
// modifiers stay in one spot.
// swiftlint:disable file_length
import EventKit
import SingleThreadCore
import Speech
import SwiftUI

// The single-screen UI keeps every view modifier in one struct; the undo
// overlay pushes it just past 500 lines.
// swiftlint:disable:next type_body_length
struct ContentView: View {
    // MARK: Lifecycle

    init(viewModel: ContentViewModel, appViewModel: AppViewModel? = nil) {
        self.viewModel = viewModel
        #if os(iOS)
            self.appViewModel = appViewModel
        #endif
    }

    /// Pre-populates state for canvas previews.
    init(
        loadsReminders: Bool = true,
        eventStore: any EventKitStoring = EKEventStore(),
        speechTranscriber: (any SpeechTranscribing)? = nil,
        backgroundImage: BackgroundImageStore = BackgroundImageStore()) {
        viewModel = ContentViewModel(
            store: ReminderStore(eventStore: eventStore, loadsReminders: loadsReminders),
            backgroundImage: backgroundImage,
            speechTranscriber: speechTranscriber ?? ReminderDictation())
        #if os(iOS)
            appViewModel = nil
        #endif
    }

    /// Pre-populates state for canvas previews.
    init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus,
        excludedListTitles: Set<String> = [],
        hasHidden: Bool = false,
        speechTranscriber: (any SpeechTranscribing)? = nil,
        backgroundImage: BackgroundImageStore = BackgroundImageStore()) {
        viewModel = ContentViewModel(
            store: ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: loadsReminders,
                reminders: reminders,
                skippedIDs: skippedIDs,
                authorizationStatus: authorizationStatus,
                excludedListTitles: excludedListTitles,
                hasHidden: hasHidden),
            backgroundImage: backgroundImage,
            speechTranscriber: speechTranscriber ?? ReminderDictation())
        #if os(iOS)
            appViewModel = nil
        #endif
    }

    // MARK: Internal

    var body: some View {
        ZStack {
            Color.systemBackground.ignoresSafeArea()
            #if os(iOS)
                BackgroundPhotoLayer(
                    imageData: viewModel.backgroundImage.imageData,
                    isEnabled: backgroundEnabled,
                    opacity: BackgroundFade.opacity(for: backgroundFadePercent))
            #endif
            if viewModel.store.loadsReminders {
                authGatedContent
            } else {
                reminderList
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                settingsBag = makeSettingsBag()
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .controlPlate()
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
            .accessibilityAddTraits(.isButton)
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        #if os(iOS)
        .overlay(alignment: .topLeading) {
            if viewModel.store.undoStore.hasUndoableReminder, showUndoButton, viewModel.store.canMutate {
                Button {
                    Task { await viewModel.undoLastCompletion() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3)
                        .controlPlate()
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Undo completion")
                .accessibilityAddTraits(.isButton)
                .padding(.top, 8)
                .padding(.leading, 12)
            }
        }
        #endif
        .overlay {
            if viewModel.completionGlow.isActive {
                completionGlowOverlay
            }
        }
        .overlay(alignment: .topLeading) {
            #if os(iOS)
                if isNotificationsUITesting {
                    notificationStatusOverlay
                }
            #endif
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: viewModel.completionGlow.isActive)
        #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
        #endif
        .task {
            await viewModel.backgroundImage.setPinned(backgroundPinned)
            await viewModel.task(showUndatedReminders: showUndatedReminders)
        }
        .onChange(of: backgroundPinned) { _, newValue in
            setBackgroundPinned(newValue)
        }
        .onChange(of: showUndatedReminders) { _, newValue in
            viewModel.handleShowUndatedReminders(newValue)
        }
        .onChange(of: sortOption) { _, newValue in
            viewModel.handleSortOption(newValue)
        }
        .onChange(of: appearanceMode) { _, newValue in
            viewModel.handleAppearanceMode(newValue)
        }
        #if os(iOS)
        .onChange(of: notificationsEnabled) { _, newValue in
            handleNotificationsEnabledChange(newValue)
        }
        #endif
        .modifier(TextSizeModifier(textSize: textSize))
        .onChange(of: isShowingSettings) { _, showing in
            // Nil the bag on dismiss so a fresh one is created next open.
            // The bag is built in the gear-button action before the flag
            // flips, so it is never nil when the sheet first renders.
            if !showing {
                settingsBag = nil
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            settingsSheetContent
        }
        .sheet(isPresented: $isShowingPurchase) {
            PurchaseSheet(
                isPresented: $isShowingPurchase,
                entitlementStore: viewModel.store.entitlementStore)
        }

    // MARK: Private

    // MARK: - Creation Feedback

    @AppStorage("appearanceMode")
    private var appearanceMode = AppearanceMode.system

    @AppStorage("textSize")
    private var textSize = TextSize.system

    #if os(iOS)
        @AppStorage("allowsLandscape")
        private var allowsLandscape = true
    #endif

    @AppStorage("showMicrophoneButton")
    private var showMicrophoneButton = true

    @AppStorage("backgroundEnabled", store: .standard)
    private var backgroundEnabled = true

    @AppStorage("backgroundFadePercent", store: .standard)
    private var backgroundFadePercent = BackgroundFade.defaultValue

    @AppStorage("backgroundPinned", store: .standard)
    private var backgroundPinned = false

    #if os(iOS)
        @AppStorage("enableActionButtons")
        private var enableActionButtons = false
    #endif

    #if os(iOS)
        @AppStorage("showSwipePrompt")
        private var showSwipePrompt = true
    #endif

    #if os(iOS)
        @AppStorage("showUndoButton")
        private var showUndoButton = true

        @AppStorage("notificationsEnabled")
        private var notificationsEnabled = false

        @AppStorage("notificationIntervalHours")
        private var notificationIntervalHours = 48
    #endif
    @AppStorage("showUndatedReminders", store: AppGroup.defaults)
    private var showUndatedReminders = false

    @AppStorage(SortOption.defaultsKey, store: AppGroup.defaults)
    private var sortOption = SortOption.priority

    @AppStorage("showDate", store: AppGroup.defaults)
    private var showDate = true

    @AppStorage("showList", store: AppGroup.defaults)
    private var showList = false

    @AppStorage("showRecurrence", store: AppGroup.defaults)
    private var showRecurrence = true
    @AppStorage("showAlarms", store: AppGroup.defaults)
    private var showAlarms = true

    @AppStorage("showCompletionGlow", store: AppGroup.defaults)
    private var showCompletionGlow = true

    @State private var isShowingSettings = false

    /// Drives the freemium upgrade-prompt sheet (shown only when the free tier
    /// cap is exhausted and the user has not purchased the unlock IAP).
    @State private var isShowingPurchase = false

    /// Stable bag of settings bindings for the currently presented sheet.
    /// Recreated when the sheet opens so it reflects the latest persisted
    /// values, then kept alive for the sheet's lifetime so edits done inside
    /// don't snap back when `ContentView` re-evaluates its body.
    @State private var settingsBag: SettingsBindings?

    @Environment(\.openURL)
    private var openURL

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Environment(\.scenePhase)
    private var scenePhase

    private let viewModel: ContentViewModel

    #if os(iOS)
        private let appViewModel: AppViewModel?
    #endif

    private var excludedListsBinding: Binding<Set<String>> {
        Binding(
            get: { viewModel.store.excludedListTitles },
            set: { viewModel.setExcludedListTitles($0) })
    }

    /// True only for the completion-glow UI test; production always hides the
    /// overlay from accessibility (unchanged behavior for real users).
    private var isGlowUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-glow")
    }

    /// iOS-only `showSwipePrompt` preference: other platforms never show the
    /// swipe prompt, so they get a constant false binding.
    private var swipePromptBinding: Binding<Bool> {
        #if os(iOS)
            $showSwipePrompt
        #else
            .constant(false)
        #endif
    }

    #if os(macOS)
        private var actionButtons: some View {
            HStack(spacing: 32) {
                Button {
                    Task { await viewModel.completeCurrentReminder() }
                } label: {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title)
                }
                .tint(.green)
                .keyboardShortcut("c", modifiers: [])
                .accessibilityLabel("Complete reminder")
                .accessibilityAddTraits(.isButton)

                Button {
                    viewModel.skipCurrentReminder()
                } label: {
                    Label("Skip", systemImage: "circle.slash")
                        .labelStyle(.iconOnly)
                        .font(.title)
                }
                .tint(.orange)
                .keyboardShortcut("s", modifiers: [])
                .accessibilityLabel("Skip reminder")
                .accessibilityAddTraits(.isButton)

                Button {
                    Task { await viewModel.deleteCurrentReminder() }
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .font(.title)
                }
                .tint(.red)
                .accessibilityLabel("Delete reminder")
                .accessibilityAddTraits(.isButton)
            }
            .padding(.bottom, 8)
        }
    #endif

    @ViewBuilder private var authGatedContent: some View {
        switch viewModel.store.authorizationStatus {
        case .notDetermined:
            ProgressView("Requesting access…")
        case .fullAccess:
            reminderList
        default:
            ContentUnavailableView(
                "Reminders Access",
                systemImage: "lock.shield",
                description: Text("Enable access in Settings to see your reminders."))
        }
    }

    private var reminderList: some View {
        GeometryReader { geometry in
            let viewHeight = geometry.size.height
                - geometry.safeAreaInsets.top
                - geometry.safeAreaInsets.bottom
            if viewModel.store.allSkipped {
                let allDoneCopy = ContentViewModel.allDoneStateCopy()
                ScrollView {
                    ContentUnavailableView(
                        allDoneCopy.title,
                        systemImage: allDoneCopy.systemImage,
                        description: Text(allDoneCopy.description))
                        .frame(minHeight: viewHeight, alignment: .center)
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await viewModel.reload(clearSkipped: true)
                }
            } else if viewModel.store.reminders.isEmpty {
                let emptyCopy = ContentViewModel.emptyStateCopy(hasHidden: viewModel.store.hasHidden)
                ZStack(alignment: .bottom) {
                    ScrollView {
                        ContentUnavailableView(
                            emptyCopy.title,
                            systemImage: emptyCopy.systemImage,
                            description: Text(emptyCopy.description))
                            .frame(minHeight: viewHeight, alignment: .center)
                    }
                    .scrollBounceBehavior(.always)
                    .refreshable {
                        await viewModel.reload()
                    }
                    bottomBar
                }
            } else {
                ZStack(alignment: .bottom) {
                    List {
                        if let reminder = viewModel.store.visibleReminders.first {
                            ReminderCardView(
                                display: ReminderDisplay(reminder: reminder),
                                showDate: showDate,
                                showList: showList,
                                showRecurrence: showRecurrence,
                                showAlarms: showAlarms,
                                showSwipePrompt: swipePromptBinding)
                                .listRowBackground(viewModel.rowChromeBackground)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 12)
                                // Center the card's plate in the row; text inside
                                // stays leading-aligned via the card's VStack.
                                .frame(maxWidth: .infinity, alignment: .center)
                                .frame(minHeight: viewHeight, alignment: .center)
                                .listRowSeparator(.hidden)
                            #if os(iOS)
                                .contextMenu {
                                    Button {
                                        let deepLink = ReminderDeepLink.url(
                                            forReminderIdentifier: reminder.calendarItemIdentifier)
                                        if let url = deepLink {
                                            openURL(url)
                                        }
                                    } label: {
                                        Label("View in Reminders", systemImage: "eye")
                                    }

                                    Button {
                                        Task { await viewModel.deleteCurrentReminder() }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            #endif
                                .swipeActions(edge: .leading) {
                                    Button {
                                        Task { await viewModel.completeCurrentReminder() }
                                    } label: {
                                        Label("Complete", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        viewModel.skipCurrentReminder()
                                    } label: {
                                        Label("Skip", systemImage: "circle.slash")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                    .listStyle(.plain)
                    // iPadOS gives `List` an opaque scroll-content background by
                    // default, which would hide the photo. Hide it so the photo
                    // (or the system background when none is shown) shows through.
                    .scrollContentBackground(.hidden)
                    // Clear the List's own background too — after the scroll-content
                    // hide, so it wins on iPadOS 18 regardless of which layer is opaque.
                    .background(Color.clear)
                    .refreshable {
                        await viewModel.reload()
                    }
                    bottomBar
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            #if os(macOS)
                if viewModel.store.visibleReminders.first != nil {
                    actionButtons
                }
            #endif
            if let error = viewModel.dictation.dictationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            if let feedback = viewModel.dictation.creationFeedback {
                creationFeedbackView(for: feedback)
            } else if viewModel.dictation.isDictating {
                if !viewModel.dictation.dictationText.isEmpty {
                    Text(viewModel.dictation.dictationText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                recordingIndicator
            } else if viewModel.dictation.canDictate, showMicrophoneButton {
                #if os(iOS)
                    if !viewModel.store.canMutate {
                        upgradePrompt
                    } else if viewModel.showsActionButtons {
                        actionCluster
                    } else {
                        micButton
                    }
                #else
                    micButton
                #endif
            }
        }
        .padding(.bottom, 16)
    }

    #if os(iOS)
        private var completeButton: some View {
            Button {
                Task { await viewModel.completeCurrentReminder() }
            } label: {
                Label("Complete", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .controlPlate()
            }
            .accessibilityLabel("Complete reminder")
            .accessibilityAddTraits(.isButton)
        }

        private var skipButton: some View {
            Button {
                viewModel.skipCurrentReminder()
            } label: {
                Label("Skip", systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
                    .controlPlate()
            }
            .accessibilityLabel("Skip reminder")
            .accessibilityAddTraits(.isButton)
        }

        private var actionCluster: some View {
            HStack(alignment: .center, spacing: 16) {
                completeButton
                micButton
                skipButton
            }
        }

        /// Shown when the free tier is gated (cap exhausted, no purchase).
        private var upgradePrompt: some View {
            UpgradePromptButton(isPresented: $isShowingPurchase)
        }
    #endif

    // MARK: - Mic Dictation

    private var micButton: some View {
        Button {
            Task { await viewModel.dictation.startDictation() }
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .controlPlate()
        }
        .accessibilityLabel("Dictate reminder")
        .accessibilityAddTraits(.isButton)
    }

    private var recordingIndicator: some View {
        Image(systemName: "mic.fill")
            .font(.title2)
            .controlPlate(fill: .red, glyph: .white)
            .symbolEffect(.pulse, options: .repeating)
            .accessibilityLabel("Recording")
    }

    /// Decorative full-screen green flash shown after a successful completion.
    /// Passes touches through and stays out of the accessibility tree; fades via
    /// the `.animation` on `body`. During the completion-glow UI test the overlay
    /// is exposed to the accessibility tree so an XCUITest can observe it.
    private var completionGlowOverlay: some View {
        Color.green
            .opacity(0.1)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(!isGlowUITesting)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("completionGlowOverlay")
            .accessibilityLabel("Completion glow")
            .transition(.opacity)
    }

    /// The Settings sheet body: `SettingsView` wrapped in the bag → @AppStorage
    /// write-back chain. Lives in its own functions so the long `.onChange`
    /// chain has its own type-check budget instead of blowing up `body`'s
    /// single expression.
    @ViewBuilder private var settingsSheetContent: some View {
        if let bag = settingsBag {
            settingsSheetWritebacks(bag)
        }
    }

    /// Builds the Settings sheet content. The write-back chain is split into
    /// staged values so each expression stays within the compiler's type-check
    /// budget (a single 17-modifier chain does not).
    private func settingsSheetWritebacks(_ bag: SettingsBindings) -> some View {
        let withAppearance = SettingsView(
            bindings: bag,
            backgroundImage: viewModel.backgroundImage,
            availableLists: viewModel.store.availableLists,
            excludedLists: excludedListsBinding,
            entitlementStore: viewModel.store.entitlementStore,
            viewModel: SettingsViewModel())
            // The bag is a plain in-memory holder; write each changed value
            // back to the @AppStorage-backed property so settings survive
            // relaunch (mirrors the old direct-bind behavior).
            .onChange(of: bag.appearanceMode) { _, new in appearanceMode = new }
            .onChange(of: bag.textSize) { _, new in textSize = new }
        #if os(iOS)
            let withIOSPreferences = withAppearance
                .onChange(of: bag.allowsLandscape) { _, new in allowsLandscape = new }
                .onChange(of: bag.enableActionButtons) { _, new in enableActionButtons = new }
                .onChange(of: bag.showSwipePrompt) { _, new in showSwipePrompt = new }
                .onChange(of: bag.showUndoButton) { _, new in showUndoButton = new }
                .onChange(of: bag.notificationsEnabled) { _, new in notificationsEnabled = new }
                .onChange(of: bag.notificationIntervalHours) { _, new in notificationIntervalHours = new }
        #else
            let withIOSPreferences = withAppearance
        #endif
        return withIOSPreferences
            .onChange(of: bag.showMicrophoneButton) { _, new in showMicrophoneButton = new }
            .onChange(of: bag.backgroundEnabled) { _, new in backgroundEnabled = new }
            .onChange(of: bag.backgroundFadePercent) { _, new in backgroundFadePercent = new }
            .onChange(of: bag.showUndatedReminders) { _, new in showUndatedReminders = new }
            .onChange(of: bag.sortOption) { _, new in sortOption = new }
            .onChange(of: bag.showDate) { _, new in showDate = new }
            .onChange(of: bag.showList) { _, new in showList = new }
            .onChange(of: bag.showRecurrence) { _, new in showRecurrence = new }
            .onChange(of: bag.showAlarms) { _, new in showAlarms = new }
            .onChange(of: bag.showCompletionGlow) { _, new in showCompletionGlow = new }
    }

    private func creationFeedbackView(for feedback: CreationFeedback) -> some View {
        Image(systemName: feedback.systemImage)
            .font(.title2)
            .controlPlate(fill: feedback.backgroundColor, glyph: .white)
            .accessibilityLabel(feedback.accessibilityLabel)
    }

    /// Dispatches the async pin-state change off the sync modifier closure.
    /// Extracted so the long `body` modifier chain still type-checks.
    private func setBackgroundPinned(_ pinned: Bool) {
        Task { await viewModel.backgroundImage.setPinned(pinned) }
    }

    /// Builds a fresh bindings bag from the current `@AppStorage`-backed
    /// preference values.
    @MainActor
    private func makeSettingsBag() -> SettingsBindings {
        #if os(iOS)
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                allowsLandscape: allowsLandscape,
                enableActionButtons: enableActionButtons,
                showSwipePrompt: showSwipePrompt,
                showUndoButton: showUndoButton,
                notificationsEnabled: notificationsEnabled,
                notificationIntervalHours: notificationIntervalHours,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                backgroundFadePercent: backgroundFadePercent,
                backgroundPinned: backgroundPinned,
                showUndatedReminders: showUndatedReminders,
                sortOption: sortOption,
                showDate: showDate,
                showList: showList,
                showRecurrence: showRecurrence,
                showAlarms: showAlarms,
                showCompletionGlow: showCompletionGlow)
        #else
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                backgroundFadePercent: backgroundFadePercent,
                backgroundPinned: backgroundPinned,
                showUndatedReminders: showUndatedReminders,
                sortOption: sortOption,
                showDate: showDate,
                showList: showList,
                showRecurrence: showRecurrence,
                showAlarms: showAlarms,
                showCompletionGlow: showCompletionGlow)
        #endif
    }
}

// MARK: - Notifications (iOS)

// Notification scheduling handlers and the UI-test seam overlay. Kept in a
// separate extension so `ContentView`'s own body stays within SwiftLint's
// `type_body_length` budget.
#if os(iOS)
    private extension ContentView {
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

        /// Routes scene-phase transitions into the notification engine: schedule on
        /// background, cancel on foreground. No-op on non-iOS platforms (the feature
        /// is iOS-only).
        func handleScenePhaseChange(_ phase: ScenePhase) {
            guard let appViewModel else { return }
            switch phase {
            case .background:
                Task { await appViewModel.scheduleNotificationIfNeeded() }
            case .active:
                Task { await appViewModel.cancelNotifications() }
            default:
                break
            }
        }

        /// Requests notification authorization the first time the user flips the
        /// enable toggle ON. A no-op once the status is already determined.
        func handleNotificationsEnabledChange(_ newValue: Bool) {
            if newValue {
                Task { await appViewModel?.requestNotificationPermissionIfNeeded() }
            }
        }
    }
#endif

// MARK: - Preview Helpers

/// A single `EKEventStore` kept alive to back the preview reminders. The
/// backing store must outlive the reminders — `EKReminder` holds a weak
/// reference to it, so a deallocated store crashes canvas with SIGTRAP.
private let mockPreviewEventStore = EKEventStore()

private let mockReminder: EKReminder = {
    let reminder = EKReminder(eventStore: mockPreviewEventStore)
    reminder.title = "Buy groceries"
    reminder.priority = 5
    reminder.dueDateComponents = DateComponents(year: 2024, month: 9, day: 15, hour: 14, minute: 0)
    reminder.notes = "Don't forget the milk"
    reminder.url = URL(string: "https://example.com/shopping-list")
    reminder.addRecurrenceRule(EKRecurrenceRule(
        recurrenceWith: .weekly, interval: 1, end: nil))
    return reminder
}()

private let mockReminderInList: EKReminder = {
    let calendar = EKCalendar(for: .reminder, eventStore: mockPreviewEventStore)
    calendar.title = "Groceries"
    let reminder = EKReminder(eventStore: mockPreviewEventStore)
    reminder.title = "Buy milk"
    reminder.calendar = calendar
    return reminder
}()

// MARK: - Previews

#Preview("Empty") {
    ContentView(
        loadsReminders: false,
        eventStore: InMemoryEventStore())
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

#Preview("Nothing Due") {
    ContentView(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .fullAccess,
        hasHidden: true)
}

#Preview("With Reminder") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

#Preview("All Skipped") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminder],
        skippedIDs: [mockReminder.calendarItemIdentifier],
        authorizationStatus: .fullAccess)
}

#Preview("All Excluded") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminderInList],
        skippedIDs: [],
        authorizationStatus: .fullAccess,
        excludedListTitles: ["Groceries"])
}

#Preview("No Access") {
    ContentView(
        loadsReminders: true,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .denied)
}

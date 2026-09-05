// The single-screen UI concentrates its view modifiers in this struct, with
// non-view plumbing (settings bag, iOS notifications) and canvas previews
// decomposed into sibling `ContentView+*.swift` extension files so this file
// stays under the `file_length` (650) and `type_body_length` (500) thresholds.
// The scene-phase wiring and the explanatory bottom bar (VAR-747) push the
// file back over 650 lines; the value drives the whole single-screen UI so
// its modifiers stay in this one spot.
// swiftlint:disable file_length
#if os(iOS)
    import UIKit
#endif
import EventKit
import SingleThreadCore
import Speech
import SwiftUI

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

    // MARK: - Creation Feedback

    @AppStorage("appearanceMode")
    var appearanceMode = AppearanceMode.system

    @AppStorage("textSize")
    var textSize = TextSize.system

    #if os(iOS)
        @AppStorage("allowsLandscape")
        var allowsLandscape = true
    #endif

    @AppStorage("showMicrophoneButton")
    var showMicrophoneButton = true

    @AppStorage("backgroundEnabled", store: .standard)
    var backgroundEnabled = true

    @AppStorage("backgroundFadePercent", store: .standard)
    var backgroundFadePercent = BackgroundFade.defaultValue

    @AppStorage("backgroundPinned", store: .standard)
    var backgroundPinned = false

    #if os(iOS)
        @AppStorage("enableActionButtons")
        var enableActionButtons = false
    #endif

    #if os(iOS)
        @AppStorage("showSwipePrompt")
        var showSwipePrompt = true
    #endif

    #if os(iOS)
        @AppStorage("showUndoButton")
        var showUndoButton = true

        @AppStorage(AppViewModel.NotificationKeys.enabled)
        var notificationsEnabled = false

        @AppStorage(AppViewModel.NotificationKeys.intervalHours)
        var notificationIntervalHours = 48
    #endif
    @AppStorage("showUndatedReminders", store: AppGroup.defaults)
    var showUndatedReminders = false

    @AppStorage(SortOption.defaultsKey, store: AppGroup.defaults)
    var sortOption = SortOption.priority

    @AppStorage("showDate", store: AppGroup.defaults)
    var showDate = true

    @AppStorage("showList", store: AppGroup.defaults)
    var showList = false

    @AppStorage("showRecurrence", store: AppGroup.defaults)
    var showRecurrence = true
    @AppStorage("showAlarms", store: AppGroup.defaults)
    var showAlarms = true

    @AppStorage("showCompletionGlow", store: AppGroup.defaults)
    var showCompletionGlow = true

    /// Drives the skip-nudge sheet (iOS only), shown when the user taps the
    /// in-card nudge banner after a reminder has been skipped 6 times.
    @State var isShowingNudgeSheet = false

    /// The due date the nudge sheet's reschedule action writes to, defaulting
    /// to tomorrow so the sheet is pre-populated with a valid date.
    @State var rescheduleDate = Date().addingTimeInterval(86400)

    // Deep link last opened via the ``--url-opener-spy`` UI-test seam. Rendered
    // back as an accessible element so an XCUITest can read it. Always nil in
    // production (the spy launch arg is absent), so this never affects real
    // users.
    #if os(iOS)
        @State var lastOpenedURL: String?
    #endif

    #if os(iOS)
        let appViewModel: AppViewModel?
    #endif

    let viewModel: ContentViewModel

    var excludedListsBinding: Binding<Set<String>> {
        Binding(
            get: { viewModel.store.excludedListTitles },
            set: { viewModel.setExcludedListTitles($0) })
    }

    /// True only under the `--url-opener-spy` UI-test seam; production never
    /// renders (or reads) the deep-link spy element. Internal (not `private`)
    /// so the iOS-only nudge sheet in `ContentView+iOS.swift` can replay the
    /// spy URL back to the overlay.
    var isURLSpyUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--url-opener-spy")
    }

    var body: some View {
        ZStack {
            Color.systemBackground.ignoresSafeArea()
            BackgroundPhotoLayer(
                imageData: viewModel.backgroundImage.imageData,
                isEnabled: backgroundEnabled,
                opacity: BackgroundFade.opacity(for: backgroundFadePercent))
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
            .accessibilityIdentifier("settingsButton")
            .accessibilityAddTraits(.isButton)
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        #if os(macOS)
        .overlay(alignment: .topLeading) {
            Button {
                Task { await viewModel.refreshManual() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .controlPlate()
            }
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
            .accessibilityIdentifier("refreshButton")
            .accessibilityAddTraits(.isButton)
            .padding(.top, 8)
            .padding(.leading, 12)
        }
        #endif
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
                .accessibilityIdentifier("undoButton")
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
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
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
        #if os(iOS)
        .sheet(isPresented: $isShowingNudgeSheet, onDismiss: { viewModel.dismissNudge() }) {
            nudgeSheetContent
        }
        .overlay {
            if isURLSpyUITesting,
               let url = lastOpenedURL {
                Text("spyURL-\(url)")
                    .opacity(0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("lastOpenedURL")
                    .accessibilityLabel("spyURL-\(url)")
            }
        }
        #endif
    }

    // MARK: Private

    @State private var isShowingSettings = false

    /// Drives the freemium upgrade-prompt sheet (shown only when the free tier
    /// cap is exhausted and the user has not purchased the unlock IAP).
    @State private var isShowingPurchase = false

    /// Stable bag of settings bindings for the currently presented sheet.
    /// Recreated when the sheet opens so it reflects the latest persisted
    /// values, then kept alive for the sheet's lifetime so edits done inside
    /// don't snap back when `ContentView` re-evaluates its body.
    @State private var settingsBag: SettingsBindings?

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Environment(\.scenePhase)
    private var scenePhase

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
                    Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title)
                }
                .tint(.green)
                .keyboardShortcut("c", modifiers: [])
                .accessibilityLabel(SharedStrings.completeReminderAccessibility)
                .accessibilityIdentifier("completeButton")
                .accessibilityAddTraits(.isButton)

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
            .padding(.bottom, 8)
        }
    #endif

    @ViewBuilder private var authGatedContent: some View {
        switch viewModel.store.authorizationStatus {
        case .notDetermined:
            ProgressView(SharedStrings.requestingAccess)
        case .fullAccess:
            reminderList
        default:
            ContentUnavailableView(
                SharedStrings.remindersAccess,
                systemImage: "lock.shield",
                description: Text("Enable access in Settings to see your reminders."))
        }
    }

    private var reminderList: some View {
        GeometryReader { geometry in
            let viewHeight = geometry.size.height
                - geometry.safeAreaInsets.top
                - geometry.safeAreaInsets.bottom
            switch viewModel.store.listContent {
            case .allDone:
                let allDoneCopy = ContentViewModel.allDoneStateCopy()
                ScrollView {
                    EmptyStateCard(
                        copy: allDoneCopy,
                        maxWidth: EmptyStateCard.maxContentWidth(viewportWidth: geometry.size.width))
                        // Park the card dead-center: the ScrollView would otherwise
                        // leading-align its full content width past the plate.
                        .frame(maxWidth: .infinity, minHeight: viewHeight, alignment: .center)
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await viewModel.reload(clearSkipped: true)
                }
            case let .empty(hasHidden):
                let emptyCopy = ContentViewModel.emptyStateCopy(hasHidden: hasHidden)
                ZStack(alignment: .bottom) {
                    ScrollView {
                        EmptyStateCard(
                            copy: emptyCopy,
                            maxWidth: EmptyStateCard.maxContentWidth(viewportWidth: geometry.size.width))
                            .frame(maxWidth: .infinity, minHeight: viewHeight, alignment: .center)
                    }
                    .scrollBounceBehavior(.always)
                    .refreshable {
                        await viewModel.reload()
                    }
                    bottomBar
                }
            case .reminder:
                // Keep the inner `if let` so the `EKReminder` identifier stays in scope
                // for the deep link below; the associated `ReminderDisplay` is unused
                // here (binding it would trip the unused-value warning→error).
                ZStack(alignment: .bottom) {
                    List {
                        if let reminder = viewModel.store.visibleReminders.first {
                            let openNudgeSheet = { isShowingNudgeSheet = true }
                            ReminderCardView(
                                display: ReminderDisplay(reminder: reminder),
                                showDate: showDate,
                                showList: showList,
                                showRecurrence: showRecurrence,
                                showAlarms: showAlarms,
                                showSwipePrompt: swipePromptBinding,
                                // The nudge args are harmless on non-iOS: the
                                // 6th-skip interrupt (and thus `nudgeIdentifier`)
                                // never fires on macOS, so `isNudged` is always
                                // false there.
                                showNudge: viewModel.isNudged(reminder.calendarItemIdentifier),
                                onNudgeTap: openNudgeSheet)
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
                                        viewModel.openInReminders(reminder)
                                        if isURLSpyUITesting {
                                            lastOpenedURL = viewModel.lastOpenedURLForUITesting
                                        }
                                    } label: {
                                        Label("View in Reminders", systemImage: "eye")
                                    }

                                    Button {
                                        Task { await viewModel.deleteCurrentReminder() }
                                    } label: {
                                        Label(SharedStrings.deleteAction, systemImage: "trash")
                                    }
                                    .accessibilityLabel(SharedStrings.deleteReminderAccessibility)
                                    .accessibilityIdentifier("deleteButton")
                                    .tint(.red)
                                }
                            #endif
                                .swipeActions(edge: .leading) {
                                    Button {
                                        Task { await viewModel.completeCurrentReminder() }
                                    } label: {
                                        Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        viewModel.skipCurrentReminder()
                                    } label: {
                                        Label(SharedStrings.skipAction, systemImage: "circle.slash")
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
            case .noAccess:
                // Unreachable: `authGatedContent` diverts non-.fullAccess before this
                // renders. Required only for exhaustiveness — if auth ever collapses
                // into the enum, this arm is the footgun to revisit.
                EmptyView()
            }
        }
    }

    #if os(iOS)
        private var completeButton: some View {
            Button {
                Task { await viewModel.completeCurrentReminder() }
            } label: {
                Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .controlPlate()
            }
            .accessibilityLabel(SharedStrings.completeReminderAccessibility)
            .accessibilityIdentifier("completeButton")
            .accessibilityAddTraits(.isButton)
        }

        private var skipButton: some View {
            Button {
                viewModel.skipCurrentReminder()
            } label: {
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
                    .controlPlate()
            }
            .accessibilityLabel(SharedStrings.skipReminderAccessibility)
            .accessibilityIdentifier("skipButton")
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
        .accessibilityIdentifier("dictateButton")
        .accessibilityAddTraits(.isButton)
    }

    private var recordingIndicator: some View {
        Image(systemName: "mic.fill")
            .font(.title2)
            .controlPlate(fill: .red, glyph: .white)
            .symbolEffect(.pulse, options: .repeating)
            .accessibilityLabel("Recording")
            .accessibilityIdentifier("recordingIndicator")
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
            .accessibilityLabel(SharedStrings.completionGlow)
            .transition(.opacity)
    }

    /// The Settings sheet body: `SettingsView` wrapped in the bag → @AppStorage
    /// write-back chain. Lives in its own functions so the long `.onChange`
    /// chain has its own type-check budget instead of blowing up `body`'s
    /// single expression.
    @ViewBuilder private var settingsSheetContent: some View {
        if let bag = settingsBag {
            settingsSheetWritebacks(bag)
            // macOS sheets are sized by the content's ideal size; without a
            // minimum frame the settings List collapses to 0px and hides every row.
            #if os(macOS)
                .frame(minWidth: 400, minHeight: 500)
            #endif
        }
    }

    // The skip-nudge sheet (iOS only) lives in `ContentView+iOS.swift`.

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
}

// MARK: - Scene Phase (all platforms)

extension ContentView {
    /// Routes scene-phase transitions: schedule notifications on background
    /// (iOS only), cancel on foreground (iOS only), and re-read speech
    /// authorization on foreground so a permission change in Settings takes
    /// effect without a force-quit.
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            #if os(iOS)
                if let appViewModel {
                    Task { await appViewModel.scheduleNotificationIfNeeded() }
                }
            #endif
        case .active:
            #if os(iOS)
                if let appViewModel {
                    Task { await appViewModel.cancelNotifications() }
                }
            #endif
            viewModel.dictation.refreshAuthorizationStatus()
        default:
            break
        }
    }
}

// MARK: - Bottom Bar

extension ContentView {
    var bottomBar: some View {
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
                    if !viewModel.store.hasResolvedEntitlement {
                        EmptyView()
                    } else if !viewModel.store.canMutate {
                        upgradePrompt
                    } else if viewModel.showsActionButtons {
                        actionCluster
                    } else {
                        micButton
                    }
                #else
                    micButton
                #endif
            } else if !viewModel.dictation.canDictate,
                      viewModel.dictation.authorizationStatus != .notDetermined,
                      showMicrophoneButton {
                VStack(spacing: 4) {
                    Text("Speech recognition is unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    #if os(iOS)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption)
                    #endif
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 16)
    }
}

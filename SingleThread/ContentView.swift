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

    #if os(iOS)
        let appViewModel: AppViewModel?
    #endif

    let viewModel: ContentViewModel

    var excludedListsBinding: Binding<Set<String>> {
        Binding(
            get: { viewModel.store.excludedListTitles },
            set: { viewModel.setExcludedListTitles($0) })
    }

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
            .accessibilityIdentifier("settingsButton")
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

    @Environment(\.openURL)
    private var openURL

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
            if viewModel.store.allSkipped {
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
            } else if viewModel.store.reminders.isEmpty {
                let emptyCopy = ContentViewModel.emptyStateCopy(hasHidden: viewModel.store.hasHidden)
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
        }
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
}

// MARK: - Empty State Card

/// Compact content-wrapping plate for the iOS empty states ("No Reminders",
/// "Nothing due", "All Done"), mirroring the reminder card: an opaque
/// off-white/black plate that hugs its own text and is centered on screen by
/// the caller's `.frame(maxWidth: .infinity, minHeight:alignment:)`. Replaces
/// `ContentUnavailableView` here, which expands to fill the proposed frame —
/// its background then stretched across the whole screen.
private struct EmptyStateCard: View {
    // MARK: Internal

    let copy: ContentViewModel.EmptyStateCopy

    /// Cap for the description text's wrap width.
    var maxWidth: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: copy.systemImage)
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(copy.title)
                .font(.title2.bold())
                .accessibilityIdentifier("emptyStateTitle")
            Text(copy.description)
                .font(.callout)
                .accessibilityIdentifier("emptyStateDescription")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: maxWidth)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: ReminderCardView.plateCornerRadius)
                .fill(ReminderCardView.plateFill(for: colorScheme))
        }
    }

    /// Caps the description's width so long copy wraps on a couple of centered
    /// lines instead of stretching the plate edge-to-edge; short copy keeps its
    /// natural size (Text hugs when the proposal exceeds its ideal width) so the
    /// plate always hugs its text. Relative so the card stays proportionate on
    /// iPads, with an absolute ceiling so it never balloons on very wide screens.
    static func maxContentWidth(viewportWidth: CGFloat) -> CGFloat {
        min(340, viewportWidth * 0.6)
    }

    // MARK: Private

    @Environment(\.colorScheme)
    private var colorScheme
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

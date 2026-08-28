import EventKit
import SingleThreadCore
import Speech
import SwiftUI

struct ContentView: View {
    // MARK: Lifecycle

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
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
        .overlay {
            if viewModel.completionGlow.isActive {
                completionGlowOverlay
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: viewModel.completionGlow.isActive)
        .task {
            await viewModel.task(showUndatedReminders: showUndatedReminders)
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
            if let bag = settingsBag {
                SettingsView(
                    bindings: bag,
                    backgroundImage: viewModel.backgroundImage,
                    availableLists: viewModel.store.availableLists,
                    excludedLists: excludedListsBinding,
                    viewModel: SettingsViewModel())
                    // The bag is a plain in-memory holder; write each changed
                    // value back to the @AppStorage-backed property so settings
                    // survive relaunch (mirrors the old direct-bind behavior).
                    .onChange(of: bag.appearanceMode) { _, new in appearanceMode = new }
                    .onChange(of: bag.textSize) { _, new in textSize = new }
                #if os(iOS)
                    .onChange(of: bag.allowsLandscape) { _, new in allowsLandscape = new }
                    .onChange(of: bag.enableActionButtons) { _, new in enableActionButtons = new }
                    .onChange(of: bag.showSwipePrompt) { _, new in showSwipePrompt = new }
                #endif
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
        }
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

    #if os(iOS)
        @AppStorage("enableActionButtons")
        private var enableActionButtons = false
    #endif

    #if os(iOS)
        @AppStorage("showSwipePrompt")
        private var showSwipePrompt = true
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

    /// Stable bag of settings bindings for the currently presented sheet.
    /// Recreated when the sheet opens so it reflects the latest persisted
    /// values, then kept alive for the sheet's lifetime so edits done inside
    /// don't snap back when `ContentView` re-evaluates its body.
    @State private var settingsBag: SettingsBindings?

    @Environment(\.openURL)
    private var openURL

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private let viewModel: ContentViewModel

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
                                showAlarms: showAlarms)
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
                    if viewModel.showsActionButtons {
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

    private func creationFeedbackView(for feedback: CreationFeedback) -> some View {
        Image(systemName: feedback.systemImage)
            .font(.title2)
            .controlPlate(fill: feedback.backgroundColor, glyph: .white)
            .accessibilityLabel(feedback.accessibilityLabel)
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
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                backgroundFadePercent: backgroundFadePercent,
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

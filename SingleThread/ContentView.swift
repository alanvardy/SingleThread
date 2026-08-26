import EventKit
import SingleThreadCore
import Speech
import SwiftUI

struct ContentView: View {
    // MARK: Lifecycle

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
    }

    /// Convenience for callers that build a `ReminderStore` directly and want a
    /// matching `ContentView` (used by the app entry point and unit tests).
    init(
        store: ReminderStore,
        speechTranscriber: (any SpeechTranscribing)? = nil,
        backgroundImage: BackgroundImageStore = BackgroundImageStore()) {
        viewModel = ContentViewModel(
            store: store,
            backgroundImage: backgroundImage,
            speechTranscriber: speechTranscriber ?? ReminderDictation())
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
        .sheet(isPresented: $isShowingSettings) {
            #if os(iOS)
                SettingsView(
                    appearanceMode: $appearanceMode,
                    textSize: $textSize,
                    allowsLandscape: $allowsLandscape,
                    enableActionButtons: $enableActionButtons,
                    showMicrophoneButton: $showMicrophoneButton,
                    backgroundEnabled: $backgroundEnabled,
                    backgroundFadePercent: $backgroundFadePercent,
                    backgroundPhotographer: viewModel.backgroundImage.photographer,
                    backgroundPhotographerURL: viewModel.backgroundImage.photographerURL,
                    showUndatedReminders: $showUndatedReminders,
                    excludedLists: excludedListsBinding,
                    availableLists: viewModel.store.availableLists,
                    sortOption: $sortOption,
                    showDate: $showDate,
                    showList: $showList,
                    showRecurrence: $showRecurrence, showAlarms: $showAlarms,
                    viewModel: SettingsViewModel())
            #else
                SettingsView(
                    appearanceMode: $appearanceMode,
                    textSize: $textSize,
                    showMicrophoneButton: $showMicrophoneButton,
                    backgroundEnabled: $backgroundEnabled,
                    backgroundFadePercent: $backgroundFadePercent,
                    backgroundPhotographer: viewModel.backgroundImage.photographer,
                    backgroundPhotographerURL: viewModel.backgroundImage.photographerURL,
                    showUndatedReminders: $showUndatedReminders,
                    excludedLists: excludedListsBinding,
                    availableLists: viewModel.store.availableLists,
                    sortOption: $sortOption,
                    showDate: $showDate,
                    showList: $showList,
                    showRecurrence: $showRecurrence, showAlarms: $showAlarms,
                    viewModel: SettingsViewModel())
            #endif
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

    @State private var isShowingSettings = false

    @Environment(\.openURL)
    private var openURL

    private let viewModel: ContentViewModel

    private var excludedListsBinding: Binding<Set<String>> {
        Binding(
            get: { viewModel.store.excludedListTitles },
            set: { viewModel.store.setExcludedListTitles($0) })
    }

    #if os(macOS)
        private var actionButtons: some View {
            HStack(spacing: 32) {
                Button {
                    Task { await viewModel.store.completeCurrentReminder() }
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
                    viewModel.store.skipCurrentReminder()
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
                    Task { await viewModel.store.deleteCurrentReminder() }
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
                    await viewModel.store.reload(clearSkipped: true)
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
                        await viewModel.store.reload()
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
                                showRecurrence: showRecurrence, showAlarms: showAlarms,
                                showsOverPhoto: viewModel.backgroundDisplayed)
                                .listRowBackground(viewModel.backgroundDisplayed ? Color.clear : nil)
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
                                        Task { await viewModel.store.deleteCurrentReminder() }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            #endif
                                .swipeActions(edge: .leading) {
                                    Button {
                                        Task { await viewModel.store.completeCurrentReminder() }
                                    } label: {
                                        Label("Complete", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        viewModel.store.skipCurrentReminder()
                                    } label: {
                                        Label("Skip", systemImage: "circle.slash")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.store.reload()
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
                Task { await viewModel.store.completeCurrentReminder() }
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
                viewModel.store.skipCurrentReminder()
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

    private func creationFeedbackView(for feedback: CreationFeedback) -> some View {
        Image(systemName: feedback.systemImage)
            .font(.title2)
            .controlPlate(fill: feedback.backgroundColor, glyph: .white)
            .accessibilityLabel(feedback.accessibilityLabel)
    }
}

// MARK: - Preview Helpers

private let mockReminder: EKReminder = {
    let store = EKEventStore()
    let reminder = EKReminder(eventStore: store)
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
    let eventStore = EKEventStore()
    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = "Groceries"
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = "Buy milk"
    reminder.calendar = calendar
    return reminder
}()

// MARK: - Previews

#Preview("Empty") {
    ContentView(
        loadsReminders: false,
        eventStore: InMemoryEventStore())
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

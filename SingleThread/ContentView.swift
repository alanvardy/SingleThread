import EventKit
import SingleThreadCore
import Speech
import SwiftUI

struct ContentView: View {
    // MARK: Lifecycle

    /// Accepts a pre-configured store (used by the app entry point, which wires
    /// WatchConnectivity hooks onto the store before handing it to the view).
    init(
        store: ReminderStore,
        speechTranscriber: (any SpeechTranscribing)? = nil,
        backgroundImage: BackgroundImageStore = BackgroundImageStore()) {
        self.store = store
        self.speechTranscriber = speechTranscriber ?? ReminderDictation()
        self.backgroundImage = backgroundImage
    }

    init(
        loadsReminders: Bool = true,
        speechTranscriber: (any SpeechTranscribing)? = nil,
        backgroundImage: BackgroundImageStore = BackgroundImageStore()) {
        store = ReminderStore(loadsReminders: loadsReminders)
        self.speechTranscriber = speechTranscriber ?? ReminderDictation()
        self.backgroundImage = backgroundImage
    }

    /// Pre-populates state for canvas previews.
    init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus,
        excludedProjectTitles: Set<String> = [],
        hasHidden: Bool = false,
        speechTranscriber: (any SpeechTranscribing)? = nil,
        backgroundImage: BackgroundImageStore = BackgroundImageStore()) {
        store = ReminderStore(
            loadsReminders: loadsReminders,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: authorizationStatus,
            excludedProjectTitles: excludedProjectTitles,
            hasHidden: hasHidden)
        self.speechTranscriber = speechTranscriber ?? ReminderDictation()
        self.backgroundImage = backgroundImage
    }

    // MARK: Internal

    /// Copy + icon describing why the `reminderList` has nothing to show —
    /// either an empty/in-window-hiding state (keyed off `hasHidden`) or the
    /// fully-skipped "All Done" state.
    struct EmptyStateCopy {
        let title: String
        let systemImage: String
        let description: String
    }

    /// Created before view init, so a plain `let` gives StateObject-like lifetime.
    var backgroundImage: BackgroundImageStore

    #if os(iOS)
        /// Whether the Complete/Skip cluster replaces the plain mic in the bottom
        /// bar: the toggle must be on AND a visible reminder must exist. Readable
        /// outside a live view (unit-test seam); inside the app it reads the live
        /// `@AppStorage` value.
        var showsActionButtons: Bool {
            enableActionButtons && store.visibleReminders.first != nil
        }
    #endif

    var body: some View {
        ZStack {
            Color.systemBackground.ignoresSafeArea()
            #if os(iOS)
                BackgroundPhotoLayer(imageData: backgroundImage.imageData, isEnabled: backgroundEnabled)
            #endif
            if store.loadsReminders {
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
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
            .accessibilityAddTraits(.isButton)
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        .task {
            store.showsUndatedReminders = showUndatedReminders
            await store.start()
            await backgroundImage.refreshIfNeeded(maxAge: 3600)
        }
        .onChange(of: showUndatedReminders) { _, newValue in
            store.showsUndatedReminders = newValue
            Task { await store.reload() }
        }
        .onChange(of: sortOption) { _, newValue in
            store.setSortOption(newValue)
        }
        .onChange(of: appearanceMode) { _, newValue in
            #if os(iOS)
                AppDelegate.applyAppearance(newValue)
            #elseif os(macOS)
                MacAppDelegate.applyAppearance(newValue)
            #endif
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
                    backgroundPhotographer: backgroundImage.photographer,
                    showUndatedReminders: $showUndatedReminders,
                    excludedProjects: excludedProjectsBinding,
                    availableProjects: store.availableProjects,
                    sortOption: $sortOption,
                    showDate: $showDate)
            #else
                SettingsView(
                    appearanceMode: $appearanceMode,
                    textSize: $textSize,
                    showMicrophoneButton: $showMicrophoneButton,
                    backgroundEnabled: $backgroundEnabled,
                    backgroundPhotographer: backgroundImage.photographer,
                    showUndatedReminders: $showUndatedReminders,
                    excludedProjects: excludedProjectsBinding,
                    availableProjects: store.availableProjects,
                    sortOption: $sortOption,
                    showDate: $showDate)
            #endif
        }
    }

    static func emptyStateCopy(hasHidden: Bool) -> EmptyStateCopy {
        if hasHidden {
            return EmptyStateCopy(
                title: "Nothing due",
                systemImage: "calendar",
                description: "Only today's and overdue reminders show here — pull to refresh.")
        }
        return EmptyStateCopy(
            title: "No Reminders",
            systemImage: "checklist",
            description: "You don't have any reminders yet.")
    }

    /// Copy + icon for the fully-skipped `reminderList` state.
    static func allDoneStateCopy() -> EmptyStateCopy {
        EmptyStateCopy(
            title: "All Done",
            systemImage: "checkmark.circle",
            description: "Pull to refresh to see all your reminders again.")
    }

    // MARK: Private

    // MARK: - Creation Feedback

    private enum CreationFeedback {
        case success
        case failure

        // MARK: Internal

        var systemImage: String {
            switch self {
            case .success: "checkmark"
            case .failure: "xmark"
            }
        }

        var backgroundColor: Color {
            switch self {
            case .success: .green
            case .failure: .red
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .success: "Task created"
            case .failure: "Task creation failed"
            }
        }
    }

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
    @State private var isDictating = false
    @State private var dictationText = ""
    @State private var dictationError: String?
    @State private var creationFeedback: CreationFeedback?
    @State private var isShowingSettings = false

    @Environment(\.openURL)
    private var openURL

    private let store: ReminderStore
    private let speechTranscriber: any SpeechTranscribing

    private var excludedProjectsBinding: Binding<Set<String>> {
        Binding(
            get: { store.excludedProjectTitles },
            set: { store.setExcludedProjectTitles($0) })
    }

    private var allSkipped: Bool {
        !store.reminders.isEmpty && store.visibleReminders.isEmpty
    }

    private var canDictate: Bool {
        speechTranscriber.authorizationStatus == .authorized
            || speechTranscriber.authorizationStatus == .notDetermined
    }

    #if os(macOS)
        private var actionButtons: some View {
            HStack(spacing: 32) {
                Button {
                    Task { await store.completeCurrentReminder() }
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
                    store.skipCurrentReminder()
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
                    Task { await store.deleteCurrentReminder() }
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
        switch store.authorizationStatus {
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
            if allSkipped {
                let allDoneCopy = Self.allDoneStateCopy()
                ScrollView {
                    ContentUnavailableView(
                        allDoneCopy.title,
                        systemImage: allDoneCopy.systemImage,
                        description: Text(allDoneCopy.description))
                        .frame(minHeight: viewHeight, alignment: .center)
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await store.reload(clearSkipped: true)
                }
            } else if store.reminders.isEmpty {
                let emptyCopy = Self.emptyStateCopy(hasHidden: store.hasHidden)
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
                        await store.reload()
                    }
                    bottomBar
                }
            } else {
                ZStack(alignment: .bottom) {
                    List {
                        if let reminder = store.visibleReminders.first {
                            ReminderCardView(reminder: reminder, showDate: showDate)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 12)
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
                                        Task { await store.deleteCurrentReminder() }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            #endif
                                .swipeActions(edge: .leading) {
                                    Button {
                                        Task { await store.completeCurrentReminder() }
                                    } label: {
                                        Label("Complete", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        store.skipCurrentReminder()
                                    } label: {
                                        Label("Skip", systemImage: "circle.slash")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await store.reload()
                    }
                    bottomBar
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            #if os(macOS)
                if store.visibleReminders.first != nil {
                    actionButtons
                }
            #endif
            if let error = dictationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            if let feedback = creationFeedback {
                creationFeedbackView(for: feedback)
            } else if isDictating {
                if !dictationText.isEmpty {
                    Text(dictationText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                recordingIndicator
            } else if canDictate, showMicrophoneButton {
                #if os(iOS)
                    if showsActionButtons {
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
                Task { await store.completeCurrentReminder() }
            } label: {
                Label("Complete", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .tint(.green)
            .accessibilityLabel("Complete reminder")
            .accessibilityAddTraits(.isButton)
        }

        private var skipButton: some View {
            Button {
                store.skipCurrentReminder()
            } label: {
                Label("Skip", systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .tint(.orange)
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
            Task { await startDictation() }
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.blue, in: Circle())
                .shadow(radius: 4)
        }
        .accessibilityLabel("Dictate reminder")
        .accessibilityAddTraits(.isButton)
    }

    private var recordingIndicator: some View {
        Image(systemName: "mic.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(.red, in: Circle())
            .shadow(radius: 4)
            .symbolEffect(.pulse, options: .repeating)
            .accessibilityLabel("Recording")
    }

    private func creationFeedbackView(for feedback: CreationFeedback) -> some View {
        Image(systemName: feedback.systemImage)
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(feedback.backgroundColor, in: Circle())
            .shadow(radius: 4)
            .accessibilityLabel(feedback.accessibilityLabel)
    }

    private func startDictation() async {
        if speechTranscriber.authorizationStatus == .notDetermined {
            let status = await speechTranscriber.requestAuthorization()
            guard status == .authorized else {
                dictationError = "Speech recognition access is required."
                return
            }
        }
        guard speechTranscriber.authorizationStatus == .authorized else {
            dictationError = "Speech recognition access was denied."
            return
        }
        isDictating = true
        dictationText = ""
        dictationError = nil
        do {
            let result = try await speechTranscriber.transcribe { text in
                dictationText = text
            }
            let parsed = ReminderDictationParser.parse(result)
            if !parsed.title.isEmpty {
                let saved = await store.addReminder(
                    title: parsed.title,
                    notes: nil,
                    dueDate: parsed.dueDateComponents,
                    recurrenceRule: parsed.recurrenceRule)
                if saved {
                    creationFeedback = .success
                } else {
                    creationFeedback = .failure
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                creationFeedback = nil
            }
        } catch {
            dictationError = error.localizedDescription
        }
        isDictating = false
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
    return reminder
}()

private let mockReminderInProject: EKReminder = {
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
    ContentView(loadsReminders: false)
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
        reminders: [mockReminderInProject],
        skippedIDs: [],
        authorizationStatus: .fullAccess,
        excludedProjectTitles: ["Groceries"])
}

#Preview("No Access") {
    ContentView(
        loadsReminders: true,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .denied)
}

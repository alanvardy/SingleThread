import SingleThreadCore
import SwiftUI
#if os(iOS) || os(macOS)
    import WidgetKit
#endif

// MARK: - ExcludedProjectsView

/// Submenu listing the projects the user has chosen to exclude. Pushed from
/// the settings screen so the main settings view stays focused on its core
/// preferences.
struct ExcludedProjectsView: View {
    // MARK: Lifecycle

    init(excludedProjects: Binding<Set<String>>, availableProjects: [String]) {
        _excludedProjects = excludedProjects
        self.availableProjects = availableProjects
    }

    // MARK: Internal

    var body: some View {
        Form {
            Section {
                ForEach(availableProjects, id: \.self) { project in
                    Toggle(isOn: excludedBinding(for: project)) {
                        Text(project)
                    }
                }
            } footer: {
                Text("Excluded projects are hidden from the reminder list.")
            }
        }
        .navigationTitle("Excluded Projects")
    }

    // MARK: Private

    @Binding private var excludedProjects: Set<String>

    private let availableProjects: [String]

    private func excludedBinding(for project: String) -> Binding<Bool> {
        Binding(
            get: { excludedProjects.contains(project) },
            set: { isExcluded in
                if isExcluded {
                    excludedProjects.insert(project)
                } else {
                    excludedProjects.remove(project)
                }
            })
    }
}

// MARK: - SettingsView

/// Modal settings screen presented from the gear button. Owns no state —
/// every preference is bound back to `ContentView`'s `@AppStorage` values.
///
/// Eleven settings, two persistence tiers, one sync scope.
///
/// Synced to Apple Watch via `SkippedReminderSyncService` (VAR-648): sort
/// option, show-undated, show date, excluded projects, plus the skip set.
///
/// Intentionally **not** synced — these seven are phone-only cosmetics with no
/// watch UI counterpart (design decision: syncing them adds payload surface
/// for no user-visible effect):
/// `appearanceMode`, `textSize`, `allowsLandscape` (iOS-only),
/// `showMicrophoneButton`, `backgroundEnabled`, `backgroundFadePercent`,
/// `enableActionButtons` (iOS-only).
struct SettingsView: View {
    // MARK: Lifecycle

    #if os(iOS)
        init(
            appearanceMode: Binding<AppearanceMode>,
            textSize: Binding<TextSize>,
            allowsLandscape: Binding<Bool>,
            enableActionButtons: Binding<Bool>,
            showMicrophoneButton: Binding<Bool>,
            backgroundEnabled: Binding<Bool>,
            backgroundFadePercent: Binding<Int>,
            backgroundPhotographer: String?,
            showUndatedReminders: Binding<Bool>,
            excludedProjects: Binding<Set<String>>,
            availableProjects: [String],
            sortOption: Binding<SortOption>,
            showDate: Binding<Bool>,
            showList: Binding<Bool>) {
            _appearanceMode = appearanceMode
            _textSize = textSize
            _allowsLandscape = allowsLandscape
            _enableActionButtons = enableActionButtons
            _showMicrophoneButton = showMicrophoneButton
            _backgroundEnabled = backgroundEnabled
            _backgroundFadePercent = backgroundFadePercent
            self.backgroundPhotographer = backgroundPhotographer
            _showUndatedReminders = showUndatedReminders
            _excludedProjects = excludedProjects
            self.availableProjects = availableProjects
            _sortOption = sortOption
            _showDate = showDate
            _showList = showList
        }
    #else
        init(
            appearanceMode: Binding<AppearanceMode>,
            textSize: Binding<TextSize>,
            showMicrophoneButton: Binding<Bool>,
            backgroundEnabled: Binding<Bool>,
            backgroundFadePercent: Binding<Int>,
            backgroundPhotographer: String?,
            showUndatedReminders: Binding<Bool>,
            excludedProjects: Binding<Set<String>>,
            availableProjects: [String],
            sortOption: Binding<SortOption>,
            showDate: Binding<Bool>,
            showList: Binding<Bool>) {
            _appearanceMode = appearanceMode
            _textSize = textSize
            _showMicrophoneButton = showMicrophoneButton
            _backgroundEnabled = backgroundEnabled
            _backgroundFadePercent = backgroundFadePercent
            self.backgroundPhotographer = backgroundPhotographer
            _showUndatedReminders = showUndatedReminders
            _excludedProjects = excludedProjects
            self.availableProjects = availableProjects
            _sortOption = sortOption
            _showDate = showDate
            _showList = showList
        }
    #endif

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                Picker("Text Size", selection: $textSize) {
                    ForEach(TextSize.allCases, id: \.self) { size in
                        Label(size.title, systemImage: size.systemImage)
                            .tag(size)
                    }
                }
                Picker("Sort By", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
                #if os(iOS)
                    Toggle(isOn: $allowsLandscape) {
                        Label("Allow Landscape", systemImage: "rectangle.landscape.rotate")
                    }
                    .onChange(of: allowsLandscape) { _, newValue in
                        AppDelegate.applyLock(allowsLandscape: newValue)
                    }
                #endif
                Toggle(isOn: $showMicrophoneButton) {
                    Label("Show Microphone", systemImage: "microphone")
                }
                Toggle(isOn: $backgroundEnabled) {
                    Label("Background", systemImage: "photo")
                }
                Picker("Background Fade", selection: $backgroundFadePercent) {
                    ForEach(BackgroundFade.allValues, id: \.self) { percent in
                        Text("\(percent)%").tag(percent)
                    }
                }
                #if os(iOS)
                    Toggle(isOn: $enableActionButtons) {
                        Label("Enable action buttons", systemImage: "hand.tap")
                    }
                #endif
                Toggle(isOn: $showUndatedReminders) {
                    Label("Show Undated", systemImage: "calendar.badge.minus")
                }
                Toggle(isOn: $showDate) {
                    Label("Show Date", systemImage: "calendar")
                }
                #if os(iOS) || os(macOS)
                .onChange(of: showDate) { _, _ in
                    WidgetCenter.shared.reloadAllTimelines()
                }
                #endif
                Toggle(isOn: $showList) {
                    Label("Show list", systemImage: "list.bullet")
                }
                Section {
                    NavigationLink {
                        ExcludedProjectsView(
                            excludedProjects: $excludedProjects,
                            availableProjects: availableProjects)
                    } label: {
                        Label("Excluded Projects", systemImage: "eye.slash")
                    }
                }
                Section {} footer: {
                    if let backgroundPhotographer {
                        Text("Photo by \(backgroundPhotographer) on Unsplash")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .modifier(TextSizeModifier(textSize: textSize))
    }

    // MARK: Private

    @Binding private var appearanceMode: AppearanceMode
    @Binding private var textSize: TextSize
    @Binding private var sortOption: SortOption
    #if os(iOS)
        @Binding private var allowsLandscape: Bool
        @Binding private var enableActionButtons: Bool
    #endif
    @Binding private var showMicrophoneButton: Bool
    @Binding private var backgroundEnabled: Bool
    @Binding private var backgroundFadePercent: Int
    @Binding private var showUndatedReminders: Bool
    @Binding private var excludedProjects: Set<String>
    @Binding private var showDate: Bool
    @Binding private var showList: Bool
    @Environment(\.dismiss)
    private var dismiss

    private let backgroundPhotographer: String?

    private let availableProjects: [String]
}

// MARK: - Previews

#if os(iOS)
    #Preview("Default") {
        SettingsView(
            appearanceMode: .constant(.system),
            textSize: .constant(.system),
            allowsLandscape: .constant(true),
            enableActionButtons: .constant(false),
            showMicrophoneButton: .constant(true),
            backgroundEnabled: .constant(true),
            backgroundFadePercent: .constant(50),
            backgroundPhotographer: "NEOM",
            showUndatedReminders: .constant(false),
            excludedProjects: .constant([]),
            availableProjects: ["Work", "Personal"],
            sortOption: .constant(.priority),
            showDate: .constant(true),
            showList: .constant(false))
    }

    #Preview("Dark + Extra Large") {
        SettingsView(
            appearanceMode: .constant(.dark),
            textSize: .constant(.extraLarge),
            allowsLandscape: .constant(false),
            enableActionButtons: .constant(false),
            showMicrophoneButton: .constant(false),
            backgroundEnabled: .constant(true),
            backgroundFadePercent: .constant(50),
            backgroundPhotographer: nil,
            showUndatedReminders: .constant(true),
            excludedProjects: .constant([]),
            availableProjects: ["Work", "Personal"],
            sortOption: .constant(.dueDate),
            showDate: .constant(false),
            showList: .constant(true))
    }
#else
    #Preview("Default") {
        SettingsView(
            appearanceMode: .constant(.system),
            textSize: .constant(.system),
            showMicrophoneButton: .constant(true),
            backgroundEnabled: .constant(true),
            backgroundFadePercent: .constant(50),
            backgroundPhotographer: "NEOM",
            showUndatedReminders: .constant(false),
            excludedProjects: .constant([]),
            availableProjects: ["Work", "Personal"],
            sortOption: .constant(.priority),
            showDate: .constant(true),
            showList: .constant(false))
    }
#endif

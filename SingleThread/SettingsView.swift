import SingleThreadCore
import SwiftUI

// MARK: - SettingsView

/// Modal settings screen presented from the gear button. Owns no state —
/// every preference is bound back through a single `SettingsBindings` bag.
///
/// `excludedLists` is the one store-backed value and is passed separately as
/// a `Binding<Set<String>>` (see the note in `SettingsBindings`).
struct SettingsView: View {
    // MARK: Lifecycle

    init(
        bindings: SettingsBindings,
        backgroundPhotographer: String?,
        backgroundPhotographerURL: URL?,
        availableLists: [String],
        excludedLists: Binding<Set<String>>,
        viewModel: SettingsViewModel = SettingsViewModel()) {
        self.bindings = bindings
        self.viewModel = viewModel
        self.backgroundPhotographer = backgroundPhotographer
        self.backgroundPhotographerURL = backgroundPhotographerURL
        self.availableLists = availableLists
        _excludedLists = excludedLists
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    #if os(iOS)
                        InterfaceSettingsView(
                            appearanceMode: $bindings.appearanceMode,
                            textSize: $bindings.textSize,
                            allowsLandscape: $bindings.allowsLandscape,
                            showMicrophoneButton: $bindings.showMicrophoneButton,
                            enableActionButtons: $bindings.enableActionButtons,
                            viewModel: viewModel)
                    #else
                        InterfaceSettingsView(
                            appearanceMode: $bindings.appearanceMode,
                            textSize: $bindings.textSize,
                            showMicrophoneButton: $bindings.showMicrophoneButton,
                            viewModel: viewModel)
                    #endif
                } label: {
                    Label("Interface", systemImage: "paintpalette")
                }
                NavigationLink {
                    ReminderSettingsView(
                        showDate: $bindings.showDate,
                        showList: $bindings.showList,
                        showRecurrence: $bindings.showRecurrence,
                        showAlarms: $bindings.showAlarms,
                        viewModel: viewModel)
                } label: {
                    Label("Reminder", systemImage: "bell.badge")
                }
                NavigationLink {
                    FilterSortSettingsView(
                        sortOption: $bindings.sortOption,
                        showUndatedReminders: $bindings.showUndatedReminders,
                        availableLists: availableLists,
                        excludedLists: $excludedLists)
                } label: {
                    Label("Filtering & Sorting", systemImage: "line.3.horizontal.decrease")
                }
                NavigationLink {
                    BackgroundSettingsView(
                        backgroundEnabled: $bindings.backgroundEnabled,
                        backgroundFadePercent: $bindings.backgroundFadePercent,
                        backgroundPhotographer: backgroundPhotographer,
                        backgroundPhotographerURL: backgroundPhotographerURL)
                } label: {
                    Label("Background", systemImage: "photo.on.rectangle")
                }
                NavigationLink {
                    PrivacySettingsView()
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                .accessibilityLabel("About")
                .accessibilityAddTraits(.isButton)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .modifier(TextSizeModifier(textSize: bindings.textSize))
    }

    // MARK: Private

    @Environment(\.dismiss)
    private var dismiss

    @Binding private var excludedLists: Set<String>

    @Bindable private var bindings: SettingsBindings

    private let viewModel: SettingsViewModel
    private let backgroundPhotographer: String?
    private let backgroundPhotographerURL: URL?
    private let availableLists: [String]
}

// MARK: - Previews

#Preview("Default") {
    SettingsView(
        bindings: SettingsBindings(),
        backgroundPhotographer: "NEOM",
        backgroundPhotographerURL: URL(string: "https://unsplash.com/@neom"),
        availableLists: ["Work", "Personal"],
        excludedLists: .constant([]))
}

#Preview("Dark + Extra Large") {
    let bag = SettingsBindings(
        appearanceMode: .dark,
        textSize: .extraLarge,
        allowsLandscape: false,
        enableActionButtons: false,
        showMicrophoneButton: false,
        backgroundEnabled: true,
        backgroundFadePercent: 50,
        showUndatedReminders: true,
        sortOption: .dueDate,
        showDate: false,
        showList: true,
        showRecurrence: true,
        showAlarms: true)
    SettingsView(
        bindings: bag,
        backgroundPhotographer: nil,
        backgroundPhotographerURL: nil,
        availableLists: ["Work", "Personal"],
        excludedLists: .constant([]))
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

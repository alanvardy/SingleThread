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
                    InterfaceSettingsView(
                        bindings: bindings,
                        viewModel: viewModel)
                } label: {
                    Label("Interface", systemImage: "paintpalette")
                }
                NavigationLink {
                    ReminderSettingsView(
                        bindings: bindings,
                        viewModel: viewModel)
                } label: {
                    Label("Reminder", systemImage: "bell.badge")
                }
                NavigationLink {
                    FilterSortSettingsView(
                        bindings: bindings,
                        availableLists: availableLists,
                        excludedLists: $excludedLists)
                } label: {
                    Label("Filtering & Sorting", systemImage: "line.3.horizontal.decrease")
                }
                NavigationLink {
                    BackgroundSettingsView(
                        bindings: bindings,
                        backgroundPhotographer: backgroundPhotographer,
                        backgroundPhotographerURL: backgroundPhotographerURL)
                } label: {
                    Label("Background", systemImage: "photo.on.rectangle")
                }
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

    private let bindings: SettingsBindings

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

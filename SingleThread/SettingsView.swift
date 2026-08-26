import SingleThreadCore
import SwiftUI

#if os(iOS) || os(macOS)
    import WidgetKit
#endif

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
            Form {
                Section {
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
                }
                Picker("Appearance", selection: $bindings.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                Picker("Text Size", selection: $bindings.textSize) {
                    ForEach(TextSize.allCases, id: \.self) { size in
                        Label(size.title, systemImage: size.systemImage)
                            .tag(size)
                    }
                }
                Picker("Sort By", selection: $bindings.sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
                #if os(iOS)
                    Toggle(isOn: $bindings.allowsLandscape) {
                        Label("Allow landscape", systemImage: "rectangle.landscape.rotate")
                    }
                    .onChange(of: bindings.allowsLandscape) { _, newValue in
                        viewModel.allowsLandscapeChanged(newValue)
                    }
                #endif
                Toggle(isOn: $bindings.showMicrophoneButton) {
                    Label("Show microphone", systemImage: "microphone")
                }
                Toggle(isOn: $bindings.backgroundEnabled) {
                    Label("Background", systemImage: "photo")
                }
                Picker("Background Fade", selection: $bindings.backgroundFadePercent) {
                    ForEach(BackgroundFade.allValues, id: \.self) { percent in
                        Text("\(percent)%").tag(percent)
                    }
                }
                #if os(iOS)
                    Toggle(isOn: $bindings.enableActionButtons) {
                        Label("Show action buttons", systemImage: "hand.tap")
                    }
                #endif
                Toggle(isOn: $bindings.showUndatedReminders) {
                    Label("Show undated reminders", systemImage: "calendar.badge.minus")
                }
                Toggle(isOn: $bindings.showDate) {
                    Label("Show date", systemImage: "calendar")
                }
                #if os(iOS) || os(macOS)
                .onChange(of: bindings.showDate) { _, _ in
                    viewModel.showPreferenceChanged()
                }
                #endif
                Toggle(isOn: $bindings.showList) {
                    Label("Show list", systemImage: "list.bullet")
                }
                Toggle(isOn: $bindings.showRecurrence) {
                    Label("Recurrence indicator", systemImage: "repeat")
                }
                #if os(iOS) || os(macOS)
                .onChange(of: bindings.showRecurrence) { _, _ in
                    viewModel.showPreferenceChanged()
                }
                #endif
                Toggle(isOn: $bindings.showAlarms) {
                    Label("Reminder alerts", systemImage: "bell")
                }
                #if os(iOS) || os(macOS)
                .onChange(of: bindings.showAlarms) { _, _ in
                    viewModel.showPreferenceChanged()
                }
                #endif
                Section {} footer: {
                    if let backgroundPhotographer {
                        if let backgroundPhotographerURL {
                            Link(
                                "Photo by \(backgroundPhotographer) on Unsplash",
                                destination: backgroundPhotographerURL)
                        } else {
                            Text("Photo by \(backgroundPhotographer) on Unsplash")
                        }
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
        .modifier(TextSizeModifier(textSize: bindings.textSize))
    }

    // MARK: Private

    @Bindable private var bindings: SettingsBindings

    @Environment(\.dismiss)
    private var dismiss

    @Binding private var excludedLists: Set<String>

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

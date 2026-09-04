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
        backgroundImage: BackgroundImageStore,
        availableLists: [String],
        excludedLists: Binding<Set<String>>,
        entitlementStore: EntitlementStore = EntitlementStore(),
        viewModel: SettingsViewModel = SettingsViewModel()) {
        self.bindings = bindings
        self.viewModel = viewModel
        self.backgroundImage = backgroundImage
        self.availableLists = availableLists
        self.entitlementStore = entitlementStore
        _excludedLists = excludedLists
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        #if os(iOS)
                            InterfaceSettingsView(
                                appearanceMode: $bindings.appearanceMode,
                                textSize: $bindings.textSize,
                                allowsLandscape: $bindings.allowsLandscape,
                                showMicrophoneButton: $bindings.showMicrophoneButton,
                                enableActionButtons: $bindings.enableActionButtons,
                                showSwipePrompt: $bindings.showSwipePrompt,
                                showUndoButton: $bindings.showUndoButton,
                                viewModel: viewModel)
                        #elseif os(macOS)
                            InterfaceSettingsView(
                                appearanceMode: $bindings.appearanceMode,
                                textSize: $bindings.textSize,
                                showMicrophoneButton: $bindings.showMicrophoneButton,
                                viewModel: viewModel)
                        #endif
                    } label: {
                        Label("Interface", systemImage: "paintpalette")
                    }
                    .accessibilityIdentifier("settingsInterfaceRow")
                    #if os(iOS)
                        NavigationLink {
                            NotificationsSettingsView(
                                notificationsEnabled: $bindings.notificationsEnabled,
                                notificationIntervalHours: $bindings.notificationIntervalHours)
                        } label: {
                            Label("Notifications", systemImage: "bell.badge")
                        }
                        .accessibilityIdentifier("settingsNotificationsRow")
                    #endif
                    NavigationLink {
                        ReminderSettingsView(
                            showDate: $bindings.showDate,
                            showList: $bindings.showList,
                            showRecurrence: $bindings.showRecurrence,
                            showAlarms: $bindings.showAlarms,
                            showCompletionGlow: $bindings.showCompletionGlow,
                            viewModel: viewModel)
                    } label: {
                        Label("Reminder", systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("settingsReminderRow")
                    NavigationLink {
                        FilterSortSettingsView(
                            sortOption: $bindings.sortOption,
                            showUndatedReminders: $bindings.showUndatedReminders,
                            availableLists: availableLists,
                            excludedLists: $excludedLists)
                    } label: {
                        Label("Filtering & Sorting", systemImage: "line.3.horizontal.decrease")
                    }
                    .accessibilityIdentifier("settingsFilterSortRow")
                    NavigationLink {
                        BackgroundSettingsView(
                            backgroundEnabled: $bindings.backgroundEnabled,
                            backgroundFadePercent: $bindings.backgroundFadePercent,
                            backgroundPinned: $bindings.backgroundPinned,
                            backgroundImage: backgroundImage)
                    } label: {
                        Label("Background", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("settingsBackgroundRow")
                    NavigationLink {
                        PurchaseSettingsView(entitlementStore: entitlementStore)
                    } label: {
                        Label(
                            entitlementStore.isEntitled ? "Manage Purchase" : "Unlock",
                            systemImage: entitlementStore.isEntitled ? "checkmark.seal" : "lock.open")
                    }
                    .accessibilityLabel(
                        entitlementStore.isEntitled ? "Manage Purchase" : "Unlock")
                    .accessibilityIdentifier("settingsPurchaseRow")
                    .accessibilityAddTraits(.isButton)
                }

                Section {
                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("settingsPrivacyRow")
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    .accessibilityLabel("About")
                    .accessibilityIdentifier("settingsAboutRow")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("settingsDoneButton")
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
    private let backgroundImage: BackgroundImageStore
    private let availableLists: [String]
    private let entitlementStore: EntitlementStore
}

// MARK: - Previews

#Preview("Default") {
    SettingsView(
        bindings: SettingsBindings(),
        backgroundImage: BackgroundImageStore(),
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
        backgroundImage: BackgroundImageStore(),
        availableLists: ["Work", "Personal"],
        excludedLists: .constant([]))
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

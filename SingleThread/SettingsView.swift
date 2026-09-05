import SingleThreadCore
import SwiftUI

// MARK: - SettingsView

/// Modal settings screen presented from the gear button. Owns no state —
/// every preference is bound back through a single `SettingsBindings` bag.
///
/// `excludedLists` is the one store-backed value and is passed separately as
/// a `Binding<Set<String>>` (see the note in `SettingsBindings`).
///
/// Every navigation destination below must end with `.settingsSubscreenLayout()`
/// to top-align pushed content on macOS; omitting it silently reintroduces
/// the vertical-centering bug on that platform.
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
                        SettingsLinkLabel(
                            title: "Interface",
                            systemImage: "paintpalette",
                            caption: "Customize the appearance, text size, and controls.")
                    }
                    .accessibilityIdentifier("settingsInterfaceRow")
                    #if os(iOS)
                        NavigationLink {
                            NotificationsSettingsView(
                                notificationsEnabled: $bindings.notificationsEnabled,
                                notificationIntervalHours: $bindings.notificationIntervalHours)
                        } label: {
                            SettingsLinkLabel(
                                title: "Notifications",
                                systemImage: "bell.badge",
                                caption: "Get reminded when you have due reminders.")
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
                        SettingsLinkLabel(
                            title: "Reminder",
                            systemImage: "bell.badge",
                            caption: "Choose what information is shown with each reminder.")
                    }
                    .accessibilityIdentifier("settingsReminderRow")
                    NavigationLink {
                        FilterSortSettingsView(
                            sortOption: $bindings.sortOption,
                            showUndatedReminders: $bindings.showUndatedReminders,
                            availableLists: availableLists,
                            excludedLists: $excludedLists)
                    } label: {
                        SettingsLinkLabel(
                            title: "Filtering & Sorting",
                            systemImage: "line.3.horizontal.decrease",
                            caption: "Control the order, visibility, and excluded lists.")
                    }
                    .accessibilityIdentifier("settingsFilterSortRow")
                    NavigationLink {
                        BackgroundSettingsView(
                            backgroundEnabled: $bindings.backgroundEnabled,
                            backgroundFadePercent: $bindings.backgroundFadePercent,
                            backgroundPinned: $bindings.backgroundPinned,
                            backgroundImage: backgroundImage)
                    } label: {
                        SettingsLinkLabel(
                            title: "Background",
                            systemImage: "photo.on.rectangle",
                            caption: "Manage the wallpaper and its appearance.")
                    }
                    .accessibilityIdentifier("settingsBackgroundRow")
                    let purchaseTitle = LocalizedStringKey(
                        entitlementStore.isEntitled ? "Manage Purchase" : "Unlock")
                    let purchaseIcon = entitlementStore.isEntitled ? "checkmark.seal" : "lock.open"
                    NavigationLink {
                        PurchaseSettingsView(entitlementStore: entitlementStore)
                    } label: {
                        SettingsLinkLabel(
                            title: purchaseTitle,
                            systemImage: purchaseIcon,
                            caption: "View and manage your purchase status.")
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
                        SettingsLinkLabel(
                            title: "Privacy Policy",
                            systemImage: "hand.raised",
                            caption: "How SingleThread handles your data.")
                    }
                    .accessibilityIdentifier("settingsPrivacyRow")
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsLinkLabel(
                            title: "About",
                            systemImage: "info.circle",
                            caption: "App version, credits, and contact.")
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
        backgroundFadePercent: 50)
    SettingsView(
        bindings: bag,
        backgroundImage: BackgroundImageStore(),
        availableLists: ["Work", "Personal"],
        excludedLists: .constant([]))
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

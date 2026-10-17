import SingleThreadCore
import SwiftUI

// MARK: - SettingsRoute

/// One pushed destination inside the Settings stack. Only the Reminder row is
/// value-driven: the screenshot harness seeds it through
/// ``LaunchArgument/openSettingsReminder``, and the value form is what lets a
/// `NavigationPath` pre-select it before the stack renders.
enum SettingsRoute: Hashable {
    case reminder
}

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
        store: ReminderStore,
        availableLists: [String],
        excludedLists: Binding<Set<String>>,
        entitlementStore: EntitlementStore = EntitlementStore(),
        viewModel: SettingsViewModel = SettingsViewModel(),
        initialRoute: SettingsRoute? = nil) {
        self.bindings = bindings
        self.viewModel = viewModel
        self.store = store
        self.backgroundImage = backgroundImage
        self.availableLists = availableLists
        self.entitlementStore = entitlementStore
        _excludedLists = excludedLists
        // Seed the path before the stack renders so a seam-driven launch lands
        // on the subscreen in the first frame instead of pushing afterwards.
        var path = NavigationPath()
        if let initialRoute {
            path.append(initialRoute)
        }
        _path = State(initialValue: path)
    }

    // MARK: Internal

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink {
                        #if os(iOS)
                            InterfaceSettingsView(
                                appearanceMode: $bindings.appearanceMode,
                                textSize: $bindings.textSize,
                                appLanguage: $bindings.appLanguage,
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
                                appLanguage: $bindings.appLanguage,
                                showMicrophoneButton: $bindings.showMicrophoneButton,
                                enableActionButtons: $bindings.enableActionButtons,
                                showMenuBarExtra: $bindings.showMenuBarExtra,
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
                    NavigationLink(value: SettingsRoute.reminder) {
                        SettingsLinkLabel(
                            title: SharedStrings.reminder,
                            systemImage: "bell.badge",
                            caption: "Choose what information is shown with each reminder.")
                    }
                    .accessibilityIdentifier("settingsReminderRow")
                    NavigationLink {
                        FilterSortSettingsView(
                            sortOption: $bindings.sortOption,
                            aiSortRules: $bindings.aiSortRules,
                            showUndatedReminders: $bindings.showUndatedReminders,
                            isAIRankingAvailable: bindings.isAIRankingAvailable,
                            availableLists: availableLists,
                            excludedLists: $excludedLists,
                            store: store)
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
                    let purchaseTitle: LocalizedStringResource =
                        entitlementStore.isEntitled ? "Manage Purchase" : "Unlock"
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
                    Toggle(isOn: $bindings.crashReportingEnabled) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Share crash reports")
                                SettingsCaption(
                                    text: "Send crash and diagnostic data to help fix bugs.")
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
                    .accessibilityIdentifier("crashReportingToggle")
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
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .reminder:
                    ReminderSettingsView(
                        showDate: $bindings.showDate,
                        showList: $bindings.showList,
                        showRecurrence: $bindings.showRecurrence,
                        showAlarms: $bindings.showAlarms,
                        showCompletionGlow: $bindings.showCompletionGlow,
                        showCompletionMomentum: $bindings.showCompletionMomentum,
                        viewModel: viewModel)
                }
            }
            .localizedNavigationTitle("Settings")
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
        .onDisappear {
            // Drop the seeded route when the sheet goes away so a re-presented
            // Settings opens at its root. Reading `path` directly — not only
            // through `$path` — is also what keeps it visible to Periphery,
            // which misses `$`-projection-only `@State` under Xcode 27 and would
            // otherwise report the property as unused.
            if !path.isEmpty {
                path = NavigationPath()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss)
    private var dismiss

    @State private var path: NavigationPath

    @Binding private var excludedLists: Set<String>

    @Bindable private var bindings: SettingsBindings

    private let viewModel: SettingsViewModel
    private let store: ReminderStore
    private let backgroundImage: BackgroundImageStore
    private let availableLists: [String]
    private let entitlementStore: EntitlementStore
}

// MARK: - Previews

#Preview("Default") {
    SettingsView(
        bindings: SettingsBindings(),
        backgroundImage: BackgroundImageStore(),
        store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
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
        store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
        availableLists: ["Work", "Personal"],
        excludedLists: .constant([]))
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

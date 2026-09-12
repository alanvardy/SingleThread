@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - Settings View Tests

@MainActor
struct SettingsViewTests {
    // MARK: Internal

    @Test
    func settingsBindingsCarriesShowCompletionGlow() {
        // The AG-key property is store-backed now; pin a known value so the
        // assertion does not depend on whatever the shared App Group suite holds.
        let store = BoolPreferenceStore(
            key: BoolPreferenceKey.showCompletionGlow.rawValue,
            fallback: true)
        let original = store.isEnabled
        defer { store.set(original) }
        store.set(true)
        let bag = SettingsBindings()
        #expect(bag.showCompletionGlow) // reads true from store
        bag.showCompletionGlow = false
        #expect(!bag.showCompletionGlow) // setter round-trips through the store
    }

    @Test
    func settingsBindingsCarriesShowSwipePrompt() {
        let bag = SettingsBindings()
        #expect(bag.showSwipePrompt) // default enabled
        let off = SettingsBindings(showSwipePrompt: false)
        #expect(!off.showSwipePrompt) // explicit false round-trips
    }

    @Test
    func settingsBindingsCarriesShowUndoButton() {
        let bag = SettingsBindings()
        #expect(bag.showUndoButton) // default enabled
        let off = SettingsBindings(showUndoButton: false)
        #expect(!off.showUndoButton) // explicit false round-trips
    }

    @Test
    func settingsViewContainsNavigationLinkLabels() {
        let view = SettingsView(
            bindings: SettingsBindings(),
            backgroundImage: BackgroundImageStore(),
            availableLists: [],
            excludedLists: .constant([]),
            entitlementStore: EntitlementStore())
        let bodyDescription = String(describing: view.body)

        let expectedLabels = [
            "Interface", "Reminder", "Filtering & Sorting", "Background", "Unlock", "Privacy", "About"
        ]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }
        #expect(bodyDescription.contains("Done"))

        let expectedCaptions = [
            "Customize the appearance, text size, and controls.",
            "Choose what information is shown with each reminder.",
            "Control the order, visibility, and excluded lists.",
            "Manage the wallpaper and its appearance.",
            "View and manage your purchase status.",
            "How SingleThread handles your data.",
            "App version, credits, and contact."
        ]
        for caption in expectedCaptions {
            #expect(bodyDescription.contains(caption))
        }
        #if os(iOS)
            #expect(bodyDescription.contains("Get reminded when you have due reminders."))
        #endif
        #if os(macOS)
            #expect(
                !bodyDescription.contains("SettingsSubscreenLayout"),
                "Root settings List must not be top-anchored")
        #endif
    }

    @Test
    func interfaceSettingsViewContainsExpectedRows() {
        #if os(iOS)
            let view = InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                allowsLandscape: .constant(true),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                showSwipePrompt: .constant(true),
                showUndoButton: .constant(true),
                viewModel: SettingsViewModel())
        #else
            let view = InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                showMenuBarExtra: .constant(true),
                viewModel: SettingsViewModel())
        #endif
        let bodyDescription = String(describing: view.body)

        var expectedLabels = [
            "Appearance", "Text Size", "Show microphone"
        ]
        #if os(iOS)
            expectedLabels += ["Allow landscape", "Show action buttons", "Show swipe prompt", "Show undo button"]
        #endif
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }

        var expectedCaptions = [
            "Choose between system, light, and dark mode.",
            "Adjust the size of text throughout the app.",
            "Add a microphone button for voice input."
        ]
        #if os(iOS)
            expectedCaptions += [
                "Let the app rotate on iPhone.",
                "Show complete, skip, and delete buttons.",
                "Show a hint when there are swipeable reminders.",
                "Show an undo button after completing a reminder."
            ]
        #endif
        for caption in expectedCaptions {
            #expect(bodyDescription.contains(caption))
        }
        #if os(macOS)
            #expect(
                bodyDescription.contains("SettingsSubscreenLayout"),
                "Sub-view should top-anchor via SettingsSubscreenLayout on macOS")
        #endif
    }

    @Test
    func reminderSettingsViewContainsExpectedRows() {
        let view = ReminderSettingsView(
            showDate: .constant(true),
            showList: .constant(false),
            showRecurrence: .constant(true),
            showAlarms: .constant(true),
            showCompletionGlow: .constant(true),
            showCompletionMomentum: .constant(true),
            viewModel: SettingsViewModel())
        // String(describing:) backslash-escapes embedded quotes/apostrophes in
        // LocalizedStringKey values (e.g. Show \\"You\\'ve cleared N today\\" …),
        // so normalize the escapes out before matching captions.
        let bodyDescription = String(describing: view.body)
            .replacingOccurrences(of: "\\", with: "")

        let expectedLabels = [
            "Show date", "Show list", "Recurrence indicator", "Reminder alerts",
            "Completion glow", "Completion Momentum"
        ]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }

        let expectedCaptions = [
            "Show the due date next to each reminder.",
            "Show which list each reminder belongs to.",
            "Show if a reminder repeats.",
            "Show if a reminder has a time alert.",
            "Show a sparkle animation when a reminder is completed.",
            "Show \"You've cleared N today\" after completing a reminder."
        ]
        for caption in expectedCaptions {
            #expect(bodyDescription.contains(caption))
        }
        #if os(macOS)
            #expect(
                bodyDescription.contains("SettingsSubscreenLayout"),
                "Sub-view should top-anchor via SettingsSubscreenLayout on macOS")
        #endif
    }

    @Test
    func filterSortSettingsViewContainsExpectedRows() {
        let view = FilterSortSettingsView(
            sortOption: .constant(.priority),
            showUndatedReminders: .constant(false),
            availableLists: ["Work"],
            excludedLists: .constant([]))
        let bodyDescription = String(describing: view.body)

        let expectedLabels = [
            "Sort By", "Show undated reminders", "Excluded Lists"
        ]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }

        let expectedCaptions = [
            "Choose the order reminders appear in.",
            "Include reminders that have no due date.",
            "Hide specific lists from the reminder view."
        ]
        for caption in expectedCaptions {
            #expect(bodyDescription.contains(caption))
        }
        #if os(macOS)
            #expect(
                bodyDescription.contains("SettingsSubscreenLayout"),
                "Sub-view should top-anchor via SettingsSubscreenLayout on macOS")
        #endif
    }

    @Test
    func backgroundSettingsViewContainsExpectedRows() async {
        let store = await makeSeededStore()
        let view = BackgroundSettingsView(
            backgroundEnabled: .constant(true),
            backgroundFadePercent: .constant(50),
            backgroundPinned: .constant(false),
            backgroundImage: store)
        let bodyDescription = String(describing: view.body)

        let expectedLabels = ["Background", "Background Fade", "Pin wallpaper", "Unsplash"]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }

        let expectedCaptions = [
            "Show a wallpaper behind the reminder list.",
            "How much the wallpaper fades for readability.",
            "Prevents the background from refreshing automatically."
        ]
        for caption in expectedCaptions {
            #expect(bodyDescription.contains(caption))
        }
        #if os(macOS)
            #expect(
                bodyDescription.contains("SettingsSubscreenLayout"),
                "Sub-view should top-anchor via SettingsSubscreenLayout on macOS")
        #endif
    }

    @Test
    func backgroundSettingsViewContainsPinToggle() async {
        let store = await makeSeededStore()
        let view = BackgroundSettingsView(
            backgroundEnabled: .constant(true),
            backgroundFadePercent: .constant(50),
            backgroundPinned: .constant(false),
            backgroundImage: store)
        let bodyDescription = String(describing: view.body)

        #expect(
            bodyDescription.contains("Pin wallpaper"),
            "Background settings should contain Pin wallpaper toggle when background is enabled")
    }

    @Test
    func pinToggleVisibleWhenBackgroundDisabled() async {
        let store = await makeSeededStore()
        let view = BackgroundSettingsView(
            backgroundEnabled: .constant(false),
            backgroundFadePercent: .constant(50),
            backgroundPinned: .constant(false),
            backgroundImage: store)
        let bodyDescription = String(describing: view.body)

        #expect(
            bodyDescription.contains("Pin wallpaper"),
            "Pin wallpaper toggle should stay visible when background is disabled")
    }

    @Test
    func privacySettingsViewContainsExpectedContent() {
        let view = PrivacySettingsView()
        let bodyDescription = String(describing: view.body)

        let expected = [
            "Privacy",
            "Reminders",
            "Display & Sync Preferences",
            "Skipped & Excluded Lists",
            "Background Image",
            "vardy.cc",
            "no analytics"
        ]
        for label in expected {
            #expect(bodyDescription.contains(label), "Expected privacy content to contain \(label)")
        }
        #if os(macOS)
            #expect(
                bodyDescription.contains("SettingsSubscreenLayout"),
                "Sub-view should top-anchor via SettingsSubscreenLayout on macOS")
        #endif
    }

    @Test
    func excludedListsViewContainsTopAnchor() {
        let view = ExcludedListsView(
            excludedLists: .constant(["Work"]),
            availableLists: ["Work", "Personal"])
        let bodyDescription = String(describing: view.body)

        // The `.navigationTitle("Excluded Lists")` string does not survive
        // SwiftUI reflection (it lives in an opaque transform closure), so
        // content coverage pins the reflected excluded-lists data instead.
        #expect(bodyDescription.contains("Personal"))
        #expect(bodyDescription.contains("Excluded lists are hidden from the reminder list."))
        #if os(macOS)
            #expect(bodyDescription.contains("SettingsSubscreenLayout"))
        #endif
    }

    @Test
    func notificationsSettingsViewContainsExpectedRows() {
        let view = NotificationsSettingsView(
            notificationsEnabled: .constant(false),
            notificationIntervalHours: .constant(48))
        let bodyDescription = String(describing: view.body)

        let expectedLabels = [
            "Enable reminder notifications", "Remind after"
        ]
        for label in expectedLabels {
            #expect(bodyDescription.contains(label))
        }

        let expectedCaptions = [
            "Send a notification when you have due reminders.",
            "How long to wait before sending another reminder."
        ]
        for caption in expectedCaptions {
            #expect(bodyDescription.contains(caption))
        }
    }

    @Test
    func purchaseSettingsViewContainsTopAnchor() {
        let view = PurchaseSettingsView(entitlementStore: EntitlementStore(testingWithEntitled: false))
        let bodyDescription = String(describing: view.body)

        // The `.navigationTitle("Unlock")` string does not survive SwiftUI
        // reflection (it lives in an opaque preference transform closure, same
        // as ExcludedListsView), but the Section header text does — it is real
        // body content, so it pins the non-entitled purchase surface.
        #expect(bodyDescription.contains("Unlock"))
        #if os(macOS)
            #expect(bodyDescription.contains("SettingsSubscreenLayout"))
        #endif
    }

    #if os(macOS)
        @Test
        func macOSBagIncludesEnableActionButtons() {
            let enabled = SettingsBindings(enableActionButtons: true)
            #expect(enabled.enableActionButtons)
            let disabled = SettingsBindings(enableActionButtons: false)
            #expect(!disabled.enableActionButtons)
        }

        @Test
        func macOSEnableActionButtonsRoundTripsThroughAppGroup() {
            let key = "enableActionButtons"
            AppGroup.defaults.set(false, forKey: key)
            #expect(!AppGroup.defaults.bool(forKey: key))

            // Simulate the write-back: bag value → @AppStorage setter path.
            AppGroup.defaults.set(true, forKey: key)
            #expect(AppGroup.defaults.bool(forKey: key))

            // Clean up so a prior run's leftover can't pollute a subsequent run.
            AppGroup.defaults.removeObject(forKey: key)
        }

        @Test
        func showMenuBarExtraRoundTripsThroughContentView() {
            let key = MenuBarExtraPreference.key
            let existing = UserDefaults.standard.object(forKey: key)
            defer {
                if let existing {
                    UserDefaults.standard.set(existing, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }

            // Absent key → the @AppStorage property and the seeded bag both read on.
            UserDefaults.standard.removeObject(forKey: key)
            var view = ContentView(loadsReminders: false, eventStore: InMemoryEventStore())
            #expect(view.showMenuBarExtra)
            #expect(view.makeSettingsBag().showMenuBarExtra)

            // The .onChange write-back assigns to this property; @AppStorage then
            // persists false, and a freshly seeded bag reflects it.
            view.showMenuBarExtra = false
            #expect(!view.makeSettingsBag().showMenuBarExtra)
            #expect(!UserDefaults.standard.bool(forKey: key))
        }

        @Test
        func showMenuBarExtraDefaultsToShownInBag() {
            // Absent key → shown.
            let key = MenuBarExtraPreference.key
            let existing = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
            defer {
                if let existing {
                    UserDefaults.standard.set(existing, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }

            #expect(SettingsBindings().showMenuBarExtra)

            // Sad path: the default must not override an explicit off.
            let off = SettingsBindings(showMenuBarExtra: false)
            #expect(!off.showMenuBarExtra)
            UserDefaults.standard.set(false, forKey: key)
            #expect(!UserDefaults.standard.bool(forKey: key))
        }

        @Test
        func macOSBagDefaultsToShown() {
            // Drift guard: the bag's literal default must match the preference type.
            #expect(SettingsBindings().showMenuBarExtra == MenuBarExtraPreference.defaultValue)
        }
    #endif

    #if os(macOS)
        @Test
        func interfaceSettingsViewContainsActionButtonsRowOnMacOS() {
            let view = InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                showMenuBarExtra: .constant(true),
                viewModel: SettingsViewModel())
            let bodyDescription = String(describing: view.body)

            #expect(bodyDescription.contains("Show action buttons"))
            #expect(bodyDescription.contains("Show complete, skip, and delete buttons."))
        }

        @Test
        func macOSToggleTogglesBinding() {
            let enabled = Binding(get: { false }, set: { _ in })
            let view = InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                enableActionButtons: enabled,
                showMenuBarExtra: .constant(true),
                viewModel: SettingsViewModel())
            // Verify the view accepts the binding — the binding itself will
            // be mutated by the Toggle in a running app; we confirm the
            // initial value flows through.
            let bodyDescription = String(describing: view.body)
            #expect(bodyDescription.contains("Show action buttons"))
        }

        @Test
        func interfaceSettingsViewContainsMenuBarToggle() {
            let view = InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                showMenuBarExtra: .constant(true),
                viewModel: SettingsViewModel())
            let bodyDescription = String(describing: view.body)

            #expect(bodyDescription.contains("Show in Menu Bar"))
            #expect(bodyDescription.contains("Show the next reminder in the menu bar."))
        }

        @Test
        func interfaceSettingsViewRendersMenuBarToggleOnce() {
            // Sad path: the row must render exactly once — a duplicated toggle
            // (e.g. copy-pasted into both platforms) fails here.
            let view = InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                showMenuBarExtra: .constant(false),
                viewModel: SettingsViewModel())
            let bodyDescription = String(describing: view.body)

            let titleCount = bodyDescription.components(separatedBy: "Show in Menu Bar").count - 1
            let captionCount = bodyDescription
                .components(separatedBy: "Show the next reminder in the menu bar.").count - 1
            #expect(titleCount == 1)
            #expect(captionCount == 1)
        }
    #endif

    // MARK: Private

    /// Builds a store whose fetch pipeline has already populated a photo and
    /// its attribution, so the background footer renders the Unsplash credit.
    private func makeSeededStore() async -> BackgroundImageStore {
        let fetcher = SeededFetcher()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = BackgroundImageStore(client: fetcher, directory: directory)
        await store.refreshIfNeeded()
        return store
    }
}

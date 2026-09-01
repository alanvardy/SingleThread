import SingleThreadCore
import SwiftUI

extension ContentView {
    /// Builds the Settings sheet content. The write-back chain is split into
    /// staged values so each expression stays within the compiler's type-check
    /// budget (a single 17-modifier chain does not).
    func settingsSheetWritebacks(_ bag: SettingsBindings) -> some View {
        let withAppearance = SettingsView(
            bindings: bag,
            backgroundImage: viewModel.backgroundImage,
            availableLists: viewModel.store.availableLists,
            excludedLists: excludedListsBinding,
            entitlementStore: viewModel.store.entitlementStore,
            viewModel: SettingsViewModel())
            // The bag is a plain in-memory holder; write each changed value
            // back to the @AppStorage-backed property so settings survive
            // relaunch (mirrors the old direct-bind behavior).
            .onChange(of: bag.appearanceMode) { _, new in appearanceMode = new }
            .onChange(of: bag.textSize) { _, new in textSize = new }
        #if os(iOS)
            let withIOSPreferences = withAppearance
                .onChange(of: bag.allowsLandscape) { _, new in allowsLandscape = new }
                .onChange(of: bag.enableActionButtons) { _, new in enableActionButtons = new }
                .onChange(of: bag.showSwipePrompt) { _, new in showSwipePrompt = new }
                .onChange(of: bag.showUndoButton) { _, new in showUndoButton = new }
                .onChange(of: bag.notificationsEnabled) { _, new in notificationsEnabled = new }
                .onChange(of: bag.notificationIntervalHours) { _, new in notificationIntervalHours = new }
        #else
            let withIOSPreferences = withAppearance
        #endif
        return withIOSPreferences
            .onChange(of: bag.showMicrophoneButton) { _, new in showMicrophoneButton = new }
            .onChange(of: bag.backgroundEnabled) { _, new in backgroundEnabled = new }
            .onChange(of: bag.backgroundFadePercent) { _, new in backgroundFadePercent = new }
            .onChange(of: bag.showUndatedReminders) { _, new in showUndatedReminders = new }
            .onChange(of: bag.sortOption) { _, new in sortOption = new }
            .onChange(of: bag.showDate) { _, new in showDate = new }
            .onChange(of: bag.showList) { _, new in showList = new }
            .onChange(of: bag.showRecurrence) { _, new in showRecurrence = new }
            .onChange(of: bag.showAlarms) { _, new in showAlarms = new }
            .onChange(of: bag.showCompletionGlow) { _, new in showCompletionGlow = new }
    }

    /// Builds a fresh bindings bag from the current `@AppStorage`-backed
    /// preference values.
    @MainActor
    func makeSettingsBag() -> SettingsBindings {
        #if os(iOS)
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                allowsLandscape: allowsLandscape,
                enableActionButtons: enableActionButtons,
                showSwipePrompt: showSwipePrompt,
                showUndoButton: showUndoButton,
                notificationsEnabled: notificationsEnabled,
                notificationIntervalHours: notificationIntervalHours,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                backgroundFadePercent: backgroundFadePercent,
                backgroundPinned: backgroundPinned,
                showUndatedReminders: showUndatedReminders,
                sortOption: sortOption,
                showDate: showDate,
                showList: showList,
                showRecurrence: showRecurrence,
                showAlarms: showAlarms,
                showCompletionGlow: showCompletionGlow)
        #else
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                backgroundFadePercent: backgroundFadePercent,
                backgroundPinned: backgroundPinned,
                showUndatedReminders: showUndatedReminders,
                sortOption: sortOption,
                showDate: showDate,
                showList: showList,
                showRecurrence: showRecurrence,
                showAlarms: showAlarms,
                showCompletionGlow: showCompletionGlow)
        #endif
    }
}

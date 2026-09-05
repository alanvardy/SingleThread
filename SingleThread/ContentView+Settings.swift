import SingleThreadCore
import SwiftUI

extension ContentView {
    /// Builds the Settings sheet content. The write-back chain is split into
    /// staged values so each expression stays within the compiler's type-check
    /// budget (a single 13-modifier chain on macOS, 19 on iOS, does not).
    func settingsSheetWritebacks(_ bag: SettingsBindings) -> some View {
        let withAppearance = SettingsView(
            bindings: bag,
            backgroundImage: viewModel.backgroundImage,
            availableLists: viewModel.store.availableLists,
            excludedLists: excludedListsBinding,
            entitlementStore: viewModel.store.entitlementStore,
            viewModel: SettingsViewModel())
            // Standard-suite keys are plain in-memory values; write each change
            // back to the @AppStorage-backed property so settings survive relaunch.
            // App-Group keys write straight through their store types instead
            // (computed props on the bag), so no write-back handlers exist for them.
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
        #elseif os(macOS)
            let withIOSPreferences = withAppearance
        #endif
        return withIOSPreferences
            .onChange(of: bag.showMicrophoneButton) { _, new in showMicrophoneButton = new }
            .onChange(of: bag.backgroundEnabled) { _, new in backgroundEnabled = new }
            .onChange(of: bag.backgroundFadePercent) { _, new in backgroundFadePercent = new }
            .onChange(of: bag.backgroundPinned) { _, new in backgroundPinned = new }
    }

    /// Builds a fresh bindings bag. Standard-suite values come from the current
    /// `@AppStorage`-backed properties; App-Group AG keys are computed on the bag
    /// from their store types, so they need no arguments here.
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
                backgroundPinned: backgroundPinned)
        #elseif os(macOS)
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                backgroundFadePercent: backgroundFadePercent,
                backgroundPinned: backgroundPinned)
        #endif
    }
}

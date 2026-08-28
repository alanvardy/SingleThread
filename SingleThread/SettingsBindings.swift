import SingleThreadCore
import SwiftUI

/// Single bag of all @AppStorage-backed preference values, passed down from
/// SettingsView to sub-views via @Bindable. Owned by SettingsView; mirrors the
/// @AppStorage defaults from ContentView exactly. `excludedLists` is NOT here:
/// it is store-backed (not @AppStorage) and is passed to sub-views as a separate
/// `Binding<Set<String>>`.
///
/// `allowsLandscape` and `enableActionButtons` are iOS-only in ContentView, but
/// the compiler does not support `#if` directives inside a parameter list, so
/// they are declared unconditionally here with their ContentView defaults. On
/// macOS they are harmless: the values are simply never wired or read.
@MainActor
@Observable
final class SettingsBindings {
    // MARK: Lifecycle

    init(
        appearanceMode: AppearanceMode = .system,
        textSize: TextSize = .system,
        allowsLandscape: Bool = true,
        enableActionButtons: Bool = false,
        showSwipePrompt: Bool = true,
        showMicrophoneButton: Bool = true,
        backgroundEnabled: Bool = true,
        backgroundFadePercent: Int = 50,
        showUndatedReminders: Bool = false,
        sortOption: SortOption = .priority,
        showDate: Bool = true,
        showList: Bool = false,
        showRecurrence: Bool = true,
        showAlarms: Bool = true,
        showCompletionGlow: Bool = true) {
        self.appearanceMode = appearanceMode
        self.textSize = textSize
        self.allowsLandscape = allowsLandscape
        self.enableActionButtons = enableActionButtons
        self.showSwipePrompt = showSwipePrompt
        self.showMicrophoneButton = showMicrophoneButton
        self.backgroundEnabled = backgroundEnabled
        self.backgroundFadePercent = backgroundFadePercent
        self.showUndatedReminders = showUndatedReminders
        self.sortOption = sortOption
        self.showDate = showDate
        self.showList = showList
        self.showRecurrence = showRecurrence
        self.showAlarms = showAlarms
        self.showCompletionGlow = showCompletionGlow
    }

    // MARK: Internal

    var appearanceMode: AppearanceMode
    var textSize: TextSize
    var allowsLandscape: Bool
    var enableActionButtons: Bool
    var showSwipePrompt: Bool
    var showMicrophoneButton: Bool
    var backgroundEnabled: Bool
    var backgroundFadePercent: Int
    var showUndatedReminders: Bool
    var sortOption: SortOption
    var showDate: Bool
    var showList: Bool
    var showRecurrence: Bool
    var showAlarms: Bool
    var showCompletionGlow: Bool
}

import SingleThreadCore
import SwiftUI

/// Single bag of all preference values, passed down from
/// SettingsView to sub-views via @Bindable. Owned by SettingsView.
/// The Standard-suite values mirror the `@AppStorage` defaults from ContentView
/// exactly. `excludedLists` is NOT here: it is store-backed (not @AppStorage)
/// and is passed to sub-views as a separate `Binding<Set<String>>`.
///
/// The seven App-Group keys are computed store-backed properties: reading/writing
/// them goes straight through the store types, which post
/// `UserDefaults.didChangeNotification` on the App Group suite, so `PreferenceHolder`
/// refreshes the main view automatically. No init arguments (or write-back
/// `.onChange` handlers) exist for them.
///
/// `allowsLandscape`, `enableActionButtons`, `showSwipePrompt`, `showUndoButton`,
/// `notificationsEnabled`, and `notificationIntervalHours` are iOS-only in
/// ContentView, but the compiler does not support `#if` directives inside a
/// parameter list, so they are declared unconditionally here with their
/// ContentView defaults. On macOS they are harmless: the values are simply
/// never wired or read.
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
        showUndoButton: Bool = true,
        notificationsEnabled: Bool = false,
        notificationIntervalHours: Int = 48,
        showMicrophoneButton: Bool = true,
        backgroundEnabled: Bool = true,
        backgroundFadePercent: Int = 50,
        backgroundPinned: Bool = false) {
        self.appearanceMode = appearanceMode
        self.textSize = textSize
        self.allowsLandscape = allowsLandscape
        self.enableActionButtons = enableActionButtons
        self.showSwipePrompt = showSwipePrompt
        self.showUndoButton = showUndoButton
        self.notificationsEnabled = notificationsEnabled
        self.notificationIntervalHours = notificationIntervalHours
        self.showMicrophoneButton = showMicrophoneButton
        self.backgroundEnabled = backgroundEnabled
        self.backgroundFadePercent = backgroundFadePercent
        self.backgroundPinned = backgroundPinned
    }

    // MARK: Internal

    var appearanceMode: AppearanceMode
    var textSize: TextSize
    var allowsLandscape: Bool
    var enableActionButtons: Bool
    var showSwipePrompt: Bool
    var showUndoButton: Bool
    var notificationsEnabled: Bool
    var notificationIntervalHours: Int
    var showMicrophoneButton: Bool
    var backgroundEnabled: Bool
    var backgroundFadePercent: Int
    var backgroundPinned: Bool

    // MARK: - App-Group preferences (store-backed, observable)

    /// Computed from the store so the sheet always opens with the current value
    /// and every write persists immediately (no @AppStorage round-trip). Views
    /// reading the property register observation through the macro-generated
    /// `access(keyPath:)`/`withMutation(keyPath:)` members, exactly like a
    /// tracked stored property — otherwise a `@Bindable` binding write would not
    /// invalidate SwiftUI and toggles would stay visually stale.
    var showUndatedReminders: Bool {
        get {
            access(keyPath: \.showUndatedReminders)
            return showUndatedPreference.isEnabled
        }
        set {
            withMutation(keyPath: \.showUndatedReminders) {
                showUndatedPreference.set(newValue)
            }
        }
    }

    var sortOption: SortOption {
        get {
            access(keyPath: \.sortOption)
            return sortStore.load()
        }
        set {
            withMutation(keyPath: \.sortOption) {
                sortStore.save(newValue)
            }
        }
    }

    var showDate: Bool {
        get {
            access(keyPath: \.showDate)
            return showDatePreference.isEnabled
        }
        set {
            withMutation(keyPath: \.showDate) {
                showDatePreference.set(newValue)
            }
        }
    }

    var showList: Bool {
        get {
            access(keyPath: \.showList)
            return showListPreference.isEnabled
        }
        set {
            withMutation(keyPath: \.showList) {
                showListPreference.set(newValue)
            }
        }
    }

    var showRecurrence: Bool {
        get {
            access(keyPath: \.showRecurrence)
            return showRecurrencePreference.isEnabled
        }
        set {
            withMutation(keyPath: \.showRecurrence) {
                showRecurrencePreference.set(newValue)
            }
        }
    }

    var showAlarms: Bool {
        get {
            access(keyPath: \.showAlarms)
            return showAlarmsPreference.isEnabled
        }
        set {
            withMutation(keyPath: \.showAlarms) {
                showAlarmsPreference.set(newValue)
            }
        }
    }

    var showCompletionGlow: Bool {
        get {
            access(keyPath: \.showCompletionGlow)
            return showCompletionGlowPreference.isEnabled
        }
        set {
            withMutation(keyPath: \.showCompletionGlow) {
                showCompletionGlowPreference.set(newValue)
            }
        }
    }

    // MARK: Private

    private let showUndatedPreference = ShowUndatedRemindersPreference()
    private let sortStore = SortOptionStore()
    private let showDatePreference = ShowDatePreference()
    private let showListPreference = ShowListPreference()
    private let showRecurrencePreference = ShowRecurrencePreference()
    private let showAlarmsPreference = ShowAlarmsPreference()
    private let showCompletionGlowPreference = ShowCompletionGlowPreference()
}

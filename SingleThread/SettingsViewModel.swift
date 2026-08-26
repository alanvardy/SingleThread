import SwiftUI
#if os(iOS) || os(macOS)
    import WidgetKit
#endif

/// Owns the Settings screen's device-level and widget side effects so the view
/// stays a pure display of preference bindings. Each method is a thin
/// delegation with no stored state.
@MainActor
@Observable
final class SettingsViewModel {
    #if os(iOS)
        func allowsLandscapeChanged(_ value: Bool) {
            AppDelegate.applyLock(allowsLandscape: value)
        }
    #endif

    #if os(iOS) || os(macOS)
        func showDateChanged(_: Bool) {
            WidgetCenter.shared.reloadAllTimelines()
        }

        func showRecurrenceChanged(_: Bool) {
            WidgetCenter.shared.reloadAllTimelines()
        }

        func showAlarmsChanged(_: Bool) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    #endif
}

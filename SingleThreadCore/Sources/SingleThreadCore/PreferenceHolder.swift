import Foundation

/// Single observable holder for all App-Group preference values consumed by the
/// iOS app's main view. Replaces the 7 `@AppStorage` AG-key declarations in
/// ContentView. Mirrors the watch `Show*State` pattern — reads from store types
/// on init, auto-refreshes on `didChangeNotification` for the App Group suite.
@MainActor
@Observable
public final class PreferenceHolder {
    // MARK: Lifecycle

    public init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: AppGroup.defaults,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: Public

    public var showUndatedReminders = false
    public var sortOption = SortOption.priority
    public var showDate = true
    public var showList = false
    public var showRecurrence = true
    public var showAlarms = true
    public var showCompletionGlow = true

    // MARK: Private

    /// Referenced from `deinit`, which is nonisolated in Swift 6, so the token
    /// escapes MainActor isolation. Touched only from `init` (registration) and
    /// `deinit` (removal), which cannot overlap.
    @ObservationIgnored private nonisolated(unsafe) var observer: NSObjectProtocol?

    private func refresh() {
        showUndatedReminders = BoolPreferenceStore(
            key: BoolPreferenceKey.showUndatedReminders.rawValue,
            fallback: false).isEnabled
        sortOption = SortOptionStore().load()
        showDate = BoolPreferenceStore(key: BoolPreferenceKey.showDate.rawValue, fallback: true).isEnabled
        showList = BoolPreferenceStore(key: BoolPreferenceKey.showList.rawValue, fallback: false).isEnabled
        showRecurrence = BoolPreferenceStore(
            key: BoolPreferenceKey.showRecurrence.rawValue,
            fallback: true).isEnabled
        showAlarms = BoolPreferenceStore(key: BoolPreferenceKey.showAlarms.rawValue, fallback: true).isEnabled
        showCompletionGlow = BoolPreferenceStore(
            key: BoolPreferenceKey.showCompletionGlow.rawValue,
            fallback: true).isEnabled
    }
}

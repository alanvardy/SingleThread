import Foundation
import SingleThreadCore

/// Reusable harness for cross-container verification on the watch.
/// Reads `AppGroup.suiteName` — never re-hardcodes the suite literal.
enum AppGroupHarness {
    /// True when the hosted watch bundle registered the shared group.
    static func suiteExists() -> Bool {
        UserDefaults(suiteName: AppGroup.suiteName) != nil
    }

    /// Seed `completionCount` into the group without touching `.standard`.
    static func seedCompletionCountInGroup(_ count: Int) {
        AppGroup.defaults.set(count, forKey: CompletionCounterStore.defaultsKey)
    }

    /// Remove `completionCount` from both containers (cleanup).
    static func clearCompletionCount() {
        AppGroup.defaults.removeObject(forKey: CompletionCounterStore.defaultsKey)
        UserDefaults.standard.removeObject(forKey: CompletionCounterStore.defaultsKey)
    }
}
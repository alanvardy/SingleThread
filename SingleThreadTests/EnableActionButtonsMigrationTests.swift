import Foundation
@testable import SingleThread
import SingleThreadCore
import Testing

/// Proves the one-shot migration in `AppViewModel.init` copies a legacy
/// `.standard` value into `AppGroup.defaults` so existing users keep their
/// action-buttons toggle after the move, while a fresh install (no `.standard`
/// value) stays default-off. Serialized: the suite runs on real UserDefaults.
@MainActor
@Suite(.serialized)
struct EnableActionButtonsMigrationTests {
    // MARK: Internal

    @Test
    func standardOnlyValueIsCopiedToAppGroup() {
        defer { clearKey() }
        UserDefaults.standard.removeObject(forKey: Self.key)
        AppGroup.defaults.removeObject(forKey: Self.key)
        UserDefaults.standard.set(true, forKey: Self.key)

        _ = AppViewModel(arguments: [])

        #expect(
            AppGroup.defaults.bool(forKey: Self.key),
            "migration copies the legacy .standard value into the App Group")
    }

    @Test
    func freshInstallLeavesAppGroupOff() {
        defer { clearKey() }
        UserDefaults.standard.removeObject(forKey: Self.key)
        AppGroup.defaults.removeObject(forKey: Self.key)

        _ = AppViewModel(arguments: [])

        #expect(
            !AppGroup.defaults.bool(forKey: Self.key),
            "no .standard value means nothing to migrate — default stays off")
    }

    // MARK: Private

    private static let key = "enableActionButtons"

    private func clearKey() {
        AppGroup.defaults.removeObject(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

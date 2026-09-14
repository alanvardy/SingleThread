import Foundation
@testable import SingleThread
import SingleThreadCore
import Testing

/// Proves the one-shot migration in `AppViewModel.init` copies a legacy
/// `.standard` value into `AppGroup.defaults` so existing users keep their
/// action-buttons toggle after the move, while a fresh install (no `.standard`
/// value) persists nothing. Serialized: the suite runs on real UserDefaults.
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
    func freshInstallLeavesNoAppGroupValue() {
        defer { clearKey() }
        UserDefaults.standard.removeObject(forKey: Self.key)
        AppGroup.defaults.removeObject(forKey: Self.key)

        _ = AppViewModel(arguments: [])

        #expect(
            AppGroup.defaults.object(forKey: Self.key) == nil,
            "fresh installs persist nothing; the default-on comes from the read sites")
    }

    @Test
    func existingAppGroupOffIsNotClobbered() {
        defer { clearKey() }
        UserDefaults.standard.removeObject(forKey: Self.key)
        AppGroup.defaults.set(false, forKey: Self.key)

        _ = AppViewModel(arguments: [])

        #expect(
            AppGroup.defaults.object(forKey: Self.key) != nil,
            "registerDefaults must not write over an existing App Group value")
        #expect(
            !AppGroup.defaults.bool(forKey: Self.key),
            "an explicitly toggled-off value stays off")
    }

    // MARK: Private

    private static let key = "enableActionButtons"

    private func clearKey() {
        AppGroup.defaults.removeObject(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

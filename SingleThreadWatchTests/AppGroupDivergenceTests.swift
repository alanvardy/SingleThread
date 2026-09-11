// No `@testable import SingleThreadWatch`: every symbol used here comes from
// SingleThreadCore (AppGroup, CompletionCounterStore). A testable import would
// be unused and fail the Periphery --strict gate.
import Foundation
import SingleThreadCore
import Testing

/// Proves the group suite and `UserDefaults.standard` are distinct containers
/// on the registered watch — the spike's acceptance criterion.
///
/// Uses `CompletionCounterStore(defaults:)`, the exact store back-end the
/// watch sync service invokes (`WatchAppViewModel.swift:244` reads `.standard`
/// while the receive path persists to the group `:197-199`).
@MainActor
@Suite(.serialized)
struct AppGroupDivergenceTests {
    // MARK: Internal

    // MARK: Happy-path

    /// Write-to-group does not appear in `.standard`, and the
    /// `.standard`-backed store reads 0.
    @Test
    func completionCountDivergesBetweenContainers() {
        defer { clearBoth() }

        // Probe-first ordering (design.md decision #3): divergence assertions
        // are only meaningful when the group suite actually resolves.
        #expect(
            AppGroupHarness.suiteExists(),
            "group suite must resolve before divergence assertions are meaningful")

        AppGroupHarness.seedCompletionCountInGroup(7)

        // Group-backed store sees the written value
        #expect(
            CompletionCounterStore(defaults: AppGroup.defaults).count == 7,
            "group store must read the value written to the group")

        // Standard-backed store (the watch sync-service divergence) reads 0
        #expect(
            CompletionCounterStore(defaults: .standard).count == 0,
            """
            standard store must NOT see group-only writes — \
            without divergence this bug is unobservable
            """)

        // Raw `.standard` also empty
        #expect(
            UserDefaults.standard.object(forKey: CompletionCounterStore.defaultsKey) == nil,
            "raw .standard should be empty after group-only write")
    }

    // MARK: Sad-path

    /// Write to `.standard` only — group stays absent. Proves divergence
    /// is bidirectional, not one-way.
    @Test
    func writingStandardDoesNotLeakIntoGroup() {
        defer { clearBoth() }

        let store = CompletionCounterStore(defaults: .standard)
        store.increment()
        store.increment()

        #expect(
            AppGroup.defaults.object(forKey: CompletionCounterStore.defaultsKey) == nil,
            "group must stay empty when only .standard is written")
    }

    // MARK: Private

    // MARK: Cleanup

    private func clearBoth() {
        AppGroupHarness.clearCompletionCount()
    }
}

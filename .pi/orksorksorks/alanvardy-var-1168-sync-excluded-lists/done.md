# Done

- **Branch / head SHA**: `alanvardy-var-1168-sync-excluded-lists` @ `1cb23259`
  (review fixes on top of the four phase commits + artifact/DELETEME chores).
- **Mechanical checks**:
  - `make format` clean; `make lint` (SwiftLint `--strict`) 0 violations / 237 files.
  - `make build` **TEST BUILD SUCCEEDED**; `make mac-build` **BUILD SUCCEEDED**.
  - Targeted suites, pinned to this worktree's simulator — all green:
    `ExcludedListCloudStoreTests` 8, `ExcludedListCloudSyncTests` 6,
    `ExcludedListCloudObserverWiringTests` 2, `ReminderStoreTests` 39,
    `EnableActionButtonsMigrationTests` 3, `UITestingSeedTests` 21, and
    `MicrophoneToggleTests` 19 (this one stalled once at the 600 s bound under
    cross-session `xcodebuild` contention; it passed on its clean run).
  - Full CI gate (`./scripts/test.sh`) ran via the `run-gate` skill in a managed
    worktree on `bbb85b4e`: **FAIL at the Periphery stage only** — the single
    finding is the pre-existing local-only Xcode-27 false positive
    `SingleThread/ReminderCardView.swift:74 'swipeOffset'`, a file this branch
    does not touch. Periphery is stage-fatal, so the test stages are *unknown,
    never green*; the branch is not implicated and CI is authority.
- **Review outcome** — one bounded `reviewer`, every finding cross-checked
  against source:
  - **B1 (blocker) fixed** — an empty local set no longer seeds `[]` into an
    absent cloud key (`seedIfAbsent` guards `!titles.isEmpty`), removing the
    fresh-install-wipes-another-device race. Tests: `emptySeedIsNeverWritten`,
    `emptyLocalSetDoesNotSeedTheCloud`.
  - **B2 (blocker) fixed** — the cloud store is resolved once through
    `makeCloudStore` and threaded into `makeStore`, so the injected seam and the
    store share one instance; `--no-reminders` was added to the UI-test guard.
    The four unit tests that built `AppViewModel(arguments: [])` now inject an
    `InMemoryUbiquitousStore` fake, so no test touches the real key-value store.
  - **B3 rejected** — watch-originated exclusions never reach iCloud, but the
    watch cannot originate exclusion edits (exclusions are phone→watch only per
    design decision 5; `WatchAppViewModel.swift:324` is a UI-test delivery
    seam), so this is out of scope, not a hole.
  - **Optional nits applied**: accurate `save`/`seedIfAbsent` return value and
    doc, reconciled unavailable-mode doc, strengthened
    `absentKeyDoesNotClearLocalSet` (now drives the apply path), and added
    `refreshExcludedListTitlesLeavesCloudUntouched`.
  - **Nits declined**: removing the observer token in `deinit` — Swift 6 rejects
    a nonisolated `deinit` reading the `@MainActor`-isolated token, matching the
    pre-existing `aiRulesObserver`/`syncDefaultsObserver` pattern; and dropping
    the synchronous `synchronize()` call (Apple guidance, but the current
    best-effort flush is benign and the change is out of scope).
- **Remaining manual items** (from `plan.md` / `implement.md`):
  - Re-run the full CI gate on the fix commit `1cb23259` (or let CI decide):
    the local gate cannot go green on Xcode 27 because of the pre-existing
    Periphery false positive.
  - Device/manual checks: two-device iCloud propagation and clear, watch still
    receives exclusions over WatchConnectivity, signed-out/degraded mode, and
    provisioning of `com.apple.developer.ubiquity-kvstore-identifier` on the
    App IDs before a real archive.

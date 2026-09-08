# Implementation Summary

Ticket: VAR-826 — Slim down unit tests
Branch: `alanvardy-var-826-slim-down-unit-tests`
PR: [#181](https://github.com/alanvardy/SingleThread/pull/181)
Plan: `.pi/orksorksorks/alanvardy-var-826-slim-down-unit-tests/plan.md`

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1 | `1d796d4` | Shared test-fixture files — canonical `TestFixtures.swift` per bundle (iOS + watch), 16 per-file fixture copies deleted, transcribers renamed to `TestFakeTranscriber` |
| 2 | `c83e742` | Dead and rotten tooling removal — deleted `SingleThreadUITestCase.swift`, fixed `count_tests.sh` (fresh numbers, dead `settle`/`forced` pattern blocks removed) |
| — | `5f34401` | chore: plan ledger correction — Phase 2's own deletion removes a `.launch()` site, so `launches` is 2 (iOS 1, watch 1), not the plan's pre-deletion 3 |
| 3 | `d13e60c` | Split brute-force multi-store tests — 8 old `@Test` bodies → 25 single-scenario tests (64 total; `#expect` set preserved 112 = 112; name `visibleRemindersFiltersExcludedListTitles` retained for its trio) |
| 4 | `b8b10d3` | Delete seam-identical cross-target mirror — 3 watch `@Test`s + watch `inListReminder` cut (`WatchSyncPipelineTests.swift` 551→421 lines) |
| 5 | `88f80ca` | Coverage guardrail + count_tests refresh — coverage diff clean (no cliff), trailing comments regenerated to final counts |

## What shipped

- **Phase 1**: one canonical fixture file per bundle holding the single module-internal copy of every duplicated fake/fixture (`sharedTestEventStore` + `makeReminder` overloads + `makeCalendar` + `inListReminder` + `FakeSession` + `TestFakeTranscriber` + background-fetcher fakes on iOS; `sharedWatchEventStore` + `watchReminder` + `WatchFakeSession` on watch). Per-file `private` copies deleted; distinct single-owner helpers (protocol methods, `canvasReminder`, the watch no-arg `watchReminder`, URL statics) kept per plan.
- **Phase 2**: `SingleThreadUITestCase.swift` gone (0 subclasses, 0 references — Periphery had been masking it). `count_tests.sh` now reports real numbers with no structurally-dead sleep-pattern metrics; keys stable.
- **Phase 3**: the 9 brute-force `ReminderStoreTests` bodies (each building 2–4 stores inline) partitioned into single-scenario `@Test`s; assertions byte-preserved.
- **Phase 4**: watch tests that re-proved the identical `InMemoryEventStore` seam the iOS bundle covers, cut. Watch-only receive/push tests, `receiveAppliesShowCompletionGlow`, `receivedPreferenceSurvivesRelaunch`, `receiveAbsentKeysAreNoOps`, and the `WatchEnableActionButtonsSyncTests` suite retained.
- **Phase 5**: coverage before/after diff — no `SingleThreadCore` line-coverage cliff (net overall coverage *rose* +0.30pp; the only stable app-code delta is 4 async scheduling-attribution lines in `AppViewModel.setupSyncObservation`, jitter in retained tests, not a deletion regression). `count_tests.sh` refreshed to final counts.

No production code, UI-suite, or target-topology changes in any phase.

## Deviations from the plan (all justified)

- **Phase 1 (plan-internal contradiction)**: the plan's prose "Deviation from structure.md" note (plan.md:32–37) says the iOS `inListReminder` "stays in SkippedReminderSyncServiceTests.swift" — but Phase 1 item 1's canonical fixture *includes* `inListReminder`, and item 8 *deletes* it from SKSS. The concrete change items (1+8) are mutually consistent and are the only reading that passes the plan's own `swiftlint --strict` gate (a kept SKSS copy would leave the canonical copy unused). **Followed items 1+8** — iOS `inListReminder` now lives module-internal in `TestFixtures.swift`. Single-line fix if the user prefers otherwise.
- **Phase 1**: `import EventKit` retained in 5 files (ListContentTests, ReminderStoreGateTests, SKSS, ReminderStoreWatchTests, WatchReminderViewModelTests) — the plan's "no new imports required" was technically true but the test bodies still reference EventKit symbols (`.fullAccess`, `.calendarItemIdentifier`) which require the import; removing it broke the build.
- **Phase 1**: removed the now-superfluous `// swiftlint:disable file_length` from `SkippedReminderSyncServiceTests.swift` (file fell 660→619 lines below the 650 warning; SwiftLint flagged the superfluous disable under `--strict`).
- **Phase 1 (behavioral nuance, no assertion depends on it)**: `ReminderStoreGateTests`' former private `makeReminder` defaulted `priority: 5`; the canonical defaults `priority: 0`. No gate test passes priority or reads it — semantics preserved.
- **Phase 2**: `launches` is 2 (iOS 1, watch 1), not the plan's 3 — the plan measured before its own `SingleThreadUITestCase.swift` deletion removed that class's `.launch()` site. `count_tests.sh` comments now carry the true 1/1.
- **Phase 5 destinations**: watch stages must pin `,OS=26.5` on this machine (the only "Apple Watch Series 11 (46mm)" is on watchOS 26.5, not the plan's 27.0); iOS must be `id=1583C89D-…` (a leftover "Gate iPhone 17" sim breaks name-only resolution).

## Automated Checks

- [x] SwiftFormat + SwiftLint `--strict` clean through every phase (`make lint`, 181 files, 0 violations)
- [x] Periphery `--strict` clean after Phases 1, 2, 4 (`SingleThreadUITestCase.swift` gone, no `inListReminder` dead-symbol warning)
- [x] Phase 1: iOS 10-suite targeted run green (pinned `id=1583C89D-…`); `make watch-test` green (46/46 on pinned watch, OS 26.5)
- [x] Phase 2: `bash scripts/count_tests.sh` — no `settle_sleeps`/`forced_400ms`; 565 / 1197 / 73 / 6 / 2.25 / 2 / 11 / 1009
- [x] Phase 3: `-only-testing:SingleThreadTests/ReminderStoreTests` green (68/68 cases, exit 0); `#expect` set preserved 112 = 112
- [x] Phase 4: `make watch-test` green (46/46 watch cases); retained `WatchSyncPipelineTests` suites pass
- [x] Phase 5: coverage diff — no `SingleThreadCore` line-coverage cliff (overall +0.30pp)
- [ ] Full `./scripts/test.sh` gate — **in flight** (async run-gate subagent in a managed worktree; verdict appended when it lands)

## Manual Verification Items (from the plan)

- [ ] `grep -rn "MicToggleFakeTranscriber\|ActionButtonFakeTranscriber\|GlowFakeTranscriber" SingleThreadTests/` returns nothing (Phase 1)
- [ ] `grep -rn "sharedTestEventStore\|sharedWatchEventStore" SingleThreadTests/ SingleThreadWatchTests/` shows only the two canonical declarations (+ no `private` copies) (Phase 1)
- [ ] `git status` shows `SingleThreadUITests/SingleThreadUITestCase.swift` deleted (Phase 2)
- [ ] No `#expect` was dropped in the Phase 3 split: diff shows the same set of assertions, partitioned, with no new logic
- [ ] `grep -rn "receiveAppliesEveryPresentKey\|excludedTitlesRefreshFiltersVisibleReminders\|receiveSkipCountsSavesAndFiresHookOnWatch" SingleThreadWatchTests/` returns nothing (Phase 4)
- [ ] PR description notes the ~17 test-count increase from splits (net suite is smaller in *maintenance* and *duplication* even though `@Test` count is flat/slightly up: 552→579, watch 44→41, iOS 521→538), and why no UI-test changes were made (Phase 5)
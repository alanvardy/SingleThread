# Implementation Summary

Ticket: VAR-796 — Slim down test suite
Branch: `alanvardy-var-796-slim-down-test-suite`
CI run: [34016920036](https://github.com/alanvardy/SingleThread/actions/runs/34016920036) — **all 11 jobs passed**

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1 | `da12318` | Protocol seam — `UserNotificationCentering` + recording fake + 6 unit tests |
| 2 | `c1f4f59` | Notification scheduling logic extracted — `NotificationScheduler` service, wired into `AppViewModel`, 9 unit tests |
| 3 | `68ce3de` | Timing injection seams — `--ui-testing-noop-settle` / `--ui-testing-reduced-glow` launch args |
| 4 | `60d736f` | UI test removal — cut 29 redundant tests (52 → 23 iOS UI tests) |
| — | (this commit) | `plan.md` full-gate checkboxes + `implement.md` |

## What shipped

- **Phase 1**: `@MainActor` `UserNotificationCentering` protocol (follows the `EventKitStoring` seam pattern), `UNUserNotificationCenter` conformance, public `FakeUserNotificationCenter`, 6 Swift Testing tests.
- **Phase 2**: `NotificationScheduler` service owning schedule/cancel/permission logic + UI-test summary seams; `AppViewModel` delegates to it; `idleReminderIdentifier`, `pendingSummary`/`lastScheduleSummary` storage, and the `refreshPendingSummary()`/`summary(requests:)` helpers moved off the view model. 9 scheduler tests.
- **Phase 3**: `--ui-testing-noop-settle` injects a no-op `settle:` (keeps the production 200 ms default when absent, preserving the relaunch-persistence trio); `--ui-testing-reduced-glow` shortens the completion glow to 0.1 s; `launchSeeded()` passes both.
- **Phase 4**: 29 UI tests cut, all behavior already proven at the unit layer: NotificationScheduling 4/4, NotificationsUITests 1 (kept a11y audit), Flows 17 (kept 12 integration-only), ActionMenu 4/4, SkipNudge 3 (kept iPad-geometry test). Empty class shells retained for NotificationScheduling/ActionMenu.

## Deviations from the plan (all justified)

- **Phase 2**: `NotificationScheduler` default defaults store is `UserDefaults.standard`, **not** `AppGroup.defaults` as written in the plan. The app's notification keys live in `.standard` (`@AppStorage` without `store:`); `AppGroup.defaults` would silently break the toggle→schedule round-trip. Matches design.md's "no new defaults keys". Supervisor-approved. `plan.md` snippet corrected.
- **Phase 2**: test suite names use UUIDs instead of `#function` (parallel static-helper collision). Plan typos fixed (`requestPermissionfNeeded`, `usesConfigredInterval`, missing brace, `cellcount`/comment mangling).
- **Phase 3**: real smoke-test name `testCompleteViaSwipeRemovesReminder` (plan typo'd `testCompleteViaswipe...`).
- **Phase 3**: `seededStore` takes an explicit `useNoopSettle` param threaded from `makeStore` (matches existing `arguments` style).
- **Phase 3 (lint fix, landed in Phase 4 commit)**: the `settle: {}` call sites shipped in Phase 3 were not lint-clean (swiftformat `conditionalAssignment`/`redundantType`, swiftlint `trailing_closure`), and `make format`'s `swiftlint --fix` corrupted them. `--unit-only` gates do not run format/lint, which is how this slipped past Phase 3. Rewritten to trailing-closure `{}` + `let store = if … else` — verified behavior-preserving (`swiftc` parse + build + all tests). Review: `git show 60d736f -- SingleThread/AppViewModel.swift`.

## Automated Checks

- [x] SwiftFormat + SwiftLint `--strict` clean (make lint, 174 files, 0 violations)
- [x] Periphery `--strict` clean (no new dead code; UI-test target excluded by config)
- [x] iOS unit tests — 483+ passing (incl. 6 `UserNotificationCenteringTests`, 9 `NotificationSchedulerTests`)
- [x] iOS UI tests — 23 remaining, all green
- [x] Watch build, watch UI tests, watch unit tests — green
- [x] macOS unit tests — green (see local caveat below)
- [x] Full CI matrix (11 jobs) — **green** on GitHub Actions
- [x] Phase gates: 6 fake tests (P1), 9 scheduler tests + full unit target (P2), make build + make test + smoke UI test with new args (P3), make build/lint/periphery (P4)

## Local-only caveats (NOT regressions)

- **iOS UI flakiness under parallel clones**: the local full gate's UI stage flaked on 4 tests (`testBackgroundAndPinTogglesPersistAcrossRelaunch`, `testSkipWithCrossDeviceCompletionShowsOnlyRemainingReminder`, `testRuntimeAppearanceToggle`, `testActionButtonsAccessibilityAudit`) with launch-`RequestDenied`/UI-query-timeout signatures from 4 concurrent simulator clones. All 4 pass 4/4 when run sequentially with `-parallel-testing-workers 1`, and all 4 corresponding CI jobs are green. CI is authoritative.
- **macOS `EntitlementStoreTests`**: `isEntitledSurvivesStoreRecreation` and `initialRefreshSettlesResolvedFlag` fail locally on macOS (StoreKit `SKTestSession` doesn't reach storekitd in an unsigned local build; cf. FB22237318 comment in the test). Verified **identical failures on `origin/main`** via a worktree — pre-existing local-machine issue, not introduced here. CI `mac-tests` passes.

## Notes for review

- `scheduleIfNeeded` now removes only the idle-identifier request (the old VM used `removeAllPendingNotificationRequests()`). The app only ever schedules that one identifier, so behavior is preserved.
- `--ui-testing-reduced-glow` overrides `--ui-testing-glow` (0.1 vs 2.0 s) if both are passed; the only callers passing the latter were the two glow tests cut in Phase 4.
- Empty `NotificationSchedulingUITests` / `ActionMenuUITests` class shells kept per the plan; build + lint + CI validate them.
- Good candidate for a follow-up (out of scope): migrate the notification keys to `AppGroup.defaults` so the phone/watch share them — the Phase 2 design consciously did NOT do this.

## Manual Verification Items (from the plan)

- [ ] Build and run on iOS simulator — toggle notifications in Settings, background the app, verify a notification is scheduled (check in Notification Center). (Phase 2)
- [ ] Optionally: `make coverage` diff to confirm behaviors moved from UI to unit still show in the unit coverage report. (Phase 4)
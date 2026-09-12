# Done

- **Branch / head SHA**: `alanvardy-var-978-reschedule-not-working-on-watch` @ `2030d349` (code under gate); PR #193.
- **Mechanical checks**:
  - `make lint` — 0 violations / 0 serious across 186 files; `make format` clean (tree unchanged).
  - Targeted: `RescheduleSyncTests` 10 cases, `SkippedReminderSyncServiceTests` 35 cases, `AppViewModelSyncWiringTests` 2 cases, watch `ReminderStoreWatchTests` + `WatchReminderViewModelTests` all green (`** TEST SUCCEEDED **`).
  - Full CI-identical gate (`./scripts/test.sh`, run once via the `run-gate` skill in a managed worktree at `2030d349`, log `/tmp/gate-978.log`): PASS on format, SwiftLint, build, watch build, Periphery ("No unused code detected"), iOS UI tests, **watch UI tests**, and all watch unit suites. Only failures were the 3 documented pre-existing local-only macOS `EntitlementStoreTests` (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`) — annotated, not debugged; CI `mac-tests` is authoritative.
  - First gate attempt failed on a destination ambiguity (`OS:latest` resolved to watchOS 27.0 where no `Apple Watch Series 11 (46mm)` exists); re-run with `WATCH_TEST_SIM` pinned to `3F69EA19-…` (watchOS 26.5) and iOS `SIM` `5A4ADAD5-…` passed the watch stage. Environment issue, not a diff failure; `scripts/test.sh:13` honors `WATCH_TEST_SIM`.

- **Review outcome**:
  - **Blocker found and fixed.** The send-or-queue fallback handed unreachable-phone requests to `WCSession.transferUserInfo`, but the counterpart implemented only `didReceiveMessage`, so queued transfers were delivered to a delegate method nobody handled and silently dropped — while `deliver()` returned `true`, so the watch reported success. Fix in `SkippedReminderSyncService.swift`: added `session(_:didReceiveUserInfo:)` routing through a shared `apply(request:)` decoder (both delivery channels cannot drift), and `queueUserInfo` now returns `Bool` (`transferUserInfo(...) != nil`) so a refused queue surfaces as failure.
  - Added tests: `rescheduleReportsFailureWhenQueueRejected` and `queuedRescheduleDeliversThroughUserInfoChannel` (queue on one service → decode via `didReceiveUserInfo` on another → hook fires), plus `queueSucceeds` on both session fakes.
  - Fixes worth doing now: the above. Optional/pre-existing left as-is and flagged: date-only reschedule zeroes an existing time-of-day, duplicated `FakeSession`/`WatchFakeSession` fixtures, `deliver` "never applied twice" doc overclaim.
  - Reviewer false alarms dismissed after cross-check: Bool closure signature change is consistent across watch send-side / iOS receive-side; no new `@MainActor`/`Sendable`/force-unwrap violation under Swift 6; disjoint keys in the decoder prevent fall-through.

- **Remaining manual items**:
  - Paired-simulator repro of the reported symptom (watch → Skip → Reschedule → Confirm) never ran; hop 4 (real `WCSession` transport) stays `UNVALIDATED`. Per repo policy a bug-fix ticket is not fully done until the reported symptom is reproduced on device.
  - No watch UI test was added (state transition covered by Stage-4 unit tests; UI tests are exceptional per repo policy).

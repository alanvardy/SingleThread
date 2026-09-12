# Design Discussion

**Ticket**: VAR-978 — reschedule not working on watch
**Branch**: `alanvardy-var-978-reschedule-not-working-on-watch`

## Current State

Rescheduling a reminder from the watch is a 7-hop fire-and-forget chain. Every hop is
nil-safe or discard-`Bool`, so a drop at any hop is indistinguishable from success
(research Q5, "Cross-Cutting Observations").

1. **Watch sheet UI** — Skip opens `.confirmationDialog` when `canShowActionMenu`
   (`SingleThreadWatch/WatchReminderView.swift:81-85`, `:143-146`); "Reschedule" opens
   the sheet (`:215-217`, `:280-281`). Confirm is an inline SwiftUI `Button` closure
   (`:290-318`) that extracts **date-only** `DateComponents` (`:299-301`) and calls
   `store.rescheduleReminder` for `visibleReminders.first`, then closes the sheet
   unconditionally (`:303-306`). The store's `Bool` is discarded; there is no error,
   toast, refresh, or reload — `refresh()`/`refreshFromCardTap()`
   (`WatchReminderViewModel.swift:142-157`) are never called from this path.
2. **Watch store relay** — `ReminderStore.rescheduleReminder` watchOS branch
   (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:369-372`) snapshots
   `onRescheduleReminder` (`:113`), invokes `handler?`, and `return true`
   **unconditionally** — even when the hook is nil or the relay never dispatches.
   Guarded only by `canMutate` (`:368`, `:183`).
3. **Watch wiring** — `WatchAppViewModel.wireStoreSyncHooks(store:service:)` sets
   `store.onRescheduleReminder = { service.requestRescheduleReminder(...) }`
   (`SingleThreadWatch/WatchAppViewModel.swift:211-227`), called after `service.activate()`.
4. **Transport** — `requestRescheduleReminder` builds a `[String: Any]` payload with a
   plist-safe `[String: Int]` under the bare literal key `"dueDateComponents"`
   (`SkippedReminderSyncService.swift:268-285`) and calls `session.sendMessage(payload,
   replyHandler: nil)`; errors are only logged. `sendMessage` requires the counterpart
   app to be *reachable*; there is no queued fallback. The `WCSession` extension and
   `FakeSession` (`SingleThreadTests/TestFixtures.swift:66-94`) model neither
   reachability nor queued delivery.
5. **Phone decode → hook** — `session(_:didReceiveMessage:)` fires only when both keys
   decode (`:314-325`) and invokes `onRescheduleReminderReceived` (`:108`).
6. **Phone wiring** — `AppViewModel.setupSyncService` sets
   `service.onRescheduleReminderReceived = { [weak store] identifier, components in
   Task { await store?.rescheduleReminder(...) } }` (`SingleThread/AppViewModel.swift:405-407`),
   assigned before `service.activate()` (`:405-414`). Gated by
   `WCSession.isSupported()` + `!usesInMemoryStore` (`:380-381`).
7. **iOS EventKit write** — find in `reminders` by `calendarItemIdentifier` only
   (`ReminderStore.swift:374-376`, miss → silent `false`), mutate
   `dueDateComponents`, `save(commit: true)` (`:378-379`), `resetSkipCount` (`:380`),
   `settle()` (`:381`, 200 ms default), `reload()` (`:382`); catch logs and returns
   `false` (`:385-386`).

**Coverage gap**: hops 1, 4 and 6 are unexercised. `RescheduleSyncTests.swift` drives
only the service's own encode/decode (`:14`, `:36`, `:60`, `:87`);
`ReminderStoreWatchTests.swift:96-150` drives the watch relay branch;
`EventKitStoringTests.swift:274-331` drives the iOS write;
`WatchReminderViewModelTests` has **zero** reschedule coverage.

## Desired End State

1. **The broken link is identified with evidence**, not inferred — a hop-level test or a
   paired-simulator repro shows which hop drops the operation, and that finding is
   recorded in the plan/PR.
2. **A red-first test reproduces the reported symptom** at the hop the evidence implicates
   (fails before the fix, passes after; `scripts/test-one.sh` exits non-zero on a
   zero-match filter, so the run must actually execute a case).
3. **Reschedule survives an unreachable phone**: when `isReachable == false` the request
   is handed to a queued, app-launch-safe delivery instead of being dropped (applied
   uniformly to complete / delete / reschedule, since all three share the defect).
4. **A failed relay is observable**: the watch store branch no longer reports
   unconditional `true`, and the watch UI surfaces failure / refreshes its list on
   success. Tapping Reschedule then visibly changes the card.
5. **Phone behaviour is unchanged**: the iOS `rescheduleReminder` semantics (save,
   skip-count reset, settle, reload, return-value contract) and the existing
   `RescheduleSyncTests` / `EventKitStoringTests` cases pass untouched.

Verified by: the new red-first test, the existing reschedule suites, and the CI-identical
`./scripts/test.sh` gate once (per the `run-gate` skill).

## Patterns to Follow

- **Callback slots + snapshot-before-invoke** — `onRescheduleReminder`
  (`ReminderStore.swift:113`) and `onRescheduleReminderReceived`
  (`SkippedReminderSyncService.swift:108`) are plain optional callbacks; the receive path
  snapshots to a local before invoking (`:322-323`). Follow this; do not introduce an
  observer bag.
- **Write-once-before-`activate()`** — handlers are assigned before `service.activate()`
  on both platforms (`AppViewModel.swift:405-414`; `WatchAppViewModel.swift:221-224` vs
  the `activate()` call above it). Reachability fallbacks must preserve this ordering.
- **Test seams** — `SkipSyncSession` protocol + `FakeSession` for service tests
  (`SkippedReminderSyncService.swift:8-15`, `TestFixtures.swift:66-94`);
  `InMemoryEventStore` for store tests (`ReminderStoreWatchTests.swift:96-127`);
  `FakeEventStore` for the iOS write (`EventKitStoringTests.swift:274`). Extend these
  seams; do not add real EventKit or real `WCSession` to a unit test.
- **`AppGroup.defaults` round-trip** — anything shared with the watch persists through
  the suite, never `UserDefaults.standard` (conventions "Gotchas"). Existing reschedule
  tests use `.standard` + UUID keys with `defer` cleanup
  (`ReminderStoreWatchTests.swift:99`) — for any *new* shared/persisted value use
  `AppGroup.defaults`, and do not copy the `.standard` shortcut.
- **Test naming** — Swift Testing names must not start with `test`/`testing`
  (SwiftFormat strips the prefix); use `rescheduleRelaysWhenPhoneUnreachable` style.
  Watch unit tests are Swift Testing, not XCTest.
- **Testability refactor is pre-agreed**: extracting the confirm closure out of
  `actionMenuRescheduleSheet()` into `WatchReminderViewModel` follows the existing
  "keep the view thin / extract to stay under SwiftLint's 50-line body limit" pattern
  already documented at `WatchReminderView.swift:287-289` and `WatchAppViewModel.swift:230-236`.
- **Do NOT follow** the two anti-patterns the research surfaced: (a) `return true`
  regardless of relay outcome (`ReminderStore.swift:369-372`); (b) silent `false` /
  logged-only failures with no user-visible consequence (`:374-376`, `:385-386`,
  `SkippedReminderSyncService.swift:283-285`). These are the defect class, not a precedent.

## Design Decisions

1. **Diagnose before fixing (Q1-B)**: run hop-level fake-session tests plus one
   paired-simulator repro with the relay's existing `Logger` output; fix the hop the
   evidence implicates. Neither "fix the likely hop blind" nor "harden everything" is
   acceptable — the prior sentence is a guess and the latter cannot be proven red-first.
2. **Uniform reachability fallback (Q2-B)**: when `session.isReachable == false`, the
   three mutation requests fall back to a queued, launch-safe delivery (candidate:
   `transferUserInfo`), extending `SkipSyncSession` with that capability and `FakeSession`
   with reachability + queued-delivery recording. Uniform, because complete/delete carry
   the identical latent defect; duplicating the fix for one verb would leave two live bugs.
   Delivery stays idempotent-friendly: each queued item carries the existing identifier key.
3. **Trustworthy outcome + visible result (Q3-C)**: the watchOS branch returns `false`
   when there is no relay outcome to report (nil handler, dispatch failure) instead of
   unconditional `true`; the watch view model refreshes its local state on success and
   exposes a failure state the sheet/list can render. The `Bool` at
   `WatchReminderView.swift:304-305` stops being discarded.
4. **Extract for testability (Q4-A)**: move the confirm logic from the SwiftUI `Button`
   closure (`WatchReminderView.swift:290-309`) into a `WatchReminderViewModel` method that
   is unit-tested in `SingleThreadWatchTests` with a relay-recording store, alongside
   tests for the new success/failure states. No new watch UI test: the value is in the
   state transition, which the unit test captures; UI tests stay exceptional per repo policy.
5. **Time-of-day semantics unchanged (Q5-A)**: the date-only picker → date-only
   `DateComponents` payload stays as-is. Phone-side write semantics and all existing
   reschedule tests are untouched; this is a known product limitation, not this fix.

## What We're NOT Doing

- **Not** changing the date-only wire semantics or preserving the original time-of-day
  (Q5-A) — no merge of new y/m/d with existing h/m on the phone.
- **Not** redesigning the sync architecture: no `updateApplicationContext`-based mutation
  queue, no new sync service, no dedupe/journal layer.
- **Not** touching the iOS `rescheduleReminder` write path's find/save/skip-reset/settle/
  reload sequence, nor its return-value contract.
- **Not** adding an iOS `AppViewModel` production change beyond what the diagnosed hop
  requires; hop 6 gets a *test*, not a rewrite, unless diagnosis shows it is the break.
- **Not** adding new UI tests, new targets, or new launch-arg seams.
- **Not** bundling unrelated silent-drop fixes (skips, exclusions, entitlement pushes).
- **Not** creating child tickets or a design branch.

## Open Risks

- **The diagnosis may implicate real `WCSession` transport (hop 4)**, which is not
  readable in-repo and cannot be exercised by a unit test; a paired-simulator repro then
  carries the proof, and the plan must flag that hop as `UNVALIDATED` until it runs.
- **`transferUserInfo` fallback semantics**: queued delivery is asynchronous and can
  arrive after app relaunch; if both `sendMessage` and a fallback fire we could double-apply
  a mutation. The plan must pick exactly one delivery per attempt (send *or* queue).
- **`SkipSyncSession` is a protocol change**: `WCSession` conformance plus every fake and
  test double must be updated, or the iOS/watch builds break under
  `SWIFT_TREAT_WARNINGS_AS_ERRORS`.
- **The `Bool` contract change** to `rescheduleReminder` could affect macOS, where the
  method compiles into the iOS branch (`#else`) and `canMutate` may be false in tests.
- **The reported symptom may be watch-side list staleness** (no refresh) rather than a
  dropped write — if the diagnosis shows the phone did write, decisions 3 and 4 carry the
  whole fix and decision 2 becomes hardening rather than repair.
- **Existing reschedule tests use `UserDefaults.standard`** with UUID keys; extending them
  without switching to `AppGroup.defaults` would violate the round-trip rule silently.
- Simulator contention during the repro (`Busy`/`RequestDenied`) can stall the diagnosis;
  the `simulator-pairing` skill's shutdown/kill remedies apply, and after two UI-stage
  contention failures CI is authoritative.

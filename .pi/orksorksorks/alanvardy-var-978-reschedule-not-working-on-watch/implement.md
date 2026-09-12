# Implementation Summary

**Ticket**: VAR-978 — reschedule not working on watch
**Branch**: `alanvardy-var-978-reschedule-not-working-on-watch`
**PR**: #193 (draft)

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| boot  | `d6102755` | chore: remove DELETEME branch bootstrap marker |
| 1     | `8d860656` | [Stage 1] test seams + hop-level diagnostic matrix (sanctioned red captured) |
| 2     | `4c09e241` | [Stage 2] sync transport send-or-queue fallback (red → green) |
| 3     | `ed68e787` | [Stage 3] core store relay truthful outcome |
| 3     | `aff14ea1` | fix plan checkbox commit reference |
| 4     | `b886b486` | [Stage 4] extracted confirm + outcome state |
| 5     | `8ec76ad8` | [Stage 5] thin rendering of relay outcome |
| 6     | `2c27f18d` | Phase 6 regression verification notes |
| 6     | `db8f3214` | Phase 6: correct gate-launch state in plan |

All pushed to `origin/alanvardy-var-978-reschedule-not-working-on-watch` (normal pushes, no force).

## Automated Checks

- [x] Phase 1: `SkippedReminderSyncServiceTests` — 33 pre-existing cases green
- [x] Phase 1: `RescheduleSyncTests` — 4 pre-existing green; `rescheduleRelaysWhenPhoneUnreachable` **FAILED** as the sanctioned red (verbatim: `RescheduleSyncTests.swift:119: Expectation failed: (fake.queuedUserInfo.count → 0) == 1`), pasted into PR #193 under "Stage 1 diagnosis"
- [x] Phase 1: `AppViewModelSyncWiringTests` (new, hop 6) — `ok: 2 case(s) ran`, both green
- [x] Phase 1: `make lint` green
- [x] Phase 2: `SkippedReminderSyncServiceTests` — 35 cases (33 + 2 new queue-parity) green; Stage-1 red now green
- [x] Phase 2: `RescheduleSyncTests` — 8 cases green (send XOR queue + error-path guard)
- [x] Phase 2: `make build` (iOS) green — `SkipSyncSession` conformance compiles
- [x] Phase 2: `make watch-build` (watchOS) green
- [x] Phase 2: `make lint` green; grep confirms `session.sendMessage` only inside `deliver` (manual item, verified)
- [x] Phase 3: `ReminderStoreWatchTests` relay cases green (hook propagates, rejects → false, missing hook → false, gated → no-op)
- [x] Phase 3: `ReminderStoreTests` — iOS write path untouched, green
- [x] Phase 3: `make watch-build` + `make lint` green
- [x] Phase 3: iOS `#else` branch body byte-identical (manual item, verified on `ed68e787`)
- [x] Phase 4: `WatchReminderViewModelTests` — 12 cases green incl. 4 new confirm tests (success refreshes + closes, rejected keeps sheet open + sets flag, no visible reminder no-op closes, date-only components on the wire)
- [x] Phase 4: `make lint` green; new fixtures persist via `AppGroup.defaults` (grep verified)
- [x] Phase 4: `make watch-build` green (manual item, verified)
- [x] Phase 5: `make watch-build` + `make lint` green; view holds no business logic — grep: no `rescheduleReminder` in `WatchReminderView.swift` (manual item, verified)
- [x] Phase 6: `ReminderStoreWriteTests` (EventKit iOS path; plan's `EventKitStoringTests` resolved to the actual Swift Testing suite `ReminderStoreWriteTests`) — 12 cases green, unchanged
- [x] Phase 6: `RescheduleSyncTests` — 8 cases green
- [x] Phase 6: DELETEME removal confirmed in the PR
- [ ] Phase 6: full CI-identical gate `./scripts/test.sh` — **NOT run yet**; per the implement/review split this runs once in the review step via the `run-gate` skill (one async gate subagent in a managed worktree, multi-hour timeout)

## Manual Verification Items (from the plan)

- [ ] Phase 1 (paired-sim repro, hop 1 + hop 4): boot the phone sim from `.simulator_id`; `xcrun simctl list pairs` to confirm a phone↔watch pair exists (else follow the `simulator-pairing` skill; watch UI tests need an unpaired watch sim)
- [ ] Phase 1: install + launch the phone and watch apps on the pair; stream logs from both (`xcrun simctl spawn <phone-udid> log stream --predicate 'subsystem == "app.alanvardy.SingleThread"'`)
- [ ] Phase 1: on the watch, open Skip → Reschedule → pick a date → Confirm
- [ ] Phase 1: observe — does the phone log a "Failed to send reschedule request" (hop 3/4 drop) or process the write (hop 1/4 fine)? Does the watch card change?
- [ ] Phase 1: record the finding. If real `WCSession` transport is implicated, mark hop 4 `UNVALIDATED` (already noted in PR body) and rely on the queued fallback + phone behaviour
- [ ] Phase 5: on the paired sim, tap Reschedule → Confirm with a reachable phone → sheet dismisses and the card reflects the new date
- [ ] Phase 6: the three local-only macOS `EntitlementStoreTests` failures are pre-existing — annotated in the PR body, do not debug

## Notes / Deviations (recorded in PR #193)

- The hop-6 wiring test drives the existing `AppViewModel.syncService` instance directly (no `init(arguments:session:)` seam) — matches structure.md deviation 1.
- `FakeSession.errorToThrow` backs `rescheduleDoesNotQueueAfterSendError` (exactly-one-delivery in the error path).
- `confirmReschedule()` closes the sheet *before* `await refresh(...)` (1 s minimum display duration stays for the list update behind it).
- Phase 4 relay test kept its pre-existing name `rescheduleFiresRelayHookAndReturnsTrue` (plan proposed renaming to `rescheduleRelayPropagatesHookResult`); semantics match the plan's intent.
- Name-only watch destinations needed id-pinning for verification runs (two watchOS runtimes present).
- The iOS service's debug log message changed from per-request strings ("Failed to send completion request") to one shared chokepoint message ("Failed to deliver sync request") — behavior equivalent, single delivery path.
- No watch UI test added — the state transition is fully covered by Stage-4 unit tests; repo policy keeps UI tests exceptional.

## Residual Risk

- **Hop 4** (real `WCSession` transport) is not unit-testable; marked `UNVALIDATED` unless the user's paired-sim repro implicates the transport, in which case the queued fallback + send-or-queue covers delivery.
- The full `./scripts/test.sh` gate has not run on the branch tip `db8f3214` — it belongs to the review step (`run-gate` skill).
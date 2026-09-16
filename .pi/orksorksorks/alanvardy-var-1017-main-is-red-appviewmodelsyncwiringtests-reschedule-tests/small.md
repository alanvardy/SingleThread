# Task

`main` is red: CI run 34995837331 failed on the **iPad (A16)** matrix leg with two
failures in `SingleThreadTests/AppViewModelSyncWiringTests.swift`:

- `rescheduleMessageReachesStoreThroughWiring()`
- `rescheduleMessageIsIgnoredWhenStoreHasNoMatchingIdentifier()`

Fix the regression so both tests pass on **both** CI matrix legs (iPhone 17 and
iPad A16). The change is a docs-only commit's fault only in chronology — the
failure predates it, so run `gh run view 34995837331 --repo alanvardy/SingleThread --log-failed`
and git-blame/CI history on the wiring test to confirm whether this is a real
regression (likely device- or timing-dependent — see the `@MainActor` /
`.serialized` suite and the 20 ms / 50 ms timing budgets in the tests) or an
environmental flake.

Definition of done:

- **Red-first:** reproduce with the pinned simulator, e.g.
  `scripts/test-one.sh 'SingleThreadTests/AppViewModelSyncWiringTests/rescheduleMessageReachesStoreThroughWiring'`
  (pinned to `.simulator_id`; the script exits non-zero on a zero-match run).
- Both tests pass on both matrix legs, or are proven local-only and annotated
  next to the three existing known-local StoreKit failures.
- `./scripts/test.sh` green via the `run-gate` skill.

## Why SMALL

Localized regression fix: single subsystem (phone sync wiring), ≤5 files,
follows the existing pattern set by the sibling complete/delete wiring tests;
no schema, no new surface, no design decision, and the DoD (reproduce → fix →
verify both legs → gate) is fully specified by the ticket.

## Key files

- `SingleThreadTests/AppViewModelSyncWiringTests.swift` — the two failing tests
  (`.serialized` `@MainActor` suite, `--ui-testing` + `--ui-testing-noop-settle`
  seams, ~20/50 ms timing budgets that likely need re-budgeting or hardening on
  slower iPad hardware).
- `SingleThread/AppViewModel.swift` — `setupSyncService` (line ~381) installs
  `service.onRescheduleReminderReceived`, which spawns a `Task` to call the
  store — check the funnel/actor-isolation story here.
- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` —
  `rescheduleReminder` (line ~368): iOS branch guards on
  `reminders.first(where: calendarItemIdentifier == identifier)`, saves, resets
  skip count, `settle()`, `reload()`.
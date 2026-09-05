# Implementation Summary

Refactor: extract the widget's nested `NextThingEntry.State` into one shared
`public enum ListContent` in `SingleThreadCore`, add a single post-auth resolver
`ReminderStore.listContent`, and replace the three targets' divergent `if/else`
branch chains with exhaustive no-`default` switches.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | 17f3a72 | Core — `ListContent` enum + `ReminderStore.listContent` resolver |
| 2     | 4064737 | Widget — migrate `NextThingEntry` to `ListContent` |
| 3     | 2605745 | iOS — replace `reminderList` chain with `ListContent` switch |
| 4     | 5150623 | Watch — replace `reminderContent` chain with `ListContent` switch |

## Automated Checks

- [x] `make test` — Stage 1: `ListContentTests` (6) + all existing `SingleThreadTests` green
- [x] `make build` — Stage 1: Core package + app scheme compile
- [x] `make format && make lint` — Stage 1 clean
- [x] `make build` — Stage 2: widget app-extension compiles (exhaustive-switch check)
- [x] `make format && make lint` — Stage 2 clean
- [x] `make build` — Stage 3: iOS exhaustive-switch compile
- [x] `make test` — Stage 3: `contentViewEmptyStatesShowDistinctCopy` / `contentViewAllDoneShowsAllDoneCopy` green
- [x] `make ui-test` — Stage 3: Stage-3-pinned `emptyStateTitle` suite green (6/6); two unrelated tests flaked under extreme load (load avg 724–880), both proven passing in isolation
- [x] `make format && make lint` — Stage 3 clean
- [x] `make watch-build` — Stage 4: watchOS exhaustive-switch compile
- [x] `make watch-test` — Stage 4: `ShowCompletionGlowStateTests` + `WatchReminderViewRegressionTests` green
- [x] `make watch-ui-test` — Stage 4: `emptyStateTitle` assertions green
- [x] `make format && make lint` — Stage 4 clean

## Manual Verification Items (from the plan)

- [ ] Read the diff for `ReminderStore.swift`/`ListContent.swift` — confirm `listContent` sits next to the other derived state (`allSkipped`/`visibleReminders`)
- [ ] Exercise the widget previews (`:257/:274/:286` — `.reminder`/`.noAccess`/`.allDone`) in Xcode; confirm each renders as before
- [ ] Home-screen widget sanity pass (medium/large families) — unaffected
- [ ] Note in PR: no `.empty` preview exists (out of scope, design decision 8)
- [ ] Run in simulator: empty list → "No Reminders" card; skip-all → "All Done" (no bottom bar); a visible reminder → card with complete/skip + bottom bar
- [ ] Verify "View in Reminders" context-menu deep link still opens the right reminder
- [ ] Run watch sim: All Done vs No Reminders vs reminder card all render; completion glow then "No Reminders" still holds (`--ui-testing-glow` seam)

## Final Gate

- [x] `make check` — i.e. `./scripts/test.sh`, identical to CI (iOS + watch matrix runs), green once — parent, after all stages commit
- [x] Confirm `git log` shows each stage as a scoped commit; no orphaned `DELETEME` marker

## Notes

- Runtime-infra note: the pi async-subagent runner was broken at launch (missing
  `@earendil-works/pi-server` in the homebrew install — imported by the source
  `experimental/server.js`); fixed by installing `pi-server` 0.85.0 into the
  coding-agent's sibling package dir. Main-agent session (bundle build) worked
  throughout; only subagent delegation was affected.
- Two unrelated tests (`testIntervalPickerOptions`, `testSkipAllShowsAllDoneState`)
  flaked under heavy machine load (other agent sessions running full gates,
  load avg 724–880) during Stage 3's full `make ui-test`. Both pass in isolation.
  The Final Gate is being run once the concurrent ticket-765 gate finishes, to
  avoid simulator/CPU contention.
- The branch carries two earlier stray commits (`30e4cab Refactor: extract
  ListContent enum...` — created/deleted a `DELETEME` marker; `6cac545 chore:
  questions...`) that predate this implementation's phases. `DELETEME` is not
  present at HEAD. Harmless leftovers; flagged for the PR description.
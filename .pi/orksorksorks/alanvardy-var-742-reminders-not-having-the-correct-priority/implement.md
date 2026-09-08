# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | 9419626 | Priority Mapping Fix |
| 2     | 07f16eb | Display Model Integration & Temporary Instrumentation |
| 3     | 42ffb62 | Skip Race Fix |
| 4     | e4c1b88 | UI Test Assertions for Priority Rendering |
| 5     | c666280 | Instrumentation Cleanup |

All pushed to `origin/alanvardy-var-742-reminders-not-having-the-correct-priority` (6 commits ahead of `origin/main`).

## Automated Checks
- [x] Unit tests green: `ReminderPriorityTests` (incl. `levelMapsHighForMidHighPriority`, `levelMapsHighForBoundary`, `levelMapsLowForMidLowPriority`, `levelMapsLowForBoundary`), `ReminderDisplayTests` (incl. `mapsHighMarkerForPriority2/4`, `mapsLowMarkerForPriority6/8`), `ReminderStoreTests.skipCurrentReminderDiscardedAfterClearSkipped`, and existing `ReminderStoreGateTests` (skip with/without gating) — all passed (`make test` / `./scripts/test.sh`)
- [x] `make lint` passes — 0 violations (SwiftLint `--strict`) after every phase
- [x] `make ui-test SIM='platform=iOS Simulator,name=iPhone 17'` — all iOS UI tests pass, incl. `testPriorityMarkerRendersForMidRangeValue`
- [x] `make ui-test SIM='platform=iOS Simulator,name=iPad (A16)'` — 30/30 passed (first run hit a non-reproducible Error-65; immediate full rerun green, unrelated to this work)
- [x] Watch UI tests — `make watch-ui-test` all pass locally, incl. watch `testPriorityMarkerRendersForMidRangeValue`
- [x] `make periphery` — no dead code
- [x] `./scripts/test.sh` full gate (format, lint, build, Periphery, unit, UI) — green after Phase 5 cleanup

## Manual Verification Items (from the plan)
- [ ] **Phase 1**: `make test SIM='platform=iOS Simulator,name=iPhone 17'` — confirm `testLevelMapsHighForMidHighPriority`, `testLevelMapsHighForBoundary`, `testLevelMapsLowForMidLowPriority`, `testLevelMapsLowForBoundary` all pass, and all existing priority tests still pass
- [ ] **Phase 2**: Build to physical device — `xcodebuild -scheme SingleThread -destination 'platform=iOS,name=<device>' -configuration Debug build`
- [ ] **Phase 2**: Exercise the app on-device for a few minutes (open, complete, skip, pull-to-refresh)
- [ ] **Phase 2**: Open Console.app, filter for `ReminderDisplay`, confirm `os_log` fires — if non-standard priorities appear, the CalDAV hypothesis is confirmed. **IMPORTANT**: the instrumentation was intentionally removed in Phase 5 (per plan); to re-run this check you would need the Phase 2 build (commit `07f16eb`) or to temporarily re-add the log — the current head has no instrumentation
- [ ] **Phase 2**: If no log entries appear after sustained use, the root cause may be elsewhere — stop here and escalate
- [ ] **Phase 3**: iOS: Open app, skip a reminder, immediately pull-to-refresh with `clearSkipped`. The un-skipped reminder stays visible — it is NOT re-hidden by the stale skip Task. Repeat 3–5 times to confirm the race window is reliably closed
- [ ] **Phase 4**: Run iOS UI tests and confirm the marker appears on screen during `testPriorityMarkerRendersForMidRangeValue` (asserts `"High priority"` — see note below; pre-fix, priority 3 rendered no marker)
- [ ] **Phase 4**: Run watch UI tests and confirm the marker appears (asserts `"Low priority"` for the priority-7 seed)
- [ ] **Phase 5**: Confirm `grep -r "os_log" SingleThreadCore/` returns no results (only gitignored `.build/` binary artifacts matched — zero source matches)
- [ ] **Phase 5**: Confirm Phase-2 `import os` fully removed from `ReminderDisplay.swift` (`grep "import os" ReminderDisplay.swift` = 0 matches). Note: `grep -r "import os" SingleThreadCore/Sources/SingleThreadCore/` still matches `EntitlementStore.swift`, `ReminderStore.swift`, `SkippedReminderSyncService.swift` — those are pre-existing, legitimate `os` module uses, not Phase-2 leftovers, and are intentionally untouched

## Notable Adaptations (small mismatches resolved in-place)
1. **Phase 3**: `reload(clearSkipped:)` body was extracted into a private `clearSkippedState()` helper — the plan's literal inline placement would have pushed `reload` to 51 lines, failing SwiftLint's 50-line `function_body_length` under `--strict`. Behavior identical: `skipGeneration &+= 1` before clearing.
2. **Phase 4**: The plan said assert `staticTexts["!!!"]` / `["!"]`, but the marker `Text` renders with `.accessibilityLabel("\(level.displayName) priority")`, so XCUITest exposes `"High priority"` / `"Low priority"`. Tests assert the accessibility-exposed label (verified empirically: the raw `"!!!"` lookup fails, the label lookup passes). This still proves the full marker chain: pre-fix, priority 3 produced no marker at all.
3. **Phase 5**: The plan's fault-isolation on-device instrumentation items (Phase 2 manual) can't be exercised on the current head since the os_log was removed per plan — see the note on the Phase 2 Console.app item above.

## Observations (no action taken, per plan scope)
- The `skipGeneration` gate only covers the `clearSkipped` path; any future reload path that resets skipped state without going through `clearSkippedState()` would not bump the generation. Matches plan intent; worth noting for future work.
- The on-device Console.app confirmation of the CalDAV priority hypothesis was deferred (manual); the automated unit + UI coverage proves the corrected mapping renders correctly for the seeded values.
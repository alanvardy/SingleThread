# Implementation Summary

VAR-835 — Improve reschedule dialog (iOS restyle of shared `RescheduleSheet`)

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| —     | `4ac3bd0` | chore: commit planning artifacts |
| 1     | `da8a8ee` | Phase 1: Structural layout — centered label+picker row |
| 2     | `0b790ad` | Phase 2: Confirm-button restyle — .borderedProminent, centered |
| 3     | `29e0a39` | Phase 3: Integration — macOS passthrough, detents, visual confirmation |

## Automated Checks

- [x] Layer 1 — `make format` + `make lint` pass (0 violations)
- [x] Layer 1 — `make build` succeeds
- [x] Layer 1 — `RescheduleSheetTests` green: 7/7 (5 helpers + 2 new layout tests)
- [x] Layer 2 — `make format` + `make lint` pass
- [x] Layer 2 — `make build` succeeds
- [x] Layer 2 — `RescheduleSheetTests` + `rescheduleSheetTextButtonsKeepNativeChrome` green
- [x] Layer 3 — `make mac-test` green (569 passed; the 3 known local-only pre-existing `EntitlementStoreTests` failures annotated, not debugged)
- [x] Layer 3 — macOS chrome suite `MacOSActionButtonChromeTests` green (3/3)
- [x] Layer 3 — iOS regression suites green (76/76: `RescheduleSyncTests`, `ReminderStoreTests`, `EventKitStoringTests`)
- [x] Layer 3 — Full CI-identical gate `./scripts/test.sh` **PASS** — 612 test cases passed across all stages; only the 3 known pre-existing local-only `EntitlementStoreTests` failures (macOS host, byte-identical to `origin/main`); watch stage needed a `WATCH_TEST_SIM` env pin (dual watchOS runtimes, env-only, no source changes)

## Manual Verification Items (from the plan)

- [ ] iPhone simulator — nudge sheet: "Reschedule to" label + picker centered side-by-side, prominent "Reschedule" confirm centered beneath; nudge title/destructive actions still present; no clipping at `.height(420)`.
- [ ] iPhone simulator — action-menu sheet: same centered row + prominent centered confirm; no clipping at `.height(320)`.
- [ ] macOS — action-menu ("Reschedule" in the menu) renders the shared sheet sanely (centered row + prominent button).
- [ ] If the picker value collapses awkwardly after centering, apply the fallback `.datePickerStyle(.compact)` on the picker and re-verify (see Cross-Cutting Notes).

## Observations / Deviations

- **Layer 1 empirical note (plan-flagged risk)**: the plan's bare
  `DatePicker(selection:displayedComponents:)` label-less call does not compile
  on the installed SDK (the label-less overload has no default for `label:`).
  Resolved within plan intent: spelled as `DatePicker(selection:
  displayedComponents:) { EmptyView() }` (trailing closure binds to the only
  ViewBuilder param → `Label == EmptyView`). The plan's `DatePicker<EmptyView`
  assertion token was **empirically confirmed** — no test-assertion changes
  required. `.labelsHidden()` kept as defensive no-op.
- No other deviations from the plan; Layer 2 diff matches the plan
  byte-for-byte for the handler closure.
- Detent heights `.height(320)`/`.height(420)` left unchanged (no visual clip
  evidence — that's a manual-verification decision).
- Committed the QRSPI planning artifacts (conventions/design/questions/
  research/structure/task) in a chore commit so the gate's managed worktree
  could launch (worktree isolation requires a clean tree).
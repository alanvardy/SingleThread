# Implementation Summary

Ticket: alanvardy-var-790 — Swipe guide should change with colour scheme

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `c130256` | Colour-decision primitive (`CardPlate.promptBoxFill(for:)`, additive) + test pins |
| 2     | `33b58cb` | View wiring (`ReminderCardView` scheme-driven prompt; dead constant removed; doc corrections) |
| 3     | `(this commit)` | Behavioural regression gate + checkbox updates / summary |

## Automated Checks

- [x] `promptBoxFill(for:)` pins green (`promptBoxFillOffWhiteInLightMode`, `promptBoxFillDarkGreyInDarkMode` in `CardPlateTests`) and old constant pins green through Phase 1 (`./scripts/test.sh --unit-only`, 564 tests).
- [x] Zero bare `promptBoxFill` (non-`(for:`) references remain after Phase 2 (grep verified; the plan's doc-comment corrections also covered `CardPlateModifier.swift:39`).
- [x] `make format` settles `CardPlate` member order (`cornerRadius` → `plateFill(for:)` → `promptBoxFill(for:)`) with no unrelated drift files touched.
- [x] `make lint` passes (`swiftformat --lint` + `swiftlint lint --strict`).
- [x] `./scripts/test.sh` full gate: format, lint, build, periphery, iOS unit (564/0), iOS UI (52/0), watch unit (43/0), watch UI (28/0) all green — **macOS unit stage has a documented deviation, see below**.
- [x] All four swipe-prompt flows pass: `testSwipePromptAppearsUnderUITesting`, `testDismissSwipePromptHidesItAndPersistsAcrossRelaunch`, `testSwipePromptToggleRoundTripsViaSettings` (all passed per xcodebuild per-test output), `testAccessibilityAudit` (`--ui-testing --reset-swipe-preference`, passed).
- [x] Reflected-body snaps in `SwipePromptTests` unchanged (assert on style names, not colour values) — colours-only change introduced no rendered-drift assertions.

## Deviation (documented)

**macOS unit stage is machine-environmentally flaky on this Mac, proven pre-existing and unrelated to this ticket:**
- The gate's macOS stage failed 2–3 nondeterministic tests across runs with different subsystems each time (run 1: `EntitlementStoreTests.isEntitledSurvivesStoreRecreation` + `initialRefreshSettlesResolvedFlag`; run 2: `EntitlementStoreTests.initialRefreshSettlesResolvedFlag` + two `ReminderStoreTests.skipCurrentReminderRefetch*`; run 3 (rerun of the 4-entry suite): all pass).
- Not this branch: failing test files are byte-identical to `origin/main` (empty `git diff origin/main..HEAD` for `EntitlementStoreTests.swift`, `ReminderStoreTests.swift`); a clean `origin/main` worktree reproduces the entitlement failures; the two affected subsystems (macOS StoreKit sandbox, EventKit) are untouched by this ticket's colour-decision-only changes.
- Known precedent: var-642 documented the same macOS StoreKitTest/aggregated-runner flakiness ("reruns in 5/6").
- CI runs the identical macOS suite on fresh `macos-26` runners and the last full gate there was green; **CI green is the authoritative confirmation** for this stage.
- No code was changed to work around this; nothing was hacked around.

## Manual Verification Items (from the plan)

- [ ] Run the app and flip **Settings → Appearance → Light/Dark**; the prompt box turns light/dark live (no restart), with the separator and dismiss button inverting contrast against the box.
- [ ] Check Dynamic Type extremes (largest/smallest text) with the prompt visible — the light box/button still read clearly.
- [ ] Confirm the orange/green hint tints and the `Dismiss` button's a11y label/hit area are unchanged in both schemes.
- [ ] (Optional, local-only) `make ui-test` with the audit's extra strictness categories — `.dynamicType` / `.hitRegion` — to confirm the new light box/button contrast. A local-only hit-region failure is documented (`SingleThreadUITests.swift:54-60`) and is not a CI break.

## Observations (not fixed — out of scope)

- The plan's Edit-1b snippet wrote `colourScheme` (British spelling); the code property is `colorScheme` — implemented with the correct spelling.
- Phase 2's grep surfaced a fourth stale "fixed dark-grey prompt fill" doc claim in `CardPlateModifier.swift:39`; corrected as a doc-only change (required by the plan's zero-bare-references rule).
- The gate log showed the active macOS daemon/aggregated-runner flakiness documented above; worth a separate machine-env cleanup ticket if it recurs, but it is not caused by this branch.
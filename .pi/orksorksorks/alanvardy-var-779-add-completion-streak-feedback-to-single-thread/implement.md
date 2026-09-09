# Implementation Summary

Feature: **Completion streak feedback** — a transient "You've cleared N today" overlay on the single card, driven by a per-calendar-day completion counter (`DailyCompletionStore`) that auto-rolls over at midnight. Preference-gated behind a `showCompletionMomentum` toggle; wired into `ReminderStore`'s complete/undo paths.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `54dc916` | Phase 1: DailyCompletionStore — persistence layer |
| 2     | `8c97e03` | Phase 2: ReminderStore integration — business logic |
| 3     | `bd56caa` | Phase 3: CompletionMomentumOverlay — presentation model |
| 4     | `e671a8d` | Phase 4: Preference gating + ContentViewModel trigger + ContentView render |
| 5     | `62ef8a9` | Phase 5: Seed/reset seams — testing infrastructure |
| —     | `f3b8877` | chore: commit planning artifacts (unblocks gate worktree) |
| —     | `f7e60d8` | test: fix gate failures from new showCompletionMomentum preference |
| —     | `9ce9237` | test: harden CompletionMomentumOverlay timing tests against slow executors |

## Automated Checks

- [x] Phase 1: `DailyCompletionStoreTests` — all 9 tests pass (build + targeted suite)
- [x] Phase 2: `ReminderStoreTests` — all existing + 5 new daily-completion tests pass
- [x] Phase 3: `CompletionMomentumOverlayTests` — all 4 tests pass
- [x] Phase 4: `make build` succeeds (iOS) + `make lint` 0 violations
- [x] Phase 5: `UITestingSeedTests` — all existing + 3 new seed tests pass
- [x] Full gate `./scripts/test.sh` — iOS/watches all green; fixed 3 branch-introduced macOS unit failures (see below); only the 3 documented pre-existing local-only `EntitlementStoreTests` failures remain (CI-green on fresh runners, per AGENTS.md)

## Plan Divergences (all intent-preserving, non-structural)

- **Phase 1**: test suite `deinit` removed (compile error under Swift 6.3 for Copyable structs; it was also a no-op — mismatched suite name); `lazy var store` → computed `var store` (lazy getter is mutating, blocked test bodies); `@Suite`/`@Test` attribute placement normalized by repo tooling; forced unwrap → `#require`.
- **Phase 3**: `@Test` attribute placement per repo convention; `retriggerResetsTimer` timing windows rescaled — the plan's numbers (duration 0.05 s, sleep 0.06 s after re-trigger) were arithmetically broken and could not pass; rescaled to duration 0.20 s, re-trigger 0.10 s, assert 0.25 s, preserving both assertions' intent.
- **Phase 4**: added `SingleThreadTests/SettingsViewTests.swift` updates (compiler-required — the `ReminderSettingsView` init gained a binding; new label/caption expectations added). `.bottom` 80 pt verified against actual layout (control plate 56 pt + 16 pt padding ⇒ clears at 72 pt). Glow label keeps `SharedStrings.completionGlow`; momentum uses the plan's literal text (l10n out of scope).
- **Phase 5**: `UITestingSeed` has no explicit init (synthesized memberwise) — adapted; test style matches file's existing conventions; reset assertions hold because the new keys are in `persistedKeys`.

## Gate Verdict (async gate subagent, workflow `590ec2ac`)

Initial gate run: FAIL — 2 branch-introduced macOS unit failures + 3 pre-existing local-only. All other stages (format, lint, iOS build, watch build, Periphery, iOS UI, watch UI, watch unit) passed. Root cause of early UI-stage Busy/RequestDenied failures was local env: `scripts/test.sh`'s `resolve_sim_udid` matched the "Gate iPhone 17" paired sim; pinning `SIM` fixed it (won't occur on CI's fresh runners).

Failures found by the gate and fixed (commits above):
1. `BoolPreferenceKeyTests/allCasesIsExhaustive` — Phase 4 added `showCompletionMomentum` (7 cases) without updating this exhaustive test. Fixed: added the key to the arguments table + bumped count to 7.
2. `SettingsViewTests/reminderSettingsViewContainsExpectedRows` — `String(describing:)` backslash-escapes embedded quotes/apostrophes in LocalizedStringKey captions, so the new Momentum caption never matched literally. Fixed: normalize backslashes out of the body description before matching.
3. `CompletionMomentumOverlayTests/autoDismissAfterDuration` — timing flake under full-suite load on macOS (dismiss-task continuation lagged past the fixed 100 ms sleep; reproduced 2× in full-suite runs, passes in isolation). Fixed: mirror the repo's established `CompletionGlowTests` pattern — `@Suite(.serialized)` + poll for the invariant (20 ms ticks, ~2 s budget); `retriggerResetsTimer` similarly polls through the original fire point.

Post-fix verification: targeted suites pass on iOS sim + macOS; full macOS `SingleThreadTests` run shows **only the 3 documented pre-existing local-only `EntitlementStoreTests` failures** (`hostStoreKitIsClean`, `initialRefreshSettlesResolvedFlag`, `isEntitledSurvivesStoreRecreation` — CI-green on fresh runners per AGENTS.md, not debugged).

## Manual Verification Items (from the plan)

- [ ] Launch in simulator, complete a reminder → overlay appears showing "You've cleared 1 today", auto-dismisses after ~2 s
- [ ] Complete again → overlay shows "You've cleared 2 today"
- [ ] Toggle off "Completion Momentum" in Settings → Reminder → complete → no overlay
- [ ] Toggle back on → overlay reappears
- [ ] Coexists with glow: both fire on completion, glow is background tint, overlay is foreground text — no visual collision

## Notes

- Not in scope per plan: watch sync keys, lifetime `completionCount` changes, haptics/sounds/toasts, streak history, persistent badge, UTC day tracking, UI tests.
- Seed keys use the real statics `DailyCompletionStore.defaultsMarkerKey` / `.defaultsCountKey` (`"completionDayMarker"` / `"completionTodayCount"`), matching the plan's intent.
- `make format` and `make lint` run clean on the full tree (0 violations, 185 files) before the gate launch.
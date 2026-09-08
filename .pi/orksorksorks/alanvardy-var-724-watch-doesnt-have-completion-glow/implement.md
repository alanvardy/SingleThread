# Implementation Summary

Ticket: VAR-724 — Watch doesn't have completion glow
Branch: `alanvardy-var-724-watch-doesnt-have-completion-glow`

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `6cfd4b4` | Make the completion glow visible on watchOS |
| 2     | `354d497` | Add watch completion-glow UI test seam |
| 3     | `e9bff2f` | Watch completion-glow UI tests |
| 4     | `2d515a4` | Integration validation (validation-only) |

All phases committed and pushed to `origin`.

## What shipped

- **Phase 1** — Root-cause fix: `CompletionGlow.duration` default raised from
  `0.25 s` → `0.50 s` (hypothesis a). At 0.5 s the glow outlives the 0.4 s
  `.easeInOut` animation envelope, producing a perceptible flash on watchOS.
  No test changes needed (timing-sensitive tests override duration explicitly).
- **Phase 2** — Watch UI test seam:
  - `WatchAppViewModel.reminderViewModel` converted from computed → stored
    `lazy var` so the test seam can hold a stable reference.
  - Added `--ui-testing-glow` / `--ui-testing-glow-disabled` launch flags
    (stored `isGlowUITesting`, `--ui-testing-glow` extends
    `completionGlow.duration = 2.0`, `-disabled` calls `showCompletionGlowState.apply(false)`).
  - `WatchReminderView.completionGlowOverlay` exposed to accessibility under the
    flag (identifier `completionGlowOverlay`, label "Completion glow"),
    mirroring the iOS `ContentView` pattern. Production behavior unchanged.
  - Unit tests added: `reminderViewModelIsStableAcrossAccesses`,
    `glowUITestSeamExtendsDuration`, `uiTestingGlowDisabledFlagPreDisablesState`.
- **Phase 3** — Two watch UI tests in `SingleThreadWatchUITestsFlows.swift`:
  `testCompletionGlowDoesNotAppearWhenDisabled` and
  `testCompletionGlowFlashesWhenEnabled`.
  - **Small plan adaptation (bug found by subagent):** `--ui-testing-glow` now
    also calls `showCompletionGlowState.apply(true)`. Without this, the
    disabled test's persisted `false` (UserDefaults) leaked into the enabled
    test within the same UI-test session, suppressing the glow. Pinned state per
    flag makes both tests deterministic. Locked in by unit test
    `uiTestingGlowFlagPreEnablesState`.
- **Phase 4** — Integration validation (no code changes).

## Automated Checks

- [x] `make format` / SwiftFormat — 0 violations
- [x] `make lint` (SwiftLint `--strict`) — 0 violations
- [x] iOS build-for-testing compiles
- [x] `make watch-build` compiles
- [x] Periphery `--strict` — "No unused code detected" (launch flags not flagged)
- [x] `make test` — iOS unit tests pass (423 passed, 0 failed)
- [x] `make watch-test` — watch unit tests pass (incl. new seam tests)
- [x] `make watch-ui-test` — all watch UI tests pass, **including both new glow
      tests**
- [x] iOS glow UI tests pass (`testCompletionGlowFlashesWhenEnabled`,
      `testCompletionGlowDoesNotAppearWhenDisabled`)
- [x] macOS build + unit tests pass
- [x] Full `./scripts/test.sh` runs; the **sole** failure is the unrelated,
      pre-existing iOS `testSettingsOpensAndShowsControls`
      (`origin/main` shows "Privacy Policy", test taps "Privacy") — out of scope.

## Known pre-existing failure (not introduced by this ticket)

`SingleThreadUITestsFlows.testSettingsOpensAndShowsControls` fails on
`origin/main` as well: the app's Settings row is labeled **"Privacy Policy"**
(`SettingsView.swift:86`) but the test taps a staticText exactly **"Privacy"**
(`SingleThreadUITestsFlows.swift:151`). This was left unfixed per the plan's
"do not touch code outside scope" rule and flagged for the reviewer/user.

## Manual Verification Items (from the plan)

- [ ] **Phase 1** — Launch watch app on simulator (`make watch-build` + run from
  Xcode with `SingleThreadWatch` scheme, Apple Watch Series 11 (46mm)); tap
  **Complete reminder**; confirm a visible green flash appears and auto-dismisses.
  (If no flash → apply hypothesis b, rebuild, retest.)
- [ ] **Phase 2** — Launch with `--ui-testing --ui-testing-glow`: tap Complete,
  green flash should stay visible for ~2 s.
- [ ] **Phase 2** — Launch with `--ui-testing --ui-testing-glow-disabled`: tap
  Complete, no green flash should appear.
- [ ] **Phase 4** — Review CI results on the PR: confirm the `ci.yml` matrix jobs
  all pass, including the `watch-ui-tests` job running the new glow tests on a
  standalone watchOS simulator.

## Observations / notable notes

- Phase 2 and Phase 3 are coupled as the plan predicted: the seam needed the
  stored `reminderViewModel` change, which Phase 2 delivered.
- The Phase 3 seam fix (`apply(true)`) is the single meaningful deviation; it is
  a correctness fix for test determinism, not a plan contradiction. Flagged in
  the commit.
- `make watch-test` also covers the Phase 1 conditional item (not applied, box 96
  left blank as the plan notes "not applied — hypothesis (a) chosen").
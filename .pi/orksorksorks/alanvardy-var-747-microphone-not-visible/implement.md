# Implementation Summary

Ticket: **Microphone not visible** (`alanvardy-var-747-microphone-not-visible`) → PR #131

Make the mic (dictation) button reliably visible: register the `showMicrophoneButton = true`
default, re-read speech authorization on foreground, and render an explanatory label when
speech recognition is denied/restricted.

Two commits (Phase 1 formatting follow-up from the first run; Phase 3 macOS test gating) went
through review here because the first implement run finished four phase commits, left the
per-phase gates checked, and the plan's Final Gate still had substantively verifiable work.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | 24d5131 | [Phase 1] Data & Protocol Layer — `SpeechTranscribing.refreshAuthorizationStatus()`, `ReminderDictation` override, `DictationViewModel` passthroughs, `registerDefaults()` for `showMicrophoneButton`, recording fake + 3 tests |
| 1     | ecdd667 | Phase 1 follow-up: SwiftFormat `organizeDeclarations` placement for `registerDefaults` (lands the `lint` CI check) |
| 2     | aeb9e55 | [Phase 2] Scene-Phase Wiring — `handleScenePhaseChange` moved out of `#if os(iOS)` (all platforms, internal), `.onChange(of: scenePhase)` un-guarded, 3 new tests |
| 3     | 2ca2cf9 | [Phase 3] Explanatory Label UI — UIKit import, denied/restricted + toggle-on branch with "Open Settings" button (iOS), 6 new tests |
| 3     | d4baaae | Phase 3 fix: gate `explanatoryLabelContainsSettingsButtonOnIOS` to `#if os(iOS)` — the Settings button is iOS-only by design, so the macOS unit-test target failed on it (CI `mac-tests` job) |

## Automated Checks

- [x] `xcodebuild … build-for-testing` (iOS, iPhone 17 / iOS 26.2, Debug) passes
- [x] Watch app build (`SingleThreadWatch`, 46mm simulator) passes
- [x] SwiftFormat check clean (0/128 files, after `ecdd667`)
- [x] SwiftLint `--strict` clean
- [x] Periphery `--strict` clean
- [x] iOS unit tests — `TEST EXECUTE SUCCEEDED`; all 16 `MicrophoneToggleTests` pass (13 new + 3 pre-existing)
- [x] macOS build + unit tests — `TEST SUCCEEDED` (after `d4baaae`; every `MicrophoneToggleTests` passes on macOS)
- [x] iOS UI tests — every test in the flows/audits/launch-appearance suites passes **except** the pre-existing `testPinWallpaperTogglePersistsAcrossRelaunch` (see below)
- [x] Watch UI tests — full `SingleThreadWatchUITests` suite passes locally (exit 0), including `testCompleteHoldsCardDuringGlow` which flakes on GitHub-hosted runners
- [x] PR #131 has unit coverage for the feature and no UI-test seam: speech authorization has no production launch-arg seam (no TCC bypass exists), so dictation is intentionally unit-tested only — noted for the PR

## Pre-existing failures observed (not caused by this branch)

- **`testPinWallpaperTogglePersistsAcrossRelaunch`** fails on this machine — reproduced at
  `origin/main` HEAD in a scratch worktree (`/tmp/var747-main`), and it fails on
  `origin/main`'s own CI (run 33439793839, Aug 31, on iPad flows). The pin-wallpaper feature
  (var-743) was merged before the notification feature (var-746) reworked
  `handleScenePhaseChange`/scene-phase handling in ContentView on main; this test is the
  victim. Assertion: pin toggle reads `"0"` after relaunch. **Actionable follow-up on
  main/var-746, not this branch.**
- **`testCompleteHoldsCardDuringGlow`** (watch) fails on `watch-ui-tests` on GitHub runners
  (4 of the last 5 `main` runs) but passes locally — runner-specific flake.

## Manual Verification Items (from the plan)

- [ ] Phase 1 manual: `make lint` and `make format` report clean (no new SwiftLint/SwiftFormat violations) — *covered by the FULL gate's format/lint stages, which passed*
- [ ] Phase 2 manual: macOS target still compiles (`xcodebuild -scheme SingleThread -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build`) — *covered by the macOS build + unit-test stage, which passed*
- [ ] Phase 3 manual: `make format` applies clean (no phantom diffs on a second run) — *verified: SwiftFormat check clean in the gate, and `d4baaae`'s edit is format-clean*
- [ ] Phase 3 manual: `make lint` passes with `--strict` — *covered by the gate's SwiftLint stage, which passed*

## Notes / adaptations vs. the plan

- **Destination pinning**: the plan's `SIM='platform=iOS Simulator,name=iPhone 17,OS=26.2'`
  matches **two** iPhone 17 simulators on this machine (UDIDs `3F6CFD49…` and `170409DD…`),
  so xcodebuild refuses it ("multiple devices matched the request"). Run with
  `SIM='platform=iOS Simulator,id=3F6CFD49-B62B-43C2-B93F-50B0D9F87E4D'` (single iPhone 17 on
  iOS 26.2). AGENTS.md-sanctioned `,id=` pinning; try `gh run`/CI's `iPhone 17` matrix for the
  name-based form.
- **Body-serialization depth**: Phase 3 tests assert on `String(describing: view.bottomBar)`
  instead of `view.body` (as written in the plan) — ContentView's deeply nested `body`
  description elides `Text` storage, while `bottomBar` (moved to internal in Phase 2)
  serializes shallowly. All six label tests use this documented pattern and pass.
- **Full-gate status**: `./scripts/test.sh` cannot finish green locally today because of the
  pre-existing pin-wallpaper test; every stage it runs passes except that one test. Plan's
  Final Gate item 1 left unchecked with this evidence; item 2 (unit coverage / no UI-test
  seam) checked.
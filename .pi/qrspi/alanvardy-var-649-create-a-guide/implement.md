# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `f77032d` | Preference Layer — `ShowGuidePreference` |
| 2     | `bb2d6f7` | State-Holder Layer — `ShowGuideState` |
| 3     | `dd73602` | Sync Guide Layer — Wire `showGuide` into WCSession |
| —     | `1418cdc` | Phase 4: iPhone Settings Layer — "Show Guide Again" Toggle |
| —     | `3815053` | Fix pre-existing Settings UI test label mismatch ("Privacy" → "Privacy Policy") |
| —     | `89490f8` | Mark Phase 4 build verification checkbox complete in plan |
| 5     | `254798a` | Watch UI Overlay Layer — `GuideOverlay` |
| 6     | `3aba1b1` | Testing Seam — `--reset-guide` Launch Argument |
| —     | `2efa9cf` | Mark final automated verification checkboxes green (full gate confirmed) |

## Automated Checks
- [x] Phase 1 — `SingleThreadWatchTests/ShowGuidePreferenceTests` pass (preference read/write/round-trip) via the corrected watch-scheme command
- [x] Phase 2 — `SingleThreadWatchTests` all green (preference + `ShowGuideState` suites) on the corrected watch-scheme command
- [x] Phase 3 — `SingleThreadWatchTests` all green (existing + 4 new sync `showGuide` tests); iOS build compiles
- [x] Phase 4 — iOS Debug build compiles; `SingleThreadTests` (incl. updated `ReminderSettingsView` test) green
- [x] Phase 5 — Watch build + watch unit tests + watch UI tests green (after accessibility/`isHittable`/`--ui-testing` adaptations)
- [x] Phase 6 — Watch build + watch unit + **all 15 watch UI tests** (guide first-launch, no-reappear, accessibility audit, phone-reset re-appear) green; iOS build compiles
- [x] **Full `./scripts/test.sh` gate: `✅ All CI checks passed`** — swiftformat, SwiftLint `--strict`, iOS/watch/macOS builds, Periphery, iOS unit tests, iOS UI tests, watch UI tests

### Adaptations / divergences from the literal plan (all verified green, none alter product intent)
- **Plan used wrong scheme/destination for watch tests** (the `SingleThread` scheme + iPhone sim). Corrected to `-scheme SingleThreadWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'` for all watch unit/UI tests.
- Phase 3 added `import Foundation` to the ShowGuide test file (Swift 6 explicit-import fix) and deferred the `showGuideState` VM injection to Phase 5 (where `WatchReminderViewModel` gains the param) to avoid a mid-phase compile break.
- Phase 2 appended a one-line test-isolation `defer { removeObject("showCompletionGlow") }` to a pre-existing flaky `ShowCompletionGlowStateTests` case (proven pre-existing, needed for the `-only-testing:SingleThreadWatchTests` gate).
- Phase 5 wrapper discovered/adapted:
  - Merged each arrow+text row into a single accessibility element (the plan's `.accessibilityHidden(true)` on the arrow images did not remove them from the watchOS AX tree, failing the a11y audit).
  - Added a `--ui-testing` default (guide off unless `--reset-guide`) so fresh `--ui-testing` installs don't block all pre-existing interaction tests — coherent with Phase 6's `removeObject`.
  - Replaced the unreliable `isHittable` assertion with a behavioral/non-hittability tap-proof.
- Phase 6: used coordinate tap (XCUITest throws when tapping a deliberately non-hittable element) in `testGuideAppearsOnFirstLaunch`.
- **Only pre-existing (not stop-feature) failure found**: `testSettingsOpensAndShowsControls()` tapped a "Privacy" label while the row is "Privacy Policy". Proven pre-existing on `origin/main` (commit `92da977`). Fixed per user approval in `3815053`. Required to unblock the green full gate.

## Manual Verification Items (from the plan — NOT checked; user confirms)
- [ ] Build to iPhone 17 simulator, open Settings → Reminder, verify "Show guide again" toggle is present and on by default
- [ ] Toggle it off, verify it stays off when re-opening settings
- [ ] (Optional smoke) If watch build available: toggle off on phone, confirm on watch the guide won't show
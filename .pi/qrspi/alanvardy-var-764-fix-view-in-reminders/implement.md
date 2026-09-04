# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `c537d6f` | `URLOpening` contract + production wrapper + test spy |
| 2     | `009e875` | `ContentViewModel` wiring (`urlOpener`, `openInReminders`) |
| 3     | `bab3072` | View wiring + production injection + UI-test seam |
| 4     | `f604c99` | UI test — "View in Reminders" context menu |

## What Was Built

A `URLOpening` protocol seam makes the "View in Reminders" context-menu
action testable:

- **`SingleThread/URLOpening.swift`** (new): `@MainActor protocol URLOpening`,
  production `SystemURLOpener` (delegates to a live `OpenURLAction`), and
  `URLOpeningSpy` (records opened URLs) living in the app target so the
  UI-test process can reference it.
- **`ContentViewModel`**: stores `urlOpener: any URLOpening` (default: no-op
  `SystemURLOpener` so previews/tests compile unchanged) and exposes
  `openInReminders(_:)` which builds the `ReminderDeepLink` URL and opens it.
- **`AppViewModel`**: `contentViewModel` property → `makeContentViewModel(openURLAction:)`.
  Under `--url-opener-spy` it keeps a shared `URLOpeningSpy`; otherwise passes
  the scene's real `OpenURLAction` (or a no-op).
- **`ContentView`**: context-menu button now calls `viewModel.openInReminders(reminder)`;
  the now-unused `@Environment(\.openURL)` was removed; under
  `--url-opener-spy` an invisible element with `accessibilityIdentifier`
  `lastOpenedURL` and label `spyURL-<url>` renders so the UI test can read it.
- **`SingleThreadApp.swift`**: passes the scene's `@Environment(\.openURL)`
  into `makeContentViewModel(openURLAction:)`.

## Deviations From Plan (with reasoning)

1. **`ContentView` spy element read via `otherElements`, not `staticTexts`**
   (Phase 3/4). Phase 3 rendered the spy as `Text(...).accessibilityElement(children: .ignore)`,
   matching the existing `completionGlowOverlay` seam — such elements surface as
   `otherElements` in XCUITest. Phase 4's UI test therefore reuses the existing
   `statusLabel(app, identifier:)` helper (checks `otherElements` first, falls
   back to `staticTexts`), and the long-press workflow is unchanged.
2. **`OpenURLAction` has no `init()`** — always built via
   `OpenURLAction { _ in .handled }` / trailing-closure form per repo
   SwiftFormat/SwiftLint canonicalization.
3. **Simulator OS is 26.5, not 26.0** as the plan's checkpoint commands
   assume; destinations were pinned `platform=iOS Simulator,id=<UDID>,OS=26.5`
   (iOS 26.5 is the only available runtime on this machine).

## Automated Checks
- [x] `URLOpeningTests` (3 tests) pass — Phase 1
- [x] `ContentViewModelTests` (3 tests) pass — Phase 2
- [x] App builds with updated `ContentViewModel`/`AppViewModel` init, all existing call sites compile
- [x] `make format` / SwiftFormat clean
- [x] `make lint` / SwiftLint `--strict` clean (0 violations)
- [x] New UI test `testViewInRemindersOpensURL` passes (with surrounding UI flows)
- [x] Full `./scripts/test.sh` gate passes: format + lint + build + Periphery + unit + UI (+ watch + macOS) — ✅ All CI checks passed
- [x] `plan.md` Phase 1-4 automated checkboxes checked

## Manual Verification Items (from the plan)
- [ ] Build succeeds — `URLOpening` protocol compiles; spy compiles; tests compile
- [ ] Build succeeds with updated `ContentViewModel` init (all existing call sites compile thanks to the default `nil` parameter)
- [ ] Run app in simulator, long-press the reminder card, tap "View in Reminders" — Reminders app opens (same UX as before, now routed through the protocol)
- [ ] Check with `--url-opener-spy` launch arg: the spy records the URL, the hidden label renders, and no real URL open occurs (the spy absorbs the call)
- [ ] Run `make ui-test` and observe the test pass: context menu appears, tap, spy element found, URL prefix matches

## Notes / Observations

- **Full-gate failure in the first local run was NOT a regression.** The
  first `./scripts/test.sh` run failed in `ReminderStoreWriteTests`,
  `UndoCompletionTests`, and `CompletionGlowViewModelTests`
  (`completeReminder` returned false / glow never activated). Root cause:
  the shared App-Group `completionCount` on this long-lived local simulator
  had accumulated to exactly 100 across prior gate runs, so `canMutate`
  (`isEntitled || count < 100`) was false for every non-entitled store and
  all mutation tests no-op'd. Reset the simulator's AppGroup
  `completionCount` to 0 (equivalent to a fresh CI runner) and the full gate
  passed; the same test code passed on CI 4h prior on a fresh runner. CI is
  unaffected because each run gets a fresh simulator. If the local gate
  flakes on these suites again, reset
  `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Shared/AppGroup/*/Library/Preferences/group.app.alanvardy.SingleThread.plist`
  `completionCount` to 0.
- This feature shipped with a unit-test layer (`URLOpeningTests`,
  `ContentViewModelTests`) and a UI test (`testViewInRemindersOpensURL`),
  satisfying the repo's testing requirements.
- No plan-phase code touches `ReminderStore`/undo/glow logic; the freemium-cap
  cleanup (comment-only drift vs `origin/main`) was pre-existing branch state.
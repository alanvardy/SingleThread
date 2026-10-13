# Recon — Change Apple Watch Skip button icon to ellipsis

## 1. Change site & iOS mirror

### Watch change site: `SingleThreadWatch/WatchReminderView.swift`
`private var actionButtons: some View` spans lines **136–159**. The Skip button
(label → modifiers) is lines **141–156**. Current code:

```swift
Button {
    if canShowActionMenu {
        viewModel.isShowingActionMenu = true
    } else {
        viewModel.store.skipCurrentReminder()
    }
} label: {
    Label(SharedStrings.skipAction, systemImage: "circle.slash")   // line 146
        .labelStyle(.iconOnly)
}
.tint(.orange)
.accessibilityLabel(SharedStrings.skipReminderAccessibility)        // line 153
.accessibilityIdentifier("skipButton")                              // line 154
.accessibilityAddTraits(.isButton)                                  // line 155
```

Change: systemImage `"circle.slash"` → `"ellipsis.circle.fill"` when
`canShowActionMenu`; accessibility label
`SharedStrings.skipReminderAccessibility` → `SharedStrings.moreAction`.
Keep `.tint(.orange)`, `accessibilityIdentifier("skipButton")`,
`.accessibilityAddTraits(.isButton)`.

`canShowActionMenu` is at lines 134–141 (gates: showEnableActionButtonsState
toggle ON, store.canMutate, a visible reminder exists). `viewModel.isShowingActionMenu`
is set at line 144.

### iOS mirror: `SingleThread/ContentView+ActionMenu.swift`
`var skipButton: some View` lines **60–83** (iOS, line 60 header, `#if os(iOS)`).
The mirrored pattern:
- label `systemImage:` uses `showActionMenu ? SwipeRevealPanel.systemImage(for: .more) : "circle.slash"` (line 74). `SwipeRevealPanel.systemImage(for: .more)` == `"ellipsis.circle.fill"` (verified in `SingleThread/SwipeToActModifier.swift:44`).
- `.accessibilityLabel(showActionMenu ? SharedStrings.moreAction : SharedStrings.skipReminderAccessibility)` (line 80).
- `.accessibilityIdentifier("skipButton")` (81), `.accessibilityAddTraits(.isButton)` (82).

macOS `macActionMenu`/`macSkipButton` also use `skipButton` identifier (a separate
pattern, untouched by this change).

## 2. Tests that touch the watch skip button / action menu

Repo-wide search for `skipButton|watchSkipButton`:
- `SingleThreadUITests/SingleThreadUITests.swift:48` — iOS UI test asserts
  `app.buttons["skipButton"].exists` (iOS, untouched).
- `SingleThreadWidget/NextThingWidget.swift:157` — widget, same identifier (untouched).
- `SingleThreadWatch/WatchReminderView.swift:154` — the change site itself.
- `SingleThread/ContentView+ActionMenu.swift:81,158,174` — iOS/macOS, untouched.

**No test references the watch skip button.**
- `SingleThreadWatchUITests/SingleThreadWatchUITests.swift` — grep for
  `skip|ActionMenu|circle\.slash|ellipsis|accessibilityLabel|moreAction`
  returned **zero matches**.
- `SingleThreadWatchTests/` files (`WatchReminderViewModelTests.swift`,
  `ReminderStoreWatchTests.swift`, `WatchSyncPipelineTests.swift`,
  `ShowCompletionGlowStateTests.swift`) reference "skip" only as skip-persistence
  / skipStore behavior — **no view-layer assertions** on icon, label, or
  `isShowingActionMenu`.

**Conclusion: no test updates required** for this icon/label-only change. If a
unit test is desired, it would need a new view-level assertion; none currently exist.

## 3. Build / test / verify commands

Pinning: `.simulator_id` = `FACB2C42-982F-474D-A9F1-41F13216D4B9` (an iOS sim UDID).
Precedence: explicit `SIM=` > `.simulator_id` > default iPhone 17. For watch
concrete-device pinning the Makefile auto-resolves `Apple Watch Series 11 (46mm)`
UDID; override with `WATCH_TEST_SIM='platform=watchOS Simulator,id=…'`.

Make targets (all in repo `Makefile`):
- `make watch-build` — `xcodebuild -scheme SingleThreadWatch -destination '$(WATCH_SIM)'` (generic watchOS Simulator) build.
- `make watch-test` — watch unit tests: `xcodebuild -scheme SingleThreadWatch -destination '$(WATCH_TEST_SIM)' -only-testing:SingleThreadWatchTests`.
- `make watch-ui-test` — `-destination '$(WATCH_TEST_SIM)' -only-testing:SingleThreadWatchUITests`.
- `make build` / `make test` — iOS (unneeded for this watch change, watch is a separate scheme).
- `make lint` — `swiftformat --lint` (all dirs incl. watch) + `swiftlint lint --strict`.
- `make format` — applies SwiftFormat + SwiftLint fixes.

Targeted single-test: `scripts/test-one.sh <Target/Suite/case>` is **iOS-only**
(`-scheme SingleThread`, pins iOS `.simulator_id`) — **not usable for watch
tests**. For a single watch test use `xcodebuild … -only-testing:SingleThreadWatchTests/<Suite>/<case>` with the `WATCH_TEST_SIM` destination directly.

## 4. SharedStrings.moreAction reachability from watch

Yes. `SharedStrings` lives in `SingleThreadCore`
(`SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`),
`moreAction` at line 37, `skipReminderAccessibility` at line 60. The watch target
imports `SingleThreadCore` (WatchReminderView.swift line 2) and already uses
`SharedStrings.skipReminderAccessibility` / `SharedStrings.skipAction` at the change
site. So `SharedStrings.moreAction` is fully reachable — the watch can NOT, however,
use `SwipeRevealPanel.systemImage(for: .more)` (that type is in the iOS app/single
target), so the literal `"ellipsis.circle.fill"` string is correct per the task.

## 5. Git state

Worktree is on branch `alanvardy-var-1131-change-apple-watch-skip-button`.
`git status --short`: ` D DELETEME` (deleted at bootstrap, expected, already gone)
and `?? .pi/orksorksorks/alanvardy-var-1131-change-apple-watch-skip-button/`
(this recon artifact). No source changes yet — this is a clean change site awaiting
the edit. DELETEME is already removed, so no `git rm` needed.

## Start Here
Open `SingleThreadWatch/WatchReminderView.swift` lines 141–156 (the Skip button
inside `private var actionButtons`). This is the only file to edit. Mirror the
iOS pattern at `SingleThread/ContentView+ActionMenu.swift:60–83` exactly.
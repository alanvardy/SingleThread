# Design Discussion

## Current State

The watch app has **all the infrastructure** for a completion glow but it doesn't
visibly flash when a reminder is completed (the ticket's premise). The code on
`main` includes:

- **Core model**: `CompletionGlow` (`CompletionGlow.swift:12-13`) — `@MainActor
  @Observable`, `trigger()` sets `isActive = true`, auto-dismisses after `duration`
  (default 0.25s). Shared by both platforms.
- **Watch view model gate**: `WatchReminderViewModel.completeCurrentReminder()`
  (`WatchReminderViewModel.swift:53-56`) gates `completionGlow.trigger()` on the
  store result AND `showCompletionGlowState.isEnabled`.
- **Watch state holder**: `ShowCompletionGlowState` (`ShowCompletionGlowState.swift:9-27`)
  seeded from `.standard` UserDefaults, updated by the sync receive path via `apply(_:)`.
- **Watch overlay**: `completionGlowOverlay` (`WatchReminderView.swift:141-148`) —
  `Color.green.opacity(0.3)`, hit-test disabled, `.transition(.opacity)`,
  animated via `.animation(reduceMotion ? nil : .easeInOut(duration: 0.4), ...)`.
- **Sync pipeline**: iPhone pushes `showCompletionGlow` via `pushAll()`
  (`SkippedReminderSyncService.swift:104-105`), sends only when
  `sendsShowCompletionGlow: true` (iPhone default); watch receives in
  `apply(context:)` (`SkippedReminderSyncService.swift:314-317`), fires
  `onShowCompletionGlowReceived` → `ShowCompletionGlowState.apply(_:)`.
- **Unit tests**: `ShowCompletionGlowStateTests` covers gate-on/off,
  `WatchSyncPipelineTests` covers receive+survive-relaunch. No watch UI tests exist
  for the glow (no `SingleThreadWatchUITests` target).

The gap between "infrastructure present" and "doesn't glow" is **unconfirmed** —
we will investigate empirically during implementation. Likely candidates include
a SwiftUI view-lifecycle issue (the `reminderViewModel` computed property could
replace the `CompletionGlow` instance mid-animation) or the 0.25s duration being
imperceptible on watchOS with a 0.4s animation envelope.

## Desired End State

The watch shows the same brief full-screen green completion glow the iPhone shows,
gated by the shared "show completion glow" setting. Specifically:

1. **Tapping Complete** on the watch triggers a visible green flash, then
   auto-dismisses.
2. **Disabling "Completion glow"** in iOS Settings suppresses the flash on both
   platforms after the setting syncs to the watch.
3. **Reduce-motion** disables the fade animation (snap on/off) on both platforms
   (already the case — no change needed).
4. **Watch UI tests** assert the glow appears and disappears, matching the iOS
   UI-test coverage.
5. **iOS `ReminderSettingsView`** stays as-is — the glow toggle has no
   `.onChange` reload because it's purely visual, not content-changing. This is
   intentional (see Design Decision 2).

Acceptance criteria:
- Tapping Complete on a real watch shows a visible green flash.
- `make test` passes with new watch UI tests.
- iOS regression: existing `testCompletionGlowFlashesWhenEnabled` /
  `testCompletionGlowDoesNotAppearWhenDisabled` still pass.

## Patterns to Follow

### Do match

- **State-holder pattern**: Every "show X" setting follows the same pattern on
  watch — a dedicated `@Observable final class` (`Show*State`) seeded from
  `.standard`, updated via `apply(_:)` from the sync receive hook
  (`WatchAppViewModel.swift:152-173`). `ShowCompletionGlowState` already follows
  this pattern.
- **Sync hook wiring**: Write-once-before-`activate()`, `nonisolated(unsafe)`
  closure captures weak state, snapshotted before invocation
  (`SkippedReminderSyncService.swift:65-69,314-317`). No changes needed.
- **View model gating**: Both `ContentViewModel.completeCurrentReminder()`
  (`ContentViewModel.swift:108-110`) and `WatchReminderViewModel.completeCurrentReminder()`
  (`WatchReminderViewModel.swift:53-56`) gate trigger on result+preference. Match
  this pattern.
- **UI test seam**: iOS uses `ProcessInfo.processInfo.arguments.contains("--ui-testing-glow")`
  to extend duration and expose `accessibilityIdentifier` (`AppViewModel.swift:213-220`,
  `ContentView.swift:211-214,485`). Replicate this pattern on watch.
- **Animation + reduce-motion**: `.animation(reduceMotion ? nil : .easeInOut(...), value:)`
  is identical on both platforms (`ContentView.swift:85-87`, `WatchReminderView.swift:90-92`).
  No change needed.

### Do NOT match

- **No `contentViewModel` computed-property pattern on watch**: iOS's
  `AppViewModel.contentViewModel` is a computed property (`AppViewModel.swift:97-107`),
  rebuilt on every access. The watch also uses a computed property
  (`WatchAppViewModel.reminderViewModel`, `WatchAppViewModel.swift:53-64`). If
  this causes the `CompletionGlow` instance to be replaced mid-animation, switch
  to a stored property that's created once.

## Design Decisions

1. **Root cause = TBD empirically**: We'll build to a watch/simulator and observe
   actual behavior. Three hypotheses to test: (a) glow fires but 0.25s is
   imperceptible on watchOS, (b) computed-property view-model lifecycles replace
   the `CompletionGlow` instance mid-animation, (c) a different unknown cause.
   Fix what we find.

2. **iOS ReminderSettingsView asymmetry is intentional**: The glow toggle has no
   `.onChange` calling `viewModel.showPreferenceChanged()` — unlike date/recurrence/
   alarms toggles. This is correct: those toggles toggle content visibility (dates,
   recurrence labels, alarms) and need a list reload; the glow toggle is purely
   visual feedback. No reload needed. Documented, not fixed.

3. **Watch uses `.standard` consistently**: All five `Show*State` holders on watch
   reference `.standard` UserDefaults (`ShowDateState.swift:28`,
   `ShowCompletionGlowState.swift:27`, etc.), as do all five `Show*Preference`
   stores passed to the sync service (`WatchAppViewModel.swift:110-114`). The
   sync receive writes to `.standard`, the state reads from `.standard` — this is
   internally consistent. No change. `AppGroup.defaults` falls back to `.standard`
   on watch anyway (`AppGroup.swift:12-16`).

4. **Watch UI test seam matches iOS**: Add `--ui-testing-glow` support to
   `WatchAppViewModel`:
   - Extend `completionGlow.duration` to `2.0` (matches iOS,
     `AppViewModel.swift:219`).
   - Add `accessibilityIdentifier("completionGlowOverlay")` and conditionally
     expose to accessibility (`accessibilityHidden(!isGlowUITesting)`), matching
     iOS (`ContentView.swift:485`).
   - This requires creating a `SingleThreadWatchUITests` target (per AGENTS.md,
     this involves pbxproj object IDs, scheme TestAction wiring, `scripts/test.sh`
     `-only-testing` entries, and CI matrix additions).

5. **Watch UI tests cover enable + disable flows**: Mirror the iOS tests
   (`testCompletionGlowFlashesWhenEnabled` at `SingleThreadUITestsFlows.swift:401`,
   `testCompletionGlowDoesNotAppearWhenDisabled` at `SingleThreadUITestsFlows.swift:374`).
   The watch tests launch with `--ui-testing` (existing seam) + `--ui-testing-glow`
   (new seam), complete the reminder, and assert the overlay exists/doesn't-exist.

6. **No `--seed` seam on watch**: The watch doesn't have a `--seed` launch-arg
   parser like iOS (`UITestingSeed`). We reuse the existing `--ui-testing` seam
   (`WatchAppViewModel.uiTestingStore(arguments:)`, lines 72-99) which bakes a
   single "Buy groceries" reminder. This is sufficient for glow UI tests since we
   only need one completable reminder.

7. **Reduce-motion behavior unchanged**: Both platforms already disable the fade
   animation under reduce motion (`ContentView.swift:86`, `WatchReminderView.swift:91`).
   Neither suppresses the glow entirely. This matches iOS — no change.

## What We're NOT Doing

- **NOT adding a reload/refresh when the glow toggle changes** — intentional
  (Design Decision 2).
- **NOT switching watch to `AppGroup.defaults`** — `.standard` is internally
  consistent across all watch `Show*State` holders (Design Decision 3).
- **NOT adding a `--seed` seam to the watch** — the existing `--ui-testing` seam
  is sufficient for glow UI tests (Decision 6).
- **NOT changing the iOS glow** — it works and is locked in by CI UI tests.
- **NOT adding a watch-side push for the glow flag** — the watch is receive-only
  for all settings (`sendsShowCompletionGlow: false`,
  `WatchAppViewModel.swift:117`). This is correct.
- **NOT showing the glow for completions that arrived from the phone** — only
  the in-view `completeCurrentReminder()` path triggers it. This matches iPhone
  behavior (you don't see the glow for completions that originated on the watch).

## Open Risks

1. **View lifecycle issue**: If the computed `reminderViewModel` property causes
   the `CompletionGlow` instance to be replaced mid-animation, the fix requires
   changing `WatchAppViewModel` to store the view model. This is a small change
   but touches the composition root. Risk: low complexity, high impact if needed.

2. **New `SingleThreadWatchUITests` target**: Per AGENTS.md, this requires pbxproj
   object IDs, scheme wiring, `scripts/test.sh` entries, and CI matrix additions.
   This is the highest-ceremony part of the change. Mitigation: follow the
   pattern from when `SingleThreadUITests` was first created.

3. **Watch simulator behavior vs real device**: The glow may render differently
   on a real Apple Watch (OLED, smaller screen, different animation timing) than
   in the simulator. We'll test on both if possible; the simulator is the
   primary CI gate.

4. **Duration tuning**: If the fix is "increase duration," choosing the right
   value requires taste. Start with 0.5s (slightly longer than the 0.4s
   animation) and iterate if needed.

5. **Accessibility audit**: The existing `SingleThreadUITests.testAccessibilityAudit()`
   uses `XCUIApplication.performAccessibilityAudit()`. If we add a watch UI test
   with accessibility exposure for the glow, the audit may flag the exposed
   overlay. Mitigation: expose the glow to accessibility only under
   `--ui-testing-glow`, same as iOS.
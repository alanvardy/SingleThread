# Design Discussion

## Current State

The mic (dictation) button in SingleThread has **three stacked visibility gates**,
any one of which can silently suppress it:

1. **EventKit gate** (`ContentView.swift:333-343`): `authorizationStatus != .fullAccess`
   → no reminder list, no bottom bar at all. Not a mic bug — removes all UI.

2. **`canDictate && showMicrophoneButton` gate** (`ContentView.swift:480`):
   - `canDictate` = speech auth `.authorized || .notDetermined`
     (`DictationViewModel.swift:27-30`). Snapshot captured once at
     `ReminderDictation.init` (`ReminderDictation.swift:32`), never refreshed
     until explicit `requestAuthorization()` or scene rebuild.
   - `showMicrophoneButton` = `@AppStorage("showMicrophoneButton")` default
     `true`, **`UserDefaults.standard`** suite (`ContentView.swift:190-191`).
     No `register(defaults:)` call exists in the entire repo — the `true`
     default lives only in the property initializer. A raw `bool(forKey:)`
     read returns `false` when unset. Never synced via WatchConnectivity
     (`SkippedReminderSyncService.swift:266-280` — absent from payload keys)
     or iCloud. Each app install has an independent copy.

3. **iOS-only freemium + action-buttons gates** (`ContentView.swift:481-488`):
   `!canMutate` → `UpgradePromptButton` replaces mic; `showsActionButtons` →
   `actionCluster` keeps mic inside a Complete/mic/Skip cluster.

When the mic is hidden by gate 2, there is **no UI indication**. The only
surface is `dictationError` text (`ContentView.swift:462-468`), which only
appears if the user previously tapped the mic and was denied — it never shows
for a fresh install where speech was already denied.

**Test coverage** (`SingleThreadTests/MicrophoneToggleTests.swift:36-104`):
one test asserts mic absence when `.denied` (`:69`). No test asserts mic
*presence*, no test exercises `.restricted` or `.notDetermined` rendering at
the UI level, and no UI-test seam exists to force a speech authorization state.

## Desired End State

1. **`showMicrophoneButton` default is reliable**: `UserDefaults.standard`
   registers the `true` default so no code path can observe `false` when the
   key hasn't been explicitly set.

2. **Authorization status stays in sync with the system**: after backgrounding
   the app, if the user changes the speech permission in Settings, the
   cached `authorizationStatus` in `ReminderDictation` is refreshed on
   foreground so the mic reappears without a force-quit.

3. **Hidden mic has an explanation**: when speech is `.denied` or
   `.restricted`, the bottom bar shows a small explanatory label instead of
   complete silence.

4. **Tests cover the new behavior**: unit tests assert the foreground re-read
   updates `canDictate`, and that the explanatory label renders in `.denied` /
   `.restricted` states.

**Verification**: on a device where the mic was hidden with speech denied,
granting speech access in Settings and returning to the app shows the mic
immediately (not after force-quit). Toggling the mic off in Settings and
back on returns it to the `true` default. The explanatory label appears when
speech is denied and disappears when granted.

## Patterns to Follow

- **`register(defaults:)`** — no existing call exists, but `@AppStorage`
  property initializers provide the canonical default values
  (`ContentView.swift:190-216`). Registration mirrors these values exactly
  and is standard Cocoa practice.
- **Scene-phase reactions** — `ContentView.handleScenePhaseChange` already
  switches on `.background`/`.active` (`ContentView.swift:715-725`). Add a
  `.active` call to refresh authorization rather than introducing a new
  observer pattern.
- **Protocol-backed test seams** — `SpeechTranscribing` (`ReminderDictation.swift:8-16`)
  already abstracts authorization for tests. Add the refresh method to the
  protocol so fakes can record the call.
- **Error/status text pattern** — `dictationError` renders as red `.caption`
  text in `bottomBar` (`ContentView.swift:462-468`). The new explanatory
  label uses the same styling.
- **Unit-test pattern** — `MicToggleFakeTranscriber` (`MicrophoneToggleTests.swift:9-24`)
  presets `authorizationStatus`. Follow this for new tests; assert body
  string contents for visibility.
- **DO NOT follow**: the `@AppStorage`-without-registration pattern for
  settings with a non-false default — it creates a silent divergence risk.

## Design Decisions

1. **Register `showMicrophoneButton = true` default**: `UserDefaults.standard.register(defaults:)`
   in `AppViewModel.init` (or a dedicated `registerDefaults()` helper). This
   is the narrowest fix — one line, no behavior change for any existing
   install, eliminates the silent-`false` risk. We do NOT move
   `showMicrophoneButton` to App Group or WatchConnectivity; that's a
   separate behavior change.

2. **Foreground auth re-read via scene-phase `.active`**: add
   `refreshAuthorizationStatus()` to `SpeechTranscribing` protocol and
   `ReminderDictation` (re-reads `SFSpeechRecognizer.authorizationStatus()`
   and updates the stored property). Call it from
   `ContentView.handleScenePhaseChange` on `.active`. The
   `ContentViewModel`/`DictationViewModel` chain already has access to the
   transcriber. This fixes the "changed permission while backgrounded"
   staleness window.

3. **Explanatory label when mic is hidden by speech denial**: in `bottomBar`,
   after the `dictationError` banner, add an `else if` branch: when
   `!canDictate && authorizationStatus != .notDetermined && showMicrophoneButton`,
   render a caption explaining speech recognition is unavailable. Include a
   Settings deep-link button on iOS. When `showMicrophoneButton == false`,
   show nothing (user chose to hide it).

4. **Gate the label on `showMicrophoneButton`**: only show the explanation
   when the user hasn't explicitly turned the mic off. A user who toggled
   "Show microphone" to off doesn't need a "mic is hidden" explanation.

## What We're NOT Doing

- **Not moving `showMicrophoneButton` to App Group or WatchConnectivity**.
  Cross-device sync of this toggle is a feature, not a bug fix.
- **Not adding a full authorization-status UI section** (Settings deep link,
  status readout, permission flow diagram). A single explanatory label
  covers the diagnostic gap.
- **Not adding UI-test seams for speech authorization**. That requires a
  production-code abstraction layer; the unit tests + explanatory label
  give enough coverage for a targeted fix.
- **Not changing the `notDetermined` → mic-visible behavior**. It's
  intentional — speech permission is requested lazily on first tap.
- **Not touching the EventKit gate or the freemium/action-buttons gates**.
  Those are unrelated to the reported bug.
- **Not adding centralized `register(defaults:)` for all `@AppStorage`
  keys**. The scope is `showMicrophoneButton` only; expanding to all keys
  would be a separate refactor.

## Open Risks

- **macOS scene-phase**: the existing `handleScenePhaseChange` is
  `#if os(iOS)`-only (`ContentView.swift:131-133`). We need to extend the
  scene-phase handler (or add a macOS equivalent) for the foreground
  re-read. macOS `ScenePhase.active` works the same way but hasn't been
  tested in this codebase.
- **`ReminderDictation` lifetime**: `contentViewModel` is a computed
  property (`AppViewModel.swift:198-205`), so it rebuilds on every
  `SingleThreadApp.body` evaluation. If SwiftUI re-evaluates the scene body
  more often than expected, the re-read on `.active` may land on a
  different `ReminderDictation` instance than the one still cached by a
  stale `ContentView`. In practice `.active` fires *before* body
  re-evaluation, so the write should land on the current instance — but
  this is worth a unit test.
- **`register(defaults:)` timing**: if `AppViewModel.init` runs before
  `@AppStorage` properties are first accessed, the registration takes
  effect correctly. If any `@AppStorage` read happens before init (e.g. in a
  static context), the default won't apply to that read. This is unlikely
  but worth verifying.
- **The affected user's actual state**: we can't reproduce VAR-747. The
  three fixes cover the most probable causes (stale denial, divergent
  toggle), but if the root cause is something else entirely (e.g. a
  `SFSpeechRecognizer` returning nil for the user's locale), the fix won't
  help. The explanatory label at least provides a diagnostic surface for
  the next report.
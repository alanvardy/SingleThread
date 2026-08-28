# Design Discussion

## Current State

The watch companion app (`SingleThreadWatch/`) has no onboarding. The user
lands directly on the reminder card with no guidance about interactions.

**Root view composition** (`WatchReminderView.swift:58-96`): A `ZStack`
(conditionally showing `allDoneState` / `reminderCard` / `noRemindersState`)
+ refresh `ProgressView` (`:68-73`) + `.overlay` for the completion glow
(`:86-88`). The glow is the codebase's full-screen overlay reference: `Color`
+ `opacity` + `.ignoresSafeArea()` + `.allowsHitTesting(false)` +
`.accessibilityHidden(true)` + `.transition(.opacity)` (`:141-148`), with
`.animation(reduceMotion ? nil : .easeInOut(0.4), value: ...)` (`:90-94`).

**State-holder pattern** (`ShowDateState.swift:10-21` and four siblings in
`SingleThreadWatch/`): An `@Observable` class that reads a `ShowXPreference`
in `init()` and publishes `isEnabled`. The paired `ShowXPreference` struct
(`ShowDatePreference.swift:9-22`, in `SingleThreadCore/`) wraps a single
`object(forKey:) as? Bool ?? <default>` read/write. Defaults are `true` for
the four early toggles, `false` for `showList`. All five show-* preferences
read/write `AppGroup.defaults` (degrading silently to `.standard` on watchOS
because the watch has no App Group entitlement — `AppGroup.swift:12-14`).

**Sync pipeline** (`SkippedReminderSyncService.swift:146-174`): Phone pushes
all five show-* flags unconditionally (`sendsShow*: true`, `AppViewModel.swift:28-35`)
via `WCSession updateApplicationContext`. Watch receives them (`WatchAppViewModel.swift:115-116`,
`sendsShow*: false`) and forwards to state holders via `onShow*Received`
hooks (`:151-169`). The show-* flags are phone→watch one-directional.

**iPhone Settings** (`ReminderSettingsView.swift`): Five `Toggle`s bound to
`@Bindable var showX` from the `SettingsBindings` bag (`SettingsBindings.swift:14-65`).
The sheet writes back to `@AppStorage` via `.onChange(of: bag.X)` in
`ContentView.swift:109-136`, which triggers `AppViewModel.setupSyncObservation()`
(`AppViewModel.swift:179-188`) → `handlePreferencesChanged()` → `pushAll()`.

**Watch testing seam** (`WatchAppViewModel.swift:14-20`): `--ui-testing`
launch arg seeds a fixed single reminder. No first-launch reset exists — unlike
iOS's`UITestingSeed.resetPersistedState()` (`UITestingSeed.swift:41-49`).
The`--reset-glow-preference` flag on iOS (`AppViewModel.swift:186-190`) is
the closest pattern for one-off key resetting.

**Card interactions** (`WatchReminderView.swift:164-180`): Tap → confiration
dialog (Refresh / Delete); two action butons (Complete `:91-102`, Skip `:104-112`).
No swipe gestures exist on the watch card — swipes are iOS-only.

## Desired End State

1. **First-launch guide overlay** on the watch: When the user opens the watch
   app for the first time, the reminder content is covered by a guide overlay
   showing "Tap Complete to finish" and "Tap Skip to skip" with arrows pointing
   at the Complete and Skip butons. A "Got it" buton dismisses the overlay.
   It never appears again (unless re-requested via setting).

2. **"Show guide again" toggle** in the iPhone Settings → Reminder screen.
   Toggling it on pushes a flag to the watch that resets the guide to appear
   on the watch's next view.

3. **Verification**: The guide fades in/out smoothly; VoiceOver reads the
   instructions and buton; Reduce Motion users get an instant cut instead of fade;
   unit tests cover state transitions; UI tests verify the guide appears on
   first launch and does not reappear on subsequent launches.

## Patterns to Follow

- **State-holder + preference pair**: Create `ShowGuide` in `SingleThreadWatch/`
  and `ShowGuidePreference` in `SingleThreadCore/`, identically to the existing
  five pairs. Key `"showGuide"`, nil → `true` (first-launch semantic).
  Reference: `ShowDateState.swift:10-21`, `ShowDatePreference.swift:9-22`.
  Use `object(forKey:) as? Bool ?? true` to avoid `bool(forKey:)` false-coercion
  (`ShowDatePreference.swift:3-5`).

- **Overlay recipe** (adapted): Use `.overlay` on the `reminderContent` ZStack
  (not as a ZStack child — `WatchReminderView.swift:86-88`). Unlike the
  decorative glow, this overlay is **interactive content**: `allowsHitTesting(true)`,
  `accessibilityHidden(false)` with appropriate labels and buton traits.
  Fade animation: `.transition(.opacity)` + `.animation(reduceMotion ? nil : .easeInOut(0.4), value: showGuide.isActive)`
  (`WatchReminderView.swift:90-94`, `:147`).

- **Sync pipeline**: Add `showGuide` to both the iOS push (phone sends it,
  `AppViewModel.swift:28-35`) and the watch receive (`WatchAppViewModel.swift:115-116`
  with `sendsShowGuide: false`). Add `PayloadKey.showGuide` to the wire-format
  enum (`SkippedReminderSyncService.swift:234-246`) and a `pushAll()` branch
  gated by `sendsShowGuide`. Hook: `onShowGuideReceived` → `showGuide.apply(value)`.

- **iPhone Settings**: Add a `Toggle` in `ReminderSettingsView` (alongside the
  existing five toggles, `ReminderSettingsView.swift:16-48`), a `showGuide` prop
  in `SettingsBindings` (`SettingsBindings.swift:14-65`), a `makeSettingsBag()`
  entry (`ContentView.swift:499-529`), and a `.onChange(of: bag.showGuide)` write-
  back (`ContentView.swift:120-135`). The toggle is "on" to request showing the
  guide; flipping it toggles the watch-side flag through the existing sync path.

- **Testing**: Add `--reset-guide` launch arg to `WatchAppViewModel.init`
  (`WatchAppViewModel.swift:14-20`) that removes `"showGuide"` from `.standard`
  before building the store — following the `--reset-glow-preference` pattern
  (`AppViewModel.swift:186-190`). New unit tests in
  `SingleThreadWatchTests/` for `ShowGuideState` (analogous to
  `ShowCompletionGlowStateTests.swift`), and new UI test for the guide flow
  in `SingleThreadWatchUITests/`.

- **Do NOT follow**: The `load()/ save()` naming on `ShowUndatedRemindersPreference`.
  Use `isEnabled`/`set(_:)` matching the show-* family. The `showList` pattern
  of no `onChange`/widget-reload is intentionally followed for `showGuide` (no
  widget impact, no `showPreferenceChanged()` call needed).

## Design Decisions

1. **Swipe instructions → buton instructions**: The guide overlay will describe
   the actual buton-based interactions ("Tap Complete" / "Tap Skip"), not
   fictional swipe gestures. The watch card has no swipes and adding them is
   out of scope. Rationale: the codebase already moved away from swipe UX on
   watchOS; the guide should reflect reality.

2. **"Show again" on iPhone only**: No watch-side settings or gear buton.
   The toggle lives in iPhone `ReminderSettingsView`, pushed to the watch via
   the existing sync pipeline. Rationale: no watch settings surface exists today;
   building one is scope creep. The user reaches for their phone to configure
   watch preferences — this is the established pattern for all five existing
   show-* flags.

3. **Active overlay with "Got it" buton**: `allowsHitTesting(true)` overlay
   with a clear buton. Explicit acknowledgment ensures the user sees the
   instructions before continuing. The overlay blocks card interaction until
   dismissed, which is the intent — first-launch orientation before use.
   Rationale: passive overlays risk being missed; this is content, not decoration.

4. **Fade animation respecting Reduce Motion**: `.transition(.opacity)` +
   `.animation(reduceMotion ? nil : .easeInOut(0.4), value: showGuide.isActive)`.
   Identical to the completion-glow animation contract. Rationale: consistency
   with the codebase's single animation pattern; Reduce Motion users get instant
   appear/disappear.

5. **`--reset-guide` launch arg for testing**: A single-purpose flag on the
   watch testing seam that removes the `"showGuide"` key from `.standard`.
   Rationale: minimal, follows `--reset-glow-preference` precedent, avoids
   backporting the full `resetPersistedState()` infrastructure which is overkill
   for one new key. If a third first-launch feature arrives, we can then
   consolidate — but premature generalization is the bigger risk here.

## What We're NOT Doing

- **No swipe gestures on the watch card.** The task description says "swipe right"
  / "swipe left" but the watch has butons, not swipes. We're changing the guide
  text, not adding swipe gestures.
- **No watch-side settings screen.** The "show guide again" buton is on iPhone only.
- **No iPhone or iPad guide overlay.** The guide is watch-only.
- **No widget update** on `showGuide` change (no `showPreferenceChanged()` call).
- **No animated arrows or particle effects.** The guide is static text + arrows.
- **No per-reminder-type gating.** The guide always describes the same
  Complete/Skip interaction regardless of reminder state (all-done, no-reminders,
  card-present).
- **No localization in V1.** The guide text will be hardcoded English strings;
  the codebase has no existing localization infra, and adding it is a separate
  feature.

## Open Risks

- **First-launch detection after app updates**: If a user upgrades from a version
  without the guide, `showGuide` will be nil →`true`, so the guide will appear.
  This is acceptable — it orientes updaters to any new interactions. If
  undesired, we'd need a migration flag, but for now nil→true is intentional.

- **VoiceOver focus management**: When the overlay appears on first launch,
  VoiceOver focus should land on the guide text or "Got it" buton, not the
  underlying card. May need `.accessibilityFocused` or `AccessibilityFocusState`
  on appearance. WatchOS accessibility APIs are more constrained than iOS — this
  warrants attention during implementation.

- **Screen real estate**: The Apple Watch has limited space for text + two arrows
  + a "Got it" buton. The layout must work on both 40mm and 49mm displays.
  Consider using `ViewThatfits` or a `ScrollView` to prevent truncation.

- **Interaction between guide and authorization flow**: On first launch, if the
  user hasn't granted reminders access, `WatchReminderView` shows
  `ProgressView("Requesting access…")` (`:44-45`) or an access-denied `Text`
  (`:48-51`). The guide should only overlay the `reminderContent` ZStack, not
  the authorization gate paths — those already provide their own orientation
  to the user.
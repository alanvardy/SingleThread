# Design Discussion

## Current State

The SingleThread iOS app shows exactly one reminder at a time in a full-height
List row (`ContentView.swift:309-361`). The row supports swipe-left to skip
(`:353-360`, orange `.tint`) and swipe-right to complete (`:345-352`, green
`.tint`), but **nothing in the UI teaches the user that swiping exists**
(research Q4). The swipe gesture is entirely undiscoverable — no hint, tip,
onboarding card, or instructional text anywhere in the app. Users learn to
swipe by accident or not at all.

The card (`ReminderCardView.swift:10-91`) renders as a VStack: title →
due/recurrence info → list name → alarm → notes (`.lineLimit(3)`). It has a
rounded-rect plate background and `.accessibilityElement(children: .combine)`
at `:80`. The plate padding self-cancels (`:86-91`), preserving outer geometry.

The Settings UI's Interface sub-screen (`InterfaceSettingsView.swift:25-57`)
already has two iOS-only toggles (`allowsLandscape`, `enableActionButtons`)
each backed by `@AppStorage` in `.standard` + a `SettingsBindings` property +
an `.onChange` write-back. These are lightweight — no `Show*Preference` struct,
no watch sync wiring (research Q2).

## Desired End State

A swipe-instruction prompt appears below the card's content (after the notes
block, inside the card's VStack), reading:

> ← Swipe left to skip | Swipe right to complete →

A "Dismiss" button sits below the prompt text. Tapping Dismiss sets the
preference to `false` and hides the prompt permanently until re-enabled.

A toggle "Show swipe prompt" in **Interface** Settings (alongside the existing
iOS-only toggles `allowsLandscape` / `enableActionButtons`) controls the same
boolean. The prompt is **enabled by default** (missing key → `true`).

This is iOS-only; the watch app is out of scope.

### Verification

- **Unit tests**: `SettingsBindings` default (true), `InterfaceSettingsView`
  snapshot contains "Show swipe prompt" label, `ReminderCardView` snapshot
  shows/omits prompt text based on flag.
- **UI tests**: `--ui-testing` launch shows the prompt. Swipe-left to skip
  followed by Dismiss tap hides it. Two-launch persistence test: dismiss,
  terminate, relaunch, verify prompt stays gone. Settings toggle round-trips.
- **Accessibility audit** continues to pass: prompt is `accessibilityHidden(true)`;
  Dismiss button remains accessible.

## Patterns to Follow

| Pattern | Source | Notes |
|---|---|---|
| `@AppStorage` in `.standard` + `SettingsBindings` property + `.onChange(of: bag.X)` write-back | `ContentView.swift:164-167` (`enableActionButtons`) + `SettingsBindings.swift:63` + `ContentView.swift:124-125` | No `Show*Preference` struct needed — this is iOS-only, like all other Interface toggles |
| iOS-only `#if os(iOS)` gate in `InterfaceSettingsView` | `InterfaceSettingsView.swift:40-42` (`allowsLandscape`), `:51-53` (`enableActionButtons`) | New toggle goes inside an `#if os(iOS)` block; `SettingsBindings` property is declared unconditionally (compiler forbids `#if` in property lists) |
| `makeSettingsBag()` iOS branch passes the value | `ContentView.swift:503-520` | Read from `@AppStorage`, pass into `SettingsBindings` init |
| `String(describing:)` snapshot assertions for view tests | `SettingsViewTests.swift:66-79`, `ShowDateTests.swift:11-16` | Assert presence/absence of rendered labels |
| `defer { UserDefaults.standard.removeObject(forKey:) }` cleanup in tests | All `Show*PreferenceTests.swift` files, `ActionButtonTests.swift` | Unique key via `UUID()` |
| `UITestingSeed.persistedKeys` literal list | `UITestingSeed.swift:52-70` | **Must append the new key** or it leaks across seeded launches |
| `--ui-testing` pre-set pattern | `AppViewModel.swift:146` (`enableActionButtons = true`) | Pre-set the new key to `true` so the prompt is always visible in UI tests |
| Dismiss triggers disable, toggle re-enables | `Q3 decision` | One boolean, two control surfaces pointing at the same `@AppStorage` key |
| Secondary text styling | `ReminderCardView.swift:43-44` (`.font(.caption)` + `.foregroundStyle(.secondary)`) | Prompt text follows this convention |
| Accessibility: hide instructional visual elements from a11y tree | `ContentView.swift:485` (completion glow `accessibilityHidden(!isGlowUITesting)`) | Prompt container is `accessibilityHidden(true)`; only Dismiss button is accessible |

### Patterns NOT to follow

- **Do NOT create a `ShowSwipePromptPreference` struct.** The `Show*Preference`
  pattern (`SingleThreadCore/Sources/SingleThreadCore/ShowCompletionGlowPreference.swift`)
  exists only for preferences that sync to watch via `SkippedReminderSyncService`
  and need a `SingleThreadCore`-side read/write API. This feature is iOS-only
  with no watch sync, so the struct adds boilerplate (init, `isEnabled`, `set`,
  dedicated test file, sync-service wiring, plus `UITestingSeed.persistedKeys`
  entry, `@AppStorage` mirror, and `SettingsBindings` property — ~50 lines)
  with no benefit. Follow the `enableActionButtons`/`allowsLandscape` pattern
  instead.

## Design Decisions

1. **Persistence model — lightweight `@AppStorage`**: Use `@AppStorage` in
   `.standard` (`ContentView.swift:164-167` pattern) + `SettingsBindings`
   property + `.onChange` write-back. No `Show*Preference` struct. This is an
   iOS-only UI preference like `enableActionButtons` — it does not sync to
   watch, does not need a `SingleThreadCore`-side API, and should not pay the
   ~50 lines of boilerplate the `Show*` struct pattern imposes.

2. **Prompt placement — inside `ReminderCardView`'s VStack after notes**:
   Appended after the notes block (`ReminderCardView.swift:68-73`). The prompt
   sits inside the card's visual plate, visually connected to the content the
   user swipes. The card grows taller to accommodate it. Swipe actions on the
   List row remain unchanged.

3. **Dismiss semantics — permanent disable**: Tapping Dismiss sets the
   preference to `false`. Same effect as toggling off in Settings. One
   boolean, two control surfaces. The task says "tapping Dismiss disables it;
   and a toggle … turns it on and off" — this is the simplest model and the
   clearest to users.

4. **Toggle placement — Interface section, iOS-only**: `#if os(iOS)` gated
   toggle in `InterfaceSettingsView` (alongside `allowsLandscape` and
   `enableActionButtons`). The Interface section already holds iOS-only UI
   toggles; this fits naturally.

5. **Accessibility — prompt hidden, Dismiss accessible**: The prompt text is
   `accessibilityHidden(true)`. VoiceOver users have their own gesture
   vocabulary; visual swipe instructions add noise to the card's combined
   accessibility label. The Dismiss button remains accessible as a standalone
   `.accessibilityLabel("Dismiss swipe prompt")` button.

6. **Default value — enabled**: Missing key → `true`. This is a discoverability
   feature; it should be on by default. Users who know the gestures can
   dismiss it.

7. **UI testing — reuse `--ui-testing` seam**: Pre-set the key to `true` in the
   `--ui-testing` block (`AppViewModel.swift:146` area) so the prompt is always
   visible. Dismiss persistence tested via the existing two-launch pattern
   (launch → dismiss → terminate → relaunch `--ui-testing` → verify gone).
   Add the key to `UITestingSeed.persistedKeys`.

## What We're NOT Doing

- **No watch app changes.** The task is iOS-only.
- **No new `Show*Preference` struct in `SingleThreadCore`.**
- **No `SkippedReminderSyncService` wiring.** No watch sync.
- **No animation on dismiss.** The prompt removes immediately. (A slide/fade
  could be added later but adds complexity without functional benefit.)
- **No per-reminder or per-session dismiss.** One global boolean.
- **No prompt on iPad / macOS.** SwiftUI `#if os(iOS)` gating on the toggle;
  the prompt view itself only renders on iOS because the toggle is never
  true elsewhere.
- **No changes to swipe-action handlers.** The prompt is purely instructional
  UI; it does not intercept gestures.

## Open Risks

- **Row height + bottomBar overlap**: Appending the prompt grows the card
  height. Under large Dynamic Type + long notes (already `.lineLimit(3)`),
  the bottom edge of the card could overlap with the `bottomBar` mic/action
  buttons. The current layout uses a ZStack with the bar overlaid on the list
  (`ContentView.swift:308,374`), so overlap is possible. Mitigation: the prompt
  is ~2 lines of `.caption` text + a small button — modest height. We'll watch
  for this in UI testing with large Dynamic Type.
- **VoiceOver audit**: The card uses `.accessibilityElement(children: .combine)`
  (`ReminderCardView.swift:80`). Adding `accessibilityHidden(true)` on the
  prompt container should exclude it from the combined label. We'll verify
  the accessibility audit still passes in CI.
- **`UITestingSeed.persistedKeys` is a literal list with no guard**: If the key
  is forgotten, it leaks across seeded UI-test launches. The implementation
  checklist must include this step; no compiler or test catches a missing
  entry.
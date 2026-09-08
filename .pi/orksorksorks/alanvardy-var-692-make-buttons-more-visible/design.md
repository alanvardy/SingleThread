# Design Discussion

## Current State

The iOS app renders controls over a decorative photo layer, but none of them
adapt to the background — they use fixed colors that wash out against photos.

- **Mic button** (`ContentView.swift:489–499`): 56×56 blue-filled circle,
  white glyph, `.shadow(radius: 4)`. Always blue regardless of scheme or photo.
- **Recording indicator** (`ContentView.swift:504–513`): same geometry with
  red fill, pulsing white glyph. Red is a deliberate "live" status signal.
- **Creation feedback** (`ContentView.swift:515–523`): transient 56×56 circle,
  green/red fill from `CreationFeedback.backgroundColor`, 1-second display.
- **Gear button** (`ContentView.swift:99–106`): 44×44 bare glyph,
  `.foregroundStyle(.secondary)`, no fill or background. Disappears against
  dark photo regions.
- **Complete/Skip buttons** (`ContentView.swift:450–476`): 44×44 flat tinted
  icons (`.tint(.green)` / `.tint(.orange)`), no fill, no shadow.
- **Photo layer** (`BackgroundImageStore.swift:163–191`): decorative only —
  hit-testing disabled, a11y hidden, opacity from `BackgroundFade` (default
  50% → 0.5 opacity). Sits below all content behind
  `Color.systemBackground`.
- **Scheme adaptation**: The only scheme-adaptive pattern is
  `ReminderCardView.swift:64–71` (black plate in dark mode, white in light
  mode). Appearance is forced at the `UIWindow` level via
  `AppDelegate.swift:18–28`; views read the effective scheme through
  `@Environment(\.colorScheme)`.
- **Accessibility**: All controls have labels and `.isButton` traits;
  `ActionButtonsUITests.swift` uses `["--ui-testing"]` launch args
  (which sets `enableActionButtons = true`, `SingleThreadApp.swift:114–127`)
  to verify button existence and tap behavior. No existing tests assert on
  visual style.

## Desired End State

All iOS controls are legible against any background photo, in both light and
dark modes, through scheme-adaptive circular plates with contrasting outlines.

**In dark mode**: each control sits on a **black circular plate** with a
**white glyph** and a **white stroke outline** (lineWidth ~2). The plate gets
`.shadow(radius: 4)` to lift it above the photo.

**In light mode**: each control sits on an **off-white circular plate** (e.g.,
`Color(white: 0.92)`) with a **dark (near-black) glyph** and a **dark stroke
outline** (lineWidth ~2). Same shadow.

**Recording state** (red fill): overrides the scheme-adaptive plate fill with
red but **keeps the white stroke outline** and white glyph, maintaining the
"live recording" signal while ensuring visibility.

**Creation feedback** (transient): inherits from the mic plate treatment but
uses its success/failure fill colors (green/red) with the outline treatment.

**Verification**: The existing `--ui-testing` launch seam exercises all
controls. No new test infrastructure needed — visual correctness is verified
manually; behavior and a11y checks remain unchanged. UI tests must still pass
`performAccessibilityAudit` and tap-flow assertions.

## Patterns to Follow

- **Scheme-adaptive fill** — `ReminderCardView.swift:66–69`:
  `colorScheme == .dark ? Color.black : Color.white`. Adapt this to off-white
  in light mode.
- **Reading scheme** — `ReminderCardView.swift:76–77`:
  `@Environment(\.colorScheme) private var colorScheme`.
- **Circle plate + shadow** — `ContentView.swift:489–499`: 56×56 frame,
  `.background(color, in: Circle())`, `.shadow(radius: 4)`.
- **Accessibility labels** — `ContentView.swift:498, 461, 474`:
  `.accessibilityLabel(...)`, `.accessibilityAddTraits(.isButton)`.
- **Launch seams for tests** — `--ui-testing` sets `enableActionButtons`,
  `--seed '<json>'` for deterministic write flows
  (`SingleThreadApp.swift:100–134`, `UITestingSeed.swift:27–47`).

**Patterns to avoid**:
- `.foregroundStyle(.secondary)` on gear (`ContentView.swift:101`) — too
  faint; replaced by scheme-adaptive glyph.
- Fixed `.tint(.green)` / `.tint(.orange)` on action buttons
  (`ContentView.swift:460, 473`) — replaced by scheme-adaptive glyph colors.
- Hardcoded `.background(.blue, in: Circle())` on mic (`ContentView.swift:496`)
  — replaced by scheme-adaptive plate.

## Design Decisions

1. **All controls get circular plates** — mic, gear, Complete, Skip, recording
   indicator, and creation feedback all sit on filled circles. Ensures every
   interactive element has a solid backdrop against any photo region, not just
   the bottom bar.

2. **Scheme-adaptive black/off-white plate fill** — dark mode: `Color.black`
   plate with white glyph; light mode: off-white plate (`Color(white: 0.92)`)
   with dark glyph. The off-white avoids the harshness of pure white against
   photos without sacrificing contrast. Follows the pattern established by
   `ReminderCardView.swift:66–69`.

3. **Recording keeps red fill with outline** — the red circle is a universally
   understood "live" signal. It retains red plate fill but gains the same
   white stroke outline as other controls in dark mode (dark stroke in light
   mode), so the circular boundary is visible even if red blends into a warm
   photo. Glyph stays white.

4. **Single solid stroke outline** — `.overlay { Circle().stroke(color,
   lineWidth: 2) }` on every plate. Simple, consistent, and implementable with
   standard SwiftUI modifiers. The stroke color is the glyph's contrast color:
   white in dark mode, dark in light mode.

5. **Unify all controls to 56×56** — mic, Complete, Skip, gear, and all
   transient indicators share the same frame size. A uniform hit target is
   better for accessibility; the current 44×44 Complete/Skip are slightly
   undersized for touch. The gear in the top-right corner at 56×56 is
   prominent but acceptable — it's a primary navigation control.

6. **Accessibility unchanged** — all existing labels, traits, and
   `contentShape` hit regions are preserved. No new a11y attributes needed
   since the plates are purely decorative backgrounds.

## What We're NOT Doing

- **Not changing watch app styling** — `WatchReminderView.swift` uses
  default borderless button styles appropriate for the watch form factor.
- **Not changing the photo layer** — opacity, fade, and compositing are
  outside scope.
- **Not adding new accessibility behaviors** — existing labels and traits
  are sufficient.
- **Not modifying dictation/recording logic** — purely visual change.
- **Not introducing new test infrastructure** — no screenshot diffing or
  color-assertion framework. Visual correctness verified manually.
- **Not touching macOS views** — the macOS `actionButtons` variant
  (`ContentView.swift:246–289`) is unchanged.
- **Not changing the `enableActionButtons` default** — stays `false`; the
  `--ui-testing` seam already sets it `true` for testing.

## Open Risks

- **Gear button at 56×56** may look oversized in the top-right corner
  compared to the current 44×44. Mitigation: the larger hit target improves
  usability; if it feels wrong in testing, drop gear back to 44×44 while
  keeping the plate treatment.
- **Stroke clipping** — a 2pt stroke on a 56×56 circle may clip at the frame
  boundary if the overlay isn't inset. Mitigation: test that the overlay
  renders fully; inset the plate fill slightly if needed.
- **Off-white perception** — `Color(white: 0.92)` may read differently on
  various device screens. Mitigation: tune the value after visual review.
- **Creation feedback timing** — the 1-second transient may flash with the
  new plate, which could be more noticeable than the current fill-only
  appearance. Acceptable; the feedback is meant to be seen.
- **Color scheme edge case** — if the user forces a scheme that mismatches
  the photo's dominant tones (e.g., dark mode with a very dark photo), the
  black plate may not contrast enough. The white stroke outline mitigates
  this — the plate boundary is always visible.
# Task

Change the Apple Watch Skip button's icon to an ellipsis (`…`, "More") so it
matches the iOS bottom-bar Skip button when that button opens the
three-action menu.

## Context

- Ticket VAR-1131: "Change the skip button icon to `…` to represent 'More'
  like on ios".
- On the watch, the button in `actionButtons` both (a) skips directly when the
  action-buttons toggle is off, and (b) opens the three-action menu
  (Skip / Reschedule / Delete) when `canShowActionMenu` is true. Today it
  always renders `Label(SharedStrings.skipAction, systemImage: "circle.slash")`
  with `accessibilityLabel(SharedStrings.skipReminderAccessibility)` and
  identifier `skipButton`.
- On iOS, `SingleThread/ContentView+ActionMenu.swift` already does the
  analogous thing: the icon is
  `showActionMenu ? SwipeRevealPanel.systemImage(for: .more) : "circle.slash"`,
  and its accessibility label swaps to `SharedStrings.moreAction` when the
  menu opens. `SwipeRevealPanel.systemImage(for: .more)` returns
  `"ellipsis.circle.fill"` (defined in `SingleThread/SwipeToActModifier.swift`,
  iOS target — not importable from the watch target, so use the SF Symbol name
  directly in the watch code).

## What to build

Mirror the iOS behavior in the watch Skip button
(`SingleThreadWatch/WatchReminderView.swift`, `actionButtons` property):

- When `canShowActionMenu` is true, render the "More" glyph
  (`ellipsis.circle.fill`) and swap the accessibility label to
  `SharedStrings.moreAction`.
- When it is false (direct skip), keep `circle.slash` and
  `SharedStrings.skipReminderAccessibility`.
- Keep the `.tint(.orange)`, `accessibilityIdentifier("skipButton")` and
  `.accessibilityAddTraits(.isButton)` unchanged.

If, after reading the ticket context, the intent reads as "always show the
More glyph on watch", state that reading in the PR rather than guessing
silently — but the iOS-mirroring (conditional) reading is the pattern the
ticket names.

## Why SMALL

Localized UI change in a single file/single target (`SingleThreadWatch`);
approach already exists on iOS to copy (A, B, E); no schema, no new subsystem,
no shared/convention code touched (C, D); tests needed are few and local (F).

## Key files

- `SingleThreadWatch/WatchReminderView.swift` — the `actionButtons` property
  (~line 127) holds the Complete + Skip buttons; this is the change site. Its
  `canShowActionMenu` gate (see `SingleThreadWatch/WatchReminderViewModel.swift`
  line ~66 comment and `SingleThreadCore/.../ActionMenuGate.swift`) decides
  menu-vs-direct.
- `SingleThread/ContentView+ActionMenu.swift` — the iOS pattern to mirror
  (`skipButton`, ~line 60), including the label swap to
  `SharedStrings.moreAction`.
- `SingleThreadCore/.../LocalizedString+Shared.swift` — source of
  `SharedStrings.moreAction`, `skipAction`, `skipReminderAccessibility`
  (already available to the watch target).
- `SingleThread/SwipeToActModifier.swift` — `SwipeRevealPanel.systemImage(for:)`,
  `.more` → `"ellipsis.circle.fill"` (iOS-only; reference for the symbol name).
- Watch unit/UI tests under `SingleThreadWatchTests/` and
  `SingleThreadWatchUITests/` — check whether any assert on `skipButton`'s
  label/icon before changing it.

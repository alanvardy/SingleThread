# Task

Change the reminder-card swipe behaviour and its on-screen guide (iOS only).

**New gesture mapping:**
- **Swipe right → Complete** (keep the existing right-swipe behaviour).
- **Swipe left → Skip** (today a left swipe reveals the "more" action panel; skip
  moves here).
- **Swipe up → open a menu with the other options** (the actions currently
  reached via the "more"/left-swipe reveal panel — i.e. the existing action
  menu — move behind the new up-swipe).

**Guide change:** the swipe guide/prompt currently renders as a card underneath
the main card. Replace it with **directional arrows positioned left, right and
above the main card**, each labelled with the action word for that direction —
for example:

```
               ↑
        Swipe up for more

->                        <-
Swipe to Complete   Swipe to Skip
```

(The exact copy/layout is the implementer's call within that structure; the
"→ / Swipe to Complete" example in the ticket is the reference shape.)

Why: the product wants the three most common per-card actions reachable by
direct gestures (complete right, skip left, everything else up) and a guide
that teaches those directions in place rather than via a standalone prompt card.

This is a UI/interaction change to existing code — no data model, storage,
API, or entitlement changes. The watch app does not use the card swipe, so the
work is confined to the iOS app plus the shared pure-gesture rule in
`SingleThreadCore`.

## Why MEDIUM
Breadth triggers **MULTI_MODULE** and **BROAD_TEST_SURFACE**: the change spans
`SingleThreadCore/SwipeGesture.swift`, several `SingleThread/` views/views +
the action menu, the string catalog, and the existing swipe/gesture/prompt test
suites (well over ~5 files). M1–M2 hold: the approach is already established by
the current swipe-reveal, action-menu and prompt patterns (add an up case /
relocate the menu, no new technology), with no schema/migration, no new
subsystem or integration, no shared/config/persistence convention risk, and no
human design trade-off beyond the guide layout the ticket already specifies.

## Key files (from light recon)
- `SingleThreadCore/Sources/SingleThreadCore/SwipeGesture.swift` — pure
  direction/threshold rule; `SwipeGestureOutcome { complete, more, none }` and
  `outcome(for:threshold:)` / `revealedOutcome(forOffset:)`. Currently
  right → `.complete`, left → `.more`, vertical-dominant drags ignored (so List
  scrolling wins).
- `SingleThread/SwipeToActModifier.swift` — live drag reveal + release firing.
- `SingleThread/ContentView+ActionMenu.swift` — the existing action menu
  ("more") the up-swipe should open.
- `SingleThread/ReminderCardView.swift` and `SingleThread/CardPlate.swift` —
  card layout and the swipe-prompt plate that becomes the directional-arrow
  guide (see the comment on `CardPlate.swift` naming "the swipe-prompt box").
- `SingleThread/ContentView.swift` and `SingleThread/ContentView+Settings.swift`
  — `showSwipePrompt` binding and guide placement.
- `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift` and
  `SingleThread/Resources/Localizable.xcstrings` — swipe guide/prompt strings.
- Tests to extend: `SingleThreadTests/SwipeGestureDecisionTests.swift`,
  `SingleThreadTests/SwipeToActModifierTests.swift`,
  `SingleThreadTests/SwipePromptTests.swift` (plus any `CardPlate` /
  `ActionButton` / `SettingsView` suites the change disturbs).

Note for planning: adding an up-swipe to a card inside a scrolling `List`
raises a vertical-gesture-vs-scroll interaction question (the current rule
deliberately yields vertical drags to the List); resolve it with the existing
`SwipeGesture` pattern rather than a new gesture stack.

# Task

Refine the swipe hint UI in the SingleThread iOS app (Linear VAR-1135). Three
changes:

1. **"More" should be yellow** — both the swipe reveal guide (the tinted hint
   plate shown while dragging up, in `SwipeToActModifier`/`CardPlate`) and the
   textual hint, currently sharing the skip colour. Introduce/use a distinct
   yellow "more" hint colour.
2. **Rename the dismiss button** — the swipe-hint prompt's dismiss button text
   should read **"Dismiss hints"** (currently "Dismiss"), in
   `ReminderCardView`. Keep it accessible (update the accessibility label /
   identifier expectations accordingly).
3. **Add black panels behind the hints** — one black panel behind the "More"
   hint (above), and one black panel behind all the remaining hints plus the
   dismiss button (below). The two panels must have a visible gap so they do
   not touch each other. Ensure contrast/accessibility and Dynamic Type still
   work.

The existing swipe-hint prompt is gated by the `showSwipePrompt` preference and
has unit coverage (`SingleThreadTests/SwipePromptTests.swift`,
`SwipeToActModifierTests.swift`, `CardPlateModifierTests.swift`). Update and add
tests for the new colour, the new button label, and the panel layout constants,
following existing patterns.

# Why SMALL

Localized UI change across an existing pattern: a handful of files in the iOS
app (`ReminderCardView.swift`, `SwipeToActModifier.swift`, `CardPlate.swift`)
plus their existing tests. No schema/migration, no new subsystem/integration,
no shared/convention risk, and no design trade-off requiring sign-off.

# Key files (recon)

- `SingleThread/ReminderCardView.swift` — the dismissible swipe-instruction
  prompt; `dismissButton` around line 280 currently renders `Text("Dismiss")`
  with accessibility label "Dismiss swipe prompt" and identifier
  `swipePromptDismissButton`.
- `SingleThread/SwipeToActModifier.swift` — `SwipeRevealPanel`/hint plates;
  `.more` currently uses `CardPlate.skipHintColor` (line ~104) and a bottom
  edge icon `ellipsis.circle.fill`.
- `SingleThread/CardPlate.swift` — hint colour helpers
  (`completeHintColor`, `skipHintColor`, `refreshHintColor`); add a yellow
  "more" colour here.
- `SingleThreadTests/SwipePromptTests.swift` — asserts the prompt description
  contains "Dismiss" and the dismiss button accessibility label.
- `SingleThreadTests/SwipeToActModifierTests.swift` and
  `SingleThreadTests/CardPlateModifierTests.swift` — existing coverage for the
  reveal panel and hint colours; extend for the yellow More tint.
- `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift` —
  shared strings (`moreAction`); check whether the new "Dismiss hints" label
  should be localized there.

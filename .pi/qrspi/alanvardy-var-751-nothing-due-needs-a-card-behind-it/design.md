# Design Discussion

## Current State

The iOS app renders reminder-list content through three branches gated by
`ReminderStore` properties (`ContentView.swift:347-453`):

| Branch | Gating condition | Rendered view | Background |
|--------|-----------------|---------------|------------|
| All Done | `store.allSkipped` (`:352`) | `ContentUnavailableView` ("All Done" / `checkmark.circle`) | None — text over photo/`systemBackground` |
| Empty | `store.reminders.isEmpty` (`:365`) | `ContentUnavailableView` ("Nothing due" or "No Reminders") | None — text over photo/`systemBackground` |
| Populated | else (`:383`) | `ReminderCardView` inside `List` row | `plateFill` card plate (`ReminderCardView.swift:47-54`) |

**The bug**: the two empty branches render `ContentUnavailableView` text directly
over the background photo layer (`ContentView.swift:68-72`) with no plate. White
text on a light photo is unreadable; on dark mode the `systemBackground` provides
incidental contrast but photos break it in both schemes.

The populated card's plate is an adaptive off-white/black `RoundedRectangle(cornerRadius: 10)`
applied via a 12pt padding pair to fit inside the `List` row without changing
row metrics (`ReminderCardView.swift:47-54`). This pattern is duplicated
inline (also at `:186-192` for the prompt box). No shared plate abstraction
exists; `ControlPlateModifier` is a different shape entirely (circle, 56×56).

The watch (`WatchReminderView.swift:77-166`) and widget (`NextThingWidget.swift:135-152`)
have no per-state plates. The watch renders plain text on its system background
(no photo layer, so contrast is adequate). The widget uses a single
`.containerBackground(.fill.tertiary)` for all states (`:119`).

Testing seams are decision-constants (`plateFill`, `promptBoxFill`, `rowChromeBackground`)
asserted in unit tests, plus `ContentUnavailableView` copy assertions
(`SingleThreadTests.swift:33-53`). No UI test covers the `hasHidden == true`
"Nothing due" path (Open Areas, research.md).

## Desired End State

1. **iOS empty states have a plate** — the "Nothing due" and "All Done"
   `ContentUnavailableView` views render on a material plate so their text is
   readable over any background photo in light or dark mode.
2. **"Nothing due" has UI test coverage** — the currently untested
   `hasHidden == true` empty path gets a UI test via the `--seed` seam.
3. **No changes to watch or widget** — the watch has no background photo layer
   (contrast adequate), and the widget already has `.fill.tertiary`.
4. **A follow-up Linear ticket exists** for extracting shared plate styling
   (deferred — this is a narrow fix, not a refactoring pass).

### Verification

- Unit test: decision-constant asserting the plate's corner radius matches the
  card's (`10pt`) and the material is `.regularMaterial`.
- UI test: `--seed` a store with all visible reminders skipped → assert "Nothing
  due" text is present and the `ContentUnavailableView` renders.
- Manual: screenshot the "Nothing due" and "All Done" states over a photo
  background in light and dark mode (matching existing
  `docs/SimulatorManualVerification.md` slots).

## Patterns to Follow

**Follow these:**

- **Decision-constant seams for untestable visuals** — `plateFill(for:)` pattern
  (`ReminderCardView.swift:61-64`, tested at
  `BackgroundCardTests.swift:69-78`). Extract a static property for the empty-state
  plate (e.g. `emptyStateCornerRadius` or `emptyStatePlateMaterial`) and assert it.
- **`ContentUnavailableView` for empty states** — already used in iOS empty/all-done
  branches (`ContentView.swift:353-357, 366-370`); keep it, don't replace with
  custom views.
- **`--seed` UI test seam** — `UITestingSeed.swift:29-35`, backed by
  `InMemoryEventStore`. Use it to seed a store with `hasHidden: true` and no
  visible reminders for the new "Nothing due" UI test.
- **SwiftUI `@Environment(\.colorScheme)` for adaptive styling** — the card
  resolves scheme at render time (`ReminderCardView.swift:67-68` →
  `:52`). Material adapts automatically; no explicit scheme handling needed.
- **Per-view inline plate styling** — current convention: the card plate is
  written twice in `ReminderCardView.swift` (`:49-54`, `:186-192`) rather than
  extracted. Keep the empty-state plate inline (deferred extraction → [VAR-752](https://linear.app/vardy/issue/VAR-752)).

**Do NOT follow these:**

- **Copying the card's padding trick** — the card uses `.padding(12)` →
  background → `.padding(-12)` to fit inside `List` row metrics
  (`ReminderCardView.swift:47-54`). The empty branches are in `ScrollView`, not
  `List` — no row constraints apply. A simple `.background` with padding is
  sufficient; the negative-padding restore is unnecessary and confusing.
- **Duplicating `plateFill` colors for empty states** — the card's off-white/black
  plate signals "here's your content." Empty states should signal "nothing here"
  with a lighter treatment. Using the same fill would blur the distinction.

## Design Decisions

1. **Material plate for iOS empty states**: The "Nothing due" and "All Done"
   `ContentUnavailableView` views get `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))`.
   Material adapts to light/dark automatically, is lighter than the card plate
   (visually distinct), and requires no color-constant extraction. Corner radius
   matches the card for visual rhythm.

2. **No changes to watch**: The watch has no background photo layer and
   already has adequate contrast for its plain-text empty states
   (`WatchReminderView.swift:146-166`). Adding plates would be a visual redesign
   for a surface with no contrast bug, and the watch's populated card also lacks
   a plate — plates would be inconsistent either way.

3. **No changes to widget**: The widget already wraps all states in
   `.containerBackground(.fill.tertiary, for: .widget)` (`NextThingWidget.swift:119`).
   Adding inner per-state plates would waste widget space with no contrast benefit.

4. **Per-view plate styling (no extraction now)**: The empty-state plate is added
   inline in `ContentView.swift`'s two empty branches. Plate extraction is a
   separate refactoring concern — a follow-up Linear subtask ([VAR-752](https://linear.app/vardy/issue/VAR-752)) covers it.
   This keeps the fix minimal and avoids touching the populated card path.

5. **Testing: decision-constant + UI test**: A static corner-radius constant
   (shared with the card) is asserted in `SingleThreadTests/`. A new UI test in
   `SingleThreadUITests/` seeds a store with all reminders skipped and asserts the
   "Nothing due" `ContentUnavailableView` renders — closing the test gap flagged
   in the research.

## What We're NOT Doing

- **No watch or widget plate changes** — contrast bug is iOS-only.
- **No `ControlPlateModifier` changes** — it's a different control surface (circle
  action buttons), not relevant to content plates.
- **No extraction of a shared card-plate modifier** — deferred to a follow-up
  Linear subtask. The fix adds plates inline.
- **No pixel-snapshot or contrast-audit tests** — the existing test philosophy
  (decision constants + UI element presence) is sufficient.
- **No changes to the populated card or its plate** — the card already works.
- **No copy changes** — "Nothing due", "All Done", etc. stay as-is.

## Open Risks

- **Material over photo**: `.regularMaterial` may look washed out over very bright
  photos. If visual review shows poor contrast, fall back to a semi-transparent
  version of `plateFill` with reduced opacity (e.g. `.opacity(0.85)`).
- **`ContentUnavailableView` + material interaction**: `ContentUnavailableView`
  has its own internal padding and layout. The `.background` modifier should work
  fine since it wraps the view's frame, but verify the plate doesn't clip or add
  unexpected insets.
- **ScrollView + material**: The empty branches are inside `ScrollView`
  (`ContentView.swift:353, 366`). Material renders correctly in scrollable
  contexts, but verify it doesn't cause visual artifacts during overscroll/bounce.
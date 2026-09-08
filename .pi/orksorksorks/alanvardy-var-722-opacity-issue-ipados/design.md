# Design Discussion — iPadOS reminder container opacity (VAR-722)

## Current State

The reminder card renders in a single-reminder `List` inside a `ZStack`
(`ContentView.swift:296-359`). Its container/background is built from three
layers that must all be transparent for the photo (or the system background)
to show through:

1. **Root stack** — `Color.systemBackground` base, then `BackgroundPhotoLayer`
   (`ContentView.swift:51-62`). This layer is fine and untouched.
2. **List scroll content** — already hidden unconditionally via
   `.scrollContentBackground(.hidden)` (`ContentView.swift:358`), added in
   commit `0c9e8b8` with a comment documenting the iPadOS divergence
   (`ContentView.swift:357-358`).
3. **Row chrome** — *conditional*: `.listRowBackground(viewModel.backgroundDisplayed
   ? Color.clear : nil)` (`ContentView.swift:308`). When no photo is shown
   (`backgroundDisplayed == false`, `ContentViewModel.swift:51-54`), the row
   falls back to the system default, which is **opaque on iPadOS** and
   transparent on iPhone.

The card's own plate is a photo-only feature: it draws a black/white
`RoundedRectangle` behind the text only when `showsOverPhoto` is true
(`ReminderCardView.swift:86-95`, gate at `:88-93`, fill at `:90-92`). It is
orthogonal to the bug and must not change.

**Root cause:** the transparent-vs-opaque split originates in the *default*
`listRowBackground` (nil) and in the `UICollectionView`-backed `List`'s
scroll-content layer, which is known to stay opaque on iPadOS 18 even after
`.scrollContentBackground(.hidden)`. The current code relies on one modifier
instead of guaranteeing transparency across every layer.

The empty and all-skipped states already use `ScrollView`, not `List`
(`ContentView.swift:281-293`), and are unaffected.

## Desired End State

The reminder card's container renders identically on iPad and iPhone in both
light and dark modes: the row chrome and scroll content are *always*
transparent, so the photo (when shown) or `Color.systemBackground` (when not)
shows through. The card plate continues to appear only when a photo is
displayed (`backgroundDisplayed == true`), and its color still follows
`colorScheme` (`ReminderCardView.swift:90-92`).

**Verification of correctness:**
- Unit: the extracted row-background seam reports "always clear" for both
  photo states (regression guard, see Decision 4).
- Manual: `make simverify SIM='platform=iOS Simulator,name=iPad (A16)'` plus a
  side-by-side iPhone/iPad screenshot in both light and dark modes, with the
  background toggle on and off. Documented in
  `docs/SimulatorManualVerification.md` (Decision 3).

## Patterns to Follow

- **Single source of truth for gates** — `ContentViewModel.backgroundDisplayed`
  (`ContentViewModel.swift:51-54`) already centralizes the "photo on screen"
  decision and feeds both the card and the row. The fix keeps this pattern: the
  row no longer needs the gate, but `showsOverPhoto` still reads it.
- **Testable computed seam** — the existing `BackgroundCardTests`
  (`BackgroundCardTests.swift:44-84`) assert gate decisions directly because
  the rendered look is unassertable via `_ConditionalContent`
  (`BackgroundCardTests.swift:38-41`). Follow the same rule: extract the new
  row decision into a computed property and test the *decision*, not the paint.
- **No device branching** — the codebase has zero `UIDevice` /
  `userInterfaceIdiom` / size-class checks (verified). The existing iPad fix
  comment (`ContentView.swift:357-358`) expresses intent as an *unconditional*
  modifier. Match that.
- **Manual-first visual verification** — `make simverify` (`Makefile:73-74`)
  already drives simulator appearance checks; extend its documented usage, do
  not invent a new harness.

**Patterns NOT to follow:**
- **UIKit introspection** — no `UIViewRepresentable` or `.appearance()`
  anywhere in the codebase (verified). Avoid introducing a collection-view
  background bridge; it is a heavier hammer than this bug needs.
- **`.background` before `.scrollContentBackground`** — modifier order matters
  on iPadOS 18; the clear background must come *after* the scroll-content hide.

## Design Decisions

1. **Clear every background layer explicitly**: replace the ternary at
   `ContentView.swift:308` with a constant `.listRowBackground(Color.clear)`,
   keep `.scrollContentBackground(.hidden)` (`:358`), and add
   `.background(Color.clear)` on the `List` after it. — Guarantees transparency
   regardless of which layer iPadOS renders as opaque; no visual change on
   iPhone (plain-list rows are already transparent when no photo).
2. **Unconditional (no idiom branching)**: apply the fix on all devices. —
   Matches the existing comment's intent and the codebase's no-branching
   convention; the change is a no-op where the default is already transparent.
3. **Manual + screenshot verification**: verify via
   `make simverify SIM='platform=iOS Simulator,name=iPad (A16)'` with
   documented light/dark × toggle-on/off screenshots, recorded in
   `docs/SimulatorManualVerification.md`. — The visual is headless-unassertable
   (`BackgroundCardTests.swift:38-41`); a UI test can only assert presence, not
   opacity, so it adds CI cost for low signal.
4. **Extract a testable row-background seam**: add a computed property (e.g.
   `ContentViewModel` returns a Bool "row chrome is always clear") and a unit
   test asserting it is true with and without a photo. — Provides a regression
   guard for the exact decision the fix changes, since the paint itself cannot
   be asserted.
5. **iOS/iPadOS scope only, plate unchanged**: no macOS `List` rendering
   changes; the card plate remains photo-only (still gated by `showsOverPhoto`,
   `ReminderCardView.swift:88-93`). — macOS is out of scope per the task and is
   non-functional; the plate's photo-only behavior is the intended design.

## What We're NOT Doing

- Not changing the card plate itself: no stroke, no always-on plate on iPad,
  no palette change. `showsOverPhoto` semantics are untouched.
- Not introducing `UIViewRepresentable` / `UICollectionView.appearance()`
  introspection.
- Not replacing `List` with `ScrollView` — that would lose swipe actions
  (Complete/Skip) that only `List` supports.
- Not branching on `userInterfaceIdiom` / size class.
- Not touching macOS rendering.
- Not adding a UI test that asserts color/opacity (impossible headlessly).
- Not modifying `BackgroundPhotoLayer`, `Color.systemBackground`, or the
  appearance override path (`AppDelegate.swift:14-24`) — they are correct.

## Open Risks

- **iPadOS 18 layer quirks**: if the opaque layer is the hosting controller
  rather than scroll content, the `.background(Color.clear)` on the `List` may
  be insufficient and a revisit to `ScrollView` (or, as a last resort,
  introspection) becomes necessary. The manual iPad screenshot is the guard
  against this.
- **Simulator vs device**: iPadOS list backgrounds have rendered differently on
  simulator vs hardware in the past; the screenshot check is simulator-only.
  Confirm on a physical iPad if available.
- **Row vs card contrast when no photo**: with the row now always clear over
  `systemBackground`, text contrast is unchanged (system dark/light), but this
  is the first time the "transparent row over system background" path is
  guaranteed on iPad — worth a visual sanity check in dark mode.
- **Test seam naming**: the extracted property must stay narrowly about the row
  background so it does not drift into an untested "view state" abstraction.

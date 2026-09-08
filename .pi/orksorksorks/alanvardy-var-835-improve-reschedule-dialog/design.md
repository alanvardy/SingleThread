# Design Discussion — Reschedule Dialog Polish

## Current State

The reminder reschedule dialog exists as a shared, reusable SwiftUI view on iOS:

- **`RescheduleSheet`** (`SingleThread/RescheduleSheet.swift:8`): a plain view with inputs
  `reminder: EKReminder?`, `onReschedule: (DateComponents) async -> Bool`, `onCancel: () -> Void`,
  `nudgeMessage: String?` (:11–14). Callers supply their own `NavigationStack` + Cancel toolbar; the
  view carries no chrome of its own (doc :4–7).
- **Layout** (:16–50): an outer `VStack(alignment: .leading, spacing: 16)` containing the optional
  nudge message, a labeled `DatePicker("Reschedule to", selection: $date, displayedComponents: …)`
  (:24–29), and the confirm button in `HStack { Spacer(); Button { … } }` — the `Spacer()` pushes
  it to the right edge (:31–45). The whole thing is `.padding().frame(maxWidth: .infinity,
  alignment: .leading)` (:48–49). Result: label above picker (or full-width picker), all left-aligned,
  confirm button shoved top-right — the "clunky" look the ticket describes.
- **Confirm button** (:31–45): `Button { Label("Reschedule", systemImage: "calendar.badge.plus") }`
  with **no explicit `buttonStyle`** — the platform-default chrome. The app's other primary/confirm
  buttons use `.borderedProminent` instead (`ReminderCardView.swift:164`, `PurchaseSettingsView.swift:113`).
- **Tailoring helpers** preserve the due-time behavior we must not regress: `hasDueTime` (:54–57),
  `displayedComponents` (`[.date, .hourAndMinute]` vs `[.date]`, :60–62), `dateComponentsMask`
  (:65–67), `@State date` defaulting to tomorrow (:72).

Two callers, plus an implicit third platform consumer:

1. **Nudge flow** (`SingleThread/ContentView+iOS.swift:59–80`, `#if os(iOS)`): wraps the sheet in a
   `NavigationStack` + `VStack`, supplies `nudgeMessage:`, Cancel via `.cancellationAction` toolbar
   (:75–78); presented with detent `.height(420)` (`ContentView.swift:300–302`).
2. **Action-menu flow** (`SingleThread/ContentView+ActionMenu.swift:179–197`): same shape,
   `nudgeMessage: nil`, Cancel toolbar (:191–195); presented with detent `.height(320)`
   (`ContentView.swift:295–297`). **This presentation line is unconditional iOS+macOS**, so the
   macOS app also renders `RescheduleSheet`.
3. **watchOS** (`SingleThreadWatch/WatchReminderView.swift:290–316`) is a fully independent,
   date-only implementation — **out of scope** (Decision 1).

**Test coverage today**: only the three static helpers are unit-tested
(`SingleThreadTests/RescheduleSheetTests.swift:16–47`). View structure is pinned by a single
description-string assertion `rescheduleSheetTextButtonsKeepNativeChrome`
(`SingleThreadTests/SingleThreadTests.swift:142–151`): builds a `ContentView`, then
`String(describing: view.actionMenuRescheduleSheet)` must contain `"Cancel"` and **not**
`"SingleThreadButtonModifier"`. No test references the `rescheduleDatePicker`/`rescheduleConfirmButton`
identifiers, and no test constructs the nudge-sheet wrapper.

## Desired End State

iOS-only changes to `RescheduleSheet.swift`:

1. **Label + picker side by side, centered** — a compact, centered row placing the literal text
   "Reschedule to" next to a label-less date picker (Decision 2).
2. **Confirm button restyled + centered** — `.borderedProminent`, horizontally centered, keeping the
   `calendar.badge.plus` icon + "Reschedule" text (Decision 3).
3. **Behavior unchanged** — every input, closure, the due-time tailoring, and both callers'
   presentation/detents still work identically; only layout + button styling change.

**How we verify it's correct**:

- Existing helper tests (`RescheduleSheetTests.swift`) and both storage/sync suites stay green
  (no logic touched).
- New view-structure tests (Decision 4) pin the new layout and styling.
- The existing chrome test still passes (or is updated deliberately — Decision 4).
- Manual/simulator check: nudge sheet and action-menu sheet both render label+picker centered and the
  prominent confirm button centered, on iPhone; macOS action-menu sheet renders sanely too (it shares
  the view — see Risks).

## Patterns to Follow

- **`.borderedProminent` = primary/confirm** — `ReminderCardView.swift:164` (nudge banner),
  `PurchaseSettingsView.swift:113`. This is the "app's other buttons" style the ticket names.
- **`Label(title, systemImage:)` icon+title button text** — `ContentView.swift:440,457,465`. Keep the
  existing `Label("Reschedule", systemImage: "calendar.badge.plus")` (:38); that's already on-pattern.
- **Centering** — whole-view centering via `.frame(maxWidth: .infinity)` emptied of a `Spacer()`
  edge-push; the codebase's centered empty-states use `.frame(maxWidth: .infinity, minHeight: …,
  alignment: .center)` (`ContentView.swift:381,394`). A center-aligned `VStack`/`HStack` with
  `Spacer()`-free centering is the right idiom (the current `HStack { Spacer(); Button }` at
  `RescheduleSheet.swift:37–46` is the anti-pattern being removed).
- **View-structure test pattern** — `String(describing:)` + `.contains()` is the established way to
  pin SwiftUI view structure cheaply (`SingleThreadButtonModifierTests.swift:14`,
  `MacOSActionButtonChromeTests.swift:14–39`, `SettingsCaptionTests.swift:10`, `SwipePromptTests.swift:12`).
  Use it for the new assertions (Decision 4).

**Patterns NOT to follow**:

- **`singleThreadButton()` / `.borderless`** (`SingleThread/SingleThreadButtonModifier.swift:12,20–23`)
  is for icon-only controls, not a labeled confirm button — and the existing chrome test explicitly
  pins that `RescheduleSheet` must NOT use it (`SingleThreadTests.swift:148–150`).
- **watchOS conventions do not apply** — watch's plain-text buttons (`WatchReminderView.swift:212–215`)
  and tint-only emphasis (`:137, :152`) exist because watch has no prominent style; do not emulate
  them on iOS.
- **leave-label-above-picker** — the current labeled-`DatePicker` full-width layout is exactly the
  thing being replaced.

## Design Decisions

1. **Scope: iOS only.** The ticket's clunky rendering described is `RescheduleSheet`; watch's
   date-only sheet is untouched. macOS is transitively covered (same shared view) but receives no
   bespoke work.
2. **"Next to each other and centered" via an explicit `HStack`**: replace the labeled
   `DatePicker("Reschedule to", …)` with `HStack { Text("Reschedule to"); DatePicker(selection:,
   displayedComponents:) }`, constrained and centered via `.frame(maxWidth: .infinity)`. This is the
   only approach that guarantees the pair sits side-by-side and centered regardless of the
   platform-opaque `DatePicker` rendering (research Q5). `.labelsHidden()`/label-less overload
   prevents a duplicated label.
3. **Confirm button = `.borderedProminent`, centered.** Change the `HStack { Spacer(); Button }` to a
   centered container; keep `Label("Reschedule", systemImage: "calendar.badge.plus")`. `.borderedProminent`
   does not reference `SingleThreadButtonModifier`, so the existing chrome assertion stays semantically
   true.
4. **Tests: add view-structure tests on iOS, update existing chrome test deliberately.** New
   `String(describing:)` assertions pin (a) the label+picker pair is side-by-side and (b) the confirm
   button uses `.borderedProminent` (or its resulting structure) and is centered. If the new layout
   changes what `actionMenuRescheduleSheet` stringifies to, update
   `rescheduleSheetTextButtonsKeepNativeChrome` (`SingleThreadTests.swift:142–151`) only to reflect the
   still-true invariant (`!contains("SingleThreadButtonModifier")`, `contains("Cancel")`), not to erase it.
5. **No logic/data-flow change.** `onReschedule`, `dateComponentsMask`, `displayedComponents`,
   `hasDueTime`, and the tomorrow default are untouched. Both callers (`ContentView+iOS.swift`,
   `ContentView+ActionMenu.swift`) and their detent heights are left as-is unless the layout change
   makes a detent visibly clip (then bump the detent in the same commit, noted in the plan).

## What We're NOT Doing

- **watchOS** — no changes to `SingleThreadWatch/` (view, VM, sync). Scope is iOS `RescheduleSheet` only.
- **No string centralization** — "Reschedule to"/"Reschedule" stay as-is; not moving them to
  `SharedStrings` (that's a separate cleanup, and watch is out of scope).
- **No UI tests** — the change is pure layout/style, pinnable by cheap view-structure unit tests;
  adding a slow `XCTest` UI flow for a restyle is not justified (AGENTS.md UI-test policy).
- **No behavior changes** to reschedule semantics, skip-count reset, or nudge identifier clearing.
- **No new files/targets** — only edits to `RescheduleSheet.swift` + test files; no pbxproj or
  `scripts/test.sh` changes needed (auto-discovered files; suites already registered).
- **No detent redesign** — unless a visible clip forces it (Decision 5).

## Open Risks

- **`DatePicker` label-less rendering is platform-opaque** (research Q5 — compiled `body`, no source).
  The exact look of a label-less picker after centering must be confirmed on the iPhone simulator (and
  macOS) during implementation; a fallback is `.datePickerStyle(.compact)` if the default collapses the
  value awkwardly.
- **macOS is a silent consumer** (`ContentView.swift:295–297` unconditional) of the action-menu path
  and has its own chrome tests (`MacOSActionButtonChromeTests.swift:14–39`). The centered HStack +
  `.borderedProminent` change must not break macOS chrome expectations — verify macOS builds/tests.
- **Detent heights** (`.height(320)` action menu vs `.height(420)` nudge, `ContentView.swift:295–302`)
  were sized for the old layout; the new centered row + button may need a nudged detent if content
  clips (Decision 5 bounds this).
- **`String(describing:)` brittleness** — assertions on stringified SwiftUI structure can be sensitive
  to SDK-version rendering; keep assertions to stable tokens already proven in sibling suites
  (`SingleThreadButtonModifierTests.swift:14`, `MacOSActionButtonChromeTests.swift:14–39`).
- **Accessibility** — the label-less picker must not lose the a11y identifier/verbal label
  ("Reschedule to"); keep `accessibilityIdentifier("rescheduleDatePicker")` and ensure the text label
  still associates with the picker for VoiceOver.
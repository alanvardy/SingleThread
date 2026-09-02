# Design Discussion

## Current State

The app target draws four distinct "plate" surfaces, three of which are
rounded-rectangle content plates that all share the same corner radius and are
driven by styling constants that live on `ReminderCardView`:

- **Card text plate** — `SingleThread/ReminderCardView.swift:43–61`. A
  scheme-adaptive `RoundedRectangle(cornerRadius: Self.plateCornerRadius)`
  filled with `Self.plateFill(for: colorScheme)` behind `.padding(12)` +
  `.padding(-12)` (a net-zero geometry restore so `List` row metrics don't
  change; comment at :50–54).
- **Swipe-prompt box** — `SingleThread/ReminderCardView.swift:158–206`. The
  same radius-10 rounded rect filled with the fixed dark-grey `promptBoxFill`,
  behind `.frame(maxWidth: .infinity)` + `.padding(12)` with **no** restore
  (:200–201).
- **Empty-state card** — `SingleThread/ContentView.swift:576–618`
  (`EmptyStateCard`). A `.padding(20)` plate that reaches into
  `ReminderCardView.plateCornerRadius` and `ReminderCardView.plateFill(for:)`
  by qualified reference (:601–602). This is a one-way back-reference:
  `ReminderCardView` never imports `ContentView`.
- **Control plates** — `SingleThread/ControlPlateModifier.swift:12–39`. A
  separate 56×56 *circular* plate vocabulary (adaptive fill, glyph, shadow)
  used at 7 iOS call sites. Not a rounded rectangle; out of scope for this
  extraction.

The decision seams are three `static` members on `ReminderCardView`
(`// MARK: Internal`, :28–69):
`promptBoxFill` (:35), `plateCornerRadius = 10` (:41), and
`plateFill(for:)` (:67–69). Their doc comments (:30–34, :37–40, :63–66)
explicitly say they exist so tests can assert the paint/radius decision
headlessly.

**Duplication being removed:** the `RoundedRectangle(cornerRadius:)` +
adaptive-fill + padding chain is spelled out twice inside
`ReminderCardView.swift` (:55–60 and :200–204), and the empty state reuses the
constants but re-spells the chain a third time (`ContentView.swift:599–603`).

**Existing shared-styling infrastructure** (the conventions to match):
- `ControlPlateModifier` + `extension View { func controlPlate(...) }` —
  `SingleThread/ControlPlateModifier.swift:12` and :42–53. Modifier struct with
  `///` + `- Parameters:` docs, `@Environment(\.colorScheme)`-driven
  `colorScheme == .dark` ternary (:21), private constants (:33–36), and a
  lowerCamelCase View helper with nil-means-auto defaults (:51).
- `TextSizeModifier` — `SingleThread/TextSizeModifier.swift:8–15`. A file-per-
  type modifier, though it lacks a View helper (call sites use
  `.modifier(...)` directly).
- `Color+CrossPlatform` — `SingleThread/Color+CrossPlatform.swift:9–19`.
  Label-form color initializers (`Color(nsColor:)`, `Color(uiColor:)`,
  `Color(white:)`, `Color(red:green:blue:)`); `#if os(macOS) … #else` guards.

## Desired End State

A single shared `CardPlateModifier: ViewModifier` plus a `View.cardPlate(...)`
helper, owned by a new `CardPlate` type that also owns the three decision
constants, so the plate pattern is defined once and reused at all three rounded-
rectangle sites with no back-reference from `ContentView` into
`ReminderCardView`.

**Verify it's correct:**
1. The three call sites compile and render unchanged: card text plate
   (`ReminderCardView.swift:43–61`), swipe prompt (:200–204), empty state
   (`ContentView.swift:599–603`).
2. The existing decision-constant tests still pass, now asserted against the
   new `CardPlate` type instead of `ReminderCardView`:
   - `BackgroundCardTests.swift:69–71` (`plateFill` light off-white),
     :76–77 (dark black), :85–86 (corner radius 10).
   - `SwipePromptTests.swift:34–35` (`promptBoxFill` dark grey),
     :15–18 (`RoundedRectangle` presence in the card body snapshot).
3. `./scripts/test.sh` is green — format, lint, build, Periphery, unit + UI
   tests. Periphery must not flag the moved constants as dead.
4. No new warnings (project-wide `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`).

## Patterns to Follow

- **Modifier + View-helper pair**, mirroring `ControlPlateModifier` exactly:
  struct `CardPlateModifier: ViewModifier` with `func body(content: Content) ->
  some View`, `@Environment(\.colorScheme)` read, and a file-level
  `extension View { func cardPlate(...) -> some View }` returning
  `modifier(CardPlateModifier(...))` (`ControlPlateModifier.swift:12, :42–53`).
- **File per type**: `SingleThread/CardPlate.swift` holding `CardPlate`
  (constants + fill functions) and `CardPlateModifier` + the View helper, in
  the same style as `ControlPlateModifier.swift`. (A separate
  `CardPlateModifier.swift` file is acceptable if preferred; the important
  thing is one type = one concern, matching existing layout.)
- **`///` docs + `- Parameters:`** on every declaration; `// MARK:` sections
  (`Internal` / `Private`) as in `ControlPlateModifier.swift:6–36`.
- **Label-form color spellings**: keep `Color(red:green:blue:)` for
  `plateFill`/`promptBoxFill` and `Color.black` / `.white` shorthands —
  never `.init(red:...)` (convention from `ReminderCardView.swift:35, :68`,
  `ControlPlateModifier.swift:21–22`).
- **`colorScheme == .dark ? ... : ...` ternary** over
  `@Environment(\.colorScheme)` for adaptation (`ReminderCardView.swift:68`,
  `ControlPlateModifier.swift:21`).
- **Test-assertable internal constants**: keep the moved constants `static let`
  / `static func` internal (not `private`) so tests can assert them
  (`ReminderCardView.swift:30–34, :37–40, :63–66`). Periphery tolerates
  internal members reachable from tests.
- **Geometry-restore technique**: `.padding(12)` before `.background`, then
  `.padding(-12)` after, documented with the "grows the view … then restores"
  comment (`ReminderCardView.swift:50–54, :55, :60`).

**Patterns NOT to follow:**
- Do **not** copy `TextSizeModifier`'s helper-less style (`.modifier(...)` at
  call sites) — the `controlPlate(...)` helper style is the better precedent
  for a styling modifier with parameters.
- Do **not** unify the two adaptive-fill vocabularies. `plateFill`'s light
  value (`Color(red: 0.96, 0.95, 0.94)`) and `ControlPlateModifier`'s light
  value (`Color(white: 0.92)`) intentionally differ; changing either is a
  visual decision outside this ticket.
- Do **not** touch `SingleThreadCore`. It holds no SwiftUI views and only one
  `canImport(SwiftUI)`-guarded color helper (`CodeSpanFormatter.swift:3–4`);
  the plate is iOS/macOS app-only UI and belongs in `SingleThread/`.

## Design Decisions

1. **Shared API = `CardPlateModifier` + `View.cardPlate(...)`**: chosen over a
   bare View extension — matches the established `ControlPlateModifier` +
   `controlPlate(...)` convention (`ControlPlateModifier.swift:12, :42–53`),
   gives tests one stable type to pin, and keeps call sites terse.
2. **Constants relocate into a new `CardPlate` type** (owner of
   `cornerRadius`, `plateFill(for:)`, `promptBoxFill`): chosen over keeping
   them on `ReminderCardView` — removes the `ContentView → ReminderCardView`
   back-reference (`ContentView.swift:601–602`) and makes the "shared" styling
   genuinely owned by a shared type. Test assertions (`BackgroundCardTests`,
   `SwipePromptTests`) and both consumer sites are updated to the new owner.
3. **Dumb modifier, `fill: Color` parameter**: call sites resolve the fill —
   card body and `EmptyStateCard` pass `CardPlate.plateFill(for: colorScheme)`,
   the prompt passes `CardPlate.promptBoxFill`. Chosen over a style enum so
   the modifier stays a pure shape/padding machine and the fill functions stay
   the single source of truth for the adaptive/fixed decision.
4. **`padding: CGFloat` + `restoresGeometry: Bool` parameters**: card =
   `padding(12)`/`restoresGeometry: true`, prompt = `12`/`false`, empty state =
   `20`/`false`. Chosen over leaving the `-12` restore at the call site — the
   net-zero restore is the subtle part and should live inside the modifier,
   documented once.
5. **`cornerRadius` stays a single shared constant** (value 10, now
   `CardPlate.cornerRadius`): all three rounded rectangles already share it
   (`ReminderCardView.swift:57, :203`; `ContentView.swift:601`); the modifier
   defaults to it with no need for a per-site override today.
6. **No behavior change**: this is a pure extraction. Padding values, fills,
   corner radius, and the scheme-adaptive behavior are preserved exactly; no
   visual or accessibility changes are intended.

## What We're NOT Doing

- **Not unifying the two adaptive-fill vocabularies** — `CardPlate.plateFill`
  (light `Color(red: 0.96, 0.95, 0.94)`) and `ControlPlateModifier`'s
  `resolvedFill` (light `Color(white: 0.92)`) stay separate
  (`ReminderCardView.swift:68` vs `ControlPlateModifier.swift:21`).
- **Not extracting the circular control plate** (`ControlPlateModifier`) — it
  is a different shape/vocabulary and already cleanly shared; no convergence
  with `CardPlate`.
- **Not extracting non-plate surfaces** — the `PurchaseSettingsView` upgrade
  capsule (`PurchaseSettingsView.swift:185–190`), the `Color.systemBackground`
  root (`ContentView.swift:149`), or `Color.clear` row chrome
  (`ContentView.swift:453`).
- **Not moving SwiftUI into `SingleThreadCore`** — the plate stays in
  `SingleThread/`, compiled only into the iOS/macOS app target
  (`project.pbxproj` folder-synchronized groups :109–148; Core has no views).
- **Not adding a `.textSize(...)` helper or touching `TextSizeModifier`** —
  unrelated to the plate extraction.
- **Not changing the watch or widget targets** — neither has any plate-like
  surface (research Q6: zero matches), so no watch/widget code changes.

## Open Risks

- **Snapshot tests are content-only**: `ShowDateTests`, `ShowAlarmsTests`,
  `ShowRecurrenceTests` snapshot `ReminderCardView.body` but assert only
  content substrings; the `RoundedRectangle` presence assertion in
  `SwipePromptTests.swift:17` must still see the shape after refactoring. If
  `String(describing:)` serialization of the modifier-wrapped background
  changes, that assertion could break and need re-verification.
- **Periphery dead-code**: `CardPlate`'s members are only "used" via test
  references; if Periphery's index doesn't see test-only reachability it may
  flag them. Mitigate with `make periphery` early; if flagged, keep a genuine
  production call site (which exists — all three) and verify the scan.
- **Geometry-restore edge case**: the `-padding` restore is only correct in
  the `List` row context. If a future caller misuses `restoresGeometry: true`
  outside a list, the frame underflows. The parameter docs must state the
  contract; today only the card body sets it true.
- **Naming churn**: renaming `plateCornerRadius → cornerRadius` /
  `plateFill → fill(for:)` inside `CardPlate` touches ~6 test assertions and 3
  production sites; mechanical, but each must be updated in the same commit.

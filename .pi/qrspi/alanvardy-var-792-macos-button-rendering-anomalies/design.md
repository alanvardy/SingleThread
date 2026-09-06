# Design Discussion — macOS Button Rendering Anomalies

## Current State

SingleThread's main target compiles the same `SingleThread/` view files for
iPhone, iPad, and macOS, diverging per platform via `#if os(...)` branches and
cross-platform helpers (mapped in `research.md` Q3). Button appearance today is
a three-way mix:

1. **Hand-drawn plates on the label** — `.controlPlate()` renders a 56×56
   adaptive circle (dark → black plate/white glyph; light → off-white plate/
   near-black glyph) with a shadow (`ControlPlateModifier.swift:20-29`,
   adaptive colors `:21-22`, size `:26,33`). It is applied *to the Button's
   label*, never to the button itself, and **never sets or replaces a button
   style** (`research.md` Q2).
2. **The platform-default button style** remains active underneath — so on
   macOS the default "bezel/bordered" chrome wraps every plate label, producing
   the translucent square around a circle. On iOS the default style is
   effectively chrome-less for icon-only labels, so the same code renders
   clean. This is the anomaly (confirmed by `research.md` Q1's observation that
   the identical Complete/Skip logic exists twice: iOS draws its own plate at
   `ContentView.swift:507` / `ContentView+ActionMenu.swift:41`; macOS carries
   no plate and relies on default chrome at `ContentView+ActionMenu.swift:96-164`).
3. **Explicit `.buttonStyle` sites** — 7 total across all targets; the only
   full opt-out is `UpgradePromptButton` `.buttonStyle(.plain)` + fully
   hand-drawn (`PurchaseSettingsView.swift:175-197`). **Zero custom
   `ButtonStyle` conformances exist anywhere** in the repo.

The macOS bottom-bar cluster is additionally *tint-colored* (green/orange/red
at `ContentView+ActionMenu.swift:104,128,158`) with no plate, so it diverges
from iOS in both chrome and color. Appearance itself is enforced at the window
level (UIWindow `overrideUserInterfaceStyle` / NSWindow `.appearance` —
`AppDelegate.swift:15-23`, `:72-76`), and SwiftUI's `@Environment(\.colorScheme)`
follows it, so plate fills already track the forced appearance.

## Desired End State

On macOS, icon-only buttons render achrome-less — **identical to iOS/iPadOS**:
white glyph on a black circle in dark mode, black glyph on an off-white circle
in light mode, with no visible translucent container.

Concretely, the macOS-facing icon-only buttons (settings gear, refresh, mic,
and the bottom-bar cluster) draw their circle via `.controlPlate()` alone, with
the platform bezel suppressed, and the cluster's color tint upgraded to the
same adaptive mono treatment iOS uses.

**Correctness is verified headlessly** by reflected-view unit tests (the repo's
"string-snapshot" technique — `SingleThreadTests.swift:73-96`,
`SwipePromptTests.swift:11-23`) plus a `make mac-build` manual screenshot as a
final visual sanity check. Painted pixels are never asserted in CI (macOS UI
tests compile but are never run — `ci.yml:296-312`); decisions are asserted at
the constant/modifier-chain level, per the repo convention that "rendered paint
can't be asserted" (`CardPlate.swift:13-14`).

## Patterns to Follow

- **Centralized, headless-testable modifiers** — `ControlPlateModifier`
  centralizes drawing so tests can assert it without rendering
  (`ControlPlateModifier.swift:2-4,42-48`). The new button modifier should do
  the same for the chrome decision rather than scattering `.buttonStyle` at
  call sites.
- **One `View` extension entry point per modifier** — `View.controlPlate(fill:glyph:)`
  (`ControlPlateModifier.swift:51-55`) and `View.cardPlate(...)`
  (`CardPlateModifier.swift:45-49`). Mirror this shape for the new modifier.
- **Adaptive colors resolved inside the modifier from `@Environment(\.colorScheme)`**
  (`ControlPlateModifier.swift:38-39`) — keep all fill/glyph decisions in the
  modifier/constant layer, not at call sites.
- **Parallel `#if` blocks for platform-divergent controls**, documented by
  header comments (`ContentView+ActionMenu.swift:7-10` is the canonical
  bottom-bar example). The macOS cluster already lives in its own gated block
  (`:70-170`); edit within it rather than restructuring.
- **Reflection-based "string-snapshot" unit tests** — assert serialized
  modifier/style chains, never pixels: `SwipePromptTests.swift:11-23`,
  `SingleThreadTests.swift:73-96`. New tests must follow this style.
- **Constant-owning enums for assertable decisions** (`CardPlate.swift:16,23,29-30`).
- **Pattern NOT to follow**: `UpgradePromptButton`'s `.plain` + hand-drawn
  background (`.background(.blue, in: Capsule())` `PurchaseSettingsView.swift:188`)
  — that is the full-custom-control escape hatch, and replicating it across the
  toolbar would duplicate the plate's already-working drawing.
- **Pattern NOT to follow**: the macOS cluster's current scattered `.tint` +
  default-chrome treatment (`ContentView+ActionMenu.swift:96-164`) — this *is*
  the anomaly, not a precedent.

## Design Decisions

1. **Chrome suppression = `.buttonStyle(.borderless)`.** Chosen over `.plain`
   (loses native press/hover affordance; `UpgradePromptButton` is the only
   precedent and is a special case) and over a custom `ButtonStyle` conforming
   type (new pattern in a codebase with zero such types). `.borderless` keeps
   macOS hover/pressed feedback while removing the persistent bezel, and its
   iOS behavior matches what the icon-only buttons already get implicitly.

2. **Centralize in a shared modifier `singleThreadButton()`** (new file
   `SingleThread/SingleThreadButtonModifier.swift`). Applies
   `.buttonStyle(.borderless)` as a `View` extension, mirroring `controlPlate`
   (`ControlPlateModifier.swift:51-55`). Every macOS-facing icon-only button
   calls it instead of inlining `.buttonStyle(.borderless)`. This makes the
   decision assertable via reflection and gives one edit point if the mechanism
   changes.

3. **Full color parity for the macOS bottom bar.** `macCompleteButton` /
   `macSkipButton` / `macDeleteButton` (`ContentView+ActionMenu.swift:96-164`)
   drop their `.tint(.green/.orange/.red)` and adopt `.controlPlate()` on the
   label, matching iOS (`ContentView.swift:507`, `ContentView+ActionMenu.swift:41`).
   The green/orange/red affordance is intentionally removed for cross-platform
   identity. (The swipe-action tints `ContentView.swift:463,471` are iOS-only
   and untouched.)

4. **The macOS-action `Menu` is a `Menu`, not a `Button`.** `macActionMenu`
   (`ContentView+ActionMenu.swift:111-133`, `.tint(.orange)` `:128`) cannot
   take `.buttonStyle`; it receives the equivalent chrome-less treatment via
   `.menuStyle(.borderlessButton)` plus `.controlPlate()` on its label so it
   reads as the same circle-in-a-cluster control.

5. **Scope = macOS-facing icon-only controls only.** Settings gear
   (`ContentView.swift:195`/label `:201`), macOS refresh (`:210-226`/`:217`),
   mic (`:536`, shared across platforms), and the macOS bottom-bar cluster.
   Dialog/sheet/form *text* buttons (e.g. "Try Again" `PurchaseSettingsView.swift:89`,
   sheet buttons `:41,210`, `BackgroundSettingsView.swift:56`) keep native macOS
   bezel — those are not the "translucent square around a circle" anomaly and
   should look macOS-native.

6. **Verification = reflection unit tests, macOS-gated.** Extend the existing
   macOS button-signature technique (`SingleThreadTests.swift:73-96`) to assert
   the fixed controls carry the borderless style / `ControlPlateModifier`.
   Adding the style to the refresh button changes that pinned reflected
   signature (`:93-96`), so the existing assertion is updated in the same
   change. Test names must NOT start with `test` (SwiftFormat strips prefixes);
   SwiftLint `identifier_name` ≥ 3 applies.

## What We're NOT Doing

- **Not touching dialog/sheet/form text buttons** — they keep native macOS
  chrome (scoped out in Decision 5).
- **Not touching the watch or widget targets** — they use separate source
  files with no `#if` and no plate usage at all (`research.md` Q1/Q3); the
  anomaly is confined to the macOS render of `SingleThread/`.
- **Not introducing a new `ButtonStyle` conforming type** — we stay with
  `.borderless` + the shared modifier.
- **Not adding macOS UI tests** — they are compiled but never executed in CI
  (`ci.yml:296-312`); verification is unit reflection + manual `make mac-build`.
- **Not changing the appearance system** — window-level override and plate
  adaptive-colors stay as-is; we only remove the bezel layer.
- **Not re-tinting / re-coloring** beyond removing the cluster's tint in favor
  of the plate's adaptive mono scheme.
- **Not reformatting existing shared/iOS-only button code** outside the scoped
  sites (minimizes SwiftFormat/`type_body_length` churn — the file splits exist
  to stay under SwiftLint budgets, `ContentView+ActionMenu.swift:7-10`).

## Open Risks

- **`macActionMenu` (`Menu`) parity fidelity** — `.menuStyle(.borderlessButton)`
  + `.controlPlate()` may not produce pixel-identical geometry to a
  `singleThreadButton()`-styled `Button`; verify against the other cluster
  circles in the manual `make mac-build` pass.
- **Hover/press feedback on macOS** — `.borderless` keeps feedback, but how it
  renders *behind* the 56×56 opaque plate is visual-only; there is no headless
  assertion for it (consistent with the repo's "paint can't be asserted"
  posture, `CardPlate.swift:13-14`).
- **Exact reflected-signature test fragility** — `SingleThreadTests.swift:73-96`
  pins a long `ModifiedContent<...>` string; the updated signature must be
  re-derived from the build, and is sensitive to unrelated modifier-order
  changes.
- **Accessibility labels on the cluster** — the icon-only controls rely on
  explicit labels (the a11y identifier seam; see `SingleThreadTests.swift:86-90`).
  Adding `.controlPlate()` must preserve them; watch for `accessibility_label_for_image`
  in `swiftlint lint --strict`.
- **`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`** — any unused dropped `.tint` or
  deprecated `.menuStyle` spelling fails the build; use the modern
  `.menuStyle(.borderlessButton)` form and confirm on `make mac-build`.
- **Line-number drift** — `ContentView.swift` bottom-bar anchors shift with
  edits; the `#if os(iOS)` block (`:497-526`) and macOS `#else` (`:683`) are the
  stable reference points (`research.md` Open Areas).
# Design Discussion

Branch: `alanvardy-var-790-swipe-guide-should-change-with-colour-scheme`
Topic: make the reminder-card swipe guide adapt to light/dark colour scheme.

## Current State

The swipe guide (the "swipe prompt") renders inside `ReminderCardView` as a `prompt`
subview gated by `if showSwipePrompt { prompt }` — `SingleThread/ReminderCardView.swift:40-41`.
The card plate behind it already adapts via `CardPlate.plateFill(for: colorScheme)`
(`ReminderCardView.swift:44`), but the prompt box itself is **fixed dark in both schemes**:

- Prompt-box plate: `CardPlate.promptBoxFill = Color(red: 0.16, green: 0.17, blue: 0.18)`
  (`CardPlate.swift:23`), applied at `ReminderCardView.swift:207`. Its doc comment
  (`CardPlate.swift:18-22`) explicitly states the grey is used "in both modes by design" —
  that is the bug we are reversing.
- Separator `|`: `.foregroundStyle(.white.opacity(0.5))` (`ReminderCardView.swift:173-174`).
- Left hint (skip): `.foregroundStyle(.orange)` (`:167-171`).
- Right hint (complete): `.foregroundStyle(.green)` (`:176-180`).
- Dismiss label: `.foregroundStyle(.black)` + `.buttonStyle(.borderedProminent)` +
  `.tint(.white)`, a11y label "Dismiss swipe prompt", id `swipePromptDismissButton`
  (`ReminderCardView.swift:185-204`).

The prompt reads `@Environment(\.colorScheme)` at the view level and already passes it to
the card plate (`ReminderCardView.swift:49-50`); it does not pass it to the prompt box.

Appearance is a live, no-restart flow: `@AppStorage("appearanceMode")` →
`window.overrideUserInterfaceStyle` / `NSWindow.appearance` per scene (`AppDelegate.swift:15-23`,
`ContentViewModel.swift:130-136`); SwiftUI consumes the resulting `\.colorScheme`. No observer
or `.preferredColorScheme` exists in the runtime path (research Q4), so the prompt must react
through the same `\.colorScheme` read every adaptive component already uses.

The guide is iOS-only (`ContentView.swift:100-103, 348-356`); macOS compiles the binding as
`.constant(false)`; watchOS has no swipe-guide code.

## Desired End State

In **light** appearance the prompt box becomes a light plate (matching the card's family),
with a mid-light fill, a dark separator, and a high-contrast dismiss button. In **dark**
appearance it keeps today's dark behaviour. Everything else — default visibility, permanent
dismiss, the Settings toggle, accessibility labels/ids, and every launch-seam UI test — is
unchanged.

Verification: the four swipe-prompt UI flows still pass
(`SingleThreadUITestsFlows.swift:517-599`), the accessibility audit that launches with
`--ui-testing --reset-swipe-preference` still passes (`SingleThreadUITests.swift:23-66`), and
all unit pins are updated and green via `./scripts/test.sh --unit-only` then `make lint`.

## Patterns to Follow

**Good — reuse these:**

- **Pure static function with explicit `ColorScheme` param**: `CardPlate.plateFill(for:)`
  (`CardPlate.swift:29-31`) returns a `Color` from an argument, no environment read inside.
  This is the idiom the prompt will adopt. Call sites read `@Environment(\.colorScheme)` at
  the view level and pass it in (`ReminderCardView.swift:49-50 → :44`);
  `EmptyStateCard.swift:48-49 → :34`.
- **Light-fill reference value**: `ControlPlateModifier` uses `Color(white: 0.92)` for its
  light fill (`ControlPlateModifier.swift:21`). Reuse this exact value for the prompt box's
  light fill rather than inventing a new one.
- **Decisions testable, paint not**: unit tests assert colour *decisions* headlessly
  (`CardPlateTests.swift:16-36`, `SwipePromptTests.swift:38`); rendering is never pixel-tested.
- **Stable a11y surface**: keep label "Dismiss swipe prompt", id `swipePromptDismissButton`,
  and `.borderedProminent` (`ReminderCardView.swift:202-204`) so the reflected-body snapshot
  (`SwipePromptTests.swift:41-54`) and UI-test queries stay valid.
- **Semantic tints for the actions**: keep `.orange` / `.green` hints matching the
  `.swipeActions` tints (`ContentView.swift:457-471`) — the prompt and the gesture must stay
  visually coupled.

**Bad — do NOT copy:**

- **Fixed constant "in both modes by design"** (`CardPlate.swift:18-23`): the exact
  anti-pattern being removed; its doc comment will be corrected.
- **Hard-coded stroke/button colours inline in a view** (`ReminderCardView.swift:173-174,
  188-195`): fixed `.white.opacity(0.5)` and `.black`/`.tint(.white)` are what wash out on a
  light plate.
- **Reaching for semantic `.foregroundStyle(.secondary)`** for the dismiss button: it is
  widespread (`ReminderCardView.swift:93-125`) but drops the explicit contrast the button
  needs and would churn the reflected-body snaps for no gain. Use explicit scheme-driven
  values here.

## Design Decisions

1. **Adaptive idiom (Q1-A)**: extend `CardPlate` with a pure
   `static func promptBoxFill(for colorScheme: ColorScheme) -> Color`, a sibling of
   `plateFill(for:)`. Rationale: the colour decision stays in `CardPlate` (where it already
   lives), stays headlessly testable, and the caller already has `colorScheme` in scope on the
   same line as the card-plate call. The old fixed constant `promptBoxFill` is removed.

2. **Light palette (Q2-B)**: `promptBoxFill(for: .light) == Color(white: 0.92)` (reusing the
   control-plate light fill); `promptBoxFill(for: .dark) == Color(red: 0.16, green: 0.17,
   blue: 0.18)` (unchanged). Light fill sits slightly darker than the card plate
   (`0.96/0.95/0.94`) for subtle contrast.

3. **Hint tints unchanged (Q3-A)**: `.orange` / `.green` stay identical in both schemes.
   Rationale: they are legible on both light and dark plates and intentionally match the
   `.swipeActions` tints; re-tinting would de-couple the prompt from the gesture. This is a
   deliberate no-op — documented so downstream doesn't "fix" it.

4. **Separator scheme-driven**: `colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)`
   in the prompt subview (`ReminderCardView.swift:173-174`). Dark keeps today's value; light
   gets a dark stroke on the light box.

5. **Dismiss button scheme-aware (Q4-A)**: keep `.borderedProminent` and the a11y label/id;
   flip label + tint to contrast against the now-adaptive box —
   - light: dark button (`label .white`, `tint .black`) so it pops on the `0.92` box;
   - dark: today's white button (`label .black`, `tint .white`).
   Implemented as explicit scheme ternaries in the prompt subview (same precedent as
   `CardPlate.swift:30`, `ControlPlateModifier.swift:21-22`).

6. **Test strategy (Q5-A) — unit only, no new UI test**: replace the fixed-fill pins with
   parametrised pins mirroring `CardPlateTests.plateFill(for:)`. No rendered-colour UI test —
   the repo has zero rendered-dark-colour assertions and no seam for forcing
   `overrideUserInterfaceStyle` on a launched app (research Q5).

7. **Correct the documentation**: update the `CardPlate.swift:18-22` doc comment to state the
   prompt box now adapts, matching the new behaviour and removing the "in both modes" claim.

## Test & Verification Plan

- `CardPlateTests.swift:17` — replace `promptBoxFill == Color(0.16,0.17,0.18)` with
  `promptBoxFill(for: .light) == Color(white: 0.92)` and
  `promptBoxFill(for: .dark) == Color(0.16,0.17,0.18)`.
- `SwipePromptTests.swift:38` — same replacement of the removed constant.
- `SwipePromptTests.swift:9-24` reflected-body snaps: `"style: orange"`, `"style: green"`,
  `"Dismiss"`, `"CardPlateModifier"`, `"BorderedProminentButtonStyle"` must all remain present
  (unchanged, since hints and button style are preserved).
- Grep for any other `promptBoxFill` references before deleting the constant (expected:
  `ReminderCardView.swift:207` + the two tests above).
- Gate: `./scripts/test.sh --unit-only`, then `make lint` (SwiftFormat `organizeDeclarations`
  will reorder new static members).

## What We're NOT Doing

- **Not** changing hint tint colours (orange/green) — Q3-A.
- **Not** adding a rendered-colour UI test — Q5-A.
- **Not** touching the card plate (`plateFill(for:)`) — already adaptive.
- **Not** changing any persistence, visibility, dismiss path, Settings toggle, accessibility
  label/id, or launch seam (`@AppStorage("showSwipePrompt")`, `--reset-swipe-preference`,
  `UITestingSeed` keys all unchanged) — `ContentView.swift:100-103`, `AppViewModel.swift:257-263`.
- **Not** adding any macOS or watchOS code — the guide is iOS-only; watch has none.
- **Not** introducing a new `EnvironmentKey`, `PreferenceKey`, runtime `.preferredColorScheme`,
  or trait observer — adaptation rides the existing `\.colorScheme` read.
- **Not** changing localization content — all swipe strings are `extractionState: manual`
  and only checked for non-empty values (`LocalizationTests.swift:36-111`).

## Open Risks

- **Contrast of new light box/button**: `Color(white: 0.92)` vs card `0.96` is subtle; the
  light-mode dismiss button (`.tint(.black)`) needs a visual check under Dynamic Type and the
  local audit's extra `.dynamicType`/`.hitRegion` categories. Local hit-region failures are
  documented as local-only, not CI breaks (`SingleThreadUITests.swift:54-60`).
- **Reflected-body snapshot fragility**: editing the prompt subview can perturb the
  `String(describing:)` output; keep the copy strings and style names byte-stable.
- **`promptBoxFill` grep coverage**: if a third reference escapes the two known tests the
  constant deletion breaks the build — the grep before deletion is load-bearing.
- **`Localizable.xcstrings` line refs** were pinned from one pass and may drift; no value edit
  is needed, so this is informational only.
- **Window-override propagation** remains unverified at the edges (sheets over scenes,
  split-screen) per research's open area — this change doesn't widen or resolve that risk.
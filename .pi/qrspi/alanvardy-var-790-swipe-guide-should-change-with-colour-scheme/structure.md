# Structure Outline

## Approach

Make the reminder-card swipe prompt adapt to `\.colorScheme` by extending `CardPlate` with a pure `promptBoxFill(for:)` sibling of the existing `plateFill(for:)`, then wiring `ReminderCardView`'s prompt subview to pass its `colorScheme` through and flip the separator/dismiss-button colours. No persistence, visibility, dismiss, Settings, a11y, or launch-seam behaviour changes — colour decisions only, unit-tested headlessly, no new UI test.

This is an iOS-UI-only change: there is no migration/data-access/service/transport tier. The layers below are *decision primitive → view wiring → regression gate*, each green before the next. The key horizontal-safety fact: **removing the old `promptBoxFill` constant breaks the build until the view switches to the new function**, so Stage 1 adds the function additively and Stage 2 is the swap + removal.

## Stage 1: Colour-decision primitive (`CardPlate`) — additive

Delivers the pure, headlessly-testable colour decision for the prompt box, while leaving the old constant in place so the build stays green.

**Files**: `SingleThread/CardPlate.swift`, `SingleThreadTests/CardPlateTests.swift`

**Key changes**:
- `static func promptBoxFill(for colorScheme: ColorScheme) -> Color` — **new**; `.light → Color(white: 0.92)`, `.dark → Color(red: 0.16, green: 0.17, blue: 0.18)` (unchanged dark value, reused control-plate light fill).
- `static let promptBoxFill: Color` — **kept this stage** (still referenced at `ReminderCardView.swift:207`; removed next stage).

**Tests**: net-new pins in `CardPlateTests` mirroring `plateFill(for:)` — `promptBoxFill(for: .light) == Color(white: 0.92)` and `promptBoxFill(for: .dark) == Color(red: 0.16, green: 0.17, blue: 0.18)`. Existing constant pins (`CardPlateTests.swift:17`, `SwipePromptTests.swift:38`) untouched and still green.

**Verify**: `./scripts/test.sh --unit-only` green. (Existing pins prove the constant still behaves; new pins prove the function.)

---

## Layer 2: View wiring (`ReminderCardView`) — the swap + removal

Consumes the Stage-1 function and makes the prompt subview fully scheme-driven; removes the now-dead constant and corrects the stale doc comment.

**Files**: `SingleThread/ReminderCardView.swift`, `SingleThread/CardPlate.swift`, `SingleThreadTests/SwipePromptTests.swift`, `SingleThreadTests/CardPlateTests.swift`

**Key changes**:
- Prompt plate at `ReminderCardView.swift:207`: `CardPlate.promptBoxFill` → `CardPlate.promptBoxFill(for: colorScheme)` (scheme already read at `:49-50` for the card plate).
- Separator `:173-174`: `.foregroundStyle(.white.opacity(0.5))` → `colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)`.
- Dismiss button `:188-195`: label `.foregroundStyle(.black)`/`.tint(.white)` → light: label `.white` + `.tint(.black)`; dark: label `.black` + `.tint(.white)` (explicit scheme ternaries; `.borderedProminent` + a11y label/id **unchanged**).
- Hint tints `.orange`/`.green` — **deliberately unchanged** (they stay coupled to `.swipeActions` tints).
- `CardPlate.swift`: remove `static let promptBoxFill`; correct doc comment `:18-22` (drop "in both modes by design", state it now adapts).
- Repoint `SwipePromptTests.swift:38` to `promptBoxFill(for: .dark)`; drop the now-redundant constant pin in `CardPlateTests.swift:17`.

**Tests**: reflected-body snaps (`SwipePromptTests.swift:9-54`) must stay byte-stable — `"style: orange"`, `"style: green"`, `"Dismiss"`, `"CardPlateModifier"`, `"BorderedProminentButtonStyle"` all still present; function pins from Stage 1 still green. **Grep `promptBoxFill` before deleting the constant** — expected hits after repointing: zero outside `promptBoxFill(for:)` definitions/calls.

> **Headlessly-untestable paint (noted)**: the separator and button colour *values* are ternaries in the view and cannot be asserted headlessly — this matches design Q5-A ("decisions testable, paint not"). They are guarded by the reflected-body structure snaps (structure unchanged) plus a manual visual check under light + dark + Dynamic Type (including the local audit's extra `.dynamicType`/`.hitRegion`). If you'd prefer they be unit-tested, the adjustment is to extract `promptSeparator(for:)` / `promptDismissButtonColors(for:) -> (label: Color, tint: Color)` into `CardPlate` (Stage-1 style) — ask and I'll add that hardening.

**Verify**: `./scripts/test.sh --unit-only` green, then `make format` + `make lint` (SwiftFormat `organizeDeclarations` reorders the new static member; SwiftLint `--strict`). Manual visual check: light ↔ dark flip via Settings, plus Dynamic Type extremes.

---

## Layer 3: Behavioural regression gate — full CI once

Confirms zero behavioural drift outside the prompt's colours: default visibility, permanent dismiss, Settings toggle, a11y, and every launch-seam UI flow still pass.

**Files**: none new (verification only).

**Tests**: full `./scripts/test.sh` once (unit + iOS/macOS + watch + UI). Specifically the four swipe-prompt flows in `SingleThreadUITestsFlows.swift:517-599` and the audit that launches with `--ui-testing --reset-swipe-preference` (`SingleThreadUITests.swift:23-66`) must stay green. Optionally run `make ui-test` locally with the audit's extra strictness categories to confirm the light box/button contrast (documented as local-only, not a CI break).

**Verify**: full `./scripts/test.sh` green.

## Testing Checkpoints

- **After Stage 1**: `./scripts/test.sh --unit-only` green — `promptBoxFill(for:)` pins green, old `promptBoxFill` constant still referenced and its pins green.
- **After Stage 2**: `--unit-only` green + `make lint` clean — grep shows no bare `promptBoxFill` (constant) references remain; reflected-body snaps unchanged.
- **After Stage 3**: full `./scripts/test.sh` green — unit, four swipe-prompt flows, and the `--reset-swipe-preference` accessibility audit all pass.
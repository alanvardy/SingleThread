# Implementation Plan

## Overview

Make the reminder-card swipe guide adapt to `\.colorScheme` by extending `CardPlate` with a pure `promptBoxFill(for:)` sibling of `plateFill(for:)`, then wiring `ReminderCardView`'s prompt subview to pass `colorScheme` through and flip the separator/dismiss-button colours. Colour decisions only — no persistence, visibility, dismiss, Settings, a11y, or launch-seam changes.

The horizontal-safety rule: **removing the old `promptBoxFill` constant breaks the build until the view switches to the new function**. Phase 1 adds the function additively (build stays green); Phase 2 does the swap + removal; Phase 3 is the full regression gate.

---

## Phase 1: Colour-decision primitive (`CardPlate`) — additive

Adds the pure, headlessly-testable colour decision for the prompt box while leaving the old constant in place so the build stays green.

### Changes

#### 1. Add `promptBoxFill(for:)` to `CardPlate`
**File**: `SingleThread/CardPlate.swift`
**Action**: modify (additive)

Add a new static function as a sibling of the existing `plateFill(for:)` (mind the actual `plateFill` body — `colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.95, blue: 0.94)`):

```swift
    /// Plate behind the swipe instructions and Dismiss button so the coloured
    /// hints read as one dismissible prompt on the card. Light mode uses a
    /// mid-light fill (`0.92`, the control-plate light fill) that sits slightly
    /// darker than the card plate; dark mode keeps the original dark grey.
    static func promptBoxFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.17, blue: 0.18) : Color(white: 0.92)
    }
```

- **Do NOT remove** `static let promptBoxFill = Color(red: 0.16, green: 0.17, blue: 0.18)` this phase — it is still referenced at `ReminderCardView.swift:207` and pinned in `CardPlateTests.swift` + `SwipePromptTests.swift`.
- Do not touch the doc comment on the constant this phase (that correction is Phase 2).

#### 2. Pin the new function in `CardPlateTests`
**File**: `SingleThreadTests/CardPlateTests.swift`
**Action**: modify (add tests)

Add two tests mirroring the existing `plateFill*` pins. Existing `promptBoxFillIsDarkGrey()` (constant pin) stays untouched this phase.

```swift
    @Test
    func promptBoxFillOffWhiteInLightMode() {
        #expect(CardPlate.promptBoxFill(for: .light) == Color(white: 0.92))
    }

    @Test
    func promptBoxFillDarkGreyInDarkMode() {
        #expect(CardPlate.promptBoxFill(for: .dark) == Color(red: 0.16, green: 0.17, blue: 0.18))
    }
```

### Verification

#### Automated
- [x] `./scripts/test.sh --unit-only` passes — new `promptBoxFill(for:)` pins green, old `promptBoxFill` constant pins (`CardPlateTests.promptBoxFillIsDarkGrey`, `SwipePromptTests.promptBoxIsDarkGrey`) still green.

#### Manual
- [ ] None — headless colour-decision pins only; no rendered change yet.

---

## Phase 2: View wiring (`ReminderCardView`) — the swap + removal

Consumes the Phase-1 function, makes the prompt subview fully scheme-driven, removes the now-dead constant, and corrects stale doc comments.

### Changes

#### 1. Make the prompt subview scheme-driven
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify

`colorScheme` is already in scope — the view reads `@Environment(\.colorScheme)` at `ReminderCardView.swift:49-50` and passes it to the card plate at `:44`, and `prompt` is an instance computed property. Make these three edits inside the `prompt` subview (`:164-207`).

**a) Prompt plate** (`:207`): `.cardPlate(fill: CardPlate.promptBoxFill)` → `.cardPlate(fill: CardPlate.promptBoxFill(for: colorScheme))`.

**b) Separator** (`:173-174`):

```swift
            Text("|")
                .foregroundStyle(colourScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
```

**c) Dismiss button label + tint** (`:188-195`):

```swift
            } label: {
                Text("Dismiss")
                    .font(.caption.bold())
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(colorScheme == .dark ? Color.white : Color.black)
```

> **Compile-safety note**: leading-dot members (`.white`, `.black`) inside a ternary are ambiguous without a type context in Swift's `foregroundStyle`/`tint` overload set — qualify them explicitly as `Color.white` / `Color.black` (shown above). This does not change the reflected-body snapshots, which assert style *names* (`"style: orange"`, `"BorderedProminentButtonStyle"`, etc.), not colour values.

- Keep `.orange` / `.green` hint tints and `.font(.caption)` unchanged (design decision 3 — they stay coupled to the `.swipeActions` tints).
- Keep `.borderedProminent`, `.accessibilityLabel("Dismiss swipe prompt")`, `.accessibilityIdentifier("swipePromptDismissButton")`, `.contentShape(Rectangle())`, and the `.padding(.vertical, 8)` hit-region padding unchanged (design decision 5).

#### 2. Remove the dead constant and fix `CardPlate` documentation
**File**: `SingleThread/CardPlate.swift`
**Action**: modify

- Delete `static let promptBoxFill = Color(red: 0.16, green: 0.17, blue: 0.18)` (its doc comment goes with it).
- Update the two stale doc comments that claim a "fixed dark-grey fill":
  - The `enum`-level summary (currently "the swipe-prompt box uses a fixed dark-grey fill.") → state all three fills adapt.
  - The removed constant's doc comment is replaced by the `promptBoxFill(for:)` doc comment added in Phase 1.

The final member order below is illustrative — `make format`'s `organizeDeclarations` will settle the actual order:

```swift
enum CardPlate {
    static let cornerRadius: CGFloat = 10

    static func plateFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.95, blue: 0.94)
    }

    static func promptBoxFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.17, blue: 0.18) : Color(white: 0.92)
    }
}
```

#### 3. Repoint the swipe-prompt test pin
**File**: `SingleThreadTests/SwipePromptTests.swift`
**Action**: modify

Replace the `promptBoxIsDarkGrey` test (constant pin at `:38`) with the function pin, and refresh its stale doc comment ("sits on a dark grey plate so the coloured hints read against both…"):

```swift
    /// The prompt box uses the adaptive `promptBoxFill(for:)` decision so the
    /// coloured hints read against both the off-white (light) and black (dark)
    /// card plates. The rendered paint can't be asserted headlessly, so the
    /// decision is asserted directly (same rationale as `plateFill`).
    @Test
    func promptBoxFillDarkGreyInDarkMode() {
        #expect(CardPlate.promptBoxFill(for: .dark) == Color(red: 0.16, green: 0.17, blue: 0.18))
    }
```

Also refresh the stale "rounded dark-grey plate" wording in the `promptShownWhenEnabled` doc comment (the assertion strings themselves must NOT change).

#### 4. Drop the redundant constant pin
**File**: `SingleThreadTests/CardPlateTests.swift`
**Action**: modify

Delete the `promptBoxFillIsDarkGrey()` test (constant pin). The Phase-1 `promptBoxFillDarkGreyInDarkMode()` pin now covers the `.dark` case; `promptBoxFillOffWhiteInLightMode()` covers `.light`.

### Verification

#### Automated
- [x] `grep -rn "promptBoxFill" --include='*.swift' SingleThread SingleThreadTests` — before deleting the constant, confirm every hit is either the `static func promptBoxFill(for` definition or a `promptBoxFill(for:` call. After the edits, confirm **zero** bare `promptBoxFill` (non-`(for:`) references remain.
- [x] `./scripts/test.sh --unit-only` passes — reflected-body snaps in `SwipePromptTests` unchanged (`"style: orange"`, `"style: green"`, `"Dismiss"`, `"CardPlateModifier"`, `"BorderedProminentButtonStyle"`, `"Button<"`, `"AccessibilityAttachmentModifier"` all still present).
- [x] `make format` — SwiftFormat `organizeDeclarations` settles the reordered `CardPlate` members; SwiftFormat + `swiftlint --fix` apply.
- [x] `make lint` passes (`swiftformat --lint` + `swiftlint lint --strict`).

#### Manual
- [ ] Run the app and flip **Settings → Appearance → Light/Dark**; the prompt box turns light/dark live (no restart), with the separator and dismiss button inverting contrast against the box.
- [ ] Check Dynamic Type extremes (largest/smallest text) with the prompt visible — the light box/button still read clearly.
- [ ] Confirm the orange/green hint tints and the `Dismiss` button's a11y label/hit area are unchanged in both schemes.

---

## Phase 3: Behavioural regression gate — full CI once

Confirms zero behavioural drift outside the prompt's colours. No code changes.

### Changes

None (verification only).

### Verification

#### Automated
- [x] `./scripts/test.sh` — full CI-identical gate green: format, lint, build, periphery, unit (iOS + macOS), watch, and UI tests.
- [x] The four swipe-prompt flows in `SingleThreadUITestsFlows.swift:517-599` pass (`testSwipePromptAppearsUnderUITesting`, `testDismissSwipePromptHidesItAndPersistsAcrossRelaunch`, `testSwipePromptToggleRoundTripsViaSettings`).
- [x] `testAccessibilityAudit` (`SingleThreadUITests.swift:23-66`, launched with `--ui-testing --reset-swipe-preference`) passes.

#### Manual
- [ ] (Optional, local-only) `make ui-test` with the audit's extra strictness categories — `.dynamicType` / `.hitRegion` — to confirm the new light box/button contrast. A local-only hit-region failure is documented (`SingleThreadUITests.swift:54-60`) and is not a CI break.

---

## Testing Checkpoints (summary)

- **After Phase 1**: `./scripts/test.sh --unit-only` green — `promptBoxFill(for:)` pins green, old `promptBoxFill` constant still referenced and its pins green.
- **After Phase 2**: `--unit-only` green + `make lint` clean — grep shows no bare `promptBoxFill` (constant) references; reflected-body snaps unchanged.
- **After Phase 3**: full `./scripts/test.sh` green — unit, four swipe-prompt flows, and the `--reset-swipe-preference` accessibility audit all pass.

## Notes / deviations

- Doc-comment corrections beyond the single `CardPlate.swift:18-22` line are included because the same "fixed dark-grey fill" claim appears in the `enum`-level summary (`CardPlate.swift:7-10`) and in two `SwipePromptTests` comments — leaving them would contradict the code. No functional scope is widened.
- Ternary colour expressions are written with explicit `Color.` qualification (rather than the leading-dot shorthand in the design sketch) to avoid Swift ternary type-ambiguity; this is a spelling-only difference.
- No schema migrations, persistence, codegen, or new test targets are involved; `SingleThreadCore` is untouched and no new UI test is added (per design decision Q5-A).
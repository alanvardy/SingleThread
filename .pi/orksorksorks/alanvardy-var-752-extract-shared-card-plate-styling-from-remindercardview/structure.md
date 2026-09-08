# Structure Outline

## Approach

Extract the rounded-rectangle card-plate pattern (radius-10 `RoundedRectangle` +
adaptive/fixed fill + padding, with an optional net-zero geometry restore) from
`ReminderCardView` into one shared `CardPlateModifier` + `View.cardPlate(...)`
owned by a new `CardPlate` constants type, then rewire all three sites. Pure
extraction — no visual, accessibility, or behavior change intended.

Bottom-up: the constants type first (tested), then the modifier that consumes it
(tested, with one live call site), then the remaining call-site migration + seam
retirement (atomic), then the full CI gate + visual pass.

---

## Stage 1: `CardPlate` — the shared decision constants (foundation)

Introduces the single owner of the three plate decisions, so every later layer
references `CardPlate` instead of `ReminderCardView`. `ReminderCardView`'s
existing static members become thin forwarders (`Self.plateCornerRadius →
CardPlate.cornerRadius`) — the "stub earlier" mechanism that keeps `CardPlate`
genuinely reachable in production (Periphery) while the old names still compile
for the not-yet-migrated call sites and tests.

**Files**:
- `SingleThread/CardPlate.swift` (new)
- `SingleThread/ReminderCardView.swift` (forwarders only)

**Key changes**:
```swift
// SingleThread/CardPlate.swift — caseless namespace, file-per-type convention
enum CardPlate {
    static let cornerRadius: CGFloat = 10
    static let promptBoxFill: Color   // Color(red: 0.16, green: 0.17, blue: 0.18)
    static func plateFill(for colorScheme: ColorScheme) -> Color
    //     colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.95, blue: 0.94)
}
```
```swift
// ReminderCardView.swift — the three `// MARK: Internal` members become:
static let plateCornerRadius: CGFloat = CardPlate.cornerRadius
static let promptBoxFill = CardPlate.promptBoxFill
static func plateFill(for colorScheme: ColorScheme) -> Color { CardPlate.plateFill(for: colorScheme) }
```

**Tests** — `SingleThreadTests/CardPlateTests.swift` (new):
- `cornerRadiusIsTenPoints()` — happy path.
- `plateFillOffWhiteInLightMode()` / `plateFillBlackInDarkMode()` — happy paths.
- `promptBoxFillIsDarkGrey()` — happy path.
- `plateFillDarkDiffersFromLight()` — sad path (guards the adaptive branch).
Existing `BackgroundCardTests` / `SwipePromptTests` must still pass unchanged via
the forwarders.

**Verify**: `./scripts/test.sh --unit-only` green; `make periphery` green
(`CardPlate` reachable through the forwarders; pin `SIM=` to a UDID if the
`iPhone 17` name is ambiguous).

---

## Stage 2: `CardPlateModifier` + `View.cardPlate(...)` — the shape/padding machine

Adds the dumb modifier that turns any content into a radius-10 plate. It consumes
`CardPlate.cornerRadius` directly (no per-site override today), resolves nothing
itself (call sites pass `fill`), and owns the subtle net-zero geometry restore.
Wired first at the canonical `ReminderCardView.body` site so the modifier has a
real production consumer from day one.

**Files**:
- `SingleThread/CardPlateModifier.swift` (new)
- `SingleThread/ReminderCardView.swift` (rewire `body` only)

**Key changes**:
```swift
struct CardPlateModifier: ViewModifier {
    var fill: Color
    var padding: CGFloat
    var restoresGeometry: Bool
    func body(content: Content) -> some View
    //   content.padding(padding)
    //     .background { RoundedRectangle(cornerRadius: CardPlate.cornerRadius).fill(fill) }
    //   then .padding(-padding) only when restoresGeometry
}

extension View {
    /// - Parameters: fill (required), padding = 12, restoresGeometry = false
    func cardPlate(fill: Color, padding: CGFloat = 12, restoresGeometry: Bool = false) -> some View
}
```
```swift
// ReminderCardView.body — replaces .padding(12) + .background {…} + .padding(-12)
.cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 12, restoresGeometry: true)
```

**Tests** — `SingleThreadTests/CardPlateModifierTests.swift` (new):
- `cardPlateRendersRoundedRectangle()` — `String(describing:)` of a modified view
  contains `"RoundedRectangle"` (same reflection technique as
  `SwipePromptTests.promptShownWhenEnabled`).
- `restoresGeometryFlagChangesModifierChain()` — sad path: description differs
  between `restoresGeometry: true` and `false` (the `-padding` restore is
  present/absent).
Existing `SwipePromptTests.promptShownWhenEnabled` `RoundedRectangle` assertion
keeps passing — `body` now routes through the modifier.

**Verify**: `./scripts/test.sh --unit-only` green; `make periphery` green
(modifier reachable via the rewired `body`).

---

## Stage 3: Migrate remaining consumers + retire the old seams (atomic)

Rewires the two remaining sites and deletes the `ReminderCardView` forwarders,
completing the ownership move. This is deliberately one commit: the constants
move off `ReminderCardView` and the ~4 test assertions repoint to `CardPlate` in
the same change (a split commit leaves either dangling forwarders or broken
assertions).

**Files**:
- `SingleThread/ReminderCardView.swift` (rewire `prompt`, delete `// MARK:
  Internal` forwarders)
- `SingleThread/ContentView.swift` (`EmptyStateCard.body`)
- `SingleThreadTests/BackgroundCardTests.swift` (repoint 3 assertions)
- `SingleThreadTests/SwipePromptTests.swift` (repoint 1 assertion)

**Key changes**:
```swift
// ReminderCardView.prompt — .frame(maxWidth: .infinity) stays, then:
.cardPlate(fill: CardPlate.promptBoxFill)          // padding 12, no restore

// ContentView EmptyStateCard.body — replaces .padding(20) + .background {…}
.cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 20)

// Removed from ReminderCardView: promptBoxFill, plateCornerRadius, plateFill(for:)
// Tests repoint: ReminderCardView.plateFill → CardPlate.plateFill,
//   .plateCornerRadius → .cornerRadius, .promptBoxFill → CardPlate.promptBoxFill
```
The `ContentView → ReminderCardView` back-reference is gone (`EmptyStateCard`
now imports only `CardPlate`).

**Tests** (modified, no new suites):
- `BackgroundCardTests.plateFillOffWhiteInLightMode` /
  `plateFillBlackInDarkMode` / `plateCornerRadiusIsTenPoints` — repointed to
  `CardPlate`, values unchanged.
- `SwipePromptTests.promptBoxIsDarkGrey` — repointed to `CardPlate.promptBoxFill`;
  `promptShownWhenEnabled` still sees `"RoundedRectangle"`.

**Verify**: `./scripts/test.sh --unit-only` green; `make periphery` green
(`CardPlate` now referenced by the modifier, all three call sites, and the tests;
nothing left dangling on `ReminderCardView`).

---

## Stage 4: Full gate + visual regression pass

The integration checkpoint. No code changes expected here — this proves the
extraction is behavior-neutral across the whole matrix and on-device.

**Files**: none (fix-ups only if the gate surfaces drift).

**Verify**:
- `./scripts/test.sh` (full: format, lint `--strict`, build, watch build,
  Periphery, unit + UI tests, watch unit/UI, macOS build + unit tests).
- No new warnings (project-wide `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`).
- Manual visual check on `iPhone 17` and `iPad (A16)`, light + dark: card text
  plate, swipe prompt, and the three empty states render pixel-identical to
  `origin/main`. The +12/−12 geometry restore (only the card body) must not change
  `List` row metrics — the parameter doc in `cardPlate(...)` states this contract.

---

## Testing Checkpoints

After each stage's gate, the tree must be green before advancing; if context
resets, resume from the first red stage:

- **After Stage 1**: `CardPlate` values asserted green in `CardPlateTests`; legacy
  suites green via forwarders; Periphery has no `CardPlate` dead-code finding.
- **After Stage 2**: `cardPlate(...)` composes a `RoundedRectangle`; the
  `SwipePromptTests` `RoundedRectangle` presence assertion still passes through the
  rewired `body`.
- **After Stage 3**: zero references to `ReminderCardView.plateCornerRadius` /
  `.plateFill` / `.promptBoxFill` anywhere (source or tests); Periphery clean.
- **After Stage 4**: full `./scripts/test.sh` green + visual pass.

## Cross-Cutting Note

The constants' ownership move is inherently atomic (constants + call sites +
test assertions change together), which is why Stage 3 bundles them. The
forwarders in Stage 1 are the explicit "stub earlier" for the Periphery
dead-code constraint flagged in the design: `CardPlate` and
`CardPlateModifier` are internal, test-asserted types, and must keep at least
one genuine production reference at every intermediate commit. Geometry
(+12/−12 restore) cannot be asserted headlessly — it is pinned only by the
modifier's documented contract and the Stage 4 visual pass, matching the design's
stated "geometry asserted nowhere" reality.

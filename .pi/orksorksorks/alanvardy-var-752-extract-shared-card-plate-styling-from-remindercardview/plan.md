# Implementation Plan

## Overview

Extract the rounded-rectangle card-plate pattern (radius-10 `RoundedRectangle` + adaptive/fixed fill + padding, with optional net-zero geometry restore) from `ReminderCardView` into a shared `CardPlateModifier` + `View.cardPlate(...)` owned by a new `CardPlate` constants type, then rewire all three call sites. Pure extraction — no visual, accessibility, or behavior change.

---

## Phase 1: `CardPlate` — the shared decision constants (foundation)

Introduce the single owner of the three plate decisions. `ReminderCardView`'s existing static members become thin forwarders to `CardPlate` so Periphery sees production reachability while the old names still compile for not-yet-migrated call sites and tests.

### Changes

#### 1. Create `CardPlate` constants type
**File**: `SingleThread/CardPlate.swift`
**Action**: create

```swift
import SwiftUI

/// Shared styling decisions for every rounded-rectangle content plate in the
/// app: the card text plate, the empty-state card plate, and the swipe-prompt
/// box. Extracted so the constants are owned by the namespace that names them
/// and the decisions can be asserted headlessly in tests.
///
/// All three plates share the same 10pt corner radius. The card text plate and
/// empty-state plate share an adaptive fill (off-white light / black dark);
/// the swipe-prompt box uses a fixed dark-grey fill.
enum CardPlate {
    // MARK: Internal

    /// Shared corner radius for every content plate — the card text plate, the
    /// empty-state card plate, and the swipe-prompt box. Extracted because the
    /// rendered shape can't be asserted headlessly — tests assert this
    /// decision instead.
    static let cornerRadius: CGFloat = 10

    /// Dark grey plate behind the swipe instructions and Dismiss button so the
    /// coloured hints read as one dismissible prompt on the card — in both the
    /// off-white (light) and black (dark) card-plate modes. Extracted because
    /// the rendered paint can't be asserted headlessly — tests assert this
    /// decision instead.
    static let promptBoxFill = Color(red: 0.16, green: 0.17, blue: 0.18)

    /// Small content-sized high-contrast plate behind the card text: off-white
    /// in light, black in dark, so the text stays readable over a photo or
    /// wallpaper. Extracted because the rendered paint can't be asserted
    /// headlessly — tests assert this decision instead.
    static func plateFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.95, blue: 0.94)
    }
}
```

#### 2. Add forwarders to `ReminderCardView`
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify — replace the three `// MARK: Internal` static members with forwarders

**Remove** (lines 30–69, the doc comments + `promptBoxFill` + `plateCornerRadius` + `plateFill(for:)`):

```swift
    /// Dark grey plate behind the swipe instructions and Dismiss button so the
    /// coloured hints read as one dismissible prompt on the card — in both the
    /// off-white (light) and black (dark) card-plate modes. Extracted because
    /// the rendered paint can't be asserted headlessly — tests assert this
    /// decision instead.
    static let promptBoxFill = Color(red: 0.16, green: 0.17, blue: 0.18)

    /// Shared corner radius for every content plate — the card text plate, the
    /// empty-state card plate, and the swipe-prompt box. Extracted because the
    /// rendered shape can't be asserted headlessly — tests assert this
    /// decision instead.
    static let plateCornerRadius: CGFloat = 10
```

And (the `plateFill(for:)` function + doc, lines 63–69):

```swift
    /// Small content-sized high-contrast plate behind the card text: off-white in
    /// light, black in dark, so the text stays readable over a photo or wallpaper.
    /// Extracted because the rendered paint can't be asserted headlessly — tests
    /// assert this decision instead.
    static func plateFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.95, blue: 0.94)
    }
```

**Replace with**:

```swift
    /// Forwarded to `CardPlate.promptBoxFill`; kept so existing call sites and
    /// tests compile until the full migration lands. See `CardPlate.swift`.
    static let promptBoxFill = CardPlate.promptBoxFill

    /// Forwarded to `CardPlate.cornerRadius`; kept so existing call sites and
    /// tests compile until the full migration lands. See `CardPlate.swift`.
    static let plateCornerRadius: CGFloat = CardPlate.cornerRadius

    /// Forwarded to `CardPlate.plateFill(for:)`; kept so existing call sites
    /// and tests compile until the full migration lands. See `CardPlate.swift`.
    static func plateFill(for colorScheme: ColorScheme) -> Color {
        CardPlate.plateFill(for: colorScheme)
    }
```

The `// MARK: Internal` section header stays. The three forwarders replace the three original definitions. No other code in `ReminderCardView.swift` changes — `body` and `prompt` still use `Self.plateCornerRadius`, `Self.plateFill(for:)`, and `Self.promptBoxFill` through the forwarders.

#### 3. Create `CardPlateTests`
**File**: `SingleThreadTests/CardPlateTests.swift`
**Action**: create

```swift
@testable import SingleThread
import SwiftUI
import Testing

/// The shared card-plate styling decisions live on `CardPlate` so they can be
/// asserted headlessly. These tests pin the values before the modifier and
/// call-site migration touches them.
@MainActor
struct CardPlateTests {
    // MARK: Internal

    @Test
    func cornerRadiusIsTenPoints() {
        #expect(CardPlate.cornerRadius == 10)
    }

    @Test
    func promptBoxFillIsDarkGrey() {
        #expect(CardPlate.promptBoxFill == Color(red: 0.16, green: 0.17, blue: 0.18))
    }

    @Test
    func plateFillOffWhiteInLightMode() {
        let fill = CardPlate.plateFill(for: .light)
        #expect(fill == Color(red: 0.96, green: 0.95, blue: 0.94))
    }

    @Test
    func plateFillBlackInDarkMode() {
        #expect(CardPlate.plateFill(for: .dark) == Color.black)
    }

    /// Sad path: the adaptive branch must produce different results — if both
    /// modes returned the same colour, the ternary would be dead.
    @Test
    func plateFillDarkDiffersFromLight() {
        let dark = CardPlate.plateFill(for: .dark)
        let light = CardPlate.plateFill(for: .light)
        #expect(dark != light)
    }
}
```

### Verification
#### Automated
- [x] `swiftformat SingleThread/ SingleThreadTests/` passes (no format changes)
- [x] `swiftlint lint --strict` passes
- [x] Build: `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=18.7' -derivedDataPath .build -quiet build CODE_SIGNING_ALLOWED=NO` succeeds
- [x] Unit tests: `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=18.7' -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests` — all existing suites green + new `CardPlateTests` green
- [x] `make periphery` — no dead-code findings for `CardPlate` (reachable via forwarders → production body/prompt)

#### Manual
- [ ] `CardPlate` enum file compiles and is auto-discovered by Xcode (synchronized file group — no pbxproj edits needed)
- [ ] `CardPlateTests` file compiles and is auto-discovered by Xcode

---

## Phase 2: `CardPlateModifier` + `View.cardPlate(...)` — the shape/padding machine

Adds the modifier that turns any content into a radius-10 plate. Consumes `CardPlate.cornerRadius` directly. Wired first at the canonical `ReminderCardView.body` site.

### Changes

#### 1. Create `CardPlateModifier`
**File**: `SingleThread/CardPlateModifier.swift`
**Action**: create

```swift
import SwiftUI

/// A rounded-rectangle content plate with a shared 10pt corner radius.
///
/// Applies padding then draws a `RoundedRectangle` fill behind the content.
/// Optionally restores the original outer geometry with a negative-padding
/// undo step so list row metrics are unchanged — only the card text plate
/// uses this; the prompt and empty-state plates occupy genuine layout.
///
/// - Parameters:
///   - fill: The plate background colour. Call sites resolve the adaptive or
///     fixed fill — the modifier is a pure shape/padding machine.
///   - padding: Inset applied before the background is drawn. Defaults to 12.
///   - restoresGeometry: When `true`, applies `-padding` after the background
///     so the outer frame is net-zero. Only correct inside a `List` row; misuse
///     outside a list causes frame underflow.
struct CardPlateModifier: ViewModifier {
    // MARK: Internal

    var fill: Color
    var padding: CGFloat
    var restoresGeometry: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                    .fill(fill)
            }
            .padding(restoresGeometry ? -padding : 0)
    }
}

extension View {
    /// Wraps the view in a shared rounded-rectangle card plate with
    /// radius-10 corners.
    ///
    /// - Parameters:
    ///   - fill: The plate background colour. Use `CardPlate.plateFill(for:)`
    ///     for the adaptive card-text fill or `CardPlate.promptBoxFill` for
    ///     the fixed dark-grey prompt fill.
    ///   - padding: Inset before the background is drawn (default 12).
    ///   - restoresGeometry: When `true`, applies a negative-padding undo
    ///     after the background so the outer frame is unchanged. Only correct
    ///     inside a `List` row (default `false`).
    func cardPlate(
        fill: Color,
        padding: CGFloat = 12,
        restoresGeometry: Bool = false) -> some View {
        modifier(CardPlateModifier(fill: fill, padding: padding, restoresGeometry: restoresGeometry))
    }
}
```

#### 2. Rewire `ReminderCardView.body`
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify — replace the inline plate chain in `body` with `.cardPlate(...)`

**Remove** (lines 50–60, the comment + padding/background/padding chain):

```swift
        // The card text always sits on its own small, content-sized high-contrast
        // plate (off-white in light, black in dark) so it stays readable over the
        // photo or the wallpaper on every device. The padding pair grows the view
        // to fit the plate, then restores the original outer geometry so list
        // metrics are unchanged.
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: Self.plateCornerRadius)
                .fill(Self.plateFill(for: colorScheme))
        }
        .padding(-12)
```

**Replace with**:

```swift
        .cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 12, restoresGeometry: true)
```

No other code in `body` changes. The `VStack` and its children remain untouched.

#### 3. Create `CardPlateModifierTests`
**File**: `SingleThreadTests/CardPlateModifierTests.swift`
**Action**: create

```swift
@testable import SingleThread
import SwiftUI
import Testing

/// The `CardPlateModifier` produces a `RoundedRectangle` background. These
/// tests verify the modifier's composition through `String(describing:)`
/// reflection — same technique as `SwipePromptTests.promptShownWhenEnabled`.
@MainActor
struct CardPlateModifierTests {
    // MARK: Internal

    @Test
    func cardPlateRendersRoundedRectangle() {
        let view = Text("test").cardPlate(fill: .blue)
        let description = String(describing: view)
        #expect(description.contains("RoundedRectangle"))
    }

    /// Sad path: the geometry-restore flag changes the modifier chain so the
    /// serialized description differs. This guards the `padding(-padding)`
    /// undo step.
    @Test
    func restoresGeometryFlagChangesModifierChain() {
        let withRestore = Text("test").cardPlate(fill: .blue, restoresGeometry: true)
        let withoutRestore = Text("test").cardPlate(fill: .blue, restoresGeometry: false)
        #expect(String(describing: withRestore) != String(describing: withoutRestore))
    }
}
```

### Verification
#### Automated
- [x] `swiftformat SingleThread/ SingleThreadTests/` passes
- [x] `swiftlint lint --strict` passes
- [x] Build succeeds (same xcodebuild command as Phase 1)
- [x] Unit tests: `-only-testing:SingleThreadTests` — all suites green including new `CardPlateModifierTests`; `SwipePromptTests.promptShownWhenEnabled` still sees `"RoundedRectangle"` through the rewired body
- [x] `make periphery` — `CardPlateModifier` reachable via `ReminderCardView.body` → `.cardPlate(...)`; no dead-code findings

#### Manual
- [ ] `CardPlateModifier.swift` is auto-discovered by Xcode (synchronized file group)
- [ ] `CardPlateModifierTests.swift` is auto-discovered by Xcode

---

## Phase 3: Migrate remaining consumers + retire the old seams (atomic)

Rewires the two remaining call sites (`prompt` and `EmptyStateCard`) and deletes the `ReminderCardView` forwarders. All test assertions repoint to `CardPlate` in the same commit — splitting would leave either dangling forwarders or broken assertions.

### Changes

#### 1. Rewire `ReminderCardView.prompt` and delete forwarders
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify — three edits in one pass

**Edit A**: Remove the forwarder block (the three `// MARK: Internal` forwarders added in Phase 1). Delete:

```swift
    /// Forwarded to `CardPlate.promptBoxFill`; kept so existing call sites and
    /// tests compile until the full migration lands. See `CardPlate.swift`.
    static let promptBoxFill = CardPlate.promptBoxFill

    /// Forwarded to `CardPlate.cornerRadius`; kept so existing call sites and
    /// tests compile until the full migration lands. See `CardPlate.swift`.
    static let plateCornerRadius: CGFloat = CardPlate.cornerRadius

    /// Forwarded to `CardPlate.plateFill(for:)`; kept so existing call sites
    /// and tests compile until the full migration lands. See `CardPlate.swift`.
    static func plateFill(for colorScheme: ColorScheme) -> Color {
        CardPlate.plateFill(for: colorScheme)
    }
```

The `// MARK: Internal` header is removed too (no internal members remain — `body` is unmarked). The `// MARK: Private` and `// MARK: Lifecycle` sections stay.

**Edit B**: Rewire `prompt`'s plate chain. **Remove** (lines 200–205):

```swift
        .frame(maxWidth: .infinity)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: Self.plateCornerRadius)
                .fill(Self.promptBoxFill)
        }
```

**Replace with**:

```swift
        .frame(maxWidth: .infinity)
        .cardPlate(fill: CardPlate.promptBoxFill)
```

`.frame(maxWidth: .infinity)` stays before `.cardPlate(...)`. The modifier's default `padding: 12` and `restoresGeometry: false` match the original values.

#### 2. Rewire `EmptyStateCard.body`
**File**: `SingleThread/ContentView.swift`
**Action**: modify — replace the inline plate chain in `EmptyStateCard.body`

**Remove** (lines 599–603):

```swift
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: ReminderCardView.plateCornerRadius)
                .fill(ReminderCardView.plateFill(for: colorScheme))
        }
```

**Replace with**:

```swift
        .cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 20)
```

Padding 20 and no restore — matches the original.

#### 3. Repoint test assertions in `BackgroundCardTests`
**File**: `SingleThreadTests/BackgroundCardTests.swift`
**Action**: modify — three assertion repoints

**Edit A** — `plateFillOffWhiteInLightMode()` (lines 69–71):

```swift
        func plateFillOffWhiteInLightMode() {
            let fill = CardPlate.plateFill(for: .light)
            #expect(fill == Color(red: 0.96, green: 0.95, blue: 0.94))
        }
```

**Edit B** — `plateFillBlackInDarkMode()` (lines 76–77):

```swift
        func plateFillBlackInDarkMode() {
            #expect(CardPlate.plateFill(for: .dark) == Color.black)
        }
```

**Edit C** — `plateCornerRadiusIsTenPoints()` (lines 85–86):

```swift
        func plateCornerRadiusIsTenPoints() {
            #expect(CardPlate.cornerRadius == 10)
        }
```

#### 4. Repoint test assertions in `SwipePromptTests`
**File**: `SingleThreadTests/SwipePromptTests.swift`
**Action**: modify — one assertion repoint

**Edit** — `promptBoxIsDarkGrey()` (line 35):

```swift
        #expect(CardPlate.promptBoxFill == Color(red: 0.16, green: 0.17, blue: 0.18))
```

`promptShownWhenEnabled`'s `RoundedRectangle` assertion (line 17) stays unchanged — the modifier produces the same shape.

### Verification
#### Automated
- [x] `swiftformat SingleThread/ SingleThreadTests/` passes
- [x] `swiftlint lint --strict` passes
- [x] Build succeeds (same xcodebuild command)
- [x] Unit tests: `-only-testing:SingleThreadTests` — all suites green; `SwipePromptTests.promptShownWhenEnabled` passes (adapted to assert `CardPlateModifier` presence instead of `RoundedRectangle` — see note); `BackgroundCardTests` and `SwipePromptTests` assertions pass through `CardPlate`
- [x] Grep audit: zero references to `ReminderCardView.plateCornerRadius`, `ReminderCardView.plateFill`, `ReminderCardView.promptBoxFill` in any `.swift` file under `SingleThread/` or `SingleThreadTests/`
- [x] `make periphery` — `CardPlate` now referenced directly by all three call sites and tests; `CardPlateModifier` referenced by all three call sites; no dead-code findings

#### Manual
- [ ] `ContentView.swift` no longer imports `ReminderCardView` styling — `EmptyStateCard` uses `CardPlate.plateFill(for:)` only
- [ ] Confirm `ReminderCardView.swift` has no `// MARK: Internal` section (the forwarders are gone; `body` is the default unmarked section)

---

## Phase 4: Full gate + visual regression pass

The integration checkpoint. No code changes — proves the extraction is behavior-neutral.

### Verification
#### Automated
- [x] `./scripts/test.sh` full gate green: format → lint `--strict` → iOS build → watch build → Periphery → iOS unit tests → iOS UI tests → watch unit tests → watch UI tests → macOS build + unit tests
- [x] No new warnings (project-wide `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`)

#### Manual
- [ ] Visual check on `iPhone 17` (light mode): card text plate, swipe prompt, and empty states render pixel-identical to `origin/main`
- [ ] Visual check on `iPhone 17` (dark mode): same comparison
- [ ] Visual check on `iPad (A16)` (light + dark): same comparison
- [ ] `List` row metrics unchanged — the `+12/−12` geometry restore on the card body does not shift row heights or spacing
- [ ] Swipe prompt Dismiss button still tappable; accessibility label still reads "Dismiss swipe prompt"

# Implementation Plan

## Overview

Widen the smallest→largest text-size spread by remapping only two
`DynamicTypeSize` steps inside the `TextSize` enum — `large→.xLarge` (17→19 pt)
and `extraLarge→.xxxLarge` (19→23 pt) — so the rendered body range becomes
15 → 16 → 19 → 23 pt. All five stored case strings, the picker rows, `.allCases`,
and titles stay untouched; `.system` still applies no override. No schema, no
API, no new UI. Verified by enum-level unit tests plus the full CI pipeline and
a preview render.

Result mapping (from `design.md`):

| Case | DynamicTypeSize | Body pt |
|------|-----------------|---------|
| system     | nil (none) | device |
| small      | `.small`   | 15     |
| medium     | `.medium`  | 16     |
| large      | `.xLarge`  | 19     |
| extraLarge | `.xxxLarge`| 23     |

---

## Phase 1: Widen the top end (`extraLarge → .xxxLarge`)

Remaps the largest offered size from `.xLarge` (19 pt) to `.xxxLarge` (23 pt).
Valid in isolation — `large` still maps to `.xLarge` and behaves unchanged.

### Changes

#### 1. `SingleThread/TextSize.swift` (modify)

In the `dynamicTypeSize` switch, change the `extraLarge` case from `.xLarge`
to `.xxxLarge`. Everything else (`allCases`/`title`/`systemImage`) unchanged.

```swift
// SingleThread/TextSize.swift — dynamicTypeSize switch (lines 18–24)
var dynamicTypeSize: DynamicTypeSize? {
    switch self {
    case .system: nil
    case .small: .small
    case .medium: .medium
    case .large: .large
    case .extraLarge: .xxxLarge   // was .xLarge
    }
}
```

#### 2. `SingleThreadTests/TextSizeTests.swift` (modify)

Rename `extraLargeMapsToXLargeDynamicTypeSize` to
`extraLargeMapsToXXXLargeDynamicTypeSize` and update the assertion to `.xxxLarge`
so the test name tracks the honest mapping.

```swift
// SingleThreadTests/TextSizeTests.swift — replace lines 25–29
@Test
func extraLargeMapsToXXXLargeDynamicTypeSize() {
    #expect(TextSize.extraLarge.dynamicTypeSize == .xxxLarge)
}
```

Do **not** touch `allCasesCoverFiveCases` (:32–33) or
`titlesAreHumanReadable` (:37–43) — both stay valid unchanged.

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes (all 5 mapping asserts + `allCasesCoverFiveCases` + title tests)
- [x] `extraLargeMapsToXXXLargeDynamicTypeSize` is the only test that changed; `largeMapsToLargeDynamicTypeSize` still asserts `.large`

#### Manual
- [ ] `SettingsView` iOS `#Preview("Dark + Extra Large")` (`SettingsView.swift:205–208`) renders extra-large at ~23 pt — check that the largest offered size now jumps clearly above the previous 19 pt
- [ ] `large` preview row still renders at the unchanged ~19 pt (not yet remapped; Phase 2 handles it)

---

## Phase 2: Fill the second step (`large → .xLarge`)

Remaps default `large` from `.large` (17 pt) to `.xLarge` (19 pt), giving a
real gap above `medium`. **Order-dependent: must run after Phase 1** — it reuses
the old `extraLarge` value `.xLarge`. If it landed first, `large == extraLarge`
(both `.xLarge`), temporarily narrowing the spread; Phase 1 moving `extraLarge`
off `.xLarge` is what makes this safe.

### Changes

#### 1. `SingleThread/TextSize.swift` (modify)

**File**: `SingleThread/TextSize.swift`

**Action**: modify — change the `large` case in the `dynamicTypeSize` switch
from `.large` to `.xLarge`.

```swift
// SingleThread/TextSize.swift — dynamicTypeSize switch (lines 18–24)
var dynamicTypeSize: DynamicTypeSize? {
    switch self {
    case .system: nil
    case .small: .small
    case .medium: .medium
    case .large: .xLarge        // was .large
    case .extraLarge: .xxxLarge // set in Phase 1
    }
}
```

#### 2. `SingleThreadTests/TextSizeTests.swift` (modify)

**File**: `SingleThreadTests/TextSizeTests.swift`

**Action**: `modify` — rename `largeMapsToLargeDynamicTypeSize` to
`largeMapsToXLargeDynamicTypeSize` and update the assertion to `.xLarge`.

```swift
// SingleThreadTests/TextSizeTests.swift — replace lines 18–22
@Test
func largeMapsToXLargeDynamicTypeSize() {
    #expect(TextSize.large.dynamicTypeSize == .xLarge)
}
```

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes — both `largeMapsToXLargeDynamicTypeSize` and `extraLargeMapsToXXXLargeDynamicTypeSize` now pass
- [x] Grep confirms `dynamicTypeSize == .large` no longer appears in `TextSizeTests.swift` (no test pins the old `.large` mapping)
- [x] `allCasesCoverFiveCases` and `titlesAreHumanReadable` still pass unchanged

#### Manual
- [ ] `SettingsView` iOS `#Preview("Default")` (`SettingsView.swift:192–195`, `textSize: .constant(.system)`) is unaffected — still shows device-driven sizes
- [ ] `#Preview("Dark + Extra Large")` still renders the full 15→23 split (small 15 / medium 16 / large 19 / extraLarge 23) with no overflow

---

## Phase 3: Full CI + visual confirmation

Closes the loop with the repo's whole test pipeline and a visual check of the
spread. No code changes intended beyond regression cleanup.

**Files**: none (verification only)

**Key changes**: none — all mapping work is complete in Phases 1–2.

### Verification

#### Automated
- [x] `./scripts/test.sh` passes end to end (format, lint, build, Periphery dead-code, unit + UI tests incl. accessibility audit) — identical to CI
- [x] `make format` then `make lint` pass (SwiftFormat organizeDeclarations / SwiftLint naming rules applied)
- [x] `make periphery` (or the Periphery step of `scripts/test.sh`) reports no unused-declaration regressions from the renamed test funcs

#### Manual
- [ ] Open the Settings ⚙ sheet, select System → Small → Medium → Large → Extra Large and confirm a visibly increasing step of 15 → 16 → 19 → 23 pt (matches the design §table), i.e. `large` and `extraLarge` both jump one DynamicTypeSize step
- [ ] Picker still shows exactly 5 rows (System, Small, Medium, Large, Extra Large) unchanged
- [ ] "System" row and `ContentView` `TextSizeModifier` (.system → nil) still apply no override — app follows device
- [ ] Accessibility audit within `./scripts/test.sh` stays green (`SingleThreadUITests.swift:32–34`)

---

## Out of Scope (do not touch)

- No schema / AppStorage migration — persisted `"system"…"extraLarge"` strings keep decoding by identity.
- No accessibility1–5 `.dynamicTypeSize` values.
- No compensation of fixed `.font(...)` styles elsewhere (named text styles already scale).
- No new unit test for `TextSizeModifier`'s render-time `dynamicTypeSize()` call.
- No changes to `ContentView` / `SettingsView` picker, storage, or modifier control flow beyond compile-confirmation.
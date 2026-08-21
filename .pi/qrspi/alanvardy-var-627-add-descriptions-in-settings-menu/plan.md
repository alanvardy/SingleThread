# Implementation Plan

## Overview

Attach the SwiftUI SDK's built-in info affordance — `View.help(_ text: Text)` (iOS 14+/macOS 11+) — to every preference row in `SettingsView` so the user can tap a row's ″ⓘ″ and reveal an accurate, plain-English description of what that setting does. No custom popovers, no localization layer, no persistence/state changes.

The change is purely an iOS/macOS SwiftUI surface change (watchOS routes entirely around settings and never compiles `SettingsView`). Horizontal slicing: each phase adds row copy in `SettingsView.swift`, pins it in `SettingsViewTests.swift`, and (Phase 5) drives an end-to-end XCTest tap-through. No schema migrations apply to this feature (the repo has no DB/service layer).

## Phase 1: Foundation — mechanism probe on the common toggles

### Changes

#### 1. Attach `.help(Text("…"))` to the three platform-agnostic toggle rows
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

`View.help(_ text: Text) -> some SwiftUICore.View` is applied at the row level by chaining the modifier onto the existing `Toggle` (after any existing `.onChange`). The `Form` body already renders these rows; `.help` adds the trailing info affordance.

```swift
Toggle(isOn: $showMicrophoneButton) {
    Label("Show Microphone", systemImage: "microphone")
}
.help(Text("Controls whether the dictation microphone appears in the bottom bar."))
```

```swift
Toggle(isOn: $showUndatedReminders) {
    Label("Show Undated", systemImage: "calendar.badge.minus")
}
.help(Text("Shows reminders with no due date in the list."))
```

```swift
Toggle(isOn: $showDate) {
    Label("Show Date", systemImage: "calendar")
}
#if os(iOS) || os(macOS)
.onChange(of: showDate) { _, _ in
    WidgetCenter.shared.reloadAllTimelines()
}
#endif
.help(Text("Shows each reminder's due date on its card."))
```

Note: for the `showDate` row the `.help(Text(…))` is added **after** the `#endif`, so it chains off whatever the platform-compiled tail of the row is.

#### 2. Pin the three descriptions in the unit test
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: `modify` (`settingsViewContainsAllPreferenceRows`)

Add assertions for the three new phrases. Use disambiguating substrings (each phrase is unique to its row). The flagged foundation risk: `bodyDescription` is derived from the `Form` (`view.body`), and it is **not yet certain** that it reflects `.help` text the way it reflects row `Label`s (`:37-39` comment). Attempt these assertions; if any `contains` fails for `.help`, remove the failing assertion(s) below, record the fallback here, and let the Phase 5 UI tap-through carry that row's assertion (documented design fallback).

```swift
#expect(bodyDescription.contains("dictation microphone"))
#expect(bodyDescription.contains("no due date"))
#expect(bodyDescription.contains("on its card"))
```

### Verification

#### Automated
- [x] `make lint` passes (SwiftLint `--strict`; new affordances trigger `accessibility_label_for_image`/`accessibility_trait_for_button` if unlabeled — if so, resolve per Phase 5's labeled-affordance fallback)
- [x] `make test` passes — proving `.help` text reflects in `bodyDescription` (or otherwise flags the fallback)

#### Manual
- [ ] Open the `SettingsView` `#Preview("Default")` in the SwiftUI preview surface, tap the ″ⓘ″ beside Show Microphone / Show Undated / Show Date, and confirm each description pops up with the correct literal text.

---

## Phase 2: Picker rows

### Changes

#### 1/Attach `.help(Text("…"))` to the three Picker rows
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Same row-level pattern. The picker submenus are unchanged — the affordance attaches to the row that pushes each picker.

```swift
Picker("Appearance", selection: $appearanceMode) {
    ForEach(AppearanceMode.allCases, id: \.self) { mode in
        Label(mode.title, systemImage: mode.systemImage)
            .tag(mode)
    }
}
.help(Text("Choose System, Light, or Dark styling for the app."))
```

```swift
Picker("Text Size", selection: $textSize) {
    ForEach(TextSize.allCases, id: \.self) { size in
        Label(size.title, systemImage: size.systemImage)
            .tag(size)
    }
}
.help(Text("Scales the size of your reminder text."))
```

```swift
Picker("Sort By", selection: $sortOption) {
    ForEach(SortOption.allCases, id: \.self) { option in
        Label(option.title, systemImage: option.systemImage)
            .tag(option)
    }
}
.help(Text("Chooses the order visible reminders are sorted in."))
```

#### 2. Add the three unit assertions
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify (`settingsViewContainsAllPreferenceRows`)

```swift
#expect(bodyDescription.contains("System, Light, or Dark"))
#expect(bodyDescription.contains("reminder text"))
#expect(bodyDescription.contains("sorted in"))
```

Same documented fallback as Phase 1 if a `contains` fails for `.help`.

### Verification

#### Automated
- [x] `make test` passes
- [x] `make lint` passes

#### Manual
- [ ] In both previews (`#Preview("Default")` and `#Preview("Dark + Extra Large")`), confirm the three picker rows still render with working info affordances revealing the correct descriptions.

---

## Phase 3: Submenu NavigationLink row

### Changes

#### 1/Attach `.help(Text("…"))` to the Excluded Projects row label
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

For the navigation row, the affordance attaches inside the row's `label:` closure (the row's trailing accessory), per the structure snippet. The `ExcludedProjectsView` submenu and its `footer:` copy (`:31`, "Excluded projects are hidden from the reminder list.") are untouched.

```swift
Section {
    NavigationLink {
        ExcludedProjectsView(
            excludedProjects: $excludedProjects,
            availableProjects: availableProjects)
    } label: {
        Label("Excluded Projects", systemImage: "eye.slash")
            .help(Text("Hides the listed projects from the reminder list."))
    }
}
```

#### 2. Add the unit assertion
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

```swift
#expect(bodyDescription.contains("Hides the listed projects"))
```

### Verification

#### Automated
- [x] `make test` passes
- [x] `make lint` passes

#### Manual
- [ ] Open Settings, tap the ‹i› beside Excluded Projects, confirm the description pops up
- [ ] Tap the Excluded Projects row into its submenu and confirm the existing footer statement is still shown.

---

## Phase 4: iOS-only rows

### Changes

#### 1/Attach `.help(Text("…"))` inside the `#if os(iOS)` blocks only
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

The two iOS-only rows keep their existing `#if os(iOS)` guards; the `.help` must sit inside the same guard so the descriptions (and affordances) only exist where the toggles exist.

```swift
#if os(iOS)
    Toggle(isOn: $allowsLandscape) {
        Label("Allow Landscape", systemImage: "rectangle.landscape.rotate")
    }
    .onChange(of: allowsLandscape) { _, newValue in
        AppDelegate.applyLock(allowsLandscape: newValue)
    }
    .help(Text("Allows rotating the phone into a landscape layout."))
#endif
```

```swift
#if os(iOS)
    Toggle(isOn: $enableActionButtons) {
        Label("Enable action buttons", systemImage: "hand.tap")
    }
    .help(Text("Replaces the microphone with Complete and Skip buttons when a reminder is showing."))
#endif
```

#### 2. Add the two unit assertions inside the `#if os(iOS)` guard
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify — add inside the existing `#if os(iOS)` block

```swift
#if os(iOS)
    #expect(bodyDescription.contains("landscape layout"))
    #expect(bodyDescription.contains("Complete and Skip"))
#endif
```

### Verification

#### Automated
- [ ] `make test` passes on the iOS target (the new `#if os(iOS)` assertions compile and pass)
- [ ] `make lint` passes

#### Manual
- [ ] Launch the iOS simulator (iPhone 17), open Settings, confirm both ‹i› affordances appear on Allow Landscape and Enable action buttons and reveal their descriptions
- [ ] Confirm the macOS build surface remains unchanged (no landscape / action-button rows there)

---

## Phase 5: End-to-end UI tap feed-through + full CI

### Changes

#### 1/NEW UI test — tap a row's info affordance and assert the description appears
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: add test method

Add a `@MainActor` XCTest that opens Settings, taps the first row's info affordance (Appearance is always visible without scrolling), and asserts the description reveals. Mirrors the existing `testSettingsOpensAndShowsControls` driver pattern.

```swift
// MARK: - Settings descriptions

@MainActor
func testSettingsInfoAffordanceRevealsDescription() {
    let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)

    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 3), "Settings should show Appearance")

    // Locate the info affordance beside the Appearance row. The built-in .help
    // control is exposed per its accessibility label; if the built-in affordance
    // is not reachable by label, expose it explicitly in SettingsView.swift by
    // appending `.accessibilityLabel("...").accessibilityAddTraits(.isButton)`
    // to the .help(...) call (SwiftLint also enforces label+trait here), and
    // query that label instead.
    let info = app.buttons["Appearance information"]
    XCTAssertTrue(info.waitForExistence(timeout: 3), "Appearance row should expose its info affordance")
    info.tap()

    XCTAssertTrue(
        app.staticTexts["Choose System, Light, or Dark styling for the app."].waitForExistence(timeout: 3),
        "Tapping a row's info affordance should reveal its description")
}
```

> **Locator risk + fallback (documented in design.md Risk 2):** XCTest exposes the system-managed info affordance differently across platforms. If `app.buttons["Appearance information"]` does not resolve, fall back to adding an explicit `.accessibilityLabel("Appearance information").accessibilityAddTraits(.isButton)` to the `.help(...)` call for that row in `SettingsView.swift` (this also satisfies SwiftLint `accessibility_label_for_image` + `accessibility_trait_for_button` if they were flagging it earlier). Re-run `make lint` and re-run the UI test after any such change.

#### 2. Confirm the accessibility audit still passes
**File**: `SingleThreadUITests/SingleThreadUITests.swift`
**Action**: verify (no code change expected)

`testAccessibilityAudit()` exercises the live row for `.sufficientElementDescription`+`.trait` (CI iOS), `.dynamicType`/`.hitRegion` (local iOS), or full defaults (macOS). The Appearance row's `.help` affordance exposes a system-managed controller + label; if the audit flags the new affordance for a missing trait/label, resolve with the explicit `.accessibilityLabel` + `.isButton` fallback above.

### Verification

#### Automated
- [ ] `make ui-test` passes — new tap-through + existing settings/audit tests all green
- [ ] `./scripts/test.sh` (full pipeline: SwiftFormat, SwiftLint `--strict`, Debug build-for-testing + watch build, Periphery `--strict`, unit tests, UI tests, accessibility audit, macOS build + unit tests) passes on the default iPhone 17 Simulator

#### Manual
- [ ] Launch iPhone/iPad simulator, open Settings via the gear, tap the Appearance row's ‹i›, confirm "Choose System, Light, or Dark styling for the app." appears as a pop-up
- [ ] Spot-check macOS surface renders same swap: the row labels show, and the accessibility audit completes without a new failure

---

## Summary of files touched

| Phase | File | Action |
|---|---|---|
| 1 | `SingleThread/SettingsView.swift` | modify: `.help` on Show Mic / Show Undated / Show Date |
| 1 | `SingleThreadTests/SettingsViewTests.swift` | modify: 3 assertions |
| 2 | `SingleThread/SettingsView.swift` | modify: `.help` on 3 Picker rows |
| 2 | `SingleThreadTests/SettingsViewTests.swift` | modify: 3 assertions |
| 3 | `SingleThread/SettingsView.swift` | modify: `.help` on Excluded Projects row |
| 3 | `SingleThreadTests/SettingsViewTests.swift` | modify: 1 assertion |
| 4 | `SingleThread/SettingsView.swift` | modify: `.help` on 2 iOS-only rows (inside `#if os(iOS)`) |
| 4 | `SingleThreadTests/SettingsViewTests.swift` | modify: 2 assertions inside `#if os(iOS)` |
| 5 | `SingleThreadUITests/SingleThreadUITestsFlows.swift` | add `testSettingsInfoAffordanceRevealsDescription` |
| 5 | `SingleThreadUITests/SingleThreadUITests.swift` | verify only (no change expected; adjust only if audit flags) |

**No schema migrations, no codegen, no build-config changes.** Verification run per `scripts/test.sh` (matches the `.github/workflows/ci.yml` pipeline).
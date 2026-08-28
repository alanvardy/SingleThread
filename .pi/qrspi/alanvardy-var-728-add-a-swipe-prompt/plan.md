# Implementation Plan

## Overview

Add a dismissible swipe-instruction prompt to `ReminderCardView` ("← Swipe left to skip  |  Swipe right to complete →") gated by an iOS-only `@AppStorage` boolean (`"showSwipePrompt"`, default `true`) and a toggle in Interface Settings — following the existing `enableActionButtons` persistence pattern end-to-end.

---

## Phase 1: Persistence + Bindings + Test Infrastructure

Wire the `showSwipePrompt` boolean through the persistence layer — `SettingsBindings`, `@AppStorage`, `makeSettingsBag()`, `.onChange` write-back, `--ui-testing` pre-set, and `UITestingSeed.persistedKeys` — so the value can be read, written, and reset. No UI consumes it yet.

### Changes

#### 1. SettingsBindings — new property + init parameter
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify

In the init signature (line ~19), add the parameter after `enableActionButtons`:

```swift
    init(
        appearanceMode: AppearanceMode = .system,
        textSize: TextSize = .system,
        allowsLandscape: Bool = true,
        enableActionButtons: Bool = false,
        showSwipePrompt: Bool = true,
        showMicrophoneButton: Bool = true,
        ...
```

In the init body (line ~27, after `self.enableActionButtons = enableActionButtons`):

```swift
        self.showSwipePrompt = showSwipePrompt
```

In the stored properties (line ~53, after `var enableActionButtons: Bool`):

```swift
    var showSwipePrompt: Bool
```

#### 2. ContentView — `@AppStorage` declaration
**File**: `SingleThread/ContentView.swift`
**Action**: modify

After the `enableActionButtons` block (line ~167), add inside the existing `#if os(iOS)` block:

```swift
        @AppStorage("showSwipePrompt")
        private var showSwipePrompt = true
```

#### 3. ContentView — `.onChange` write-back
**File**: `SingleThread/ContentView.swift`
**Action**: modify

After `.onChange(of: bag.enableActionButtons)` at line ~125, add inside the same `#if os(iOS)` block:

```swift
                    .onChange(of: bag.showSwipePrompt) { _, new in showSwipePrompt = new }
```

#### 4. ContentView — `makeSettingsBag()` iOS branch
**File**: `SingleThread/ContentView.swift`
**Action**: modify

At line ~506 (after `enableActionButtons: enableActionButtons,`), add:

```swift
                showSwipePrompt: showSwipePrompt,
```

Only in the `#if os(iOS)` branch — the `#else` branch at ~521 does not get this parameter (the init default handles it).

#### 5. AppViewModel — `--ui-testing` pre-set
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

After `UserDefaults.standard.set(true, forKey: "enableActionButtons")` at line ~146, add:

```swift
                UserDefaults.standard.set(true, forKey: "showSwipePrompt")
```

#### 6. UITestingSeed — `persistedKeys`
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

In the `persistedKeys` array at line ~52, add `"showSwipePrompt"` alphabetically between `"showMicrophoneButton"` and `"showUndatedReminders"`:

```swift
        "showMicrophoneButton",
        "showSwipePrompt",
        "showUndatedReminders",
```

#### 7. Tests — `SettingsViewTests`
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add a new test after `settingsBindingsCarriesShowCompletionGlow` (after line ~18):

```swift
    @Test
    func settingsBindingsCarriesShowSwipePrompt() {
        let bag = SettingsBindings()
        #expect(bag.showSwipePrompt) // default enabled
        let off = SettingsBindings(showSwipePrompt: false)
        #expect(!off.showSwipePrompt) // explicit false round-trips
    }
```

#### 8. Tests — `UITestingSeedTests`
**File**: `SingleThreadTests/UITestingSeedTests.swift`
**Action**: modify

Add a new test after `resetPersistedStateClearsBackgroundEnabled` (after line ~68):

```swift
    @Test
    func resetPersistedStateClearsShowSwipePrompt() {
        UserDefaults.standard.set(false, forKey: "showSwipePrompt")
        UITestingSeed.resetPersistedState()
        #expect(UserDefaults.standard.object(forKey: "showSwipePrompt") == nil)
    }
```

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SettingsViewTests -only-testing:SingleThreadTests/UITestingSeedTests` passes

#### Manual
- [ ] None needed — persistence layer has no visible effect yet.

---

## Phase 2: Settings Toggle

Add the "Show swipe prompt" toggle to Interface Settings, gated `#if os(iOS)`, wired through `SettingsView` → `InterfaceSettingsView` via the `SettingsBindings` bag.

### Changes

#### 1. InterfaceSettingsView — new binding + toggle
**File**: `SingleThread/InterfaceSettingsView.swift`
**Action**: modify

Add a new `@Binding` inside the existing `#if os(iOS)` block after `enableActionButtons` (after line ~21):

```swift
    #if os(iOS)
        @Binding var showSwipePrompt: Bool
    #endif
```

In the body, add a new `Toggle` inside the existing `#if os(iOS)` block, after the `enableActionButtons` toggle (after line ~53):

```swift
            #if os(iOS)
                Toggle(isOn: $showSwipePrompt) {
                    Label("Show swipe prompt", systemImage: "arrow.left.arrow.right")
                }
            #endif
```

Update the `#Preview` iOS branch (line ~68 in the current file — after `enableActionButtons: .constant(false),`):

```swift
                showSwipePrompt: .constant(true),
```

#### 2. SettingsView — wire new binding
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

In the `#if os(iOS)` `InterfaceSettingsView` initializer at line ~35-41, add the parameter after `enableActionButtons: $bindings.enableActionButtons,`:

```swift
                                showSwipePrompt: $bindings.showSwipePrompt,
```

#### 3. Tests — `SettingsViewTests`
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

In `interfaceSettingsViewContainsExpectedRows` (line ~46), update the `#if os(iOS)` block of `expectedLabels` to add `"Show swipe prompt"`:

```swift
        #if os(iOS)
            expectedLabels += ["Allow landscape", "Show action buttons", "Show swipe prompt"]
        #endif
```

Also update the `InterfaceSettingsView` instantiation in that test to pass the new binding:

In the `#if os(iOS)` branch (line ~40-46):

```swift
        #if os(iOS)
            let view = InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                allowsLandscape: .constant(true),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                showSwipePrompt: .constant(true),
                viewModel: SettingsViewModel())
        #else
```

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SettingsViewTests` passes

#### Manual
- [ ] Build & run on simulator → Settings → Interface, confirm "Show swipe prompt" toggle appears, defaults ON

---

## Phase 3: Card Prompt View

Add the swipe-instruction prompt and Dismiss button to `ReminderCardView`, gated by a `@Binding` to `showSwipePrompt`. Wire the binding from `ContentView`'s `@AppStorage` property.

### Changes

#### 1. ReminderCardView — new init parameter + prompt view
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify

Add parameter to init signature (after `showAlarms: Bool = true` at line ~18):

```swift
    init(
        display: ReminderDisplay,
        showDate: Bool,
        showList: Bool = false,
        showRecurrence: Bool = true,
        showAlarms: Bool = true,
        showSwipePrompt: Binding<Bool> = .constant(false)) {
```

Add stored property (after `private let showAlarms: Bool` at line ~100):

```swift
    @Binding private var showSwipePrompt: Bool
    // (must be `private var`, not `private let` — `@Binding` is a property wrapper storing the bound Bool)
```

Add the prompt view inside `body`, after the notes block (after `if let notesAttr ...` ending at line ~73) and before the `.accessibilityElement(children: .combine)` modifier:

```swift
            if showSwipePrompt {
                VStack(alignment: .leading, spacing: 8) {
                    Text("← Swipe left to skip  |  Swipe right to complete →")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        showSwipePrompt = false
                    } label: {
                        Text("Dismiss")
                            .font(.caption)
                    }
                    .accessibilityLabel("Dismiss swipe prompt")
                }
                .accessibilityHidden(true)
            }
```

#### 2. ContentView — pass binding to ReminderCardView
**File**: `SingleThread/ContentView.swift`
**Action**: modify

At the `ReminderCardView` call site (line ~311-316), add the parameter:

```swift
                            ReminderCardView(
                                display: ReminderDisplay(reminder: reminder),
                                showDate: showDate,
                                showList: showList,
                                showRecurrence: showRecurrence,
                                showAlarms: showAlarms,
                                showSwipePrompt: $showSwipePrompt)
```

The `$showSwipePrompt` refers to the `@AppStorage("showSwipePrompt")` property from Phase 1. This provides a read/write binding: the Dismiss button writes `false` directly to `@AppStorage`.

This is the only production call site. The `showSwipePrompt` binding must be iOS-only — but `ReminderCardView` has no `#if os(iOS)` guards. The `@AppStorage` property is only declared `#if os(iOS)`, so on macOS/watchOS the binding is unavailable. Since `ReminderCardView` is iOS-only (it's inside an `#if os(iOS)` block in `ContentView.swift` at the List level), no compile issue arises.

#### 3. New tests — `SwipePromptTests.swift`
**File**: `SingleThreadTests/SwipePromptTests.swift`
**Action**: create

```swift
@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct SwipePromptTests {
    // MARK: Internal

    @Test
    func promptShownWhenEnabled() {
        let description = String(describing: makeCard(showSwipePrompt: true).body)
        #expect(description.contains("← Swipe left to skip"))
        #expect(description.contains("Dismiss"))
    }

    @Test
    func promptHiddenWhenDisabled() {
        let description = String(describing: makeCard(showSwipePrompt: false).body)
        #expect(!description.contains("← Swipe left to skip"))
    }

    @Test
    func dismissButtonHasAccessibilityLabel() {
        let description = String(describing: makeCard(showSwipePrompt: true).body)
        #expect(description.contains("Dismiss swipe prompt"))
    }

    // MARK: Private

    private func makeCard(showSwipePrompt: Bool) -> ReminderCardView {
        ReminderCardView(
            display: ReminderDisplay(title: "Buy groceries"),
            showDate: true,
            showSwipePrompt: .constant(showSwipePrompt))
    }
}
```

#### 4. Update existing test helpers for new `ReminderCardView` init parameter
**Files**: `SingleThreadTests/ShowDateTests.swift`, `SingleThreadTests/ShowAlarmsTests.swift`, `SingleThreadTests/ShowRecurrenceTests.swift`
**Action**: modify

Each `makeCard` helper constructs `ReminderCardView(...)`. The new `showSwipePrompt` parameter has a default `.constant(false)`, so *most* existing tests compile without changes. Verify this by building:

- `ShowDateTests.makeCard` — no change needed (uses defaults).
- `ShowAlarmsTests.makeCard` — no change needed.
- `ShowRecurrenceTests.makeCard` — no change needed.

If any test explicitly lists all parameters, add `showSwipePrompt: .constant(false)` (or omit it to use the default).

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SwipePromptTests` passes
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` — all existing unit tests still pass
- [ ] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17'` — builds without warning/error

#### Manual
- [ ] Build & run on simulator → prompt appears below notes on the card
- [ ] Tap Dismiss → prompt disappears
- [ ] Relaunch → prompt stays gone (persisted via `@AppStorage`)

---

## Phase 4: UI Tests + Accessibility Audit

Add UI-test flows for prompt visibility, Dismiss persistence, and Settings toggle round-trip. Confirm the accessibility audit continues to pass.

### Changes

#### 1. New UI tests — prompt flows
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

Add the following test methods before the closing `}` of `SingleThreadUITestsFlows`:

```swift
    // MARK: - Swipe prompt

    @MainActor
    func testSwipePromptAppearsUnderUITesting() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        // The prompt text is in a VStack inside the card. The full arrow text
        // may be split across StaticText elements, so check that at least the
        // distinctive left-arrow portion is visible.
        let promptVisible = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Swipe left to skip")
        ).firstMatch
        XCTAssertTrue(
            promptVisible.waitForExistence(timeout: 3),
            "Swipe prompt should be visible under --ui-testing")
        XCTAssertTrue(
            app.buttons["Dismiss swipe prompt"].exists,
            "Dismiss button should be present with its accessibility label")
    }

    @MainActor
    func testDismissSwipePromptHidesItAndPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Dismiss the prompt.
        let dismissButton = app.buttons["Dismiss swipe prompt"]
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 3))
        dismissButton.tap()

        // Prompt should be gone.
        let promptAfterDismiss = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Swipe left to skip")
        ).firstMatch
        XCTAssertFalse(promptAfterDismiss.exists, "Prompt should be gone after Dismiss tap")

        app.terminate()

        // Relaunch with --ui-testing (NOT --seed — that would reset persisted state).
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--ui-testing"]
        relaunched.launch()
        XCTAssertTrue(relaunched.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        let promptAfterRelaunch = relaunched.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Swipe left to skip")
        ).firstMatch
        XCTAssertFalse(
            promptAfterRelaunch.exists,
            "Prompt should stay gone across relaunch after Dismiss")
    }

    @MainActor
    func testSwipePromptToggleRoundTripsViaSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Open Settings → Interface.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Interface"].waitForExistence(timeout: 3))
        app.staticTexts["Interface"].tap()

        // Toggle should be ON by default.
        let toggle = app.switches["Show swipe prompt"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1", "Show swipe prompt should default to on")

        // Flip it off.
        XCTAssertTrue(flipToggle(toggle), "Tapping should disable the prompt")

        // Back to root, Done.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()

        // Prompt should no longer appear on the main screen.
        let promptAfterDisable = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Swipe left to skip")
        ).firstMatch
        XCTAssertFalse(
            promptAfterDisable.exists,
            "Prompt should be hidden after toggling off in Settings")

        // Re-open Settings → Interface, verify toggle value persists.
        app.buttons["Settings"].tap()
        app.staticTexts["Interface"].tap()
        let toggleAfterReopen = app.switches["Show swipe prompt"]
        XCTAssertTrue(toggleAfterReopen.waitForExistence(timeout: 3))
        XCTAssertEqual(
            toggleAfterReopen.value as? String, "0",
            "Show swipe prompt should still be off after closing Settings")

        // Flip it back on.
        XCTAssertTrue(flipToggle(toggleAfterReopen, target: "1"), "Tapping should re-enable the prompt")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()

        // Prompt should be visible again.
        let promptAfterReenable = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Swipe left to skip")
        ).firstMatch
        XCTAssertTrue(
            promptAfterReenable.waitForExistence(timeout: 3),
            "Prompt should reappear after re-enabling in Settings")
    }
```

Note: These tests reuse the existing private `flipToggle(_:target:)` helper at line ~326. The helper is already in scope since new methods are added to the same class.

#### 2. Accessibility audit — no source changes
**File**: `SingleThreadUITests/SingleThreadUITests.swift`
**Action**: none

The audit test `testAccessibilityAudit()` launches with `--ui-testing`, which pre-sets `showSwipePrompt = true`. The prompt container is `accessibilityHidden(true)` and the Dismiss button has an explicit `.accessibilityLabel("Dismiss swipe prompt")`. The audit should pass unchanged — the hidden container is excluded from the audit, and the Dismiss button has proper traits.

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests/SingleThreadUITestsFlows` — all flow tests pass including the three new ones
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests/SingleThreadUITests` — accessibility audit passes

#### Manual
- [ ] Build & run on simulator, verify prompt → Dismiss → Settings toggle round-trip all work visually
- [ ] Run VoiceOver, verify the card reads normally (prompt text not spoken) and Dismiss button is reachable

---

## Gate Check

After all four phases are complete:

- [ ] `./scripts/test.sh` passes end-to-end (format, lint, build, periphery, unit tests, UI tests)

---

## Cross-Cutting Notes

1. **`showSwipePrompt` is stored in `.standard`**, matching `enableActionButtons` and `allowsLandscape`. It does NOT sync to watch — correct for an iOS-only UI preference.

2. **No `ShowSwipePromptPreference` struct, no `SingleThreadCore` changes** beyond `UITestingSeed.persistedKeys`. This follows the `enableActionButtons` pattern: iOS-only `.standard` preferences stay lightweight.

3. **`ReminderCardView` init signature change (Phase 3)** adds `showSwipePrompt: Binding<Bool> = .constant(false)`. The default value means existing test helpers (`ShowDateTests.makeCard`, `ShowAlarmsTests.makeCard`, `ShowRecurrenceTests.makeCard`) compile unchanged — they omit the new parameter and get the default.

4. **`@AppStorage` vs `SettingsBindings` sync**: The `@AppStorage("showSwipePrompt")` property in ContentView is the source of truth. The `SettingsBindings.showSwipePrompt` bag property mirrors it during settings editing. The `.onChange(of: bag.showSwipePrompt)` write-back persists changes from the toggle. The Dismiss button writes `false` directly through the `$showSwipePrompt` binding, which hits `@AppStorage` directly — no bag involvement.

5. **Stage dependency**: Stage 2 (toggle) and Stage 3 (card prompt) are independent — both depend only on Stage 1. They can be implemented in either order. The structure orders Stage 2 first because the toggle is the simpler incremental layer.
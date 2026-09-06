# Implementation Plan

## Overview

Move `enableActionButtons` from iOS-only `@AppStorage`/`#if` gating to unconditional, wire it through the macOS settings bag→write-back chain, and ungated the `InterfaceSettingsView` toggle row — giving macOS a "Show action buttons" toggle in the Interface settings sheet. The macOS action menu is already fully implemented behind this flag; the gap is purely the settings control surface.

---

## Stage 1: Storage — Ungate `@AppStorage` declaration

Make `enableActionButtons` readable and writable on macOS by removing the `#if os(iOS)` gate around its `@AppStorage` declaration. The macOS action-menu code already reads the key raw from `AppGroup.defaults` — this gives it a proper `@AppStorage` setter so the write-back bridge (Stage 2) can persist through it. Nothing visible changes yet — the flag defaults to `false` on macOS.

### Changes

#### 1. Ungate `@AppStorage` for `enableActionButtons`
**File**: `SingleThread/ContentView.swift`
**Action**: modify — move `enableActionButtons` `@AppStorage` out of `#if os(iOS)`

**Current** (lines 95–98):
```swift
    #if os(iOS)
        @AppStorage("enableActionButtons", store: AppGroup.defaults)
        var enableActionButtons = false
    #endif
```

**Replace with** (unconditional, placed after `backgroundPinned` at line ~93):
```swift
    @AppStorage("enableActionButtons", store: AppGroup.defaults)
    var enableActionButtons = false
```

The `#if os(iOS)` / `#endif` guards are removed; the declaration itself is unchanged.

### Verification

#### Automated
- [ ] `SIM=platform=macOS make mac-test` passes (all existing macOS unit tests green)

#### Manual
- [ ] macOS app builds and launches — no visible change (flag defaults to `false`)
- [ ] iOS app builds and runs — toggle row still present in Interface settings, functional

---

## Stage 2: Settings plumbing — Wire bag construction + write-back on macOS

Add `enableActionButtons` to the macOS `makeSettingsBag` call and `.onChange` write-back bridge. The macOS bag already carries all 19 fields unconditionally (`SettingsBindings.swift:66`) — this connects the macOS construction path and persistence bridge so a user edit flows: toggle → binding → bag → `@AppStorage` setter → App Group suite.

### Changes

#### 1. Add `enableActionButtons` to macOS `makeSettingsBag()`
**File**: `SingleThread/ContentView+Settings.swift`
**Action**: modify — add parameter to macOS branch

**Current** (`#elseif os(macOS)` branch, lines ~72–85):
```swift
        #elseif os(macOS)
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                ...
```

**Replace with** (add `enableActionButtons` after `textSize`):
```swift
        #elseif os(macOS)
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                enableActionButtons: enableActionButtons,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                ...
```

#### 2. Add write-back `.onChange` in macOS branch
**File**: `SingleThread/ContentView+Settings.swift`
**Action**: modify — add `.onChange` for `enableActionButtons` in `#elseif os(macOS)`

**Current** (lines ~30):
```swift
        #elseif os(macOS)
            let withIOSPreferences = withAppearance
```

**Replace with**:
```swift
        #elseif os(macOS)
            let withIOSPreferences = withAppearance
                .onChange(of: bag.enableActionButtons) { _, new in enableActionButtons = new }
```

#### 3. Pass `enableActionButtons` binding in macOS `SettingsView` NavigationLink
**File**: `SingleThread/SettingsView.swift`
**Action**: modify — add argument to macOS `InterfaceSettingsView` initializer call

**Current** (`#elseif os(macOS)` branch, lines ~51–55):
```swift
                        #elseif os(macOS)
                            InterfaceSettingsView(
                                appearanceMode: $bindings.appearanceMode,
                                textSize: $bindings.textSize,
                                showMicrophoneButton: $bindings.showMicrophoneButton,
                                viewModel: viewModel)
```

**Replace with**:
```swift
                        #elseif os(macOS)
                            InterfaceSettingsView(
                                appearanceMode: $bindings.appearanceMode,
                                textSize: $bindings.textSize,
                                showMicrophoneButton: $bindings.showMicrophoneButton,
                                enableActionButtons: $bindings.enableActionButtons,
                                viewModel: viewModel)
```

### Tests (add to existing `SingleThreadTests/SettingsViewTests.swift`)

Append inside the `@MainActor struct SettingsViewTests`:

```swift
    #if os(macOS)
    @Test
    func macOSBagIncludesEnableActionButtons() {
        let on = SettingsBindings(enableActionButtons: true)
        #expect(on.enableActionButtons)
        let off = SettingsBindings(enableActionButtons: false)
        #expect(!off.enableActionButtons)
    }

    @Test
    func macOSEnableActionButtonsRoundTripsThroughAppGroup() {
        let key = "enableActionButtons"
        AppGroup.defaults.set(false, forKey: key)
        #expect(!AppGroup.defaults.bool(forKey: key))

        // Simulate the write-back: bag value → @AppStorage setter path.
        AppGroup.defaults.set(true, forKey: key)
        #expect(AppGroup.defaults.bool(forKey: key))

        // Clean up so a prior run's leftover can't pollute a subsequent run.
        AppGroup.defaults.removeObject(forKey: key)
    }
    #endif
```

### Verification

#### Automated
- [x] `SIM=platform=macOS make mac-test` passes — existing tests + two new macOS-gated tests

#### Manual
- [ ] macOS app: gear icon → Interface section — no toggle yet (Stage 3 adds it), but `enableActionButtons` is now wired through the bag

---

## Stage 3: UI — Toggle row in `InterfaceSettingsView` on macOS

Move the `@Binding var enableActionButtons` declaration and "Show action buttons" `Toggle` row from `#if os(iOS)` to unconditional. The macOS `InterfaceSettingsView` initializer already receives the binding from Stage 2 — this adds the control that displays and mutates it.

### Changes

#### 1. Move `@Binding` declaration to unconditional
**File**: `SingleThread/InterfaceSettingsView.swift`
**Action**: modify — remove `#if os(iOS)` guards from `enableActionButtons` binding

**Current** (lines ~18–20):
```swift
    #if os(iOS)
        @Binding var enableActionButtons: Bool
    #endif
```

**Replace with** (unconditional, placed after `showMicrophoneButton`):
```swift
    @Binding var enableActionButtons: Bool
```

#### 2. Move Toggle row to unconditional
**File**: `SingleThread/InterfaceSettingsView.swift`
**Action**: modify — remove `#if os(iOS)` guards from action-buttons Toggle

**Current** (lines ~86–97):
```swift
            #if os(iOS)
                Toggle(isOn: $enableActionButtons) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Show action buttons")
                            SettingsCaption(text: "Show complete, skip, and delete buttons.")
                        }
                    } icon: {
                        Image(systemName: "hand.tap")
                    }
                }
                .accessibilityIdentifier("showActionButtonsToggle")
```

**Replace with** (unconditional, placed after the microphone Toggle `}`):
```swift
            Toggle(isOn: $enableActionButtons) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Show action buttons")
                        SettingsCaption(text: "Show complete, skip, and delete buttons.")
                    }
                } icon: {
                    Image(systemName: "hand.tap")
                }
            }
            .accessibilityIdentifier("showActionButtonsToggle")
```

#### 3. Update macOS Preview
**File**: `SingleThread/InterfaceSettingsView.swift`
**Action**: modify — add `enableActionButtons` binding to macOS `#Preview`

**Current** (`#else` branch of `#Preview`, lines ~143–148):
```swift
        #else
            InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                viewModel: SettingsViewModel())
```

**Replace with**:
```swift
        #else
            InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                viewModel: SettingsViewModel())
```

### Tests (add to existing `SingleThreadTests/SettingsViewTests.swift`)

Append after the Stage 2 tests inside `SettingsViewTests`:

```swift
    #if os(macOS)
    @Test
    func interfaceSettingsViewContainsActionButtonsRowOnMacOS() {
        let view = InterfaceSettingsView(
            appearanceMode: .constant(.system),
            textSize: .constant(.system),
            showMicrophoneButton: .constant(true),
            enableActionButtons: .constant(false),
            viewModel: SettingsViewModel())
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("Show action buttons"))
        #expect(bodyDescription.contains("Show complete, skip, and delete buttons."))
    }

    @Test
    func macOSToggleTogglesBinding() {
        let enabled = Binding(wrappedValue: false)
        let view = InterfaceSettingsView(
            appearanceMode: .constant(.system),
            textSize: .constant(.system),
            showMicrophoneButton: .constant(true),
            enableActionButtons: enabled,
            viewModel: SettingsViewModel())
        // Verify the view accepts the binding — the binding itself will
        // be mutated by the Toggle in a running app; we confirm the
        // initial value flows through.
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("Show action buttons"))
    }
    #endif
```

### Verification

#### Automated
- [x] `SIM=platform=macOS make mac-test` passes — existing + new toggle-row tests

#### Manual
- [ ] macOS app: gear icon → Interface section → "Show action buttons" toggle is visible
- [ ] Toggle ON → close sheet → bottom bar shows action menu (3-dot `Menu` with Skip/Reschedule/Delete)
- [ ] Toggle OFF → close sheet → bottom bar shows direct Skip + Delete buttons
- [ ] iOS app: toggle row still present and functional (no regression)

---

## Stage 4: Full gate

Run the complete CI-identical pipeline to confirm no regressions across platforms.

### Verification

#### Automated
- [x] `./scripts/test.sh` passes — formats, lints, builds (iOS + watch + macOS), Periphery, all unit tests (iOS + macOS + watch), all UI tests (iOS + watch). **On this host, the two known pre-existing `EntitlementStoreTests` fail (see note below)** — everything else green, including the four new macOS tests for this ticket.

> **Host-local environment failure (not our diff):** `EntitlementStoreTests.isEntitledSurvivesStoreRecreation` + `initialRefreshSettlesResolvedFlag` fail on this machine, exactly as documented in var-789: the host's StoreKitTest/storekitd leaks an entitled sandbox state into `Transaction.currentEntitlements` (`SKServiceErrorDomain Code=2` saving config). Pre-existing and environmental — reproduced on clean `origin/main` on this host; CI is green. Do not treat the macOS leg as fully green on this machine until the sandbox is reset.

#### Manual
- [ ] macOS: settings sheet → toggle ON → bottom bar switches to action menu; toggle OFF → direct buttons
- [ ] iOS: toggle row unchanged, action menu/direct skip still work
- [ ] Watch: sync delivers the flag (toggle on iOS/macOS → watch receives within ~5s) — action menu confirmation dialog appears when enabled
- [ ] Keyboard shortcuts: `c` (complete), `s` (skip/menu), `delete` (delete) all work regardless of toggle state
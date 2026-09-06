# Structure Outline

## Approach

Move `enableActionButtons` from iOS-only `@AppStorage` to unconditional, wire it through the macOS settings bag→write-back chain, and ungated the `InterfaceSettingsView` toggle row — the macOS action menu is already fully implemented behind this flag; the gap is purely the settings control surface.

---

## Stage 1: Storage — Ungate `@AppStorage` declaration

Make `enableActionButtons` readable and writable on macOS by removing the `#if os(iOS)` gate around its `@AppStorage` declaration. The macOS action-menu code already reads the key raw from `AppGroup.defaults` — this stage gives it a proper `@AppStorage` setter so the write-back bridge (Stage 2) can persist through it. Nothing visible changes yet — the flag defaults to `false` on macOS, same as today.

**Files**: `SingleThread/ContentView.swift`

**Key changes**:
- `@AppStorage("enableActionButtons", store: AppGroup.defaults) var enableActionButtons = false` — move from inside `#if os(iOS)` block (line ~96) to unconditional, alongside the other App-Group-backed declarations (`showUndatedReminders`, `sortOption`, `showDate`, etc.)

**Tests**: 
- Existing `EnableActionButtonsMigrationTests` — still pass (migration reads both suites, macOS has `.standard` same as iOS)
- Existing `AppGroupTests` — still pass (suite round-trip unchanged)
- Existing macOS unit suite (`make mac-test`) — still passes; `@AppStorage` with `AppGroup.defaults` store compiles on macOS

**Verify**: `SIM=platform=macOS make mac-test` passes (same green as today)

---

## Stage 2: Settings plumbing — Wire bag construction + write-back on macOS

Add `enableActionButtons` to the macOS `makeSettingsBag` call and `.onChange` write-back bridge. The macOS bag already carries all 19 fields unconditionally (`SettingsBindings.swift:66`) — this stage connects the macOS construction path and persistence bridge so a user edit flows: toggle → binding → bag → `@AppStorage` setter → App Group suite.

**Files**: `SingleThread/ContentView+Settings.swift`, `SingleThread/SettingsView.swift`

**Key changes**:
- `ContentView+Settings.swift` — macOS `makeSettingsBag` call (line ~72-85): add `enableActionButtons: enableActionButtons` parameter (the `@AppStorage` property now visible on macOS from Stage 1)
- `ContentView+Settings.swift` — macOS write-back branch (`let withIOSPreferences = withAppearance` at ~30): add `.onChange(of: bag.enableActionButtons) { _, new in enableActionButtons = new }` before the existing appearance `.onChange`
- `SettingsView.swift` — macOS `InterfaceSettingsView` `NavigationLink` (lines ~51-55): add `enableActionButtons: $bindings.enableActionButtons` to the three existing macOS bindings (`appearanceMode`, `textSize`, `showMicrophoneButton`)

**Type signatures** (no new types; existing `SettingsBindings` unchanged):
- macOS `InterfaceSettingsView` initializer call gains one argument: `enableActionButtons: Binding<Bool>`
- `makeSettingsBag()` macOS overload gains one argument: `enableActionButtons: Bool`

**Tests** (add to existing `SettingsViewTests.swift`):
- `macOSBagIncludesEnableActionButtons` — under `#if os(macOS)`, construct bag with `enableActionButtons: true`/`false`, assert `bindings.enableActionButtons` matches input (`SettingsBindings` already carries the field unconditionally)
- `macOSWriteBackPersistsToAppGroup` — under `#if os(macOS)`, simulate the `.onChange` bridge: set `AppGroup.defaults` to a known value, trigger write-back, assert the key in App Group updated; clean up after

**Verify**: `SIM=platform=macOS make mac-test` includes new tests and passes

---

## Stage 3: UI — Toggle row in `InterfaceSettingsView` on macOS

Move the `@Binding var enableActionButtons` declaration and "Show action buttons" `Toggle` row from `#if os(iOS)` to unconditional. The macOS `InterfaceSettingsView` initializer already receives the binding from Stage 2 — this stage adds the control that displays and mutates it. The toggle label, caption, and `.accessibilityIdentifier("showActionButtonsToggle")` are identical on both platforms.

**Files**: `SingleThread/InterfaceSettingsView.swift`

**Key changes**:
- `@Binding var enableActionButtons: Bool` (lines ~19-20) — move from inside `#if os(iOS)` to unconditional, alongside `appearanceMode`, `textSize`, `showMicrophoneButton`
- `Toggle(isOn: $enableActionButtons)` row with label "Show action buttons" and caption "Show complete, skip, and delete buttons." (lines ~86-97) — move from inside `#if os(iOS)` to unconditional (or `#if os(iOS) || os(macOS)` if the project convention prefers explicit platform gating over unconditional)

**No signature changes** — the `@Binding` declaration is identical; only the `#if` guard moves.

**Tests** (add to existing `SettingsViewTests.swift`):
- `interfaceSettingsViewContainsActionButtonsRowOnMacOS` — under `#if os(macOS)`, assert the toggle row label is "Show action buttons" and caption is "Show complete, skip, and delete buttons." (mirrors the existing iOS assertion at `:95-124`)
- `macOSToggleTogglesBinding` — under `#if os(macOS)`, instantiate `InterfaceSettingsView` with a `@Bindable` binding, toggle it on, assert binding reads `true`; toggle off, assert `false`

**Verify**: `SIM=platform=macOS make mac-test` includes new tests and passes

---

## Stage 4: Full gate

Run the complete CI-identical pipeline to confirm no regressions across platforms.

**Verify**: `./scripts/test.sh` passes — formats, lints, builds (iOS + watch + macOS), Periphery, all unit tests (iOS + macOS + watch), all UI tests (iOS + watch). Manual smoke test: macOS app → gear icon → Interface section → "Show action buttons" toggle → close sheet → bottom bar switches between menu and direct buttons.

---

## Testing Checkpoints

After each stage's incremental test gate, the following must be green before advancing:

| Stage | Checkpoint command | What must pass |
|---|---|---|
| 1 | `SIM=platform=macOS make mac-test` | All existing macOS unit tests (no regressions) |
| 2 | `SIM=platform=macOS make mac-test` | Existing + new bag/write-back tests |
| 3 | `SIM=platform=macOS make mac-test` | Existing + new toggle-row tests |
| 4 | `./scripts/test.sh` | Full pipeline (all platforms) |
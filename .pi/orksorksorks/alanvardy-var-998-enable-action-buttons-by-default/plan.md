# Implementation Plan

## Overview

Flip the `enableActionButtons` preference default from `false` to `true` at every
read site so a fresh install (no stored key) shows the Complete/Skip/Reschedule
cluster on iOS and watch without a settings change. The existing Settings toggle
must still turn the cluster off and persist that off state through
`AppGroup.defaults` + WatchConnectivity: the key, the suite, the wire payload,
and the `--ui-testing`/`--seed` seams are all unchanged. The one-shot
`AppViewModel.registerDefaults()` migration stays as-is and must not clobber an
existing App Group value.

Two phases, one commit each: iOS read sites first, then the watch read site.
Each phase leaves the tree green with its own targeted tests.

### Ground truth from recon (do not re-derive)

- Key is the string literal `enableActionButtons` everywhere.
- `AppGroup.defaults` (`SingleThreadCore/.../AppGroup.swift`) is
  `UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard`.
- Absent key → `bool(forKey:)` returns `false`, so every "default" is a literal
  in a read site, not a stored value. `@AppStorage` defaults are NOT written to
  the store; therefore a "fresh install persists nothing" test must assert
  `object(forKey:) == nil`, not `bool(forKey:) == true`.
- `registerDefaults()` copies a legacy `.standard` value into the App Group only
  when `UserDefaults.standard.object(forKey:) != nil && AppGroup.defaults.object(forKey:) == nil`
  (guard already prevents clobbering). No logic change — comment only.
- `makeSettingsBag()` seeds the bag from the `@AppStorage` property, so the bag
  default `true` genuinely tracks the view default (no clobber path).

### Explicitly out of scope (do NOT touch)

- `SingleThread/ContentView+ActionMenu.swift:91` — `macShowActionMenu` reads
  `AppGroup.defaults.bool(forKey: "enableActionButtons")` raw for the macOS
  fallback render. macOS is not in the ticket's acceptance criteria (iOS +
  watch); leaving it means macOS fresh installs keep rendering the direct-skip
  cluster. Not a regression and not part of this change.
- No migration of existing installs, no new key, no schema, no widget changes.
- `SingleThread/AppViewModel.swift:215-231` (`--ui-testing`) and `:311-314`
  (`--seed`) already force `true`; leave them alone.

---

## Phase 1: iOS read-site defaults + migration-guard tests

### Changes

#### 1. `@AppStorage` source of truth
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Within the `@AppStorage("enableActionButtons", store: AppGroup.defaults)` block
(around line 100-101):

```swift
@AppStorage("enableActionButtons", store: AppGroup.defaults)
var enableActionButtons = true
```

#### 2. `ContentViewModel` view mirror
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify

Around line 74-77, change the default and correct the doc comment (the current
comment asserts the old placeholder rationale):

```swift
#if os(iOS)
    /// Mirrors ContentView's `@AppStorage("enableActionButtons")`. Driven from
    /// the view via `.task`/`.onChange` (see `ContentView`). Defaults true so a
    /// fresh install shows the action cluster until the view injects the value.
    var enableActionButtons = true
```

#### 3. `SettingsBindings` default argument
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify

Around line 31, in the initializer parameter list:

```swift
enableActionButtons: Bool = true,
```

The file-level doc comment already states the bag "mirrors the `@AppStorage`
defaults from ContentView exactly" — no comment change needed.

#### 4. `registerDefaults()` doc comment
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify (comment only — do not touch the migration guard or bodies)

Around line 103-107, the comment currently says "fresh installs stay
default-off". Update to match the new reality:

```swift
/// Also runs one-time storage migrations: `enableActionButtons` moved from
/// `.standard` to `AppGroup.defaults` (shared with the watch), and existing
/// users' value is copied over once. Fresh installs persist no App Group value;
/// the read sites supply the default-on.
```

#### 5. Flip the migration test's fresh-install assertion + add the off sad path
**File**: `SingleThreadTests/EnableActionButtonsMigrationTests.swift`
**Action**: modify

Replace `freshInstallLeavesAppGroupOff` with the absent-key semantics, and add
an explicit-off guard test. Update the suite doc comment (it says "stays
default-off").

```swift
/// Proves the one-shot migration in `AppViewModel.init` copies a legacy
/// `.standard` value into `AppGroup.defaults` so existing users keep their
/// action-buttons toggle after the move, while a fresh install (no `.standard`
/// value) persists nothing. Serialized: the suite runs on real UserDefaults.
```

```swift
@Test
func freshInstallLeavesNoAppGroupValue() {
    defer { clearKey() }
    UserDefaults.standard.removeObject(forKey: Self.key)
    AppGroup.defaults.removeObject(forKey: Self.key)

    _ = AppViewModel(arguments: [])

    #expect(
        AppGroup.defaults.object(forKey: Self.key) == nil,
        "fresh installs persist nothing; the default-on comes from the read sites")
}

@Test
func existingAppGroupOffIsNotClobbered() {
    defer { clearKey() }
    UserDefaults.standard.removeObject(forKey: Self.key)
    AppGroup.defaults.set(false, forKey: Self.key)

    _ = AppViewModel(arguments: [])

    #expect(
        AppGroup.defaults.object(forKey: Self.key) != nil,
        "registerDefaults must not write over an existing App Group value")
    #expect(
        !AppGroup.defaults.bool(forKey: Self.key),
        "an explicitly toggled-off value stays off")
}
```

Leave `standardOnlyValueIsCopiedToAppGroup` unchanged.

#### 6. iOS default-on test for the view mirror
**File**: `SingleThreadTests/ActionButtonTests.swift`
**Action**: modify

Inside the `#if os(iOS)` `ActionButtonTests` struct, alongside the existing
tests (the suite already has `makeViewModel(store:)` and `storeWithReminder()`
helpers):

```swift
@Test
func freshViewModelDefaultsToActionButtonsOn() {
    let viewModel = makeViewModel(store: storeWithReminder())
    #expect(
        viewModel.enableActionButtons,
        "the ContentViewModel mirror tracks ContentView's new @AppStorage default")
}
```

#### 7. iOS default-on test for the bindings bag
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add a test for the bag default. Place it in the suite so it compiles on both
platforms (do not wrap it in `#if os(macOS)`):

```swift
@Test
func enableActionButtonsDefaultsToOn() {
    #expect(
        SettingsBindings().enableActionButtons,
        "the bindings bag default mirrors ContentView's @AppStorage default")
}
```

### Verification

#### Automated
- [x] `make format` — no diff after SwiftFormat (unit-test names must not start with `test`; these do not)
- [x] `make lint` — SwiftLint `--strict` clean
- [x] `make build` succeeds
- [x] `SIM= scripts/test-one.sh EnableActionButtonsMigrationTests` passes and the run reports >0 cases (both `standardOnlyValueIsCopiedToAppGroup`, `freshInstallLeavesNoAppGroupValue`, `existingAppGroupOffIsNotClobbered`)
- [x] `SIM= scripts/test-one.sh ActionButtonTests` passes, including `freshViewModelDefaultsToActionButtonsOn`
- [x] `SIM= scripts/test-one.sh SettingsViewTests` passes, including `enableActionButtonsDefaultsToOn`

#### Manual
- [ ] Confirm by inspection that `registerDefaults()` bodies and the migration guard at `AppViewModel.swift:115-124` are byte-for-byte unchanged (comment only).
- [ ] Confirm by inspection that `AppViewModel.swift:231` and `:311-314` still force `AppGroup.defaults.set(true, forKey: "enableActionButtons")`.
- [ ] Confirm the Settings toggle write path is untouched: `SingleThread/ContentView+Settings.swift` `onChange(of: bag.enableActionButtons)` → `enableActionButtons = new`, and `InterfaceSettingsView.swift` `Toggle(isOn: $enableActionButtons)`.
- [ ] Confirm `SkippedReminderSyncService.swift` push (`:222`) / apply (`:483-486`) are untouched, so off-state still persists and syncs.

---

## Phase 2: watchOS read-site default + tests

### Changes

#### 1. `ShowEnableActionButtonsState` absent-key fallback
**File**: `SingleThreadWatch/ShowEnableActionButtonsState.swift`
**Action**: modify

The raw `bool(forKey:)` read must default on when the key is absent. Update the
class doc comment (it says "default-off when unset" is covered elsewhere; just
ensure the behavior sentence reads true) and the initializer:

```swift
private static let actionButtonsKey = "enableActionButtons"

init() {
    let stored = AppGroup.defaults.object(forKey: Self.actionButtonsKey)
    isEnabled = stored == nil ? true : AppGroup.defaults.bool(forKey: Self.actionButtonsKey)
}

func apply(_ value: Bool) {
    AppGroup.defaults.set(value, forKey: Self.actionButtonsKey)
    isEnabled = value
}
```

(The `actionButtonsKey` constant replaces the two duplicated string literals; if
the implementer prefers the smallest diff, inline the literals — behavior is
identical.)

#### 2. Flip the watch default test + add the off sad path
**File**: `SingleThreadWatchTests/ShowEnableActionButtonsStateTests.swift`
**Action**: modify

Update the suite doc comment ("default-off when unset" → default-on). Replace
`unsetKeyDefaultsToOff` and add a persisted-off test:

```swift
@Test
func unsetKeyDefaultsToOn() {
    defer { clearKey() }
    AppGroup.defaults.removeObject(forKey: Self.key)
    let state = ShowEnableActionButtonsState()
    #expect(state.isEnabled, "no persisted value means the new default-on")
}

@Test
func persistedOffStaysOff() {
    defer { clearKey() }
    AppGroup.defaults.set(false, forKey: Self.key)
    #expect(
        !ShowEnableActionButtonsState().isEnabled,
        "an explicitly toggled-off value overrides the default")
}
```

Leave `applyRoundTripsTrueAndFalse`, `applyPersistsToAppGroupDefaults`, and
`initReadsPersistedValue` unchanged. `clearKey()` already clears both the App
Group suite and `.standard`.

### Verification

#### Automated
- [ ] `make format` — no diff after SwiftFormat
- [ ] `make lint` — SwiftLint `--strict` clean (the new `actionButtonsKey` and `stored` names satisfy the 3-char `identifier_name` minimum)
- [ ] `make watch-build` succeeds
- [ ] `make watch-test` passes, including `unsetKeyDefaultsToOn` and `persistedOffStaysOff`
- [ ] `SIM= scripts/test-one.sh ShowEnableActionButtonsStateTests` is not applicable (watch destination differs) — use `make watch-test` as the targeted command

#### Manual
- [ ] Confirm `SingleThreadWatch/WatchAppViewModel.swift:43,82` and `WatchReminderViewModel.swift:24,50` consume `isEnabled` unchanged.
- [ ] Confirm `SingleThreadWatchTests/WatchSyncPipelineTests.swift:379-418` (receive-persists-then-hook, push-unchanged) still pass — off-state sync is unchanged.

---

## Post-phase: full gate

After both phases have committed, run the full CI-identical gate once via the
`run-gate` skill (one async gate subagent, managed worktree) — `./scripts/test.sh`,
never ad-hoc `nohup`. This covers the iOS UI test
`SingleThreadUITests.testLaunchAndRenderSmoke` (`--ui-testing` seam, asserts the
cluster renders with `enableActionButtons` ON) and the retained sync/settings
suites.

- [ ] `./scripts/test.sh` green via `run-gate` after both phases
- [ ] `SingleThreadUITests.testLaunchAndRenderSmoke` still passes (seam unchanged)

# Implementation Plan

## Overview

Give macOS a Settings → Interface toggle ("Show in Menu Bar", default on) backed by
`UserDefaults.standard["showMenuBarExtra"]`, and bind it to the `MenuBarExtra` scene via
`isInserted:` so the menu bar icon appears/disappears live (and ⌘-drag-off persists `false`).
Everything is `#if os(macOS)`-gated; the icon-removal effect itself is framework behaviour and is
covered by manual checks only (`UNVALIDATED` in CI).

**Deviation from `structure.md`, noted up front:** Stage 2's literal
`init(showMenuBarExtra: Bool = MenuBarExtraPreference.defaultValue)` cannot compile, because
`MenuBarExtraPreference.swift` is macOS-only while `SettingsBindings` builds for iOS too. The plan
uses a plain `= true` default in the bag and adds a macOS drift-guard test
(`macOSBagDefaultsToShown`) that ties it back to `MenuBarExtraPreference.defaultValue`. Keeping the
whole-file `#if os(macOS)` gate is deliberate: an ungated type would be compiled into the iOS index
with no iOS usage and would trip Periphery `--strict`.

Ordering is unchanged from `structure.md` (Stage 1 → 4).

---

## Phase 1: Preference constant + defaults

### Changes

#### 1. New preference constant
**File**: `SingleThread/MenuBarExtraPreference.swift`
**Action**: create

Whole file, gated, no imports (constants only). Mirrors `MenuBarExtraOptions.swift`'s whole-file
gate style.

```swift
#if os(macOS)
    /// Single source of truth for the "Show in Menu Bar" preference: the
    /// `UserDefaults.standard` key and its opt-out default. Consumed by the
    /// `@AppStorage` sites in `SingleThreadApp` and `ContentView`.
    enum MenuBarExtraPreference {
        static let key = "showMenuBarExtra"
        static let defaultValue = true
    }
#endif
```

New `.swift` file → **no pbxproj edit** (synchronized file groups).

#### 2. New test suite
**File**: `SingleThreadTests/MenuBarExtraPreferenceTests.swift`
**Action**: create

Whole file gated, mirroring `MenuBarExtraOptionsTests.swift:1`.

```swift
#if os(macOS)
    @testable import SingleThread
    import Testing

    @Suite
    struct MenuBarExtraPreferenceTests {
        @Test
        func menuBarExtraPreferenceKeyIsStable() {
            // Pins the persistence literal: changing it silently orphans every
            // existing user's stored value.
            #expect(MenuBarExtraPreference.key == "showMenuBarExtra")
        }

        @Test
        func menuBarExtraPreferenceDefaultsToShown() {
            #expect(MenuBarExtraPreference.defaultValue)
            // Sad path: an accidental flip to opt-in must fail loudly.
            #expect(MenuBarExtraPreference.defaultValue != false)
        }
    }
#endif
```

New test file → **no pbxproj edit** (synchronized file groups; do not add an
`-only-testing:` entry, it is inside `SingleThreadTests` which `make mac-test` already runs).

### Verification

#### Automated
- [x] `make mac-test` passes (whole macOS `SingleThreadTests` target)
- [x] Targeted: `xcodebuild -scheme SingleThread -destination 'platform=macOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests/MenuBarExtraPreferenceTests` runs **2 cases** and passes
- [x] `make format` then `make lint` clean

#### Manual
- [ ] None (pure constants; no user-visible surface yet)

---

## Phase 2: Settings data plumbing — bag, storage, write-back

### Changes

#### 1. `SettingsBindings` — new unconditional member
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify

`#if` is illegal in a parameter list, so the member is declared unconditionally with its default —
same convention as `allowsLandscape` / `showSwipePrompt` / `showUndoButton` (see the header
comment at `:20-23`).

Insert `showMenuBarExtra` as the **last** init parameter (after `backgroundPinned`) so all existing
named-argument call sites are unaffected:

```swift
    init(
        appearanceMode: AppearanceMode = .system,
        textSize: TextSize = .system,
        allowsLandscape: Bool = true,
        enableActionButtons: Bool = false,
        showSwipePrompt: Bool = true,
        showUndoButton: Bool = true,
        notificationsEnabled: Bool = false,
        notificationIntervalHours: Int = 48,
        showMicrophoneButton: Bool = true,
        backgroundEnabled: Bool = true,
        backgroundFadePercent: Int = 50,
        backgroundPinned: Bool = false,
        showMenuBarExtra: Bool = true) {
        ...
        self.backgroundPinned = backgroundPinned
        self.showMenuBarExtra = showMenuBarExtra
    }
```

and the stored property after `backgroundPinned`:

```swift
    var backgroundPinned: Bool
    var showMenuBarExtra: Bool
```

Also extend the header comment's list of "declared unconditionally here with their ContentView
defaults" to name `showMenuBarExtra` (it is macOS-only in ContentView, like `allowsLandscape` is
iOS-only).

> Rationale for the literal `= true`: `MenuBarExtraPreference` is macOS-only and this file compiles
> for iOS. `macOSBagDefaultsToShown` (below) guards the drift.

#### 2. `ContentView` — macOS-gated `@AppStorage`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add inside the existing `@AppStorage` block, next to `appearanceMode`/`textSize` (`:72-76`) so the
standard-suite macOS preferences read together. Declare it inside `#if os(macOS)` (like the
`#if os(iOS)`-gated declarations at `:78-80`, `:99-110`) so the iOS build and the iOS Periphery
index never see it:

```swift
    #if os(macOS)
        @AppStorage(MenuBarExtraPreference.key)
        var showMenuBarExtra = MenuBarExtraPreference.defaultValue
    #endif
```

Deliberately **no** `store: AppGroup.defaults` — nothing else consumes this flag (research Q2/Q3;
design "Do NOT follow" #1).

#### 3. `makeSettingsBag()` — seed from the property
**File**: `SingleThread/ContentView+Settings.swift`
**Action**: modify

In the `#elseif os(macOS)` branch (`:55-66`), add:

```swift
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                enableActionButtons: enableActionButtons,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                backgroundFadePercent: backgroundFadePercent,
                backgroundPinned: backgroundPinned,
                showMenuBarExtra: showMenuBarExtra)
```

The `#if os(iOS)` branch is unchanged (it takes the `true` default).

#### 4. Write-back handler
**File**: `SingleThread/ContentView+Settings.swift`
**Action**: modify

In the `#elseif os(macOS)` branch of `settingsSheetWritebacks(_:)` (`:24-25`), add the write-back
alongside `enableActionButtons`:

```swift
        #elseif os(macOS)
            let withIOSPreferences = withAppearance
                .onChange(of: bag.enableActionButtons) { _, new in enableActionButtons = new }
                .onChange(of: bag.showMenuBarExtra) { _, new in showMenuBarExtra = new }
        #endif
```

#### 5. New tests
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add to the existing `#if os(macOS)` block that already contains `macOSBagIncludesEnableActionButtons`
/ `macOSEnableActionButtonsRoundTripsThroughAppGroup` (`:351-375`), following the
`AppGroup.defaults.set` … `removeObject(forKey:)` cleanup shape used there (`:373-374`) but against
`UserDefaults.standard`:

```swift
        @Test
        func showMenuBarExtraRoundTripsThroughBag() {
            let key = MenuBarExtraPreference.key
            UserDefaults.standard.set(false, forKey: key)
            #expect(!UserDefaults.standard.bool(forKey: key))

            // Simulate the write-back: bag value → @AppStorage setter path.
            UserDefaults.standard.set(true, forKey: key)
            #expect(UserDefaults.standard.bool(forKey: key))

            // Clean up so a prior run's leftover can't pollute a subsequent run.
            UserDefaults.standard.removeObject(forKey: key)
        }

        @Test
        func showMenuBarExtraDefaultsToShownInBag() {
            // Absent key → shown.
            let key = MenuBarExtraPreference.key
            let existing = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
            defer {
                if let existing { UserDefaults.standard.set(existing, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }

            #expect(SettingsBindings().showMenuBarExtra)

            // Sad path: the default must not override an explicit off.
            let off = SettingsBindings(showMenuBarExtra: false)
            #expect(!off.showMenuBarExtra)
            UserDefaults.standard.set(false, forKey: key)
            #expect(!UserDefaults.standard.bool(forKey: key))
        }

        @Test
        func macOSBagDefaultsToShown() {
            // Drift guard: the bag's literal default must match the preference type.
            #expect(SettingsBindings().showMenuBarExtra == MenuBarExtraPreference.defaultValue)
        }
```

Note the bag member is a plain in-memory value (like `enableActionButtons`), so the round-trip is
proven through `UserDefaults.standard` — the same namespace `@AppStorage(MenuBarExtraPreference.key)`
writes.

### Verification

#### Automated
- [x] `make mac-test` passes
- [x] Targeted: `xcodebuild -scheme SingleThread -destination 'platform=macOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests/SettingsViewTests` passes and includes the 3 new cases
- [x] `make build` (iOS, `SingleThread` scheme) passes — the bag change is cross-platform
- [x] `make format` then `make lint` clean

#### Manual
- [ ] None yet (no UI reads the value; Stage 3 surfaces it)

---

## Phase 3: Settings UI — macOS-only Interface toggle

### Changes

#### 1. New macOS-only binding + toggle
**File**: `SingleThread/InterfaceSettingsView.swift`
**Action**: modify

(a) Add the binding after `enableActionButtons` (`:19`), before the iOS-only block, mirroring the
existing `#if os(iOS)` binding declarations:

```swift
    #if os(macOS)
        @Binding var showMenuBarExtra: Bool
    #endif
```

(b) Add the toggle immediately after the `showActionButtonsToggle` (`:85-94`), inside the same
`Form`, matching the `Label { VStack { Text + SettingsCaption } } icon: { Image(systemName:) }`
shape:

```swift
            #if os(macOS)
                Toggle(isOn: $showMenuBarExtra) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Show in Menu Bar")
                            SettingsCaption(text: "Show the next reminder in the menu bar.")
                        }
                    } icon: {
                        Image(systemName: "menubar.rectangle")
                    }
                }
                .accessibilityIdentifier("showMenuBarToggle")
            #endif
```

(c) Update the `#else` (macOS) arg list in `#Preview("Default")` (`:141-146`):

```swift
            InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                showMenuBarExtra: .constant(true),
                viewModel: SettingsViewModel())
```

#### 2. Pass the binding from the macOS Interface destination
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

In the `#elseif os(macOS)` branch of the Interface row (`:50-55`), add
`showMenuBarExtra: $bindings.showMenuBarExtra` (last argument, after `enableActionButtons`). The
`#if os(iOS)` branch (`:41-48`) is unchanged. `.settingsSubscreenLayout()` stays on
`InterfaceSettingsView` — no change needed there.

#### 3. Localization entries
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify

Add both strings as `manual` entries with all six languages. Insert them adjacent to the existing
action-buttons caption entry, immediately **before** the `"Show a hint when there are swipeable reminders."`
key (currently `:4656`), so the caption group stays together. JSON:

```json
    "Show in Menu Bar": {
      "extractionState": "manual",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Show in Menu Bar"
          }
        },
        "zh-Hans": {
          "stringUnit": {
            "state": "translated",
            "value": "在菜单栏中显示"
          }
        },
        "es": {
          "stringUnit": {
            "state": "translated",
            "value": "Mostrar en la barra de menús"
          }
        },
        "ja": {
          "stringUnit": {
            "state": "translated",
            "value": "メニューバーに表示"
          }
        },
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "In der Menüleiste anzeigen"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Afficher dans la barre des menus"
          }
        }
      }
    },
    "Show the next reminder in the menu bar.": {
      "extractionState": "manual",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Show the next reminder in the menu bar."
          }
        },
        "zh-Hans": {
          "stringUnit": {
            "state": "translated",
            "value": "在菜单栏中显示下一个提醒。"
          }
        },
        "es": {
          "stringUnit": {
            "state": "translated",
            "value": "Muestra el próximo recordatorio en la barra de menús."
          }
        },
        "ja": {
          "stringUnit": {
            "state": "translated",
            "value": "次のリマインダーをメニューバーに表示します。"
          }
        },
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Zeige die nächste Erinnerung in der Menüleiste."
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Affichez le prochain rappel dans la barre des menus."
          }
        }
      }
    },
```

Keep the trailing comma after the second entry (it precedes the next key). Validate the JSON with
`plutil -lint SingleThread/Resources/Localizable.xcstrings`.

#### 4. Fix the existing macOS call sites
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

`InterfaceSettingsView` has no defaulted initializer, so three macOS constructions gain
`showMenuBarExtra: .constant(true)`:
- `interfaceSettingsViewContainsExpectedRows` `#else` branch (`:87-100`)
- `interfaceSettingsViewContainsActionButtonsRowOnMacOS` (`:378-384`)
- `macOSToggleTogglesBinding` (`:393-399`)

The `#if os(iOS)` branch (`:80-86`) is unchanged.

#### 5. New macOS content tests
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add to the same macOS block as the existing `interfaceSettingsViewContainsActionButtonsRowOnMacOS`:

```swift
        @Test
        func interfaceSettingsViewContainsMenuBarToggle() {
            let view = InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                showMenuBarExtra: .constant(true),
                viewModel: SettingsViewModel())
            let bodyDescription = String(describing: view.body)

            #expect(bodyDescription.contains("Show in Menu Bar"))
            #expect(bodyDescription.contains("Show the next reminder in the menu bar."))
        }

        @Test
        func interfaceSettingsViewOmitsMenuBarToggleCopy() {
            // Sad path: the row must render exactly once — a duplicated toggle
            // (e.g. copy-pasted into both platforms) fails here.
            let view = InterfaceSettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true),
                enableActionButtons: .constant(false),
                showMenuBarExtra: .constant(false),
                viewModel: SettingsViewModel())
            let bodyDescription = String(describing: view.body)

            let titleCount = bodyDescription.components(separatedBy: "Show in Menu Bar").count - 1
            let captionCount = bodyDescription
                .components(separatedBy: "Show the next reminder in the menu bar.").count - 1
            #expect(titleCount == 1)
            #expect(captionCount == 1)
        }
```

If the exact-once counts prove brittle against `String(describing:)` rendering of `Form`, reduce
`interfaceSettingsViewOmitsMenuBarToggleCopy` to asserting `titleCount >= 1 && captionCount >= 1`
plus a `false`-valued binding still rendering (the anti-conditional-hiding guard) — record the
actual counts in a comment either way.

### Verification

#### Automated
- [x] `make mac-test` passes (both new tests ran)
- [x] Targeted: `xcodebuild -scheme SingleThread -destination 'platform=macOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests/SettingsViewTests` passes and includes `interfaceSettingsViewContainsMenuBarToggle` + `interfaceSettingsViewOmitsMenuBarToggleCopy`
- [x] `make build` (iOS) passes with the toggle gated out
- [x] `plutil -lint SingleThread/Resources/Localizable.xcstrings` → OK
- [x] `make format` then `make lint` clean

#### Manual
- [ ] `make mac-run`; open Settings (gear) → **Interface**: the "Show in Menu Bar" toggle is
      visible below "Show action buttons" with its caption.
- [ ] Toggle it off, close the sheet, reopen Settings → it reads off.
- [ ] Quit and relaunch the app, reopen Settings → still off.

---

## Phase 4: Scene wiring — `isInserted` effect

### Changes

#### 1. `SingleThreadApp` — read the preference and bind it
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

(a) Add the `@AppStorage` next to `appearanceMode` in the `#if os(macOS)` private block (`:50-53`):

```swift
    #if os(macOS)
        @AppStorage("appearanceMode")
        private var appearanceMode = AppearanceMode.system

        @AppStorage(MenuBarExtraPreference.key)
        private var showMenuBarExtra = MenuBarExtraPreference.defaultValue
    #endif
```

(b) Add `isInserted:` to the scene (`:36-41`):

```swift
            MenuBarExtra(
                "SingleThread",
                systemImage: "checkmark.circle",
                isInserted: $showMenuBarExtra) {
                MenuBarExtraOptions(store: viewModel.store)
            }
            .menuBarExtraStyle(.menu)
```

Do **not** change the surrounding comment about the conditional-scene compiler bug, and do **not**
make the scene conditional — `isInserted:` is the supported mechanism.

### Verification

#### Automated
- [x] `make mac-build` passes
- [x] `make build` (iOS) passes — the scene is `#if os(macOS)`-gated, so iOS is unchanged
- [x] `make mac-test` still passes (no regression)
- [x] `make format` then `make lint` clean
- [ ] `UNVALIDATED` (record in the PR): no automated test can assert that the framework removes the
      icon — `isInserted` is framework behaviour with no seam. Do **not** add a test-only helper;
      Periphery `--strict` would flag it.

#### Manual (macOS — this is the acceptance check for the ticket)
- [ ] `make mac-run`; with the toggle **off**, the menu bar icon disappears immediately (no relaunch).
- [ ] Relaunch the app → the icon is still gone (persisted).
- [ ] Open Settings → Interface, toggle **on** → the icon returns immediately.
- [ ] With the icon visible, ⌘-drag it off the menu bar → reopen Settings → the toggle reads off.
- [ ] Confirm the app's Dock icon and ⌘-Tab entry remain (recovery path intact; not `LSUIElement`).
- [ ] Reset the preference between checks with
      `defaults delete app.alanvardy.SingleThread showMenuBarExtra`.

---

## Final: gate + marker

### Changes
- [x] Remove the branch-bootstrap marker: `git rm DELETEME` (it is not gitignored and its commit
      subject reads like the real change).
- [x] PR description must call out the "macOS dock widget" misnomer: the shipped surface is the
      macOS **menu bar extra**; macOS widgets cannot live in the Dock, and no dock widget exists in
      the repo (research Q4). Also flag the stated assumption that the Dock icon stays, since it is
      the recovery path.

### Verification
#### Automated
- [ ] Run the full CI-identical gate **once** via the `run-gate` skill (async gate subagent, managed
      worktree, multi-hour timeout) — `./scripts/test.sh`. Never `nohup` it ad-hoc and never re-run
      it from a phase subagent.
- [ ] `./scripts/test.sh` green (format + lint + iOS build + watch build + Periphery + UI tests +
      watch UI/unit + macOS unit).
- [ ] If Periphery `--strict` flags `SettingsBindings.showMenuBarExtra` as unused on the iOS index,
      add `// periphery:ignore` on that declaration (existing repo convention, e.g.
      `InterfaceSettingsView.swift:1`) and re-run `make periphery`.

#### Manual
- [ ] Confirm every checkbox above is ticked and the macOS manual checklist in Phase 4 passed on a
      real macOS run.
- [ ] Merge with `gh pr merge <n> --rebase --delete-branch` (merge commits and squashes are disabled).

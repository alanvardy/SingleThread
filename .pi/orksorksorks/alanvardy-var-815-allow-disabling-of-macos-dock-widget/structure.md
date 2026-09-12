# Structure Outline

## Approach

The "macOS dock widget" is actually the **macOS menu bar extra**; "disable" = remove the icon. Build it bottom-up:
a macOS-only key constant → standard-suite storage plumbing (bag + write-back) → the Interface toggle → the
`MenuBarExtra(isInserted:)` scene binding. The final effect is framework behaviour and cannot be unit-tested — it is
the one cross-cutting item, covered by the manual macOS checks and marked `UNVALIDATED` for CI.

All work is `#if os(macOS)`-gated, so the iOS/watch builds and their existing tests are untouched at every stage.

---

## Stage 1: Preference constant + defaults (bottom layer)

Delivers the single source of truth for the key and its default, so no bare literals drift between the two
`@AppStorage` sites. Green tests prove key/default stability.

**Files**: `SingleThread/MenuBarExtraPreference.swift` (new, whole-file `#if os(macOS)`, mirroring
`MenuBarExtraOptions.swift`), `SingleThreadTests/MenuBarExtraPreferenceTests.swift` (new, whole-file `#if os(macOS)`).

**Key changes**:
- `enum MenuBarExtraPreference { static let key: String; static let defaultValue: Bool }` — new (values
  `"showMenuBarExtra"`, `true`).

**Tests** (`SingleThreadTests/MenuBarExtraPreferenceTests.swift`): `menuBarExtraPreferenceKeyIsStable` (guards the
persistence literal) and `menuBarExtraPreferenceDefaultsToShown` (guards the opt-out default). Sad path: assert the
default is **not** `false`, so an accidental flip to opt-in fails loudly.
**Verify**: `make mac-test` (macOS destination, `-only-testing:SingleThreadTests`) green.

---

## Stage 2: Settings data plumbing — bag, storage, write-back

Makes the value readable/writable through the existing standard-suite chain: `@AppStorage` property ← bag ← write-back,
with the bag seeded from storage on every settings open. Green tests prove the storage round-trip and that the
standard suite (not the App Group) is used.

**Files**: `SingleThread/SettingsBindings.swift`, `SingleThread/ContentView.swift`,
`SingleThread/ContentView+Settings.swift`, `SingleThreadTests/SettingsViewTests.swift`.

**Key changes**:
- `SettingsBindings.init(showMenuBarExtra: Bool = MenuBarExtraPreference.defaultValue)` + stored
  `var showMenuBarExtra: Bool` — new (unconditional declaration, as with the other platform-specific bag members —
  `#if` is illegal in a parameter list).
- `ContentView`: `#if os(macOS) @AppStorage(MenuBarExtraPreference.key) private var showMenuBarExtra = MenuBarExtraPreference.defaultValue #endif`
  — new; standard suite, deliberately **not** `store: AppGroup.defaults`.
- `makeSettingsBag()` macOS branch — seed `showMenuBarExtra: showMenuBarExtra`.
- `settingsSheetWritebacks(_:)` `#elseif os(macOS)` branch — `.onChange(of: bag.showMenuBarExtra) { _, new in showMenuBarExtra = new }`.

**Tests**: extend `SettingsViewTests.swift` with `showMenuBarExtraRoundTripsThroughBag` (bag write/read) and
`showMenuBarExtraDefaultsToShownInBag` (absent key → `true`; sad path: a set `false` is not overridden by the default).
Mutate `UserDefaults.standard` and **clean the key afterwards**, mirroring `SettingsViewTests.swift:373-374`.
**Verify**: `make mac-test` green; `make format` + `make lint` clean.

---

## Stage 3: Settings UI — macOS-only Interface toggle

Surfaces the binding as "Show in Menu Bar" / "Show the next reminder in the menu bar." inside the existing Interface
`Form`, next to the action-buttons toggle. Green tests prove the toggle row renders on macOS with the expected
title + caption, and that no iOS row changed.

**Files**: `SingleThread/InterfaceSettingsView.swift`, `SingleThread/SettingsView.swift`,
`SingleThread/Resources/Localizable.xcstrings`, `SingleThreadTests/SettingsViewTests.swift`.

**Key changes**:
- `InterfaceSettingsView`: `#if os(macOS) @Binding var showMenuBarExtra: Bool #endif` — new; a
  `Toggle(isOn: $showMenuBarExtra)` with `SettingsLinkLabel`-style caption, `.accessibilityIdentifier("showMenuBarToggle")`,
  inside the `Form`; update both `#Preview` macOS arg list.
- `SettingsView.swift` macOS Interface destination (`:50-55`): pass `showMenuBarExtra: $bindings.showMenuBarExtra`
  (iOS branch `:41-48` unchanged).
- `Localizable.xcstrings`: add both strings as `manual` entries with `en`, `de`, `es`, `fr`, `ja`, `zh-Hans`.

**Tests**: `interfaceSettingsViewContainsMenuBarToggle` (macOS `String(describing: view.body)` contains title +
caption) and `interfaceSettingsViewOmitsMenuBarToggleCopy` guard (sad path: neither string appears twice / on the iOS
arg list path). Construct with `.constant(…)` binds per `SettingsViewTests.swift:383-401`; update the two existing
macOS call sites for the new argument.
**Verify**: `make mac-test` green; `make build` (iOS) still compiles with the gated-out toggle; `make format` +
`make lint` clean; manual: toggle is visible and persists across a sheet close/reopen.

---

## Stage 4: Scene wiring — `isInserted` effect (top layer)

Binds the persisted value to the `MenuBarExtra`, making the icon appear/disappear live and letting ⌘-drag-off write
`false` back. This is **the cross-cutting item**: the icon-removal itself is SwiftUI framework behaviour with no
seam to assert, so CI proves only that the scene compiles and the binding is wired; the effect is manual.

**Files**: `SingleThread/SingleThreadApp.swift`.

**Key changes**:
- `#if os(macOS) MenuBarExtra("SingleThread", systemImage: "checkmark.circle", isInserted: $showMenuBarExtra) { … }`
  — modified (`isInserted:` added); add the `@AppStorage(MenuBarExtraPreference.key) private var showMenuBarExtra =
  MenuBarExtraPreference.defaultValue` alongside `appearanceMode`.

**Tests**: no unit test is possible (framework-owned); the existing macOS suite must stay green and the app must build
for both platforms. Manual macOS checks (`UNVALIDATED` in CI): toggle off → icon disappears with no relaunch; relaunch
→ still gone; toggle on → returns; ⌘-drag off → reopened Settings shows the toggle off.
**Verify**: `make mac-build` + `make build` green; `make mac-test` unchanged; then the manual checklist above.

---

## Testing Checkpoints

- After Stage 1: preference constant test green → safe to reference the key from storage code.
- After Stage 2: bag round-trip + default tests green, defaults key cleaned up → safe to render a toggle against it.
- After Stage 3: macOS Interface content tests green, iOS build still compiles → safe to bind the scene.
- After Stage 4: both-platform builds green + manual menu-bar checklist run → full `./scripts/test.sh` once via the
  `run-gate` skill, then the `DELETEME` marker removed before merge.

**Flagged for the plan**: Stage 4's user-visible outcome has no automated proof. If the plan wants a red-first test,
the only valid seam is `MenuBarExtraPreference.defaultValue` (Stage 1) plus a deterministic `@AppStorage` read
(Stage 2) — do **not** add a test-only helper; Periphery `--strict` would flag it.

# Design Discussion

Branch: `alanvardy-var-623-appearance-system-not-working`
Task: make the "System" appearance choice actually re-follow the device appearance
after a Light → System (or Dark → System) transition, so all three modes take effect
consistently.

## Current State

- The appearance preference is a persisted `AppearanceMode` enum (`system`/`light`/
  `dark`) on `ContentView`:
  - `@AppStorage("appearanceMode")` declared `SingleThread/ContentView.swift:128-129`,
    default `.system`, stored in the SwiftUI default `UserDefaults` suite (NOT the
    App Group suite, unlike `showUndatedReminders` at `:142`).
  - Enum `AppearanceMode.swift:8-11` is `String, CaseIterable`; raw values are
    compiler-synthesized into `"system"`/`"light"`/`"dark"`.
  - `colorScheme: ColorScheme?` (`AppearanceMode.swift:16-22`) maps `.system → nil`,
    `.light → .light`, `.dark → .dark`.
- The value is applied to the view hierarchy via the SwiftUI modifier
  `.preferredColorScheme(_:)` at exactly two call sites:
  1. Root `ContentView` ZStack — `ContentView.swift:72` (reads `@AppStorage`).
  2. `SettingsView` sheet body — `SettingsView.swift:142` (reads the shared
     `@Binding`).
  - The sheet re-applies `.preferredColorScheme` itself because a presented sheet
    does not inherit the root's override; this was a deliberate portability
    mitigation (`var-617/design.md:164-166`).
- Settings picker → storage is a direct binding: `ContentView` projects
  `@AppStorage` → `$appearanceMode` (`ContentView.swift:77` iOS / `:86` else),
  passed into `SettingsView` (`SettingsView.swift:98` `Picker`, `:148` `@Binding`).
  `SettingsView` is deliberately stateless (`SettingsView.swift:56-57`) — no local
  copies, eager writes.
- The app already bridges UIKit on iOS via `@UIApplicationDelegateAdaptor`:
  `AppDelegate` is iOS-only (`AppDelegate.swift:1` `#if os(iOS)`), registered at
  `SingleThreadApp.swift:63`, and pushes `allowsLandscape` → `UIWindowScene` from a
  SwiftUI `.onChange` (`SettingsView.swift:143-146` calling `AppDelegate.applyLock`
  at `AppDelegate.swift:23-32`). It reads `UserDefaults.standard` directly at
  launch for `allowsLandscape` (`AppDelegate.swift:43-51`).
- iOS / macOS deployment target is **26.5** (`project.pbxproj:617,620`).

## The Bug

`.preferredColorScheme(nil)` — what `.system` emits via `colorScheme` — does
**not reliably tear down** a prior `.light`/`.dark` override once it has been
applied. This is a known SwiftUI defect that has regressed across OS releases: the
framework retains the last forced scheme instead of re-inheriting the device
appearance (Apple Forums 677212/763251/728955; resolved for 18.1+ but still
version-flaky). So System → Light → System converges to Light. Any fix that keeps
shuttling `nil` through SwiftUI is therefore fragile by construction.

## Desired End State

- The appearance the user selects is applied at the **window/app level**, not the
  SwiftUI per-scope modifier:
  - iOS: set the window's interface-style override to `.unspecified` for System
    (a clear "override → follow device" reset), `.light`, or `.dark`.
  - macOS: set the AppKit-level appearance to an equivalent cleared/explicit value
    for parity.
- The override is applied:
  1. At **launch** — before the first SwiftUI view appears, from the persisted
     `appearanceMode`, mirroring the existing `allowsLandscape` launch pattern —
     avoiding a wrong-appearance flash.
  2. **Eagerly on change** — when the picker selection changes, whether or not the
     sheet is open.
- The SwiftUI `.preferredColorScheme` modifiers at `ContentView.swift:72` and
  `SettingsView.swift:142` are **removed** — the window override is the single
  source of the applied appearance. A sheet presented in the same window follows
  automatically, so the sheet-level re-apply rationale in `var-617` is obsolete.
- Verification:
  - Unit test: the System override maps to a "clear override → reset" sentinel
    (not nil-into-SwiftUI), so replaying System after `light`/`dark` re-emitting
    the reset sentinel.
  - Unit test: the `UserDefaults` value of `appearanceMode` follows a written
    selection (closes the existing readback gap).
  - Manual / simulator check: System → Light → System and System → Dark → System
    both return to the device appearance while the sheet is open, matching the
    device's current mode.

## Patterns to Follow

- **UIKit bridging via `AppDelegate`** (`AppDelegate.swift:23-32`): the established
  way to push SwiftUI state into a UIKit window. Extend it with an appearance apply
  function rather than inventing a new iOS bridge.
- **Read `UserDefaults` at launch for a persisted toggle** — set the window
  appearance before SwiftUI appears (like the `supportedInterfaceOrientationsFor`
  pattern in `AppDelegate.swift`), already proven for `allowsLandscape`.
- **Drive the bridge from a SwiftUI `.onChange`** (`SettingsView.swift:143-146`
  → `AppDelegate.applyLock`). Moving the appearance hook to root
  `ContentView.onChange(of: appearanceMode)` reuses the convention and fires
  whether the sheet is open or at launch.
- **Enums map to styles as pure functions** (like `AppearanceMode.colorScheme`,
  `AppearanceMode.swift:16-22`) — the new override mapping should be a pure
  switch so it is unit-testable, not buried in view rendering.
- **Keep enum raw persistence** — the synthesized `String` raw-values with
  `@AppStorage` default fallback to `.system` is unchanged and fine
  (`AppearanceMode.swift:8-11`).

### Do NOT follow
- Do **not** keep shipping appearance through `.preferredColorScheme(nil)` —
  the research flags it as framework/untested behavior and Apple Forums confirm the
  nil-reset is broken/regressed. It is the root of the bug.
- Do **not** re-add a sheet-local appearance re-apply (`var-617/design.md:164-166`)
  — it becomes obsolete once the override is window-scoped.
- Do **not** force a SwiftUI `.id(appearanceMode)` recreation to drop the override —
  it rebuilds transient UI state (scroll/nav) and remains OS-flaky.

## Design Decisions

1. **System reset mechanism (iOS)**: window-level `UIWindow.overrideUserInterfaceStyle`,
   `.system → .unspecified`, `.light → .light`, `.dark → .dark`. `.unspecified` is
   the only reliable "clear override → follow the device" sentinel. Grounded in the
   proven community workaround; avoids the `nil` behavior entirely.

2. **macOS wiring**: AppKit-level appearance (System → cleared; Light/Dark →
   explicit), read at launch and re-applied on change. Net-new — no AppKit bridge
   exists today (`AppDelegate` is iOS-only) — implement a small macOS-side handler
   mirroring the iOS AppDelegate seam.

3. **Single source of truth** — remove `.preferredColorScheme` at
   `ContentView.swift:72` and `SettingsView.swift:142`, plus the old sheet re-apply
   rationale. The window override is the only appearance path.

4. **Drive from root `ContentView`** — apply the bridge from
   `.onChange(of: appearanceMode)` (and at launch). The shared `@AppStorage` is read
   by both the picker and the override, so one value drives both. `SettingsView`
   stays stateless; no new binding — the picker already writes `@AppStorage` eagerly.

5. **Unit-testable mapping** — put the enum→override mapping in a small pure
   function per platform (UIKit/AppKit types differ) and test System→`.unspecified`/
   cleared, Light, Dark, including the Light→System retake.

## What We're NOT Doing

- **Not** touching `@AppStorage` storage schema, defaults, or raw-value persistence.
- **Not** adding Appearance to the App Group sync target (the `showUndatedReminders`
  suite) or introducing a new storage key.
- **Not** changing the `SettingsView` picker UI or the stateless-binding design.
- **Not** adding SwiftUI `.id` / forced-recreation hacks.
- **Not** handling appearance per-scope — the sheet/root distinction is removed.
- **Not** adding new UI-test interaction flows unless needed — the fix is
  unit-testable; a pixel-level UI test is deferred (see Open Risks).

## Open Risks

- **UIKit/AppKit API availability on SDK 26.5** — verify `overrideUserInterfaceStyle`
  on `UIWindowScene` and the macOS AppKit appearance names against the installed SDK
  before coding; macOS is net-new and carries the highest compile risk.
- **Live device toggling in System** — `.unspecified` should reflect the device
  while in System; confirm the override re-reads the device trait when the OS
  appearance changes, not only at switch time.
- **Sheet/window scoping** — the window override covers the presented sheet as
  intended, but verify multiple `UIWindow`s / iPad Split View all follow uniformly.
- **Scenario/regression fidelity** — the simulator may not reproduce the OS nil
  defect; rely on the unit-level sentinel test plus manual simulator checks, and
  validate in CI (iPhone 17 + iPad (A16) simulators).
- **Sheet-only gaps after removing the reapply** — if SwiftUI scopes a sheet
  outside the window override on some OS, the sheet could stay stale; verify in
  both simulators that the sheet follows the override.
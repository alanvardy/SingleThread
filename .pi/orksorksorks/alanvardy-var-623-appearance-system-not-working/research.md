# Research Findings — Appearance System

SingleThread iOS app (`ContentView`-based). Appearance preference = `AppearanceMode`
enum persisted via `@AppStorage`, applied via `.preferredColorScheme(_:)`.

## Q1: How is `appearanceMode` declared and persisted?

### Findings
- Declared on `ContentView`:
  `SingleThread/ContentView.swift:128-129`
  ```swift
  @AppStorage("appearanceMode")
  private var appearanceMode = AppearanceMode.system
  ```
  - Storage key: `"appearanceMode"`.
  - Default: `AppearanceMode.system`.
  - **No `store:` argument** → SwiftUI default suite (`UserDefaults.standard`),
    NOT the App Group suite. Contrast: the only App-Group-backed `@AppStorage`
    in the struct is `showUndatedReminders` via `store: AppGroup.defaults`
    (`ContentView.swift:142`). Sibling default-suite keys: `"textSize"` (131),
    `"allowsLandscape"` (135), `"showMicrophoneButton"` (139).
- Enum: `SingleThread/AppearanceMode.swift:8-11` — `String, CaseIterable`
  ```swift
  enum AppearanceMode: String, CaseIterable {
      case system   // raw "system"
      case light    // raw "light"
      case dark     // raw "dark"
  }
  ```
  - Raw values are compiler-synthesized from the `String` raw type (no custom
    `init?(rawValue:)`, no custom `Codable`, no explicit `RawRepresentable`
    conformance anywhere in `SingleThread/`). Sole non-static members:
    `colorScheme` (16-22), `systemImage` (25-31), `title` (34-40).
- Readback: synthesized `init?(rawValue:)` maps `"system"`/`"light"`/`"dark"`
  → `.system`/`.light`/`.dark`. `CaseIterable` order confirmed by test
  `allCasesCoverSystemLightDark` (`SingleThreadTests/AppearanceModeTests.swift:23-25`).
- **Unknown-string fallback:** for a stored string that matches no case, the
  synthesized `init?(rawValue:)` returns `nil`. SwiftUI's `@AppStorage` raw-value
  wrapper then falls back to the property's default `AppearanceMode.system`
  (`ContentView.swift:129`). There is no enum-level decode path to `.light`
  or `.dark`; the fallback is always **System** (via the default, not via enum
  logic). Repo contains no explicit fallback code — this is framework behavior.
- Persistence plumbing: `SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift`
  defines `AppGroup.suiteName = "group.app.alanvardy.SingleThread"` (8-9) and
  `defaults` = `UserDefaults(suiteName:) ?? .standard` (14-16), but `appearanceMode`
  does **not** use it. `SingleThreadCore` has zero references to `AppearanceMode`.

## Q2: Where and how is `.preferredColorScheme(_:)` applied?

### Findings
- Exactly **two** call sites in the whole repo (watch, widget, and
  `SingleThreadCore` targets have none; `AppearanceMode.swift:6` is only a doc
  comment).
  1. Root `ContentView` root `ZStack` — `ContentView.swift:72`:
     ```swift
     .preferredColorScheme(appearanceMode.colorScheme)
     ```
     Value source `@AppStorage("appearanceMode")` (128-129). Placement in the
     chain (72-74): `.preferredColorScheme` → `.modifier(TextSizeModifier)` (73)
     → `.sheet(isPresented:$isShowingSettings)` (74). It decorates the root
     content subtree, NOT the sheet presentation.
  2. `SettingsView` (the sheet's content) body end — `SettingsView.swift:142`:
     ```swift
     .preferredColorScheme(appearanceMode.colorScheme)
     ```
     Value source `@Binding private var appearanceMode` (148), fed by
     ContentView's `$appearanceMode` (`ContentView.swift:77` iOS / `:86` else).
- Exact value per case (from `AppearanceMode.colorScheme`, `AppearanceMode.swift:16-22`):
  System → `nil`, Light → `.light`, Dark → `.dark`. Both call sites pass the
  *same* computed value.
- Sheet ⇄ root interaction:
  - The root modifier is **outside view** of the ZStack, **before** `.sheet`
    (72 vs 74), so it scopes to the root content only. The sheet is a separate
    presentation hosted by the presenting view; its content (`SettingsView`) is
    a distinct view that does not inherit the root's override as an applied
    preference — which is why `SettingsView` re-applies it on its own body (142).
  - While the sheet is up: both modifiers are simultaneously in effect in their
    own scopes; the sheet visually covers the root.
  - On dismissal: the root modifier was never removed — it is still attached to
    the root ZStack. With `appearanceMode` already updated through the shared
    `@AppStorage`/`@Binding`, the root content is revealed again with the new
    scheme. Root re-applies by remaining present, not by re-running on dismiss.
- Prior design rationale (repo note, not current source):
  `.pi/qrspi/alanvardy-var-617-turn-settings-menu-into-another-view/design.md:164-166`
  — "`.preferredColorScheme` / `.dynamicTypeSize` may not propagate into a
  presented sheet automatically on all platforms; mitigated by re-apply inside
  `SettingsView`."

## Q3: How does a `SettingsView` picker change propagate back to storage and observers?

### Findings
- Binding chain:
  - `ContentView` `@AppStorage` wrapped value → projected value `$appearanceMode`
    (a `Binding<AppearanceMode>`) passed in the sheet closure:
    `appearanceMode: $appearanceMode` at `ContentView.swift:77` (iOS) / `:86` (else),
    inside `.sheet(isPresented:$isShowingSettings)` (74). `isShowingSettings` is
    `@State private var isShowingSettings = false` (149), set `true` by the gear
    button (44).
  - `SettingsView` init takes `appearanceMode: Binding<AppearanceMode>`
    (iOS `SettingsView.swift:61`, else `:78`) and stores it via
    `_appearanceMode = appearanceMode` (`:68` / `:84`) into
    `@Binding private var appearanceMode: AppearanceMode` (`:148`).
  - `Picker("Appearance", selection: $appearanceMode)` (`SettingsView.swift:98`)
    iterates `AppearanceMode.allCases` with `.tag(mode)` (99-102). `$appearanceMode`
    here is the projected binding — the **same instance** passed from
    ContentView. No local `@State` copy, no `onChange`/`onDisappear` writeback.
- `SettingsView` is a separate struct but owns **no copy**; it holds the shared
  `@Binding` to ContentView's `@AppStorage`. `.constant(...)` bindings appear only
  in previews (`SettingsView.swift:167, 178, 189`).
- Timing (SwiftUI semantics, framework behavior — no in-repo code proof):
  - `@AppStorage` writes eagerly to UserDefaults on set; persistence is not
    deferred to dismiss (picker selection change immediately sets the stored
    value). No dismiss-time persistence code exists.
  - Root observes eagerly while the sheet is open: `@AppStorage` is a
    `DynamicProperty`; `ContentView.body` reads
    `appearanceMode.colorScheme` at `ContentView.swift:72`, so a binding write
    invalidates/re-evaluates ContentView's body (and its `.preferredColorScheme`
    modifier) while the sheet is still presented.
  - The sheet observes the same value eagerly too — its own
    `.preferredColorScheme` reads the shared binding (`SettingsView.swift:142`).
  - Dismiss handling is orthogonal: `@Environment(\.dismiss)` (156-157) + `Done`
    Button calling `dismiss()` (136-138); no appearance sync needed on dismiss.
- Attempting to verify binding timing from within `SettingsView` is limited: the
  only canonical `Binding`-seeded content exercised is in `SettingsViewTests`
  (`SingleThreadTests/SettingsViewTests.swift:12-27`), which uses `.constant(...)`
  and asserts labels only, not mutation timing.

## Q4: What does `.system` actually resolve to?

### Findings
- `AppearanceMode` is `String, CaseIterable` (`AppearanceMode.swift:8`), cases
  `system`/`light`/`dark` (9-11).
- `colorScheme: ColorScheme?` (`AppearanceMode.swift:16`) returns:
  `.system → nil` (18), `.light → .light` (19), `.dark → .dark` (20).
  `.system` resolves to **no `ColorScheme`** — `nil`.
- Doc comments state intent: `.system` produces `nil` so the app follows the
  device's appearance (`AppearanceMode.swift:6-7`); "The `ColorScheme` to prefer,
  or `nil` to follow the system." (15).
- Passed at both call sites as `appearanceMode.colorScheme`
  (`ContentView.swift:72`, `SettingsView.swift:142`).
- SwiftUI mapping: `.preferredColorScheme(_:)` takes `ColorScheme?`. `.light`
  /`.dark` install an explicit color-scheme preference in the view subtree's
  environment; `nil` installs no override so the view inherits from its
  environment — which, with no ancestor override, resolves to the device's
  current appearance.
- Stale? The enum is a pure switch over the stored value with no caching
  (`AppearanceMode.swift:16-22`), so the mapping itself cannot go stale; the
  current stored value (`.system → nil`) is always emitted.
- Staleness concern lives in the SwiftUI layer: a modifier re-evaluates when its
  input changes. `Dark → System` changes the input `.dark → nil` (non-nil to nil
  = a real change) and should clear the override. `System → System` changes
  nothing (`nil → nil`), so no re-evaluation is triggered. **The codebase has no
  comment, test, or control path proving that `.preferredColorScheme(nil)` after
  a prior non-nil reliably restores system-following** — that is framework
  behavior and is untested here. (`nil`-after-`.dark` re-application is exactly
  the scenario Q4 flags; it is not covered by any existing test or comment.)

## Q5: What testing / preview / regression coverage exists?

### Findings
- Frameworks: unit tests use **Swift Testing** (`@Test`, `#expect` —
  `AppearanceModeTests.swift:3`, `SettingsViewTests.swift:3`); UI + launch tests
  use **XCTest** (`SingleThreadUITests.swift:8`, `SingleThreadUITestsLaunchTests.swift:8`).
- `SingleThreadTests/AppearanceModeTests.swift` — `@MainActor struct` (6):
  - `systemMapsToNilColorScheme` (8-10): `AppearanceMode.system.colorScheme == nil`
  - `lightMapsToLightColorScheme` (13-15): `== .light`
  - `darkMapsToDarkColorScheme` (18-20): `== .dark`
  - `allCasesCoverSystemLightDark` (23-25): `allCases == [.system, .light, .dark]`
  - `titlesAreHumanReadable` (28-32): titles `"System"/"Light"/"Dark"`
  - Covers enum→ColorScheme mapping and static values only. No persistence,
    no cross-mode retake, no UserDefaults involvement.
- `SingleThreadTests/SettingsViewTests.swift` — single test
  `settingsViewContainsAllPreferenceRows` (10): builds `SettingsView` with
  `.constant(...)` bindings (iOS 12-19 / else 21-27), stringifies `view.body` (30)
  and asserts row labels `"Appearance"`/`"Text Size"`/`"Microphone"`/`"Show
  Undated"`/`"Excluded Projects"`/`"Done"` (34-39) + `"Landscape"` iOS-only (41).
  - **No UserDefaults readback** for `appearanceMode`/`textSize` anywhere in the
    suite. The only UserDefaults read/write patterns in unit tests are for
    `"showMicrophoneButton"` (`MicrophoneToggleTests.swift:54-55, 72-73, 85-86`)
    and `"allowsLandscape"` (`AppDelegateTests.swift:10, 21, 32`).
- `SingleThreadUITests/SingleThreadUITests.swift` — one test,
  `testAccessibilityAudit` (17): launches with `--ui-testing` (19), waits for
  visible text (25-27), runs `performAccessibilityAudit` for
  `[.dynamicType, .hitRegion, .sufficientElementDescription, .trait]` on iOS
  (32-33), defaults on macOS (37). **No settings navigation, no appearance
  toggle, no assertion that a preference change retakes effect.**
- `SingleThreadUITests/SingleThreadUITestsLaunchTests.swift` — `testLaunch` (23):
  launches and attaches a launch-screen screenshot (29-32). No interaction.
- Previews:
  - `ContentView.swift`: `#Preview` at 484, 488, 496, 504, 513.
    None vary appearance.
  - `SettingsView.swift`: iOS `#Preview("Default")` (165, `.constant(.system)`
    appearance) and `#Preview("Dark + Extra Large")` (176, `.constant(.dark)` /
    `.constant(.extraLarge)`, 178-179) — the **only** appearance/text-size
    variant preview; plus macOS `#Preview("Default")` (187).
- **No existing pattern asserts a preference change retakes effect across modes**
  (e.g. System → Dark → System verifying the applied `ColorScheme`). Tests cover
  only the static enum mapping and Form-row label presence.

## Cross-Cutting Observations
- Two-modifier pattern: the appearance preference is applied `.preferredColorScheme`
  at exactly one place per presentation scope — root `ContentView.swift:72` and
  sheet `SettingsView.swift:142` — both reading the same logical value, root via
  `@AppStorage`, sheet via the shared `@Binding`.
- `@AppStorage`/`@Binding` are the persistence-to-UI bridge; `SettingsView` is
  intentionally stateless ("Owns no state — every preference is bound back"
  doc comment at `SettingsView.swift:56-57`). The gear button toggles `@State
  isShowingSettings` (44, 149) to present the `.sheet` (74).
- `AppearanceMode` is a pure value enum (`String, CaseIterable`) with synthesized
  raw-value decoding; persistence falls back to `.system` for any unknown string
  purely through `@AppStorage`'s default (no repo-side fallback logic).
- The appearance key does not participate in App Group sync; it lives in the
  standard UserDefaults suite, unlike `showUndatedReminders`/`showMicrophoneButton`
  plumbing that crosses to `ReminderStore`/watch.
- The related design note documents the rationale for re-applying color scheme +
  text size inside the sheet as a cross-platform portability mitigation
  (`var-617/design.md:164-166`).

## Open Areas
- Whether `.preferredColorScheme(nil)` after a preceding `.light`/`.dark`
  reliably restores system-following is **framework (SwiftUI) behavior** that the
  codebase neither documents nor tests; there is no repo-side evidence for the
  `nil`/stale re-evaluation question (Q4/Q3 timing).
- Eager write/reevaluation timing (Q3) is inferred from `@AppStorage`/
  `DynamicProperty` semantics; nothing in the repo exercises or asserts it.
- No test covers unknown-string decode fallback, UserDefaults persistence
  readback for `appearanceMode`, or a cross-mode retake assertion (Q5 gaps).
- Exact byte-level line numbers for `SettingsView` init/`@Environment` positions
  were cross-checked; some line offsets (e.g. `SettingsView.swift:56-57` doc
  comment) may shift if earlier formatting changes.
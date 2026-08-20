# Structure Outline

Branch: `alanvardy-var-623-appearance-system-not-working`

## Approach

Replace the `.preferredColorScheme(_:)` path (which shuttles `nil` for System and fails
to tear down a prior override — the bug) with a **window-level override** per platform:
iOS `UIWindow.overrideUserInterfaceStyle` (System → `.unspecified` = "clear override → follow
device"), macOS `NSWindow.appearance` (System → `nil`). Applies at launch from persisted
`appearanceMode` and eagerly on change via root `ContentView.onChange`. Pure enum→override
mappings stay unit-testable. iOS and macOS are **parallel slices, not stacked layers** — each
is independently complete.

## Phase 1: iOS window override (the core fix)

Delivers the actual bug fix end-to-end on iOS: picking System/Light/Dark in Settings
re-applies the appearance at window level, and System reliably returns to the device
appearance — even replayed after Light/Dark, and while the sheet is open.

**Files**: `SingleThread/AppearanceMode.swift`, `SingleThread/AppDelegate.swift`,
`SingleThread/ContentView.swift`, `SingleThread/SettingsView.swift`,
`SingleThreadTests/AppearanceModeTests.swift`, `SingleThreadTests/AppDelegateTests.swift`

**Key changes**:
- `AppearanceMode.windowOverrideStyle: UIUserInterfaceStyle` — new pure switch
  (`#if os(iOS)` + `import UIKit`): `.system → .unspecified`, `.light → .light`, `.dark → .dark`
- `AppearanceMode.load(from defaults: UserDefaults = .standard) -> AppearanceMode` — new:
  reads `"appearanceMode"`; missing/unknown string → `.system` (closes the readback gap;
  mirrors AppDelegate's `allowsLandscape` launch read)
- `AppDelegate.applyAppearance(_ mode: AppearanceMode)` — new static; sets
  `overrideUserInterfaceStyle` on every `UIWindowScene.keyWindow` (covers iPad Split View);
  idempotent, so replaying Light→System converges on `.unspecified`
- Launch apply: AppDelegate reads `AppearanceMode.load()` and calls `applyAppearance`
  before the first frame (exact hook — `didFinishLaunching` vs `applicationDidBecomeActive` —
  pinned in `/5_plan`; windows may not exist at `didFinishLaunching`)
- `ContentView` body: add `.onChange(of: appearanceMode) { _, newValue in
  AppDelegate.applyAppearance(newValue) }` (`#if os(iOS)`) — beside the existing
  `showUndatedReminders` onChange; fires whether or not the sheet is open
- **Interim gate** (intentional cross-phase coupling): wrap both
  `.preferredColorScheme(appearanceMode.colorScheme)` call sites (`ContentView.swift:72`,
  `SettingsView.swift:142`) in `#if os(macOS)` so macOS behavior doesn't regress until Phase 2

**Verify**: `./scripts/test.sh --unit-only` (iPhone 17) passes, including: mapping tests
(`system → .unspecified`), `load()` readback + fallback tests, and an `AppDelegateTests`
replay test — `applyAppearance(.light)` then `applyAppearance(.system)` asserts the window
ends at `.unspecified`. Manual: Settings sheet open → System→Light→System and
System→Dark→System return to the device mode (toggle device appearance via sim
Settings → Developer); cold launch with persisted `.light` opens Light without flash.

---

## Phase 2: macOS AppKit parity

Delivers the same three modes at window level on macOS: System clears the explicit
appearance and follows the system; Light/Dark apply explicitly.

**Files**: `SingleThread/AppearanceMode.swift`, `SingleThread/AppDelegate.swift` (add
`#if os(macOS)` block), `SingleThread/SingleThreadApp.swift`, `SingleThread/ContentView.swift`,
`SingleThread/SettingsView.swift`, `SingleThreadTests/AppearanceModeTests.swift`

**Key changes**:
- `AppearanceMode.appKitAppearance: NSAppearance?` — new pure switch (`#if os(macOS)` +
  `import AppKit`): `.system → nil`, `.light → .aqua`, `.dark → .darkAqua`
- `MacAppDelegate: NSObject, NSApplicationDelegate` — new (same file as `AppDelegate`, new
  `#if os(macOS)` block): `static func applyAppearance(_ mode: AppearanceMode)` sets
  `NSApp.windows[].appearance`; `applicationDidFinishLaunching` applies `AppearanceMode.load()`
- `SingleThreadApp`: `@NSApplicationDelegateAdaptor(MacAppDelegate.self)` under
  `#if os(macOS)` (mirrors the iOS adaptor at `SingleThreadApp.swift:63`)
- `ContentView` `.onChange(of: appearanceMode)` gains the macOS arm:
  `MacAppDelegate.applyAppearance(newValue)`
- **Retire the old mapping**: delete the Phase 1 `#if os(macOS)` gates (both
  `.preferredColorScheme` call sites gone entirely), delete `AppearanceMode.colorScheme` and
  its 3 tests (`systemMapsToNilColorScheme`, `lightMapsToLightColorScheme`,
  `darkMapsToDarkColorScheme`) — the nil-into-SwiftUI mapping is retired by design; run
  `make periphery` to confirm nothing else dangles

**Verify**: `./scripts/test.sh` full pipeline passes, including the `platform=macOS` build
and macOS unit tests (new `#if os(macOS)` mapping tests: `system → nil`, `light → .aqua`,
`dark → .darkAqua`). Manual: macOS app — System→Light→Dark→System with the sheet open;
System follows System Settings → Appearance; cold launch with persisted `.dark` opens Dark.
`rg "preferredColorScheme"` returns 0 hits.

---

## Phase 3: Cross-platform regression sweep (verification-only)

No product code unless the sweep surfaces a defect. Retires the design.md open risks.

**Files**: none required; `@Test`s only if a gap appears (e.g. `allCases` order, unknown-string
fallback)

**Activity**:
- Full `./scripts/test.sh` twice: default (`iPhone 17`) and
  `SIM='platform=iOS Simulator,name=iPad (A16)'`
- Manual matrix (both simulators + macOS): System→Light→System / System→Dark→System; change
  the device appearance while in System (override re-reads the device trait at runtime);
  sheet follows the override in one window; iPad Split View / multiple windows uniform;
  cold launches in each persisted mode

**Verify**: all CI checks green on both iOS simulators + macOS; no stale-sheet or stale-mode
reports. Pixel-level appearance UI test remains deferred (design.md Open Risks).

## Testing Checkpoints

- **After Phase 1**: iOS fully fixed (unit tests + both simulators manually); macOS behavior
  untouched via the interim gate. `colorScheme` still referenced (macOS gate) so it stays live.
- **After Phase 2**: all three platforms honored at window level; zero
  `.preferredColorScheme` / `colorScheme` references in the repo; iOS + macOS unit tests green;
  Periphery clean.
- **After Phase 3**: full CI green on iPhone 17 + iPad (A16) + macOS; open risks closed or
  explicitly deferred in design.md.
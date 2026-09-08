# Implementation Plan

## Overview

Replace the `.preferredColorScheme(_:)` path (which shuttles `nil` for System and fails to tear down a prior override — the bug) with a window-level override per platform: iOS sets `UIWindow.overrideUserInterfaceStyle` (System → `.unspecified` = "clear override → follow device"), macOS sets `NSWindow.appearance` (System → `nil`). The override applies at launch from persisted `appearanceMode` and eagerly on change via root `ContentView.onChange(of: appearanceMode)`. iOS and macOS are parallel slices; each phase leaves the repo green.

Cross-cutting facts (verified):
- Target `SingleThread` is multi-platform (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`, deployment target 26.5) — same scheme/destination tests run on iOS simulators and `platform=macOS`.
- Bundle id: `app.alanvardy.SingleThread`. `appearanceMode` lives in the standard `UserDefaults` suite (key `"appearanceMode"`), NOT the App Group suite.
- App target has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; all new code is implicitly `@MainActor` — no extra annotations or `Task { @MainActor in }` needed.
- `AppearanceMode` is a pure `String, CaseIterable` enum with synthesized raw-value decoding; unknown/missing stored strings fall back to `.system`.

---

## Phase 1: iOS window override (the core fix)

### Changes

#### 1. `SingleThread/AppearanceMode.swift`
**Action**: modify

Add the UIKit import and the pure enum→`UIUserInterfaceStyle` mapping plus the persistence read. `colorScheme` stays (still referenced by the macOS-gated call sites and its 3 tests until Phase 2).

```swift
import SwiftUI

#if os(iOS)
    import UIKit
#endif

// MARK: - AppearanceMode

/// The app's appearance override, persisted in `UserDefaults` via `@AppStorage`.
/// Applied at the window level (`UIWindow.overrideUserInterfaceStyle` on iOS,
/// `NSWindow.appearance` on macOS). `.system` clears the override so the app
/// follows the device.
enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    // MARK: Internal

    #if os(iOS)
        /// The window interface style to force, or the "clear override → follow
        /// device" sentinel for `.system`.
        var windowOverrideStyle: UIUserInterfaceStyle {
            switch self {
            case .system: .unspecified
            case .light: .light
            case .dark: .dark
            }
        }
    #endif

    /// Reads the persisted appearance from `UserDefaults`, defaulting to
    /// `.system` for a missing or unknown value. Mirrors `AppDelegate`'s
    /// `allowsLandscape` launch read and `@AppStorage`'s fallback-to-default.
    static func load(from defaults: UserDefaults = .standard) -> AppearanceMode {
        guard let rawValue = defaults.object(forKey: "appearanceMode") as? String,
              let mode = AppearanceMode(rawValue: rawValue)
        else { return .system }
        return mode
    }

    /// The `ColorScheme` to prefer, or `nil` to follow the system.
    var colorScheme: ColorScheme? { /* unchanged — removed in Phase 2 */ }

    // ... `systemImage` and `title` unchanged ...
}
```

> `load(from:)` is `MainActor`-isolated by default; it is only called from `AppDelegate`/`MacAppDelegate` lifecycle methods, both of which are already `@MainActor`.

#### 2. `SingleThread/AppDelegate.swift`
**Action**: modify

Add `applyAppearance(_:to:)` and the launch hook. **Hook pinned here (was open in structure): `applicationDidBecomeActive(_:)`** — at `didFinishLaunching` no `UIWindowScene` is connected yet (`connectedScenes` is empty), so applying there is a guaranteed no-op. By `applicationDidBecomeActive` the scene is connected and its windows exist, so the override lands before the first rendered frame (no flash). It also re-fires on subsequent activations, which is harmless (idempotent) and re-syncs after the device appearance changes while backgrounded.

Apply to **every window of every connected `UIWindowScene`** (strict superset of "each scene's keyWindow"; covers iPad Split View scenes and non-key windows). The `to windows:` parameter exists so the replay test can inject a deterministic `UIWindow` instead of depending on the live host-app window.

```swift
        /// Applies the persisted appearance to every window in every connected
        /// scene, and on demand to explicit windows. The `.system` sentinel
        /// (`.unspecified`) clears any prior override so the window re-follows
        /// the device — replaying Light → System converges reliably.
        static func applyAppearance(_ mode: AppearanceMode, to windows: [UIWindow]? = nil) {
            let targets = windows
                ?? UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
            for window in targets {
                window.overrideUserInterfaceStyle = mode.windowOverrideStyle
            }
        }

        func applicationDidBecomeActive(_ application: UIApplication) {
            Self.applyAppearance(AppearanceMode.load())
        }
```

No change to `applyLock` or `supportedInterfaceOrientationsFor`; the `#if os(iOS)` wrapper stays.

#### 3. `SingleThread/ContentView.swift`
**Action**: modify

Immediately after the existing `.onChange(of: showUndatedReminders)` block (current line 68-70): add the iOS appearance bridge, and gate the root `.preferredColorScheme` call (current line 72) with `#if os(macOS)` so macOS behavior is untouched until Phase 2.

```swift
        .onChange(of: showUndatedReminders) { _, newValue in
            store.showsUndatedReminders = newValue
            Task { await store.reload() }
        }
        #if os(iOS)
            .onChange(of: appearanceMode) { _, newValue in
                AppDelegate.applyAppearance(newValue)
            }
        #endif
        #if os(macOS)
            .preferredColorScheme(appearanceMode.colorScheme)
        #endif
        .modifier(TextSizeModifier(textSize: textSize))
```

The `$appearanceMode` projection that `SettingsView` receives is the same `@AppStorage` binding, so a picker change inside the sheet invalidates `ContentView` and fires this `onChange` whether or not the sheet is open.

#### 4. `SingleThread/SettingsView.swift`
**Action**: modify

Gate the sheet's `.preferredColorScheme` (current line 142) the same way (interim gate; removed in Phase 2):

```swift
        }
        #if os(macOS)
            .preferredColorScheme(appearanceMode.colorScheme)
        #endif
        .modifier(TextSizeModifier(textSize: textSize))
```

#### 5. `SingleThreadTests/AppearanceModeTests.swift`
**Action**: modify

Add iOS-gated mapping tests and the `load(from:)` readback/fallback tests (pure, no SwiftUI dependency — imports stay as-is in Phase 1):

```swift
    #if os(iOS)
        @Test
        func systemMapsToUnspecifiedWindowStyle() {
            #expect(AppearanceMode.system.windowOverrideStyle == .unspecified)
        }

        @Test
        func lightMapsToLightWindowStyle() {
            #expect(AppearanceMode.light.windowOverrideStyle == .light)
        }

        @Test
        func darkMapsToDarkWindowStyle() {
            #expect(AppearanceMode.dark.windowOverrideStyle == .dark)
        }
    #endif

    @Test
    func loadReadsPersistedValue() {
        UserDefaults.standard.set("dark", forKey: "appearanceMode")
        #expect(AppearanceMode.load() == .dark)
    }

    @Test
    func loadFallsBackToSystemWhenKeyMissing() {
        UserDefaults.standard.removeObject(forKey: "appearanceMode")
        #expect(AppearanceMode.load() == .system)
    }

    @Test
    func loadFallsBackToSystemOnUnknownString() {
        UserDefaults.standard.set("sepia", forKey: "appearanceMode")
        #expect(AppearanceMode.load() == .system)
    }
```

Each `load` test seeds its own value first, so test order can't interfere. The 3 existing `colorScheme` tests remain (deleted in Phase 2).

#### 6. `SingleThreadTests/AppDelegateTests.swift`
**Action**: modify

Add the replay test (Light → System converges on `.unspecified`). Uses an injected window so it does not depend on host-app scene timing:

```swift
        @Test
        func replayingSystemAfterLightClearsWindowOverride() {
            let window = UIWindow(frame: .zero)

            AppDelegate.applyAppearance(.light, to: [window])
            #expect(window.overrideUserInterfaceStyle == .light)

            AppDelegate.applyAppearance(.system, to: [window])
            #expect(window.overrideUserInterfaceStyle == .unspecified)
        }
```

(`import UIKit` is already present in this file; the struct is `@MainActor`.)

### Verification

#### Automated
- [x] `./scripts/test.sh --unit-only` passes on iPhone 17 (includes the 3 new `windowOverrideStyle` mapping tests, 3 `load()` tests, and the replay test)
- [x] `make lint` passes (`swiftformat --lint` + `swiftlint lint --strict`)
- [x] `make periphery` clean (no dangles; `colorScheme` stays used via tests + macOS-gated call sites)
- [x] Full `./scripts/test.sh` passes — proves the interim gate leaves macOS behavior untouched

#### Manual
- [ ] iPhone 17 simulator: launch → gear → Appearance → pick Light; UI goes light while the sheet is open
- [ ] System → Light → System with the sheet open: returns to the device appearance
- [ ] System → Dark → System with the sheet open: returns to the device appearance
- [ ] In System mode, toggle device appearance (sim Settings → Developer → Dark Appearance) and confirm the app follows immediately
- [ ] Cold launch with persisted Light opens Light without a wrong-appearance flash:
  ```fish
  xcrun simctl terminate booted app.alanvardy.SingleThread
  xcrun simctl spawn booted defaults write app.alanvardy.SingleThread appearanceMode -string light
  xcrun simctl launch booted app.alanvardy.SingleThread
  ```
- [ ] Repeat cold-launch check for `dark` and for a deleted key (returns to System)

---

## Phase 2: macOS AppKit parity

### Changes

#### 1. `SingleThread/AppearanceMode.swift`
**Action**: modify

Remove `import SwiftUI` (no longer used — `ColorScheme` goes away), add the AppKit import and the macOS mapping, update the file-top doc comment (shown in Phase 1, final text: "Applied at the window level… `.system` clears the override so the app follows the device."), and **delete the `colorScheme` property entirely**.

```swift
#if os(iOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

// MARK: - AppearanceMode

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    // MARK: Internal

    #if os(iOS)
        var windowOverrideStyle: UIUserInterfaceStyle { /* Phase 1, unchanged */ }
    #endif

    #if os(macOS)
        /// The `NSAppearance` to force, or `nil` for `.system` (clear override
        /// → follow the system).
        var appKitAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    #endif

    static func load(from defaults: UserDefaults = .standard) -> AppearanceMode { /* Phase 1, unchanged */ }

    // ... `systemImage` and `title` unchanged ...
}
```

#### 2. `SingleThread/AppDelegate.swift`
**Action**: modify

Add a `#if os(macOS)` block **after** the existing `#endif` that closes the iOS `AppDelegate`, defining `MacAppDelegate`. It applies at `applicationDidFinishLaunching` **and** `applicationDidBecomeActive` — SwiftUI does not guarantee `NSApp.windows` is populated at `didFinishLaunching`, so the second hook catches the window once it exists (idempotent, so double-apply is harmless) and re-syncs on every activation.

```swift
#if os(macOS)
    import AppKit

    /// Bridges the persisted appearance into every `NSWindow`, mirroring the
    /// iOS `AppDelegate` seam. Registered via `@NSApplicationDelegateAdaptor`.
    final class MacAppDelegate: NSObject, NSApplicationDelegate {
        /// Re-applies `mode` to every open window. `.system` sets `nil`,
        /// clearing the explicit appearance so the window follows the system.
        static func applyAppearance(_ mode: AppearanceMode) {
            for window in NSApp.windows {
                window.appearance = mode.appKitAppearance
            }
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            applyLaunchAppearance()
        }

        func applicationDidBecomeActive(_ notification: Notification) {
            applyLaunchAppearance()
        }

        private func applyLaunchAppearance() {
            Self.applyAppearance(AppearanceMode.load())
        }
    }
#endif
```

#### 3. `SingleThread/SingleThreadApp.swift`
**Action**: modify

Mirror the iOS adaptor (current line 63) with a macOS arm:

```swift
    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self)
        private var appDelegate
    #endif
    #if os(macOS)
        @NSApplicationDelegateAdaptor(MacAppDelegate.self)
        private var macAppDelegate
    #endif
```

#### 4. `SingleThread/ContentView.swift`
**Action**: modify

Extend the `onChange` to both platforms and **delete the interim gate** (the `.preferredColorScheme` line and its `#if os(macOS)` wrapper):

```swift
        .onChange(of: appearanceMode) { _, newValue in
            #if os(iOS)
                AppDelegate.applyAppearance(newValue)
            #elseif os(macOS)
                MacAppDelegate.applyAppearance(newValue)
            #endif
        }
        .modifier(TextSizeModifier(textSize: textSize))
```

#### 5. `SingleThread/SettingsView.swift`
**Action**: modify

**Delete** the interim gate entirely — the window override now covers the sheet, making the sheet-level re-apply obsolete. Result: the body ends with `.modifier(TextSizeModifier(textSize: textSize))` only. The `@Binding appearanceMode` stays (the picker still uses it).

#### 6. `SingleThreadTests/AppearanceModeTests.swift`
**Action**: modify

Remove the 3 `colorScheme` tests (`systemMapsToNilColorScheme`, `lightMapsToLightColorScheme`, `darkMapsToDarkColorScheme`), `import SwiftUI` (now unused — analyzer rule `unused_import` is enabled), and add the macOS-gated mapping tests. Compare by `name` rather than instance equality (`NSAppearance(named:)` instances are not guaranteed identical):

```swift
    #if os(macOS)
        @Test
        func systemClearsAppKitAppearance() {
            #expect(AppearanceMode.system.appKitAppearance == nil)
        }

        @Test
        func lightMapsToAqua() {
            #expect(AppearanceMode.light.appKitAppearance?.name == .aqua)
        }

        @Test
        func darkMapsToDarkAqua() {
            #expect(AppearanceMode.dark.appKitAppearance?.name == .darkAqua)
        }
    #endif
```

Final imports for the file: `@testable import SingleThread`, `import Testing`, `#if os(iOS) import UIKit #endif`, `#if os(macOS) import AppKit #endif` (alphabetical per block — `sorted_imports` opt-in rule).

#### 7. No schema/migration impact
`AppearanceMode` raw values (`"system"`/`"light"`/`"dark"`) and the `@AppStorage` default unchanged; no codegen involved. No existing test asserts a schema version.

### Verification

#### Automated
- [x] `./scripts/test.sh` full pipeline passes — includes `make format`, lint, iOS build, Periphery, iPhone 17 unit + UI tests, **macOS build**, and **macOS unit tests** (the 3 new `#if os(macOS)` mapping tests + `load()` tests run on `platform=macOS`)
- [x] `make mac-test` passes standalone (macOS-only unit tests)
- [x] `rg -n "preferredColorScheme|colorScheme" SingleThread/ SingleThreadTests/` returns 0 hits
- [x] `make periphery` clean — confirms nothing dangles after deleting `colorScheme`

#### Manual
- [ ] macOS app: gear → Appearance → System → Light → Dark → System with the sheet open; each switch takes effect immediately
- [ ] In System mode, toggle System Settings → Appearance → Dark; app follows (override cleared)
- [ ] Cold launch with persisted `dark`:
  ```fish
  defaults write app.alanvardy.SingleThread appearanceMode dark
  killall SingleThread
  open -a ...
  ```
  opens Dark without a flash; repeat for `light` and for a deleted key (System)
- [ ] Note: a brand-new window opened via File ▸ New Window while the app is already active and in an explicit mode is a known edge (new window inherits system until next activation/change) — flagged for the Phase 3 sweep

---

## Phase 3: Cross-platform regression sweep (verification-only)

No product code unless the sweep surfaces a defect (then fix + re-run the full pipeline). Files: none required; `@Test`s only if a gap appears (e.g. `allCases` order after the mapping additions, unknown-string fallback — both already covered).

### Verification

#### Automated
- [x] `./scripts/test.sh` passes on default `iPhone 17`
- [x] `SIM='platform=iOS Simulator,name=iPad (A16)' ./scripts/test.sh` passes (full pipeline on iPad, matching the CI matrix)
- [x] Both unit-test runs above are green on the new appearing tests (`system → .unspecified` / `light → .light` / `dark → .dark`; `load()` readback + fallback; replay test; macOS `system → nil` / `→ .aqua` / `→ .darkAqua`)

#### Manual
- [ ] iPhone 17 + iPad (A16) + macOS: System → Light → System and System → Dark → System with the sheet open — each returns to the device appearance
- [ ] Change the device appearance while in System on both iOS simulators (Settings → Developer → Dark Appearance) — the override re-reads the device trait at runtime, not only at switch time
- [ ] Sheet follows the override in both iOS simulators (design.md open risk "sheet-only gaps")
- [ ] iPad Split View: two scenes side by side, switch modes once — both uniform (open-risks "multi-window uniformity")
- [ ] macOS: open a second window (File ▸ New Window) while in Light; if it doesn't follow, fix = observe `NSWindow.didBecomeKeyNotification` in `MacAppDelegate` and re-apply (product code only if this defect is confirmed)
- [ ] Cold launches in each persisted mode on all three targets (no wrong-appearance flash)
- [ ] No stale-sheet or stale-mode reports; UI-test accessibility audit still passes (included in `./scripts/test.sh`)

---

## Phase-to-phase notes

- After Phase 1: iOS fully fixed; macOS untouched via the interim gate; `colorScheme` still referenced (macOS gate + 3 tests) so it stays live for Periphery.
- After Phase 2: all three platforms honored at window level; zero `.preferredColorScheme`/`colorScheme` references; iOS + macOS unit tests green; Periphery clean.
- After Phase 3: full CI green on iPhone 17 + iPad (A16) + macOS; open risks closed or explicitly deferred (pixel-level appearance UI test remains deferred per design.md).
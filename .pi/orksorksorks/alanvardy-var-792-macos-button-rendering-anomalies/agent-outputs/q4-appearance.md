# Q4 — Light/dark appearance adaptation for buttons and backgrounds (file:line trace)

All line references are against the current working tree at repo root `/Users/vardy/dev/alanvardy-var-792-macos-button-rendering-anomalies`. Findings are descriptive only; no suggestions.

---

## 1. `SingleThread/Color+CrossPlatform.swift` (22 lines, read fully)

The file is a single `extension Color` with one member.

- `Color+CrossPlatform.swift:1` — `import SwiftUI`; `:3-7` platform import gate: `#if os(macOS) import AppKit #else import UIKit #endif` (the `#else` covers iOS AND watchOS per the doc comment at `:12`).
- `Color+CrossPlatform.swift:9` — `extension Color {`.
- `Color+CrossPlatform.swift:15-21` — the only defined symbol, `static var systemBackground: Color`:
  - `:16-17` — `#if os(macOS)` → `Color(nsColor: .windowBackgroundColor)` (i.e. `NSColor.windowBackgroundColor`).
  - `:18-19` — `#else` → `Color(uiColor: .systemBackground)` (i.e. `UIColor.systemBackground`).
  - `:12-14` — doc: exists so shared views reference one symbol instead of guarding each platform inline.

No other cross-platform colors exist in this file. The only other AppKit/UIKit to SwiftUI Color bridge in the repo is `CodeSpanFormatter.platformSecondaryBackground()`:
- `SingleThreadCore/Sources/SingleThreadCore/CodeSpanFormatter.swift:138-151`:
  - `:140-142` watchOS → `SwiftUI.Color.gray.opacity(0.15)`
  - `:144-145` UIKit → `SwiftUI.Color(uiColor: .secondarySystemBackground)`
  - `:147-148` AppKit → `SwiftUI.Color(nsColor: .underPageBackgroundColor)` (comment at `:147` notes macOS has no `.secondarySystemBackground`)
  - `:150-151` fallback → `gray.opacity(0.15)`; applied to `AttributedString.backgroundColor` at `:131`.

`Color.systemBackground` consumers:
- `SingleThread/ContentView.swift:183` — `Color.systemBackground.ignoresSafeArea()` (first child of the root ZStack, behind the photo layer and content).
- `SingleThread/ContentView.swift:184-188` — `BackgroundPhotoLayer(...)` stacked on top.
- Test: `SingleThreadTests/ColorCrossPlatformTests.swift:9-11` asserts `String(describing: color)` is non-empty (no per-platform value assertion).

---

## 2. `SingleThread/AppearanceMode.swift` (85 lines, read fully)

- `AppearanceMode.swift:2-4` — `#if os(iOS) import UIKit`; `:5-7` — `#if os(macOS) import AppKit`.
- `AppearanceMode.swift:15` — `enum AppearanceMode: String, CaseIterable`; `:16-18` cases `system`, `light`, `dark`.
- iOS mapping `windowOverrideStyle: UIUserInterfaceStyle` `:22-32`: `:27` `.system` → `.unspecified` (clear-override sentinel); `:28` `.light` → `.light`; `:29` `.dark` → `.dark`.
- macOS mapping `appKitAppearance: NSAppearance?` `:34-44`: `:39` `.system` → `nil` (clear override); `:40` `.light` → `NSAppearance(named: .aqua)`; `:41` `.dark` → `NSAppearance(named: .darkAqua)`.
- Shared `colorScheme: ColorScheme?` `:50-56`: `:52` `.system` → `nil`; `:53` `.light` → `.light`; `:54` `.dark` → `.dark`. Doc at `:46-49` says it exists for SwiftUI previews only (previews have no window to override).
- Presentation: `systemImage` `:59-65`; `title` `:68-74`.
- Persistence: `load(from:)` `:79-84` reads UserDefaults key `appearanceMode`, falling back to `.system` on missing/unknown raw value (`:80-82`).

### What is set (and what is not)
- `.preferredColorScheme(_:)` is used in previews only, via `AppearanceMode.dark.colorScheme`:
  - `SingleThread/ContentView+Previews.swift:39` (Empty preview) and `:57` (With Reminder preview)
  - `SingleThread/SettingsView.swift:216` (Dark + Extra Large preview)
- `.environment(\.colorScheme)` is used nowhere in the repo (grep across `SingleThread/`, `SingleThreadWatch/`, `SingleThreadWidget/`, `SingleThreadCore/` — no matches).
- No `.preferredColorScheme` in the watch or widget targets (grep: no matches in either directory).

### Where AppearanceMode is applied at runtime
- `SingleThread/ContentView.swift:72-73` — `@AppStorage("appearanceMode") var appearanceMode = AppearanceMode.system`.
- `SingleThread/InterfaceSettingsView.swift:9` — `@Binding var appearanceMode`; Picker `:35-46` (ForEach over AppearanceMode.allCases, accessibilityIdentifier `appearancePicker` at `:46`).
- Sheet write-back: `SingleThread/ContentView+Settings.swift:19` — `.onChange(of: bag.appearanceMode)` → writes `appearanceMode`.
- Dispatch: `SingleThread/ContentView.swift:277-278` — `.onChange(of: appearanceMode)` → `viewModel.handleAppearanceMode(newValue)`.
- `SingleThread/ContentViewModel.swift:130-135` — `handleAppearanceMode(_ mode:)`: `:131-132` `#if os(iOS) AppDelegate.applyAppearance(mode)`; `:133-134` `#elseif os(macOS) MacAppDelegate.applyAppearance(mode)`.

iOS AppDelegate (`#if os(iOS)`, `SingleThread/AppDelegate.swift:1-60`):
- `:15-23` — `applyAppearance(_:to:)` sets `window.overrideUserInterfaceStyle = mode.windowOverrideStyle` (`:21`) on every window of every connected UIWindowScene (`:16-20`).
- `:45-48` — `applicationDidBecomeActive` → `Self.applyAppearance(AppearanceMode.load())` (`:47`).

macOS MacAppDelegate (`#if os(macOS)`, `SingleThread/AppDelegate.swift:62-92`):
- `:72-76` — `applyAppearance(_:)` sets `window.appearance = mode.appKitAppearance` (`:74`) for every `NSApp.windows` entry.
- `:78-80` — `applicationDidFinishLaunching` → `applyLaunchAppearance()`; `:82-84` — `applicationDidBecomeActive` → `applyLaunchAppearance()`; `:88-90` — `applyLaunchAppearance()` reads `AppearanceMode.load()`.

Adaptors: `SingleThreadApp.swift:32-35` — `@UIApplicationDelegateAdaptor(AppDelegate.self)`; `:36-39` — `@NSApplicationDelegateAdaptor(MacAppDelegate.self)`. No appearance modifier is attached to the WindowGroup at `SingleThreadApp.swift:19-24`.

Tests: `SingleThreadTests/AppearanceModeTests.swift` — `:15-22` iOS windowOverrideStyleMaps; `:27-34` macOS appKitAppearanceMaps; `:37-43` colorSchemeMaps; `:46-49` loadReadsPersistedValue; `:51-55` loadFallsBackToSystemOnMissingOrUnknown; `:57-61` allCasesAndTitlesAreHumanReadable.

---

## 3. Scheme-adaptive fills on buttons/cards

### 3a. `ControlPlateModifier.swift` — adaptive circular button plate
- `SingleThread/ControlPlateModifier.swift:20-22` — `body` resolves:
  - `:21` — `resolvedFill = fill ?? (colorScheme == .dark ? .black : Color(white: Self.lightPlateWhite))`
  - `:22` — `resolvedGlyph = glyph ?? (colorScheme == .dark ? .white : Color(white: Self.darkGlyphWhite))`
  - i.e. dark → black plate / white glyph; light → off-white (0.92) / near-black (0.15).
- `:24-28` — applies `.foregroundStyle(resolvedGlyph)`, `56×56` frame (`:26`, `Self.plateSize` = 56 at `:33`), `.background(resolvedFill, in: Circle())` (`:27`), `.shadow(radius: 4)` (`:28`, constant at `:36`).
- Constants `:33-36`: `plateSize` 56 (`:33`), `lightPlateWhite` 0.92 (`:34`), `darkGlyphWhite` 0.15 (`:35`), `shadowRadius` 4 (`:36`).
- `:38-39` — `@Environment(\.colorScheme) private var colorScheme`.
- `:51-55` — `View.controlPlate(fill:glyph:)` extension entry point.

Call sites (button/control glyphs):
- `SingleThread/ContentView.swift:201` — gear (Settings) button, `.controlPlate()`.
- `SingleThread/ContentView.swift:217` — macOS-only Refresh button (inside `#if os(macOS)` overlay `:211-226`).
- `SingleThread/ContentView.swift:235` — iOS-only Undo button (inside `#if os(iOS)` overlay `:227-245`).
- `SingleThread/ContentView.swift:507` — iOS Complete button.
- `SingleThread/ContentView.swift:536` — mic/dictate button.
- `SingleThread/ContentView.swift:546` — recording indicator `.controlPlate(fill: .red, glyph: .white)`.
- `SingleThread/ContentView.swift:588` — creation feedback bubble `.controlPlate(fill: feedback.backgroundColor, glyph: .white)`; `feedback.backgroundColor` = fixed `.green`/`.red` at `SingleThread/CreationFeedback.swift:20-25`.
- `SingleThread/ContentView+ActionMenu.swift:41` — iOS Skip button `.controlPlate()`.

### 3b. `CardPlate.swift` + `CardPlateModifier.swift` — adaptive card plates
- `SingleThread/CardPlate.swift:16` — `cornerRadius = 10`.
- `SingleThread/CardPlate.swift:23` — `promptBoxFill = Color(red: 0.16, green: 0.17, blue: 0.18)` (fixed dark grey, not adaptive).
- `SingleThread/CardPlate.swift:29-30` — `plateFill(for colorScheme:)`:
  - `:30` — `colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.95, blue: 0.94)` — dark → black; light → off-white (0.96/0.95/0.94).
- `SingleThread/CardPlateModifier.swift:17-30` — `CardPlateModifier.body`: `.padding(padding)` (`:23`), `.background { RoundedRectangle(cornerRadius: CardPlate.cornerRadius).fill(fill) }` (`:25-27`), undo `.padding(restoresGeometry ? -padding : 0)` (`:29`). Entry point `:45-49`.

Adaptive (scheme-dependent) uses:
- `SingleThread/ReminderCardView.swift:44` — `.cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 12, restoresGeometry: true)`; scheme read at `:49-50`.
- `SingleThread/EmptyStateCard.swift:34` — `.cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 20)`; scheme read at `:48-49`.

Fixed (scheme-independent) use:
- `SingleThread/ReminderCardView.swift:207` — swipe-prompt box `.cardPlate(fill: CardPlate.promptBoxFill)`.

Tests pinning these decisions (rendered paint is not asserted; the constants are):
- `SingleThreadTests/CardPlateTests.swift:15-38` — corner radius `:16-18`; prompt fill `:19-22`; light fill `:23-26`; dark fill `:27-29`; light≠dark `:31-38`.
- `SingleThreadTests/BackgroundCardTests.swift:56-79` — row-chrome clear asserts `:56-64` (`rowChromeBackground == Color.clear` at `:60-61`, `:66-68`); `plateFill` light/dark asserts `:69-79`.
  - Row chrome seam: `SingleThread/ContentViewModel.swift:73-75` — `rowChromeBackground = .clear`; applied at `SingleThread/ContentView.swift:428` `.listRowBackground(viewModel.rowChromeBackground)`; List opacity seams `:479` `.scrollContentBackground(.hidden)` and `:482` `.background(Color.clear)`.
- `SingleThreadTests/SwipePromptTests.swift:34-66` — reflects `CardPlateModifier` in the card type chain (`:42-46`), hint styles orange/green (`:47-48`), `promptBoxIsDarkGrey` (`:52-55`), `BorderedProminentButtonStyle` on Dismiss (`:62-66`).
- `SingleThreadTests/SingleThreadTests.swift:95-101` — macOS-only reflected signature containing `ControlPlateModifier`.

### 3c. Fixed white-on-black / black-on-white contrast (existing implementations)
- Swipe-prompt Dismiss: `SingleThread/ReminderCardView.swift:186-197` — label `.foregroundStyle(.black)` (`:190`) on `.buttonStyle(.borderedProminent)` (`:194`) + `.tint(.white)` (`:195`), over the fixed dark-grey `promptBoxFill` plate (`:207`). White button / black text / dark-grey plate identical in both schemes.
- Swipe-prompt divider: `SingleThread/ReminderCardView.swift:174` — `.foregroundStyle(.white.opacity(0.5))` between orange hint `:171` and green hint `:173`.
- Nudge banner: `SingleThread/ReminderCardView.swift:142-162` — `.foregroundStyle(.orange)` label (`:150`) + `.buttonStyle(.borderedProminent)` (`:153`) + `.tint(.white)` (`:154`) — fixed white prominent button in both schemes.
- Upgrade button: `SingleThread/PurchaseSettingsView.swift:174-192` — `UpgradePromptButton` label `.foregroundStyle(.white)` (`:184`) over `.background(.blue, in: Capsule())` (`:188`), `.shadow(radius: 4)` (`:189`) — fixed white-on-blue in both schemes.
- Adaptive black/white switching fills (the pair that flips with the scheme) are exactly: `SingleThread/ControlPlateModifier.swift:21-22` (black plate / white glyph vs off-white plate / near-black glyph) and `SingleThread/CardPlate.swift:30` (black vs off-white 0.96/0.95/0.94).

### 3d. System semantic colors in use
- `.foregroundStyle(.secondary)` (system-adaptive secondary label): `SingleThread/ReminderCardView.swift:93,103,111,120,125`; `SingleThread/ContentView.swift:650,660,668,692`; `SingleThread/EmptyStateCard.swift:30`; `SingleThread/SettingsCaption.swift:14`; `SingleThread/PurchaseSettingsView.swift:100,129`; widget `SingleThreadWidget/NextThingWidget.swift:173,182,195,205,210,215,221,227`; watch `SingleThreadWatch/WatchReminderView.swift:170,227,231,345,350,355,360,365`.
- No `Color.primary` / `.foregroundStyle(.primary)` anywhere in `SingleThread/` (grep: no matches).
- Widget: `SingleThreadWidget/NextThingWidget.swift:100` — `.containerBackground(.fill.tertiary, for: .widget)` (semantic fill); action buttons `.tint(.green)` + `.buttonStyle(.bordered)` (`:153-154`) and `.tint(.orange)` + `.buttonStyle(.bordered)` (`:162-163`) — framework colors, no scheme branches.
- Watch: no scheme-adaptive color code exists in `SingleThreadWatch/` — only `.tint(.green)` `WatchReminderView.swift:137`, `.tint(.orange)` `:152`, `.foregroundStyle(.secondary)` rows, and `priorityColor` (`.green`/`.yellow`/`.red`) `:373-378`. No `Color(`, `.background(`, `RoundedRectangle`, or `.black`/`.white` matches in the watch target.
- Completion glow (not appearance-adaptive): `Color.green.opacity(0.1)` `SingleThread/ContentView.swift:556-564`; watch variant `Color.green.opacity(0.3)` `SingleThreadWatch/WatchReminderView.swift:189-198`; state machine in `SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift` — `isActive` `:22`, `duration` `:27`, `trigger()` `:33-44`; Core holds no color at all.
- `SingleThread/BackgroundFade.swift` — no color/scheme logic; only opacity mapping `:27-30` (`opacity(for:)` = `1 - percent/100`), consumed at `SingleThread/ContentView.swift:186`.

---

## 4. Where appearance handling differs macOS vs iOS (platform-gated code)

| Concern | macOS | iOS/watchOS |
|---|---|---|
| Color bridge import gate | `#if os(macOS) import AppKit` `Color+CrossPlatform.swift:3-4` | `#else import UIKit` `:5-6` |
| System background | `Color(nsColor: .windowBackgroundColor)` `:16-17` | `Color(uiColor: .systemBackground)` `:18-19` |
| Appearance override enum | `NSAppearance?` `.aqua`/`.darkAqua`/`nil` `AppearanceMode.swift:34-44` | `UIUserInterfaceStyle` `.light`/`.dark`/`.unspecified` `:22-32` |
| Runtime apply | `NSWindow.appearance` `AppDelegate.swift:72-76`; hooks `applicationDidFinishLaunching` `:78-80` + `applicationDidBecomeActive` `:82-84` (`#if os(macOS)` `:62-92`) | `UIWindow.overrideUserInterfaceStyle` `AppDelegate.swift:15-23`; hook `applicationDidBecomeActive` `:45-48` (`#if os(iOS)` `:1-60`) |
| SwiftUI color-scheme modifier | none outside `#Preview` blocks (`ContentView+Previews.swift:39,57`; `SettingsView.swift:216`) | same |
| ViewModel dispatch | `MacAppDelegate.applyAppearance(mode)` `ContentViewModel.swift:133-134` | `AppDelegate.applyAppearance(mode)` `:131-132` |
| App-delegate adaptor | `@NSApplicationDelegateAdaptor` `SingleThreadApp.swift:36-39` | `@UIApplicationDelegateAdaptor` `:32-35` |
| Floating controls | macOS-only Refresh plate `#if os(macOS)` `ContentView.swift:211-226` | iOS-only Undo plate `#if os(iOS)` `:227-245` |
| Bottom-bar action buttons | macOS `actionButtons` (`ContentView.swift:634`; body `ContentView+ActionMenu.swift:75-160`) use plain default-styled Buttons with `.tint(.green/.orange/.red)` + `.keyboardShortcut`, **no controlPlate** (`macCompleteButton` `:87-99`, `macActionMenu` `:101-126`, `macSkipButton` `:128-142`, `macDeleteButton` `:144-160`) | iOS controls use the 56pt adaptive black/white `.controlPlate()` circles (`ContentView.swift:201,235,507,536,546,588`; `ContentView+ActionMenu.swift:41`) |
| Settings sheet sizing | `#if os(macOS) .frame(minWidth: 400, minHeight: 500)` `ContentView.swift:576-578` | no equivalent |
| Code-span background | `Color(nsColor: .underPageBackgroundColor)` `CodeSpanFormatter.swift:147-148` | watchOS `gray.opacity(0.15)` `:140-142`; iOS `Color(uiColor: .secondarySystemBackground)` `:144-145` |
| Image decode |  `NSImage(data:)` `BackgroundImageStore.swift:245`; `Image.init(nsImage:)` `:290` | `UIImage(data:)` `:243`; `Image.init(uiImage:)` `:292` (splits `:242-246` and `:289-293`) |

---

## Summary of the data/mutation flow

1. Persist: `InterfaceSettingsView` picker (`SingleThread/InterfaceSettingsView.swift:35-46`) → `@Binding` → settings bag (`SingleThread/ContentView+Settings.swift:19`) → `@AppStorage("appearanceMode")` (`SingleThread/ContentView.swift:72-73`).
2. Observe: `ContentView.onChange(of: appearanceMode)` (`SingleThread/ContentView.swift:277-278`) → `ContentViewModel.handleAppearanceMode` (`SingleThread/ContentViewModel.swift:130-135`) → platform delegate.
3. Apply (window level only): iOS `window.overrideUserInterfaceStyle` (`SingleThread/AppDelegate.swift:21`); macOS `window.appearance` (`:74`). Re-applied at launch/activation (`:47`, `:78-84`).
4. Render-time reads: `@Environment(\.colorScheme)` in `ControlPlateModifier.swift:38-39`, `ReminderCardView.swift:49-50`, `EmptyStateCard.swift:48-49` — resolved against the window-forced appearance; views switch colors at `ControlPlateModifier.swift:21-22` and `CardPlate.swift:30`.
5. Fixed contrast (no scheme switch): swipe-prompt plate `CardPlate.swift:23`; white prominent buttons `ReminderCardView.swift:153-154,190,194-195`; white-on-blue upgrade capsule `PurchaseSettingsView.swift:184,188`.

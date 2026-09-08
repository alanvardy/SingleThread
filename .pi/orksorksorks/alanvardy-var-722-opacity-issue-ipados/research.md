# Research Findings

## Q1: How is the reminder card's container rendered in `ReminderCardView.swift`?

### Findings
- `ReminderCardView` lays out the reminder's title, priority marker, optional due-date / recurrence / list / alarm rows, and notes in a `VStack(alignment: .leading, spacing: 4)` (`SingleThread/ReminderCardView.swift:37-74`).
- The combined card content is one accessibility element via `.accessibilityElement(children: .combine)` (`ReminderCardView.swift:85`).
- **`showsOverPhoto`** is an `init` param defaulting to `false` (`ReminderCardView.swift:19`), stored at `:25` and `:112-113`, documented "True when the reminder renders over a visible background photo".
- The container is built from three chained modifiers after the VStack (`ReminderCardView.swift:86-95`):
  1. `.padding(showsOverPhoto ? 12 : 0)` — grow view to make room for the plate (`:87`).
  2. `.background { if showsOverPhoto { RoundedRectangle(cornerRadius: 10).fill(colorScheme == .dark ? Color.black : Color.white) } }` — draws the plate behind the text only when the flag is on; closure yields nothing otherwise (`:88-93`).
  3. `.padding(showsOverPhoto ? -12 : 0)` — restores the original outer geometry so `List` metrics are unchanged (`:94`).
- The plate has **no stroke/border** — a plain `RoundedRectangle` corner radius 10, solid black in dark / white in light (`ReminderCardView.swift:90-92`).
- `colorScheme` is read via `@Environment(\.colorScheme)` (`ReminderCardView.swift:105-106`).

## Q2: How is the `List` configured around the card in `ContentView.swift`?

### Findings
- A single-reminder `List` inside a `ZStack` + `GeometryReader`; renders only the first visible reminder (`ContentView.swift:296-355`).
- Row modifiers (`ContentView.swift:302-315`):
  - `.listRowBackground(viewModel.backgroundDisplayed ? Color.clear : nil)` `:308`
  - `.padding(.horizontal, 40)` `:309` and `.padding(.vertical, 12)` `:310`
  - `.frame(maxWidth: .infinity, alignment: .center)` `:313`
  - `.frame(minHeight: viewHeight, alignment: .center)` `:314` (fills safe-area height)
  - `.listRowSeparator(.hidden)` `:315`
  - iOS-only `.contextMenu` and `.swipeActions` (leading/trailing) `:316-353`.
- List-level: `.listStyle(.plain)` (`:354`), `.scrollContentBackground(.hidden)` (`:358`), and `.refreshable` (`:356`).
- **iPad vs iPhone**: the only explicit device-family remark is the comment at `:357-358`: "iPadOS gives `List` an opaque scroll-content background by default, which would hide the photo. Hide it so the photo (or the system background when none is shown) shows through." The hide is applied unconditionally; there is **no** `UIDevice` / `userInterfaceIdiom` / size-class branching in the list.
- Empty and all-skipped states use `ScrollView` + `ContentUnavailableView` (`:281-293`), not the row/list modifiers.

## Q3: What does `ContentViewModel.backgroundDisplayed` gate on?

### Findings
- Definition (`SingleThread/ContentViewModel.swift:51-54`):
  ```swift
  var backgroundDisplayed: Bool {
      UserDefaults.standard.bool(forKey: "backgroundEnabled")
          && backgroundImage.imageData != nil
  }
  ```
- Gates on two facts: the persisted **`backgroundEnabled` toggle** (key `"backgroundDisplayed"` → actually `"backgroundEnabled"` in UserDefaults) AND a **non-nil stored photo** (`BackgroundImageStore.imageData`).
- Flow into views: the same property feeds both `showsOverPhoto:` and `.listRowBackground(...)` in `ContentView.swift:307-308`.
- Expected transparent/opaque:
  - **`backgroundDisplayed == true`** → row chrome `Color.clear`, card draws its own plate (`showsOverPhoto`), i.e. opaque text plate over the photo.
  - **`backgroundDisplayed == false`** → `listRowBackground` nil (default system), card draws no plate (Q1 background closure is empty), i.e. default opaque row over the system background.

## Q4: How do the root view's layers composite, and how does the scheme resolve?

### Findings
- `ContentView.body` is a `ZStack` (`ContentView.swift:51-58`):
  1. `Color.systemBackground.ignoresSafeArea()` `:52` (base)
  2. `BackgroundPhotoLayer(...)` under `#if os(iOS)` `:54-56`
  3. `authGatedContent` / `reminderList` `:58-62` (the List on top).
- `BackgroundPhotoLayer` (`SingleThread/BackgroundImageStore.swift:151-177`): renders only when `isEnabled` and `imageData` decodes to a `UIImage`; the photo is wrapped in `Color.clear.overlay { Image.resizable().scaledToFill() }`, then `.ignoresSafeArea()`, `.opacity(...)`, `.allowsHitTesting(false)`, `.accessibilityHidden(true)`.
- `Color.systemBackground` (`SingleThread/Color+CrossPlatform.swift:10-16`): iOS/watchOS → `UIColor.systemBackground`, macOS → `NSColor.windowBackgroundColor`.
- The List's `.scrollContentBackground(.hidden)` (`ContentView.swift:358`) lets the photo (or system background) show through the scroll content.
- Fade: `BackgroundFade.opacity(for:)` = `1 - clamped(percent)/100` (`SingleThread/BackgroundFade.swift:22-24`), default `50`; 0%=full, 90%=faintest; persisted as `Int` percent in `"backgroundFadePercent"`.

## Q5: How is `colorScheme`/appearance applied and read?

- Persisted appearance read in two places:
  - SwiftUI: `@AppStorage("appearanceMode")` in `ContentView` (`ContentView.swift:135`).
  - Window-level: `AppDelegate.applyAppearance(_:to:)` sets `UIWindow.overrideUserInterfaceStyle` per window (`SingleThread/AppDelegate.swift:14-24`), via `SingleThreadApp` `@UIApplicationDelegateAdaptor` (`SingleThreadApp.swift:36-38`).
- Applied on `applicationDidBecomeActive` (`AppDelegate.swift:38-41`) which calls `AppearanceMode.load()`; live toggle applies via `ContentViewModel.handleAppearanceMode` (`ContentViewModel.swift:93-98`).
- `.system` → `UIUserInterfaceStyle.unspecified` (clear override, follow device) (`AppearanceMode.swift:22-29`).
- Previews use `preferredColorScheme(AppearanceMode.dark.colorScheme)` because canvases have no window.
- The card plate fill reads `colorScheme == .dark ? .black : .white` (`ReminderCardView.swift:91`) at render time; that `colorScheme` resolves from the effective window style, so the plate flips correctly under Light/Dark.

## Q6: How is the container/background rendering verified today?

- `SingleThreadTests/BackgroundCardTests.swift` (iOS-only) asserts only the **gate decision**, not the visuals — tests `displayedWhenToggleOnAndPhotoStored` (`:50`), `hiddenWhenToggleOff` (`:55`), `hiddenWhenNoPhotoStored` (`:61`), and `backgroundSurvivesViewModelConstruction` regression for VAR-703 (`:71`).
- Doc-comment `:38-41` explains why visual is manual-only: `_ConditionalContent` includes both branches in reflected `body`, so the rendered look cannot be distinguished by assertion; tests assert the `backgroundDisplayed` gate directly (same rationale as `ActionButtonTests`).
- `make simverify` (`Makefile:73-74`) → `scripts/simverify.sh`, with `SIM=` override (e.g. `iPhone 17` default, `iPad (A16)` etc.): boots device + `bootstatus -b`, `build-for-testing` and `test-without-building` limited to `SingleThreadUITestsAppearanceLaunchTests`, plus a screenshot.
- The appearance UI launch tests (`SingleThreadUITests/SingleThreadUITestsAppearanceLaunchTests.swift`): `testColdLaunchAppearance` (`:33`), `testRuntimeAppearanceToggle` (`:60`), `testDeviceFollowingClearsOverride` (`:94`); they assert foreground + content + attachment, not the in-process override.
- `docs/SimulatorManualVerification.md` documents the manual `--no-reminders` launch, the `SimVerify: app active` log, and caveats (override value not readable headless; screenshot is supporting evidence only).

## Cross-Cutting Observations

- **One gate → two views**: a single computed `viewModel.backgroundDisplayed` drives both the card's `showsOverPhoto` and the row's `listRowBackground`; the visual result depends on the two reads staying in sync.
- **See-through requires both toggle AND photo**; a missing photo silently falls back to the default system background.
- **Plate color is relative to the effective `colorScheme`** (light→white, dark→black), not to a fixed palette.
- **iPad fix is unconditional** (`.scrollContentBackground(.hidden)`), applied to both platforms; device sensitivity is limited to a comment, not code.

## Key references
| Subject | File:line |
|---|---|
| `showsOverPhoto` default/stored | `ReminderCardView.swift:19,:25,:112-113` |
| Container composition | `ReminderCardView.swift:86-95` |
| Plate fill black/white | `ReminderCardView.swift:90-92` |
| `colorScheme` env | `ReminderCardView.swift:105-106` |
| List row modifiers | `ContentView.swift:307-315` |
| List plain + scroll hide | `ContentView.swift:354,358` |
| iPad comment | `ContentView.swift:357` |
| `backgroundDisplayed` gate | `ContentViewModel.swift:51-54` |
| Root layers | `ContentView.swift:51-62` |
| `BackgroundPhotoLayer` | `BackgroundImageStore.swift:178` |
| `systemBackground` map | `Color+CrossPlatform.swift:10-16` |
| `BackgroundFade.opacity` | `BackgroundFade.swift:22-24` |
| Window override | `AppDelegate.swift:14-24` |
| applyAppearance on active | `AppDelegate.swift:38-41` |
| `handleAppearanceMode` | `ContentViewModel.swift:93-98` |
| `BackgroundCardTests` | `BackgroundCardTests.swift:44-84` |
| `make simverify` | `Makefile:73-74` |

## Open Areas
- Whether the visual plate color flips when only a `colorScheme` override is applied in-app (window override) versus only in previews — both read the same `colorScheme`, but headless assertion of the flipped plate is documented as unavailable.
- The subtle bezel-less plate (no stroke) may make a black/white plate look near-invisible against a close-valued photo; this is a rendering-design concern, not documented here.
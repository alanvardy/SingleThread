# Research Findings — macOS Button Rendering Anomalies

Research produced by 5 parallel agents + targeted verification reads. All `file:line` refs verified against the working tree at `1b5c7c4`.

## Q1: Button styling inventory (app, watch, widget)

### Findings

- **Scope**: 48 `Button` call sites — 34 in `SingleThread/` (the shared iPhone/iPad/macOS target), 12 in `SingleThreadWatch/WatchReminderView.swift`, 2 in `SingleThreadWidget/NextThingWidget.swift`.
- Exactly **7 `.buttonStyle` sites** and **14 `.tint(` sites**; **zero `.controlSize(`** anywhere. No custom `ButtonStyle` structs exist — the only `ButtonStyle` string in the repo is a reflected built-in name in a test (`SingleThreadTests/SwipePromptTests.swift:51`).

**Explicitly-styled buttons (a)**:

| Button | `file:line` | Treatment |
|---|---|---|
| Settings gear | `ContentView.swift:195`, label plate `:201` | `.controlPlate()` on label; **no** `.buttonStyle` |
| macOS Refresh (`#if os(macOS)`) | `ContentView.swift:210-226`, plate `:217` | `.controlPlate()`, `.disabled(isRefreshing)` `:219`) |
| iOS Undo (`#if os(iOS)`) | `ContentView.swift:227-245`, plate `:235` | `.controlPlate()` |
| iOS Complete (bottom bar) | `ContentView.swift:501-511`, plate `:507` | `.labelStyle(.iconOnly)` + `.controlPlate()` |
| Mic | `ContentView.swift:530-539`, plate `:536` | `.controlPlate()`; shared across platforms (`bottomBar` uses it on both, `:681`/`:684`) |
| iOS Skip | `ContentView+ActionMenu.swift:30-64`, plate `:41` | `.labelStyle(.iconOnly)` + `.controlPlate()` + `.confirmationDialog` `:46` |
| Nudge banner | `ReminderCardView.swift:143-162` | `.buttonStyle(.borderedProminent)` `:153` + `.tint(.white)` `:154` |
| Swipe-prompt Dismiss | `ReminderCardView.swift:185-207` | `.buttonStyle(.borderedProminent)` `:194` + `.tint(.white)` `:195` |
| Try Again | `PurchaseSettingsView.swift:85-89` | `.buttonStyle(.bordered)` `:89` |
| urchase price | `PurchaseSettingsView.swift:103-114` | `.buttonStyle(.borderedProminent)` `:113` |
| UpgradePromtButton | `PurchaseSettingsView.swift:175-197` | hand-drawn look: label `.foregroundStyle(.white)` `:184`, `.background(.blue, in: Capsule())` `:188`, `.shadow(radius: 4)` `:189`; `.buttonStyle(.plain)` `:191` — the ONLY button that suppresses platform chrome |
| Widget Complete/Skip | `NextThingWidget.swift:149-156` / `:158-165` | `Button(intent:)` `.labelStyle(.iconOnly)` + `.tint(.green/.orange)` + `.buttonStyle(.bordered)` `:154`/`:163` |

**Platform-default buttons (b)** — no `.buttonStyle`, no plate:
- Zero-styling group: context-menu rows `ContentView.swift:438,447`; dialog/resheet/toolbar buttons `ContentView+ActionMenu.swift:47,50,55,189`, `ContentView+iOS.swift:77,97,113`, `SettingsView.swift:161`, `PurchaseSettingsView.swift:41,210`, `RescheduleSheet.swift:33`, `BackgroundSettingsView.swift:56`; watch buttons `WatchReminderView.swift:202,212,215,219,250,255,262,270,305,323`.
- Tint/labelStyle-only group: swipe actions `.tint(.green)` `ContentView.swift:463`, `.tint(.orange)` `:471`; **macOS bottom-bar cluster** `macCompleteButton` `ContentView+ActionMenu.swift:96-109` (`.tint(.green)` `:104`, `.keyboardShortcut("c")` `:105`), `macActionMenu` (SwiftUI `Menu` `:111-133`, `.tint(.orange)` `:128`), `macSkipButton` `:135-148`, `macDeleteButton` `:150-164` (`.tint(.red)` `:158`) — all `.labelStyle(.iconOnly)` + `.font(.title)`, **no controlPlate**; watch Complete/Skip `.tint(.green)` `WatchReminderView.swift:137`, `.tint(.orange)` `:152`.

### Default style macOS vs iOS (identical code)

- The same logical Complete/Skip buttons exist **twice**: iOS versions draw their own chrome with `.controlPlate()` (`ContentView.swift:507`, `ContentView+ActionMenu.swift:41`); macOS versions carry no plate and rely on the platform default (`.tint` + default chrome, `ContentView+ActionMenu.swift:96-164`). This is the in-repo evidence that default buttons render differently: macOS draws the default "bezel" chrome; iPhone/iPad render chrome-less. Prior research confirms the same split (`.pi/qrspi/alanvardy-var-783-work-on-settings-in-macos/research.md:57,83-84`) and that watch default is borderless (`.pi/qrspi/alanvardy-var-692-make-buttons-more-visible/research.md:110`).
- `ControlPlateModifier` doc states the motiviation explicitly: manual chrome "ensures controls are legible against any background" (`ControlPlateModifier.swift:2-4,42-48`).

## Q2: Appearance modifier composition

### Findings

**`controlPlate()` — `SingleThread/ControlPlateModifier.swift`**
- `ViewModifier` at `:12`; `body` `:20-29`. Draws: `.foregroundStyle(resolvedGlyph)` `:25`; `.frame(width: 56, height: 56)` `:26` (`plateSize` `:33`); `.background(resolvedFill, in: Circle())` `:27`; `.shadow(radius: 4)` `:28`.
- Adaptive colors resolved at `:21-22`: dark → black plate / white glyph; light → `Color(white: 0.92)` plate (`lightPlateWhite` `:34`) / `Color(white: 0.15)` glyph (`darkGlyphWhite` `:35`). Optional `fill:`/`glyph:` overrides.
- `@Environment(\.colorScheme)` read at `:38-39`. Extension entry `View.controlPlate(fill:glyph:)` `:51-55`. **Zero `#if os` inside the modifier** — byte-identical drawing on macOS/iOS.

**`cardPlate()` — `SingleThread/CardPlateModifier.swift`**
- `ViewModifier` `:17`; `body` `:22-29`: `.padding(padding)` `:24`, `.background { RoundedRectangle(cornerRadius: CardPlate.cornerRadius).fill(fill) }` `:25-27`, optional negative-padding undo `.padding(restoresGeometry ? -padding : 0)` `:29`. Pure shape/padding machine — fill resolved at call sites. Extension `:45-49`.

**`CardPlate` constants — `SingleThread/CardPlate.swift`**
- `cornerRadius = 10` `:16`; `promptBoxFill = Color(red: 0.16, 0.17, 0.18)` (fixed dark grey, not adaptive) `:23`; `plateFill(for:)` `:29-30`: dark → `.black`, light → `Color(red: 0.96, 0.95, 0.94)`.
- Doc comments in all three files state decisions live here precisely so tests can assert them headlessly ("rendered paint can't be asserted" — `CardPlate.swift:13-14,21-22,27-28`).

**Composition with the Button's chrome** — the key structural fact:
- `.controlPlate()` is applied **to the Button's label** inside `label: { ... }` (e.g. `Image(...).font(.title3).controlPlate()` at `ContentView.swift:199-201`). It neither replaces nor sets a button style.
- **No `.buttonStyle(.plain)`/`.borderless` at or inside any plate call site** (the only 7 `.buttonStyle` sites in the app target are the ones in the Q1 table). So every `.controlPlate()`-styled button keeps the **platform-default style**, whose chrome wraps the 56×56 plate label — on macOS the default bezel draws around/behind the plate.
- Three plate call sites are not Buttons: recording indicator (`ContentView.swift:543-549`, `.controlPlate(fill: .red, glyph: .white)` `:546`), creation-feedback bubble (`:585-589`, `fill: feedback.backgroundColor`), and the card text plate (non-interactive).
- Full plate call-site list: `ContentView.swift:201,217,235,507,536,546,588`; `ContentView+ActionMenu.swift:41`; `ReminderCardView.swift:44,207`; `EmptyStateCard.swift:34`. **No plate usage in watch or widget targets.**

## Q3: Cross-platform view conventions

### Findings

- **83 `#if os(` sites across 18 files** in `SingleThread/` (60 iOS-only, 16 macOS-only, 7 `os(iOS) || os(macOS)`, 8 bare `#else`). **Zero** in `SingleThreadWatch/` and `SingleThreadWidget/` — those targets separate platforms by separate source files, never conditional compilation.
- **Convention: parallel `#if` blocks inside one file for platform-divergent controls.** The bottom-bar action buttons are the canonical example: iOS block `ContentView+ActionMenu.swift:14-68` (`skipButton` with `.confirmationDialog`), macOS block `:70-170` (`actionButtons` `:75` choosing between `macCompleteButton + macActionMenu` or `macCompleteButton + macSkipButton + macDeleteButton`, `:77-86`), shared un-gated tail `actionMenuRescheduleSheet` `:175-213`. Header comments at `:7-10` say the file split is for SwiftLint `type_body_length`.
- **Second convention: whole-file gating.** `ContentView+iOS.swift` extensions both wrapped `#if os(iOS)` `:10,54` (comment `:5-7`: keeps `ContentView` under SwiftLint's `type_body_length` budget). Same pattern for the two app delegates in `AppDelegate.swift` (`:1-60` iOS, `:62-92` macOS).
- **Reated platform pairs**: top-left overlay = macOS Refresh `ContentView.swift:210-226` vs iOS Undo `:227-245`; settings sheet chrome = macOS `.frame(minWidth: 400, minHeight: 500)` `:577-579` (macOS sheets size to content); `InterfaceSettingsView` init arity differs per platform (`SettingsView.swift:40-48` iOS 8-arg vs `:50-55` macOS 3-arg, properties gated `InterfaceSettingsView.swift:13-29`).
- **Shared-abstraction helpers**:
  - `Color.systemBackground` — `Color+CrossPlatform.swift:15-21`, internal `#if`: macOS `Color(nsColor: .windowBackgroundColor)`, else UIKit `.systemBackground`. Consumers call one symbol (`ContentView.swift:183`).
  - `settingsSubscreenLayout()` — modifier defined only `#if os(macOS)` `SettingsSubscreenLayout.swift:3-12`; on iOS it's a pass-through `:21-22`. Required on every settings sub-screen (`SettingsView.swift:12-13`); call sites `InterfaceSettingsView.swift:124`, `ReminderSettingsView.swift:95`, `AboutView.swift:40`, `BackgroundSettingsView.swift:88`, `PurchaseSettingsView.swift:56`, `PrivacySettingsView.swift:21`, `ExcludedListsView.swift:31`, `FilterSortSettingsView.swift:59`.
  - `AppearanceMode` — one enum, platform accessors gated (`windowOverrideStyle` `AppearanceMode.swift:22-32`, `appKitAppearance` `:34-44`), neutral members shared (`colorScheme` `:50-56`, `systemImage` `:59-65`, `title` `:68-74`, `load(from:)` `:79-84`).
  - `SettingsBindings` — **deliberately no `#if`** (comment `:9-14`: the compiler can't `#if` inside a parameter list; iOS-only bindings are declared unconditionally and simply never wired on macOS). Platform split happens at the two construction sites `ContentView+Settings.swift:50-86`.
  - `URLOpening` protocol + `SystemURLOpener`/`URLOpeningSpy` — zero platform branches (`URLOpening.swift:9-51`). `SettingsCaption`, `TextSize`, `TextSizeModifier` — zero platform branches.

## Q4: Light/dark appearance adaptation

### Findings

- **Window-level appearance override only** — no SwiftUI appearance modifier at runtime: `.preferredColorScheme` appears **only in `#Preview`** blocks (`ContentView+Previews.swift:39,57`; `SettingsView.swift:216`); `.environment(\.colorScheme)` is used nowhere in the repo (grep across all targets: no matches). No `.preferredColorScheme` in watch/widget.
- **AppearanceMode flow**: settings picker (`InterfaceSettingsView.swift:35-46`) → `@Binding` → bag `ContentView+Settings.swift:19` → `@AppStorage("appearanceMode")` `ContentView.swift:72-73` → `.onChange` `:277-278` → `ContentViewModel.handleAppearanceMode` `ContentViewModel.swift:130-135` → platform delegate: iOS `AppDelegate.applyAppearance` sets `window.overrideUserInterfaceStyle` on every scened window (`AppDelegate.swift:15-23`); macOS `MacAppDelegate.applyAppearance` sets `window.appearance = mode.appKitAppearance` on `NSApp.windows` (`:72-76`). Re-applied at launch/activate (`:45-48`, `:78-90`).
- **Per-platform mapping**: `AppearanceMode.windowOverrideStyle` `.system→.unspecified/.light/.dark` `:27-29`; `appKitAppearance` `.system→nil/.aqua/.darkAqua` `:39-41`.
- **Adaptive fills (switch with scheme)**: `ControlPlateModifier.swift:21-22` (black plate/white glyph ↔ off-white/near-black) and `CardPlate.swift:29-30` (black ↔ 0.96/0.95/0.94). Both read `@Environment(\.colorScheme)` (`ControlPlateModifier.swift:38-39, `ReminderCardView.swift:49-50, `EmptyStateCard.swift:48-49), which resolves from the window-forced appearance.
- **Fixed white-on-black/black-on-white contrast already implemented**: swipe-prompt Dismiss — `.foregroundStyle(.black)` text `ReminderCardView.swift:190` on `.borderedProminent` + `.tint(.white)` `:194-195` over the fixed dark-grey `promptBoxFill` plate `:207` (white button/black text identity in both schemes); nudge banner `.tint(.white)` `:154`; divider `.foregroundStyle(.white.opacity(0.5))` `:174`; upgrade capsule white-on-blue `PurchaseSettingsView.swift:184,188`.
- **System semantic colors**: `.foregroundStyle(.secondary)` throughout (e.g. `ReminderCardView.swift:93,103,111,120,125`; `EmptyStateCard.swift:30`; widget `NextThingWidget.swift:173-227`; watch `WatchReminderView.swift:170-365`). **No `.foregroundStyle(.primary)` anywhere in `SingleThread/`**. Watch target has no scheme-adaptive color code at all — only `.tint` (`WatchReminderView.swift:137,152`), `.foregroundStyle(.secondary)`, and `priorityColor` (`:373-378`).
- **Other platform bridges**: `CodeSpanFormatter.platformSecondaryBackground()` — watchOS `gray.opacity(0.15)`, UIKit `.secondarySystemBackground`, AppKit `.underPageBackgroundColor` (`SingleThreadCore/Sources/SingleThreadCore/CodeSpanFormatter.swift:138-151`). `BackgroundImageStore.swift:242-246` (`UIImage` vs `NSImage` decode), `:289-293` (`Image.init(uiImage:)` vs `nsImage:`).
- **Completion glow** is not appearance-adaptive: `Color.green.opacity(0.1)` `ContentView.swift:556-564`, watch `0.3` `WatchReminderView.swift:189-198`; state machine in `CompletionGlow.swift` holds no color.

## Q5: Testing button appearance

### Findings

- **Unit tests use `String(describing: view.body)` reflection** — the repo's own notion of "snapshot testing" (`ReminderCardView.swift:8` calls it "string-snapshot tests") — asserting serialized view/modifier chains, never rendered pixels.
- **`SwipePromptTests.swift`**: `promptShownWhenEnabled` `:11-23` asserts body contains `"CardPlateModifier"` `:20`, `"style: orange"` `:21`, `"style: green"` `:22`; `promptBoxIsDarkGrey` `:37-38` asserts the `CardPlate.promptBoxFill` constant (comment `:31-35`: "painted color can't be asserted headlessly"); `dismissButtonHasAccessibilityLabel` `:42-52` asserts `"Button<"`, `"BorderedProminentButtonStyle"` `:51`, `"AccessibilityAttachmentModifier"`.
- **`BackgroundCardTests.swift`** (whole file `#if os(iOS)` `:8`): seam/decision assertions only — `viewModel.rowChromeBackground == .clear` `:52-62`, `CardPlate.plateFill(for: .light)` equality `:69-71`, `.dark == .black` `:76-77`, `cornerRadius == 10` `:85-86`. Header `:9-17` defers rendered look to manual review.
- **`CardPlateTests.swift`** `:11-37` and **`CardPlateModifierTests.swift`** `:14-27` duplicate the constant/reflection assertions.
- **`SingleThreadTests.swift:73-96`** — the only test asserting a concrete button-style stack: `contentViewBodyContainsRefreshButtonOnMacOS` (`#if os(macOS)`) pins the exact reflected signature `"Button<ModifiedContent<ModifiedContent<Image, ...>, ControlPlateModifier>>, _EnvironmentKeyTransformModifier<Bool>>, AccessibilitéAttachmentModifier"` `:93-96`. Comment `:86-90`: a11y identifiers don't serialize, so the structural signature pins the ControlPlate-wrapped macOS refresh button.
- **`AppearanceModeTests.swift`** `:18-40`: per-platform import gates (`#if os(iOS)`/`#if os(macOS)`) assert the UIUserInterfaceStyle/NSAppearance mappings by value equality.
- **UI tests — accessibilité-audit splits**: `ActionButtonsUITests.swift:70-76` — `#if os(iOS)` runs `performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])`, `#else` (macOS) plain `performAccessibilityAudit()` (comment `:68-69`: "macOS offers a different audit set"). `SingleThreadUITests.swift:45-64`: iOS further splits on `ProcessInfo.processInfo.environment["CI"] == "true"` `:53` — CI runs only `[.sufficientElementDescription, .trait]` `:54-56`, local adds `.dynamicType, .hitRegion` `:58-60`; macOS `#else` defaults `:62-64`.
- **No `UI_USER_INTERFACE_IDIOM` anywhere** in UI tests. No pixel/golden-image infra — only `XCTAttachment` screenshots kept as artifacts, never compared (`SingleThreadUITestsAppearanceLaunchTests.swift:42-44,82-84,114-116`).
- **Cross-platform test infrastructure**: same unit-test binary runs on iPhone 17, iPad (A16), **and macOS** in CI (`.github/workflows/ci.yml` unit-tests job device matrix `:25`; `mac-tests` job `- only-testing:SingleThreadTests` with `- destination "platform=macOS"` `:296-312`). UI tests run **only on iOS simulators** (matrixed over iPhone 17 + iPad (A16), never macOS — the `#else` audit branches are compiled but never executed in CI. `ActionButtonsUITests`/`SingleThreadUITests` set `runsForEachTargetApplicationUIConfiguration = false` (`ActionButtonsUITests.swift:6-13`) so the same UI isn't run per-config.

## Cross-Cutting Observations

1. **No custom `ButtonStyle` conformances exist anywhere.** Appearance divergence between platforms is entirely the interplay of (a) the platform-default style's chrome and (b) hand-drawn plates on the label. `ControlPlateModifier` draws the 56×56 adaptive circle *inside* the label while the button keeps the default style — the default style's chrome (macOS bezel vs iOS none) wraps the plate.
2. **`UpgradePromptButton` is the singular exception**: it sets `.buttonStyle(.plain)` and hand-draws everything (white text on blue Capsule + shadow) — the only button that explicitly opts out of default chrome.
3. **Style decisions are centralized enums precisely for headless testability**: `CardPlate` owns radius/fills because "rendered paint can't be asserted" (`CardPlate.swift:11-31`); the plate modifiers are pure shape/padding machines that take resolved colors (`CardPlateModifier.swift:8-15`).
4. **Platform divergence has two structuring idioms**: parallel `#if` blocks inside shared files (`ContentView+ActionMenu`, `ContentView`, `AppDelegate`) and whole-file `#if` wrappers (`ContentView+iOS.swift`); the watch and widget targets use neither — separate source files, no `#if` at all.
5. **Appearance is enforced at the window level** (UIWindow `overrideUserInterfaceStyle` / NSWindow `.appearance`), never by SwiftUI modifiers at runtime; SwiftUI's `@Environment(\.colorScheme)` follows that override, so plate fills stay in sync with the forced appearance.
6. **Contrast patterns**: adaptive black/white switching is used only for plates (`ControlPlateModifier.swift:21-22`, `CardPlate.swift:29-30`); fixed white-on-color is used for prominent buttons (nudge, Dismiss, upgrade).

## Open Areas

- **No test asserts the actual macOS bezel/translucent-square rendering** — the macOS chrome around the plate label is never verified programmatically (no macOS UI tests, no golden images); only the structural signature of the ControlPlate-wrapped button is pinned (`SingleThreadTests.swift:73-96`). Appearance verification on macOS rests on unit tests of `AppearanceMode` mapping + manual review.
- The **exact geometry interaction** between macOS default-bezel chrome and the 56×56 plate label (how the bezel frames/pads the label) is undocumented in code — prior research (`.pi/qrspi/alanvardy-var-783-work-on-settings-in-macos/research.md:57`) notes the macOS cluster deliberately has no plate, implying the bezel + plate combination is the observed anomaly, but nothing in code comments describes it.
- **`ContentView.swift` bottom-bar line numbers** (`actionCluster` `:514-519`, mic branch `:673-685`) shift with future edits; the `#if os(iOS)` block at `:497-526` and `#else` at `:683` are the stable anchors.
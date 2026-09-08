# Research Findings

All paths relative to repo root. Line numbers verified by grep against the working tree.

## Q1: How `ReminderCardView` draws its two card plates

Source: `SingleThread/ReminderCardView.swift` (`struct ReminderCardView: View` at :11).

### The three decision constants (all in `// MARK: Internal`, :28–69)

- `static let promptBoxFill = Color(red: 0.16, green: 0.17, blue: 0.18)` — :35. Doc (:30–34): dark-grey plate behind swipe instructions + Dismiss so the coloured hints read as one dismissible prompt "in both the off-white (light) and black (dark) card-plate modes", extracted because "the rendered paint can't be asserted headlessly — tests assert this decision instead".
- `static let plateCornerRadius: CGFloat = 10` — :41. Doc (:37–40): "Shared corner radius for every content plate — the card text plate, the empty-state card plate, and the swipe-prompt box"; same test-assertion rationale.
- `static func plateFill(for colorScheme: ColorScheme) -> Color` — :67–69. Doc (:63–66): content-sized high-contrast plate behind card text, off-white light / black dark, same rationale. Body (:68): `colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.95, blue: 0.94)`. The scheme arrives via `@Environment(\.colorScheme) private var colorScheme` (:73–74).

### Plate 1 — content plate in `body` (:43–61)

```swift
VStack(alignment: .leading, spacing: 4) {          // :44
    content                                       // :79–153
    if showSwipePrompt { prompt }                 // :47–48, prompt :158
}
.padding(12)                                      // :55
.background {
    RoundedRectangle(cornerRadius: Self.plateCornerRadius)   // :57
        .fill(Self.plateFill(for: colorScheme))              // :58
}
.padding(-12)                                     // :60
```

- `.padding(12)` (:55) grows the frame 12pt on every side; the `background` (:56–59) draws the radius-10 rounded rect filled with the scheme-adaptive `plateFill` behind the padded content; `.padding(-12)` (:60) shrinks the outer frame back. In-code comment (:50–54): "The padding pair grows the view to fit the plate, then restores the original outer geometry so list metrics are unchanged."
- `content` is `private var content` (:79–153), ends with `.accessibilityElement(children: .combine)` (:152) — accessibility chain, not plate.

### Plate 2 — swipe-prompt box in `prompt` (:158–206)

```swift
VStack(spacing: 10) {                              // :159
    HStack(spacing: 8) { /* "Swipe left to skip" | "Swipe right to complete" */ }  // :160–175
    Button { showSwipePrompt = false } label: { /* "Dismiss" */ }                  // :177–197
        .buttonStyle(.borderedProminent).tint(.white)                              // :188–189
        .padding(.vertical, 8).contentShape(Rectangle())                           // :193–196
        .accessibilityLabel("Dismiss swipe prompt")                                // :197
}
.frame(maxWidth: .infinity)                       // :200
.padding(12)                                      // :201
.background {
    RoundedRectangle(cornerRadius: Self.plateCornerRadius)   // :203
        .fill(Self.promptBoxFill)                            // :204
}
```

### How the two chains differ

- `body` applies `+12` then `−12` (:55, :60): net-zero outer geometry, so the `List` row metrics are unchanged; the plate is a visual-only surround for the card text.
- `prompt` applies `.frame(maxWidth: .infinity)` (:200) then `.padding(12)` (:201) with **no** `−12` restore: horizontal expansion is absorbed by the infinity frame instead; the 12pt inset genuinely adds height to the card's vertical stack (the prompt sits inside `body`'s `VStack`, itself the plate-1 background target). The prompt plate is a fixed second color layer (`promptBoxFill`, scheme-independent) drawn on top of the plate-1 background region, versus the scheme-dependent `plateFill`.
- Constant use sites inside the file: :57–58 (card plate), :203–204 (prompt box); definitions :35, :41, :67–69.

## Q2: iOS empty states in `ContentView.swift` and their dependency on the constants

### `EmptyStateCard` (private struct, `SingleThread/ContentView.swift:576`)

Doc (:570–575): "Compact content-wrapping plate for the iOS empty states ('No Reminders', 'Nothing due', 'All Done'), mirroring the reminder card: an opaque off-white/black plate that hugs its own text and is centered on screen by the caller's `.frame(maxWidth: .infinity, minHeight:alignment:)`."

```swift
VStack(spacing: 8) {                               // :586
    Image(systemName: copy.systemImage)            // :587–589
    Text(copy.title).font(.title2.bold())          // :590–592
    Text(copy.description)… .frame(maxWidth: maxWidth)   // :593–598
}
.padding(20)                                       // :599
.background {
    RoundedRectangle(cornerRadius: ReminderCardView.plateCornerRadius)   // :601
        .fill(ReminderCardView.plateFill(for: colorScheme))              // :602
}
```

- Supporting members: `maxContentWidth(viewportWidth:)` = `min(340, viewportWidth * 0.6)` (:611–613); own `@Environment(\.colorScheme)` (:617–618); payload `ContentViewModel.EmptyStateCopy` (title / systemImage / description, `SingleThread/ContentViewModel.swift:27–31`) produced by `emptyStateCopy(hasHidden:)` (:58–75) and `allDoneStateCopy()` (:77–85).

### `reminderList` call sites (`SingleThread/ContentView.swift:353`)

- All-done branch (`store.allSkipped`, :358–371): `EmptyStateCard` at :361–363, centered by `.frame(maxWidth: .infinity, minHeight: viewHeight, alignment: .center)` (:366).
- Empty branch (`store.reminders.isEmpty`, :372–386): `EmptyStateCard` at :376–378, same centering (:379), `bottomBar` overlaid via `ZStack(alignment: .bottom)` (:374, :385).
- Reached from `body` :98–100 (`loadsReminders ? authGatedContent : reminderList`) and `authGatedContent`'s `.fullAccess` branch (:343–344); runs on iOS and macOS alike (only `#if os(iOS)` sections differ).

### Dependency relationship

- `EmptyStateCard` **consumes** exactly two `ReminderCardView` static members by qualified reference: `plateCornerRadius` (:601 — value 10) and `plateFill(for:)` (:602 — `.dark ? .black : Color(red: 0.96, green: 0.95, blue: 0.94)`). It declares **no** plate constants of its own — no duplicated numeric values anywhere in `ContentView.swift`.
- `promptBoxFill` is not consumed by `ContentView.swift`; its only in-app consumer is the swipe-prompt box (`ReminderCardView.swift:204`).
- Direction is one-way (`EmptyStateCard` → `ReminderCardView`); `ReminderCardView` never references `ContentView`. `ReminderCardView`'s doc (:37–40) already names "the empty-state card plate" as a first-class consumer of `plateCornerRadius`.
- Not shared: padding geometry — `.padding(20)` no-restore (:599) vs the card's +12/−12 pair (`ReminderCardView.swift:55, :60`) vs the prompt box's 12 no-restore (:201); also the icon/title/description text styling and the `maxContentWidth` cap are `EmptyStateCard`-local.

## Q3: shared view-styling infrastructure in the `SingleThread` target

All three named items exist.

### `ControlPlateModifier` — `SingleThread/ControlPlateModifier.swift`

- `struct ControlPlateModifier: ViewModifier` (:12). Doc (:4–10): scheme-adaptive circular plate — 56×56 frame, solid fill circle, shadow "lifts the control above the background"; dark → black plate / white glyph; light → off-white plate / dark glyph.
- Overridable `var fill: Color?`, `var glyph: Color?` (:17–19), defaults nil = auto: `resolvedFill = fill ?? (colorScheme == .dark ? .black : Color(white: Self.lightPlateWhite))` (:21), `resolvedGlyph = glyph ?? (colorScheme == .dark ? .white : Color(white: Self.darkGlyphWhite))` (:22). Reads `@Environment(\.colorScheme)` (:39).
- Private constants (:33–36): `plateSize = 56`, `lightPlateWhite = 0.92`, `darkGlyphWhite = 0.15`, `shadowRadius = 4`.
- `extension View` helper at :42: `func controlPlate(fill: Color? = nil, glyph: Color? = nil) -> some View` (:51, doc :44–50) → `modifier(ControlPlateModifier(fill:glyph:))`.
- Call sites (all on iOS UI): `SingleThread/ContentView.swift:169` (settings), :186 (undo), :470 (complete), :483 (skip), :512 (mic) — all defaults; :522 `.controlPlate(fill: .red, glyph: .white)` (recording indicator); :557 `.controlPlate(fill: feedback.backgroundColor, glyph: .white)` (creation feedback; color owns `CreationFeedback.backgroundColor`, `CreationFeedback.swift:17–22`). macOS action buttons use plain `Label` + `.tint(...)` instead (`ContentView.swift:293–337`).

### `TextSizeModifier` — `SingleThread/TextSizeModifier.swift`

- `struct TextSizeModifier: ViewModifier` (:8); `let textSize: TextSize` (:9); applies `content.dynamicTypeSize(size)` only when `textSize.dynamicTypeSize` is non-nil; `.system` applies nothing (:12–15). Doc (:5–7).
- No `View` extension helper: call sites use `.modifier(TextSizeModifier(textSize: ...))` directly — `ContentView.swift:236`, `SettingsView.swift:139`. Enum `TextSize (String, CaseIterable)` lives separately in `SingleThread/TextSize.swift:8`.

### `Color+CrossPlatform` — `SingleThread/Color+CrossPlatform.swift`

- `extension Color` (:9); `static var systemBackground` (:15) → `#if os(macOS) Color(nsColor: .windowBackgroundColor) #else Color(uiColor: .systemBackground)` (:16–19); note the `#else` covers iOS **and** watchOS (:3–8 comment). Single use: `ContentView.swift:149` `Color.systemBackground.ignoresSafeArea()`.

### Conventions observed

- Naming: file per type (`TextSizeModifier.swift`, `ControlPlateModifier.swift`); `+` suffix for cross-platform extension (`Color+CrossPlatform.swift`); View helper is the modifier name lowerCamelCased (`controlPlate`).
- Platform guards: `#if os(macOS) … #else …` for shared colors; separate `#if os(iOS)` / `#if os(macOS)` blocks for platform UI; whole-extension guards too (`ContentView+iOS.swift:5–46`).
- Color spellings: label-form initializers only — `Color(nsColor:)` (`Color+CrossPlatform.swift:17`), `Color(uiColor:)` (:19), `Color(white:)` for grays (`ControlPlateModifier.swift:21–22`), `Color(red:green:blue:)` for RGB fills (`ReminderCardView.swift:35, :68`); shorthand `.black/.white/.red` at call sites. No `.init(red:green:blue:)` spelling anywhere.
- Defaults: helper methods default nil-means-auto (`controlPlate(fill: nil, glyph: nil)`, `ControlPlateModifier.swift:51`); struct inits use trailing `= false` / `.constant(false)` (`ReminderCardView.swift:12–17`).
- Docs: `///` on essentially every declaration, `- Parameters:` lists for parameterized funcs (`ControlPlateModifier.swift:44–50`); `// MARK:` section markers throughout.
- Accessibility: styling constants on `ReminderCardView` are **internal** (not private) specifically so tests can assert the paint/radius decisions (`ReminderCardView.swift:30–34, :37–40, :63–66`); `ControlPlateModifier`'s are `private static let`.
- Scheme-adaptive pattern: `colorScheme == .dark` ternary over `@Environment(\.colorScheme)` in both `ControlPlateModifier.swift:21` and `ReminderCardView.swift:68`.
- Non-existences: no `ShapeStyle` extensions; only these two `ViewModifier`s; only one `extension View`; no shared radii/spacing constants beyond `ReminderCardView.plateCornerRadius`; no `.textSize()` helper.
- Related non-view constants: `BackgroundFade` (`SingleThread/BackgroundFade.swift:13–31`: `defaultValue = 50`, `step = 10`, `allValues = stride(0…90 by 10)`, `opacity(for:)`), used at `ContentView.swift:156`.

## Q4: test files pinning the card-plate styling seams

Only **two** test files assert the seam values. Values verified by grep.

### `SingleThreadTests/BackgroundCardTests.swift` (iOS-only suite, `#if os(iOS)` :8; `@MainActor @Suite(.serialized)` :42–44)

| Line | Test | Assertion |
|---|---|---|
| :69–71 | `plateFillOffWhiteInLightMode()` | `#expect(fill == Color(red: 0.96, green: 0.95, blue: 0.94))` where `fill = ReminderCardView.plateFill(for: .light)` |
| :76–77 | `plateFillBlackInDarkMode()` | `#expect(ReminderCardView.plateFill(for: .dark) == Color.black)` |
| :85–86 | `plateCornerRadiusIsTenPoints()` | `#expect(ReminderCardView.plateCornerRadius == 10)`; doc :80–83 says it covers "the card plate, empty-state plate, and swipe-prompt box" |
| :54, :62 | `rowBackgroundClearWithPhotoStored()` / `rowBackgroundClearWithoutPhoto()` | `#expect(viewModel.rowChromeBackground == Color.clear)` (adjacent row-chrome seam) |

Suite doc (:36–41): reflected `body` descriptions cannot distinguish `_ConditionalContent` branches, so the visual decision is asserted through the decision-constant seam directly.

### `SingleThreadTests/SwipePromptTests.swift`

| Line | Test | Assertion |
|---|---|---|
| :34–35 | `promptBoxIsDarkGrey()` | `#expect(ReminderCardView.promptBoxFill == Color(red: 0.16, green: 0.17, blue: 0.18))`; doc :29–33 "same rationale as `plateFill`" |
| :15–18 | inside `promptShownWhenEnabled()` | snapshot `String(describing: makeCard(showSwipePrompt: true).body)`; `:17 #expect(description.contains("RoundedRectangle"))` (plus `style: orange` / `style: green` / `Dismiss`). The snapshot covers the whole `body`, so it also serializes the card plate's `RoundedRectangle`; the assertion only checks presence |

### What tests do NOT assert

- No test asserts padding/geometry values — nothing pins `padding(12)`, `padding(-12)`, or the prompt's `.frame(maxWidth: .infinity)` (grep for `padding(-12)|padding(12)` in tests returns nothing).
- Three further suites instantiate `ReminderCardView` via private `makeCard` factories and string-snapshot `.body`, but assert **content substrings only** (a plate change leaving the reflection otherwise unchanged would not break them): `ShowDateTests.swift` (:46–49 factory; assertions :15–41 on `FormatStyleStorage` / `Groceries` / `Errands`), `ShowAlarmsTests.swift` (:33–35 factory; :16–28 on `NamedImageProvider`), `ShowRecurrenceTests.swift` (:33–35 factory; :16–28 on `Weekly`).
- `SingleThreadUITests/` has no constant references; plate-adjacent coverage is swipe-prompt presence/persistence only — `SingleThreadUITestsFlows.swift:559–571` (`testSwipePromptAppearsUnderUITesting`), :573–600 (`testDismissSwipePromptHidesItAndPersistsAcrossRelaunch`), :604–648 (settings toggle round-trip). The only "plate" text in the bundle is a comment at :739 plus upgrade-button frame geometry (:742, :744) — unrelated to the card seams.
- `SingleThreadWatchTests/` and `SingleThreadWatchUITests/`: zero matches for `ReminderCardView`, any plate constant, `RoundedRectangle`, or `cornerRadius` — they target `WatchReminderView`/watch view models.
- The empty-state plate itself has no styling test: `SingleThreadTests.swift:34–46` asserts only `ContentViewModel.emptyStateCopy` copy strings (:36–43).

## Q5: how the three targets share code; build rules constraining SwiftUI view code

### Targets (`SingleThread.xcodeproj/project.pbxproj`, 1240 lines)

7 native targets (PBXNativeTarget section :238–406): SingleThread app, SingleThreadTests, SingleThreadUITests, SingleThreadWatch, SingleThreadWidget, SingleThreadWatchUITests, SingleThreadWatchTests. **No core Xcode target** — shared code is the local SPM package `SingleThreadCore` (package ref :1225–1229; product dependency :1232–1236).

### Key build settings (Debug/Release identical; verified by grep)

| Setting | SingleThread app | SingleThreadWatch | SingleThreadWidget |
|---|---|---|---|
| SUPPORTED_PLATFORMS | iphoneos iphonesimulator macosx (:772/:822) | watchos watchsimulator (:956/:984) | iphoneos iphonesimulator macosx (:1016/:1047) |
| SWIFT_DEFAULT_ACTOR_ISOLATION | MainActor (:774/:824) | MainActor (:958/:986) | **absent** (Swift 6 default: nonisolated) |
| SWIFT_APPROACHABLE_CONCURRENCY | YES (:773/:823) | YES (:957/:985) | YES (:1017/:1048) |
| SWIFT_VERSION | 6.0 (:777/:827) | 6.0 (:960/:988) | 6.0 (:1020/:1051) |
| TARGETED_DEVICE_FAMILY | 1,2 (:778/:828) | 4 (:961/:989) | 1,2 (:1021/:1052) |
| Deployment | iOS 18.7 (:762/:812), macOS 26.5 (:765/:815) | watchOS 26.5 (:962/:990) | iOS 18.7 (:1006/:1037) |

- The widget is the only shipping target without `SWIFT_DEFAULT_ACTOR_ISOLATION`; a whole-file search matches only the phone app and watch app.
- Project-level `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` (:673/:728); relaxed to NO only in `SingleThreadTests` (:853/:882, comment cites a StoreKitTest PCM failure). Test targets otherwise mirror their host (no actor isolation).
- Embedding (iOS only): app embeds the watch app (copy phase :65–75, `platformFilter = ios` at :15, target dep :589–594) and the widget appex (:76–86, dep :595–600). On macOS neither is embedded.

### Source-file membership — folder-synchronized groups

- `PBXFileSystemSynchronizedRootGroup` groups (:109–148); every `PBXSourcesBuildPhase` is **empty** (:526–576). Membership = folder: SingleThread target ← `SingleThread/` (:255–257), watch ← `SingleThreadWatch/` (:325–327), widget ← `SingleThreadWidget/` (:348–350, `membershipExceptions = ( Info.plist )` :102–104), tests ← their folders.
- No `.swift` file is a member of more than one target (basename intersections across all folders are empty). No duplicated files, no shared folders.

### The `SingleThreadCore` package (`SingleThreadCore/Package.swift`)

- `// swift-tools-version: 6.0` (:1); platforms `.iOS(18.7)` / `.watchOS(26.5)` / `.macOS(26.5)` (:7–9) — covers every shipping target; one `.library` product (:12); one `.target` with `Resources/Localizable.xcstrings` (:15–17). 35 source files.
- **No SwiftUI views in the package.** `import SwiftUI` appears in exactly one file, `CodeSpanFormatter.swift`, behind `#if canImport(SwiftUI)` (:3–4), used only for `AttributedString` background colors via `platformSecondaryBackground()` (:137–151, `#if os(watchOS)` / `canImport(UIKit)` / `canImport(AppKit)` branches; applied at :122/:132). No `View`, `@ViewBuilder`, or `some View` anywhere in `SingleThreadCore/Sources/`.
- Package wired into five targets (dependency :260/:284/:330/:353/:400; Frameworks link :155/:163/:178/:186/:201) — the two UI-test targets link nothing.

### How sharing happens today

- Exclusively **module import of `SingleThreadCore`**: 17 files in `SingleThread/`, 8 of 9 in `SingleThreadWatch/` (only `SingleThreadWatchApp.swift` does not), and `SingleThreadWidget/NextThingWidget.swift:1–5` (imports AppIntents, EventKit, SingleThreadCore, SwiftUI, WidgetKit). All import examples verified.
- Watch preference wrappers: e.g. `SingleThreadWatch/ShowAlarmsState.swift:1,8,28` wraps `ShowAlarmsPreference` from the package (`SingleThreadCore/Sources/SingleThreadCore/ShowAlarmsPreference.swift:8–19`); same pattern for ShowCompletionGlow, ShowDate, ShowList, ShowRecurrence.

### Constraint summary for SwiftUI view code

1. Directory equals target: `SingleThread/` compiles only into the phone app, `SingleThreadWatch/` only into watch, `SingleThreadWidget/` only into widget; the pbxproj has no cross-target sharing mechanism except the package.
2. `SingleThreadCore` is the only cross-target container and must compile on iOS/watchOS/macOS; it currently holds no SwiftUI views, and any added SwiftUI would need platform guards.
3. Concurrency: phone and watch default to `@MainActor`; widget code is nonisolated by default unless annotated.
4. Warnings are errors project-wide except `SingleThreadTests`.

## Q6: plate-like background surfaces across the `SingleThread` target

Five distinct explicit plate constructions; **no `Material` anywhere** (the closest is the widget's `.containerBackground(.fill.tertiary, for: .widget)` at `SingleThreadWidget/NextThingWidget.swift:119` — a hierarchical `ShapeStyle` fill, not a Material).

| # | Surface | Shape | Radius | Fill | Padding | Shadow | Location |
|---|---|---|---|---|---|---|---|
| A | Card text plate | RoundedRectangle | 10 (const) | `plateFill(for:)`: dark `.black`, light `Color(red: 0.96, green: 0.95, blue: 0.94)` | 12 then −12 (net zero) | none | `ReminderCardView.swift:55–60` (fill :58; def :67–69) |
| B | Swipe-prompt box | RoundedRectangle | 10 (const) | `promptBoxFill` = `Color(red: 0.16, green: 0.17, blue: 0.18)` | 12, no restore | none | `ReminderCardView.swift:200–205` (fill :204; def :35) |
| C | Empty-state card | RoundedRectangle | 10 (const, cross-type) | `ReminderCardView.plateFill(for:)` | 20, no restore | none | `ContentView.swift:599–603` (fill :602) |
| D | Control plate (7 call sites) | Circle | n/a | `resolvedFill`: dark `.black`, light `Color(white: 0.92)` | none (56×56 frame) | radius 4 (const) | `ControlPlateModifier.swift:21–28` (consts :33–36); call sites `ContentView.swift:169,186,470,483,512,522,557` |
| E | Upgrade button capsule | Capsule | system | `.blue` literal | vertical 14 / horizontal 24 | radius 4 (literal) | `PurchaseSettingsView.swift:185–190` (:187 background, :188 shadow) |

### Parameter overlap vs difference

- **Corner radius**: all three rounded rectangles share the single constant `plateCornerRadius = 10` (`ReminderCardView.swift:57, :203`; `ContentView.swift:601`). No literal `cornerRadius` value exists anywhere in the repo; only those three RoundedRectangle sites match.
- **Adaptive fill — two concurrent schemes with different values**: card plates (A+C) use `plateFill(for:)` (light RGB 0.96/0.95/0.94 — `Color(red:green:blue:)`); circle plate (D) uses an independent inline ternary with light `Color(white: 0.92)` — same dark value (`.black`) but a different light value and a different color spelling. Glyph scheme (D): dark `.white`, light `Color(white: 0.15)`.
- **Non-adaptive fills**: `promptBoxFill` dark grey (0.16/0.17/0.18) — `ReminderCardView.swift:35`, used only at :204; capsule `.blue` literal — `PurchaseSettingsView.swift:187`.
- **Padding**: 12/−12 (A), 12 (B), 20 (C), 14 vertical/24 horizontal (E), none (D).
- **Shadow**: only D (constant 4, `ControlPlateModifier.swift:36`) and E (literal 4, `PurchaseSettingsView.swift:188`) — radius 4 recurs at two independent sites with different mechanisms.
- **No `.stroke` and no `.overlay`** on any plate. `.contentShape(Rectangle())` (interaction region, not visual) appears at `ContentView.swift:170, :187` and `ReminderCardView.swift:196`.
- **System-rendered button "plates"** (no explicit shape code): `.buttonStyle(.borderedProminent)` + `.tint(.white)` Dismiss (`ReminderCardView.swift:188–189`); `.borderedProminent` price button (`PurchaseSettingsView.swift:112`), `.bordered` Try Again (:88); widget Complete/Skip `.bordered` (`NextThingWidget.swift:173, :182`).
- **Color tokens adjacent to plates**: `Color.systemBackground` root (`ContentView.swift:149`); `Color.clear` list-row chrome seam (`ContentView.swift:453`; asserted `BackgroundCardTests.swift:54, :62`); `rowChromeBackground` defined as `.clear` (`ContentViewModel.swift:54–56`).
- **Watch side**: no plate-like surfaces at all — zero matches for RoundedRectangle/Capsule/Circle/background/fill/shadow/Material; `WatchReminderView.swift:208–227` applies `.padding()` only. Widget has no shapes either.
- **SingleThreadCore**: SwiftUI `Color` only in `CodeSpanFormatter.swift` (:142 watchOS `Color.gray.opacity(0.15)`, :145 iOS `Color(uiColor: .secondarySystemBackground)`, :148 macOS `Color(nsColor: .underPageBackgroundColor)`, :151 fallback) — attributed-text backgrounds, not plate shapes.

## Cross-Cutting Observations

- **Decision-constant pattern**: the plate look is driven by static members on `ReminderCardView` (`plateCornerRadius`, `plateFill(for:)`, `promptBoxFill`), and both other consumers (`EmptyStateCard` in `ContentView.swift:601–602`; tests `BackgroundCardTests.swift:69–87`, `SwipePromptTests.swift:34–35`) reach into that type. The extraction rationale is documented identically in the source docs and the test docs: rendered paint/shape can't be asserted headlessly, so the decision seams are asserted instead.
- **Two independent adaptive-plate vocabularies** coexist in the app target: `ReminderCardView.plateFill` (light `Color(red: 0.96, green: 0.95, blue: 0.94)`) and `ControlPlateModifier`'s `resolvedFill` (light `Color(white: 0.92)`). Same dark value, different light values and color spellings; only one is reused cross-view.
- **Geometry-restore pattern** (`+padding` / `-padding` around `.background`) exists only in the card `body` (`ReminderCardView.swift:55, :60`); the empty state and prompt plates occupy genuine layout (no restore, different paddings 20 vs 12).
- **Target isolation**: folder-synchronized targets mean iOS/macOS app view code cannot be reached from the watch or widget targets; cross-target sharing is exclusively the `SingleThreadCore` package, which contains no SwiftUI views (one `canImport(SwiftUI)`-guarded `AttributedString` color helper).
- **Conventions**: `///` docs + `- Parameters:`, `// MARK:` sections, `#if os(macOS) … #else` guards, label-form `Color(nsColor:/uiColor:/white:/red:green:blue:)` spellings, nil-means-auto default parameters, `@Environment(\.colorScheme)` ternaries for adaptation, internal (test-assertable) styling constants on `ReminderCardView` vs private constants inside the modifier.

## Open Areas

- No test asserts the empty-state plate's styling (only `EmptyStateCard` copy strings at `SingleThreadTests.swift:34–46`) — the seam is pinned solely by `BackgroundCardTests`/`SwipePromptTests` via the `ReminderCardView` constants.
- No test pins any plate padding/geometry (the +12/−12 pair, prompt's infinity frame, `.padding(20)`); geometry behavior is asserted nowhere.
- `TextSizeModifier` call-site list (two sites) was verified; a full inventory of every `.modifier(` in the target was not exhaustively enumerated.
- The Q6 survey is grep-exhaustive for shape tokens but could miss shapes constructed via local `CustomShape` types or `UIViewRepresentable`-based rounding; none were found in the surveyed targets.
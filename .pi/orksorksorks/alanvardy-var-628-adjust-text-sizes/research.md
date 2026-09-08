# Research Findings

Codebase: SingleThread iOS app (SwiftUI). Text-size preference surfaces in the
`SettingsView` modal sheet, persisted on `ContentView` via `@AppStorage`, and
applied to the view hierarchy through the `TextSizeModifier` view modifier.

The framework availability notes are taken from the installed SDK interfaces
(`SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface` under
`iPhoneOS.sdk`) and Apple/UIKit documentation.

---

## Q1: DynamicTypeSize values, rendered sizes, and range

### Findings
- `SwiftUICore.DynamicTypeSize` is a frozen, `Comparable`+`CaseIterable` enum
  with exactly 12 ordered cases (`.swiftinterface` line 11690):
  `xSmall, small, medium, large, xLarge, xxLarge, xxxLarge, accessibility1,
  accessibility2, accessibility3, accessibility4, accessibility5`.
  `DynamicTypeSize.allCases` yields these in ascending order.
- **There is no `.default` enum case.** `default` is a static property that
  resolves to `.large` (the baseline / 1.0× step). The enum exposes
  `isAccessibilitySize` (true only for accessibility1–5).
  [Apple DynamicTypeSize](https://developer.apple.com/documentation/SwiftUI/DynamicTypeSize)
- SwiftUI ↔ UIKit mapping is 1:1 via `DynamicTypeSize.init?(_ uiSizeCategory:)`
  and `UIContentSizeCategory.init(_:)` (`.swiftinterface` lines 17978–17986):
  xSmall↔extraSmall, small↔small, medium↔medium, large↔large, xLarge↔extraLarge,
  xxLarge↔extraExtraLarge, xxxLarge↔extraExtraExtraLarge, accessibility1–5↔
  accessibilityMedium…accessibilityExtraExtraExtraLarge. `UIContentSizeCategory`
  adds a 13th `.unspecified` value that `init?` rejects (returns nil).
  [Apple UIContentSizeCategory](https://developer.apple.com/documentation/uikit/uicontentsizecategory)
- **Actual rendered point sizes are not published in Apple's API docs.** Apple
  publishes only base text-style sizes at `.large` (HIG Typography). The most
  authoritative numeric table is Unit-tested Chromium `dynamic_type_util.mm`,
  derived from `UIFont.preferredFont(forTextStyle: .body).pointSize`. For the
  **`.body`** style the 12 steps are:
  xSmall 14, small 15, medium 16, large 17 (1.00×), xLarge 19 (1.12×),
  xxLarge 21 (1.24×), xxxLarge 23 (1.35×), accessibility1 28 (1.65×),
  accessibility2 33 (1.94×), accessibility3 40 (2.35×), accessibility4 47
  (2.76×), accessibility5 53 (3.12×).
  [Apple UIFontMetrics](https://developer.apple.com/documentation/uikit/uifontmetrics),
  [Chromium dynamic_type_util](https://chromium.googlesource.com/chromium/src/+/f2b44a/components/ui_util/dynamic_type_util.mm)
- The scale curve is **per text style, not a single multiplier.**
  Text styles have their own point tables (e.g. Title 2 = 22 pt, Title 1 =
  28 pt, Title 3 = 20 pt, Body = 17 pt, Callout = 16 pt, Caption = 12 pt at
  Large). Numbers drift slightly across OS builds; Apple docs do not publish
  a full 12-step per-style table.
- **Max range without accessibility sizes** is `.xxxLarge` (1.35×); the
  accessibility1–5 steps render only when the device enables "Larger
  Accessibility Sizes". [Apple HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- The **app-adjacent gap**: `.extraLarge` maps to `.xLarge` (19 pt body /
  ≈1.12×), with `.xxLarge`(.xLarge+1) and `.xxxLarge` the two larger non-AX
  steps the app does not expose.

---

## 2. TextSize declaration, persistence, and decoding

### Findings
- Enum declared in `SingleThread/TextSize.swift:8-13` as
  `enum TextSize: String, CaseIterable` with cases `system, small, medium,
  large, extraLarge`.
- **Persistence identity:** because `TextSize` is a `String`-backed
  `CaseIterable` enum, its canonical raw strings are exactly the case names
  (`"system"`, `"small"`, `"medium"`, `"large"`, `"extraLarge"`). `.system` is
  not a special sentinel to the store — its stored string is `"system"`.
- Stored property in `SingleThread/ContentView.swift:144-145`:
  `@AppStorage("textSize") private var textSize = TextSize.system`. The default
  value `TextSize.system` — resolves to the raw string `"system"` — round-trips
  through AppStorage since it's just a String-typed enum value.
- `@AppStorage` does not create extra steps: once set, the enum's rawValue is the
  String identity, so `.system == first launch == stored "system" == reads
  "system"` — no sentinel needed. `UserDirectory.defaults.object(forKey:)`
  returns the string and the framework casts to `TextSize`.
- Decoding is implicit: `@AppStorage("textSize")` casts the persisted string
  back to `TextSize` by raw-value identity. The sibling type shows the
  explicit shape in `AppearanceMode.swift:66-70`
  (`static func load(...)`, `defaults.object(forKey:) as? String`), but
  `TextSize` itself defines **no explicit `load` decoder** — it relies solely
  on `@AppStorage("textSize")`'s identity decoding, with the same unknown→
  `.system` guard fallback style as AppearanceMode.

---

## 3. Selection flow: picker → persistence → applied hierarchy

- `ContentView` passes a live `Binding<TextSize>` into the settings sheet:
  `SettingsView(... textSize: $textSize ...)` (`ContentView.swift:87`, iOS
  branch; 98 macOS branch) inside a `.sheet(isPresented:)` (`Content:83`).
- Separately, the whole sheet is wrapped in
  `.modifier(TextSizeModifier(textSize: textSize))` (`ContentView.swift:82`).
- `SettingsView` holds it as `@Binding private var textSize: TextSize`
  (`SettingsView.swift:174`) and renders the picker:
  `Picker("Text Size", selection: $textSize)` (`SettingsView.swift:116`) with
  `ForEach(TextSize.allCases, ...)` → `Label(size.title, systemImage:...)` /
  `tag(size)` (117–119). `.allCases` is auto-synthesized for
  `String, CaseIterable`.
- Labels / icons come from `TextSize.swift:29-46` (`systemImage` and `title`).
- `ContentView` itself applies the same modifier to its full body:
  `TextSizeModifier(textSize: textSize)` (ContentView.swift:82 → `:428-441`);
  a modifier pattern only takes effect on the view's own content, not on a
  sibling sheet — which is why `SettingsView` **also** wraps itself in
  `TextSizeModifier` (`SettingsView.swift:168`).
- Behavior of the modifier (`ContentView.swift:433-439`): reads
  `textSize.dynamicTypeSize`; if non-nil it calls
  `content.dynamicTypeSize(size)`, otherwise returns content unchanged. So
  `.system` applies **none** and the app follows the device's dynamic type.
- The `dynamicTypeSize?` mapping is defined in `TextSize.swift:18-24`:
  system→nil, small→.small, medium→.medium, large→.large, extraLarge→.xLarge.

---

## 4. Composition with the existing `.font(...)` hierarchy

- `TextSizeModifier` sits at the **top of the view body** in `ContentView.swift:82`
  and `SettingsView.swift:168`; the framework `dynamicTypeSize` is a subtree
  environment override, so it scales all descendant dynamic-type-responsive
  content.
- Dynamic Type does **not** apply a single zoom. Only system text styles, SF
  Symbols, and `@ScaledMetric` values scale. Explicit fixed-size fonts and
  non-text metrics do not.
- The app uses these **system text styles** throughout its hierarchy; being
  named text styles they are dynamic, so they scale under the modifier.
- `ContentView.swift` font uses: gear image `.font(.title3)` (54), error text
  `.font(.caption)` (326) and `.font(.callout)` (336) for dictation,
  `.font(.title2)` for mic/recording/feedback (356, 368, 379); macOS action
  buttons `.font(.title)` (198, 210).
- `ReminderCardView.swift`: title `.font(.title)` (26, 31), due date
  `.font(.caption)` (35), notes `.font(.callout)` (40).
- Because these are all `.font(.textStyle)` named styles (not `.system(size:)`
  fixed sizes), each is dynamically resolved — the top-level
  `dynamicTypeSize` override therefore shifts every one off the system curve
  by about the body table ratios (×1.12 for `.xLarge`, etc.), proportionally
  per text style.

---

## 5. Tests, previews, accessibility

### Unit tests — `SingleThreadTests/TextSizeTests.swift`
- `systemMapsToNilDynamicTypeSize` (7–8): `TextSize.system.dynamicTypeSize == nil`
- `small/medium/large/extraLarge` map to `.small/.medium/.large/.xLarge`
  (12–28).
- `allCasesCoverFiveCases` (32–33): `.allCases == [.system,...extraLarge]`
- `titlesAreHumanReadable` (37–38): titles "System"/"Small"/"Medium"/"Large"/
  "Extra Large".
- Test target: Swift Testing (`@Test`), `import Testing`.

### TextSizeModifier
- Behavior itself has **no dedicated unit test**; the `.system → nil`
   behavior is covered indirectly via `systemMapsToNilDynamicTypeSize`
  (TextSizeTests.swift:8). No tests assert the render-time `dynamicTypeSize()`
  call path.

### SettingsView canvas previews (`SettingsView.swift`)
- iOS `#Preview("Default")` (192): `textSize: .constant(.system)` (195).
- iOS `#Preview("Dark + Extra Large")` (205): `appearanceMode: .constant(.dark)` + `textSize: .constant(.extraLarge)` (208) — exercises the AX branch.
- macOS `#Preview("Default")` (218): `textSize: .constant(.system)` (221).

### ContentView canvas previews (`ContentView.swift`)
- Five previews (470–500): Empty, With Reminder, All Skipped, All Excluded,
  No Access. None vary `textSize`; all use the `ContentView` default
  `TextSize.system`.

### Accessibility checks
- `SingleThreadUITests/SingleThreadUITests.swift:32-34`: iOS accessibility
  audit with `.performAccessibilityAudit(for: [.dynamicType, .hitRegion,
  .sufficientElementDescription, .trait])`.
- SwiftLint opt-in rules (`swiftlint.yml:43-45`):
  `accessibility_label_for_image`, `accessibility_trait_for_button`.
- Note: contrast is skipped in the UI audit (comment at UITests.swift:33) —
  known false positives for system colors. macOS runs defaults.

---

## Cross-Cutting Observations

- **`String, CaseIterable` is the app's preference idiom.** TextSize
  (`TextSize.swift:8`), AppearanceMode (AppearanceMode.swift) and SortOption
  (Core-SortOption.swift + kindred presentation extension) all use the same
  auto-synced raw-string + `.allCases` + template shape. TextSize's
  `dynamicTypeSize`/`systemImage`/`title` mirror AppearanceMode's
  `windowOverrideStyle`/`appKitAppearance`/`systemImage`/`title`.
- **`.system` = follow-device sentinel, not a value.** Both TextSize and
  AppearanceMode (`.unspecified` / `nil`) express "clear override" as the
  first case; TextSize applies no modifier for `.system` (ContentView.
  437-438).
- **Preference state lives on `ContentView` only; `SettingsView` is stateless.**
  Every picker/toggle is a `Binding` back to `ContentView`'s `@AppStorage`
  values (SettingsView.swift:174, etc.).
- **Persistence domain vs. app domain split:** TextSize/AppearanceMode live in
  the iOS app target, while SortOption / showDate / showUndatedReminders /
  showDate persist via `AppGroup.defaults` in `SingleThreadCore`
  (`ContentView.swift` `@AppStorage(... store: AppGroup.defaults)`; e.g.
  `SortOption.swift:25`). `textSize` is stored in standard `UserDefaults`
  (no `store:` clause, `ContentView.swift:144`).
- **Centralized modifier reuse:** the single `TextSizeModifier` is defined once
  (ContentView.swift:428) and applied both to ContentView and SettingsView,
  keeping hierarchy scaling consistent.

## Open Areas

- **Exact per-style point rendering** is not fully documented by Apple; the
  body/numerics table is corroborated from Chromium's unit-tested constants
  but exact values per iOS build drift. Runtime measurement via
  `UIFont.preferredFont(forTextStyle: .body).pointSize` would confirm.
- **`.system` round-trip at storage level** is guaranteed by the String-enum
  identity, but no unit test asserts a persisted `"system"` string decodes
  back to `.system`.
- **No test asserts the actual `dynamicTypeSize(size)` call from
  `TextSize` preview active.** Coverage is enum-level only; the modifier's
  render-time behavior (apply-none on `.system`, `dynamicTypeSize(size)`
  otherwise) is unverified.
- If pixel-accurate scaling is needed for a specific `.font(...)` style at a
  particular iOS release, that is not captured anywhere in the repo.
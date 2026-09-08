# Research Findings

## Q1: What navigation infrastructure exists anywhere in the codebase?

### Findings
- There is **no** `NavigationStack`, `NavigationLink`, or `NavigationView` anywhere in the codebase (grep across all `.swift` files returns zero matches).
- There is **no** `.sheet`, `.fullScreenCover`, `.popover`, `.alert`, or `@Environment(\.dismiss)` usage in any target. The only presentation/dismissal mechanism in the entire project is a single `.confirmationDialog` in the watch app: `SingleThreadWatch/WatchReminderView.swift:132` (`isPresented: $isShowingRefreshConfirmation`), triggered by a long-press (`.onLongPressGesture` at `WatchReminderView.swift:117`).
- The iOS/macOS app scene is a single `WindowGroup` that renders exactly one view with no navigation wrapper: `SingleThread/SingleThreadApp.swift:43-45` → `WindowGroup { ContentView(store: store) }`.
- The watch app is likewise a single `WindowGroup` rendering one view: `SingleThreadWatch/SingleThreadWatchApp.swift:27-29` → `WindowGroup { WatchReminderView(store: store) }`.
- `ContentView`'s only view-switching is state-driven, not navigation-driven: `authGatedContent` (`ContentView.swift:156-166`) switches on `store.authorizationStatus` between `ProgressView`, `reminderList`, and `ContentUnavailableView`; `reminderList` (`ContentView.swift:170-271`) switches between all-skipped / empty / list branches. No view pushes or presents another.
- The app's "settings" is a SwiftUI `Menu` (popover-style), not a presented view or sheet: `ContentView.swift:273-303`.

## Q2: How does `ContentView` compose and layer its interface?

### Findings
- `body` (`ContentView.swift:38-56`) is a `ZStack` containing `Color.systemBackground.ignoresSafeArea()` plus a conditional (`store.loadsReminders ? authGatedContent : reminderList`, lines 40-45).
- The gear settings control is hosted via `.overlay(alignment: .topTrailing)` at `ContentView.swift:47-51`, padding the menu `.top, 8` / `.trailing, 12`.
- The full body is then decorated in order: `.task { await store.start() }` (52-54), `.preferredColorScheme(appearanceMode.colorScheme)` (55), `.modifier(TextSizeModifier(textSize: textSize))` (56).
- The settings `Menu` (`ContentView.swift:273-303`) contains, in order:
  1. `Picker("Appearance", selection: $appearanceMode)` looping `ForEach(AppearanceMode.allCases, id: \.self)` producing `Label(mode.title, systemImage: mode.systemImage).tag(mode)` (275-280).
  2. `Picker("Text Size", selection: $textSize)` looping `ForEach(TextSize.allCases, id: \.self)` producing `Label(size.title, systemImage: size.systemImage).tag(size)` (281-286).
  3. iOS-only `Toggle(isOn: $allowsLandscape)` with `Label("Landscape", systemImage: "rectangle.landscape.rotate")` plus `.onChange(of: allowsLandscape) { _, newValue in AppDelegate.applyLock(allowsLandscape: newValue) }` (287-294).
  4. `Toggle("Microphone", isOn: $showMicrophoneButton)` (295).
- The `Menu` label is `Image(systemName: "gearshape")` with `.font(.title3)`, `.foregroundStyle(.secondary)`, `.frame(width: 44, height: 44)`, `.contentShape(Rectangle())`, and `.accessibilityLabel("Settings")` (296-303).
- `@AppStorage`-backed preferences (all in `ContentView`):
  - `appearanceMode` → key `"appearanceMode"`, default `AppearanceMode.system` (`ContentView.swift:91-92`).
  - `textSize` → key `"textSize"`, default `TextSize.system` (94-95).
  - `allowsLandscape` → key `"allowsLandscape"`, default `true`, wrapped `#if os(iOS)` (97-100).
  - `showMicrophoneButton` → key `"showMicrophoneButton"`, default `true` (102-103).

## Q3: How are the settings preferences applied to the surrounding hierarchy?

### Findings
- **Appearance**: `appearanceMode.colorScheme` feeds `.preferredColorScheme` on the root `ZStack` (`ContentView.swift:55`). `AppearanceMode.colorScheme` returns a `ColorScheme?`, mapping `.system → nil`, `.light → .light`, `.dark → .dark` (`AppearanceMode.swift:16-24`).
- **Text size**: `textSize` feeds `TextSizeModifier(textSize:)` applied via `.modifier(...)` (`ContentView.swift:56`). `TextSizeModifier` is a private `ViewModifier` (`ContentView.swift:432-443`) that only applies `.dynamicTypeSize(size)` when `textSize.dynamicTypeSize` is non-`nil`; when non-nil it returns `content` untouched (follows system Dynamic Type). `TextSize.dynamicTypeSize` maps `.system → nil`, `.small → .small`, `.medium → .medium`, `.large → .large`, `.extraLarge → .xLarge` (`TextSize.swift:18-27`).
- **Orientation**: the `allowsLandscape` toggle's `onChange` calls `AppDelegate.applyLock(allowsLandscape: newValue)` (`ContentView.swift:291-293`). `applyLock` (`AppDelegate.swift:17-29`) computes `UIInterfaceOrientationMask` → `.allButUpsideDown` (allows landscape) vs `.portrait` (locked), finds the first `UIWindowScene`'s `keyWindow?.rootViewController`, calls `setNeedsUpdateOfSupportedInterfaceOrientations()`, then `requestGeometryUpdate(.iOS(interfaceOrientations: mask))`.
- **Launch orientation (no flash)**: the mask actually returned by the system comes from `application(_:supportedInterfaceOrientationsFor:)` (`AppDelegate.swift:32-38`), which reads `UserDefaults.standard` directly — checks `object(forKey: "allowsLandscape") != nil` and falls back to `true` when unset — so the persisted lock is in effect before any SwiftUI view appears. The doc comment at `AppDelegate.swift:7-10` states this intent ("before any SwiftUI view appears — avoiding a wrong-orientation flash"). `AppDelegate` is registered via `@UIApplicationDelegateAdaptor(AppDelegate.self)` gated `#if os(iOS)` (`SingleThreadApp.swift:50-53`).

## Q4: What shape and conventions do the settings option enums use?

### Findings
- Both are raw-value enums conforming to `String, CaseIterable` (which enables `ForEach(…, id: \.self)` in the `Picker` and `@AppStorage` raw-value persistence):
  - `AppearanceMode: String, CaseIterable` with `system`/`light`/`dark` (`AppearanceMode.swift:8-11`).
  - `TextSize: String, CaseIterable` with `system`/`small`/`medium`/`large`/`extraLarge` (`TextSize.swift:8-13`).
- Each exposes exactly three computed properties, following an identical pattern:
  - A mapping property that returns a framework value or `nil` for `.system`: `AppearanceMode.colorScheme` (`AppearanceMode.swift:16-24`), `TextSize.dynamicTypeSize` (`TextSize.swift:18-27`).
  - `systemImage: String` for the picker label icon (`AppearanceMode.swift:25-32`, `TextSize.swift:29-38`).
  - `title: String` for the human-readable picker label (`AppearanceMode.swift:34-41`, `TextSize.swift:40-48`).
- `@AppStorage` key naming: the keys are **string literals** in `ContentView` (`"appearanceMode"`, `"textSize"`, `"allowsLandscape"`, `"showMicrophoneButton"` at `ContentView.swift:91-103`), not derived from the enum type names. The doc comments note this is the "`String, CaseIterable` pattern" that lets each "slot into the settings menu as a `Picker`" (`AppearanceMode.swift:4-6`, `TextSize.swift:4-6`).
- Cross-references to the keys elsewhere: only the orientation key is read outside `ContentView` — `AppDelegate.swift:34-36` uses the literal `"allowsLandscape"` string (not a shared constant). Separate from `@AppStorage`, `SkippedReminderStore` persists `"skippedReminderIdentifiers"` in the App Group defaults (`ReminderSkip.swift:104,109-113`, `AppGroup.swift:4-13`).

## Q5: How does the codebase conditionalize behavior per platform?

### Findings
- Platform guards used: `#if os(iOS)`, `#if os(macOS)`, and combined `#if os(iOS) || os(macOS)`.
- `SingleThreadApp.swift`:
  - `#if os(iOS)` imports `UIKit` + `WatchConnectivity` (3-6); `#if os(iOS) || os(macOS)` imports `WidgetKit` (7-9).
  - WatchConnectivity / `SkippedReminderSyncService` setup is `#if os(iOS)` (20-32); `WidgetCenter.shared.reloadAllTimelines()` is `#if os(iOS) || os(macOS)` (33-37).
  - `@UIApplicationDelegateAdaptor(AppDelegate.self)` is `#if os(iOS)` (50-53).
- `AppDelegate.swift` is entirely wrapped `#if os(iOS)` (line 1).
- `Color+CrossPlatform.swift`: `#if os(macOS)` imports `AppKit` else `UIKit` (3-8); `Color.systemBackground` maps to `NSColor.windowBackgroundColor` on macOS vs `UIColor.systemBackground` elsewhere (15-20).
- `ContentView.swift` gates: `#if os(iOS)` around the `allowsLandscape` `@AppStorage` (97-100); `#if os(macOS)` around the `actionButtons` computed property (125-152); `#if os(iOS)` around the reminder `.contextMenu` (232-243); `#if os(iOS)` around the landscape `Toggle` + `onChange` (287-294); `#if os(macOS)` around `actionButtons` placement inside `bottomBar` (308-310).
- `ReminderDictation.swift`: audio-session setup/teardown (`AVAudioSession`) is `#if os(iOS)` (two occurrences, in `prepareRecording` and `tearDownRecording`).
- **Which targets compile `ContentView`**: `ContentView.swift` lives in the `SingleThread/` folder and is compiled only into the `SingleThread` app target — that target's `PBXFileSystemSynchronizedRootGroup` is the `SingleThread` folder (pbxproj `project.pbxproj:84-87` and its `fileSystemSynchronizedGroups` entry at ~209-211). The `SingleThread` scheme builds for both iOS simulators and macOS (`Makefile:14-17` `mac-build`/`mac-test` use `platform=macOS`; `.github/workflows/ci.yml:126-160` runs a `mac-tests` job). The watch app has its own synchronized folder `SingleThreadWatch` (pbxproj `project.pbxproj:96-99` / target entry ~279-281) and does **not** compile `ContentView` — it compiles only `SingleThreadWatchApp.swift` and `WatchReminderView.swift`. Thus `ContentView`/settings compile on iOS **and** macOS, but not watchOS.

## Q6: How are views extracted and organized into separate types/files?

### Findings
- **Private `some View` computed properties within one view** is the dominant factoring convention in `ContentView`: `authGatedContent` (156), `reminderList` (170), `settingsMenu` (273), `bottomBar` (306), `micButton` (340), `recordingIndicator` (355), and the macOS-only `actionButtons` (125-152). Helper `func`-returning-views also appear: `creationFeedbackView(for:)` (366) and `priorityColor(_:)` (378).
- **`private struct … : ViewModifier` at file bottom**: `TextSizeModifier` (427-443) is the canonical example — a private `ViewModifier` with a `let textSize` property whose `body(content:)` conditionally applies `.dynamicTypeSize`.
- **Standalone view files**: `WatchReminderView.swift` is a full separate `View` type with its own `body` and five `#Preview` blocks; `NextThingWidget.swift` (widget) defines separate `View`/`Provider`/`TimelineEntry` types.
- **Small pure helpers in dedicated files**: `AppearanceMode.swift` and `TextSize.swift` (leaf enums), `Color+CrossPlatform.swift` (a `Color` extension), tying to "one type/concept per file."
- **`// MARK:` organization**: `ContentView` groups with `// MARK: Lifecycle`, `// MARK: Internal`, `// MARK: Private`, then sub-marks `Creation Feedback`, `Mic Dictation`, `Priority`, `TextSizeModifier`, `Preview Helpers`, `Previews`. SwiftFormat settings `.swiftformat` enforce `blankLinesAroundMark` and `organizeDeclarations`.
- **Synchronized file groups auto-discover new files**: the project uses `objectVersion = 77` and `PBXFileSystemSynchronizedRootGroup` entries (pbxproj `project.pbxproj:6,82-111`); each target lists its folder via `fileSystemSynchronizedGroups` (lines 209, 233, 257, 279, 302). Dropping a `.swift` file into `SingleThread/`, `SingleThreadTests/`, etc. is picked up automatically — no pbxproj edit. The only exception set is the widget folder, which excludes `Info.plist` via `membershipExceptions` (`project.pbxproj:112-120`).
- **Preview helper convention**: a file-level `private let mockReminder: EKReminder` factory using `EKEventStore()` + `EKReminder(eventStore:)` (`ContentView.swift:446-457`), and `private let mockWatchReminder` in the watch view (`WatchReminderView.swift:208` area). Previews use the three dedicated `ContentView` initializers injecting `loadsReminders`/`reminders`/`skippedIDs`/`authorizationStatus` (`ContentView.swift:14-32`, `#Preview` blocks at 459-484).

## Q7: How is `ContentView` — and the settings menu specifically — tested?

### Findings
- **`MicrophoneToggleTests`** (`SingleThreadTests/MicrophoneToggleTests.swift`):
  - Uses a `MicToggleFakeTranscriber` — a `private final class` conforming to `@MainActor` `SpeechTranscribing` (lines 7-29) — injected via `ContentView(loadsReminders: false, speechTranscriber:)`.
  - The key technique is `String(describing: view.body)` and asserting on the resulting description string:
    - `settingsMenuContainsMicrophoneToggle` asserts `bodyDescription.contains("Microphone")` (lines 38-43).
    - `micButtonHiddenWhenSpeechDenied` sets `UserDefaults.standard.set(true, forKey: "showMicrophoneButton")`, injects a `.denied` fake, and asserts `!bodyDescription.contains("mic.fill")` (44-60).
    - `micButtonAbsentWhenToggleOff` / `micButtonWithToggleEnabledDoesNotCrash` set the `showMicrophoneButton` key to `false`/`true` and assert the body description is non-empty (no crash) (61-84).
- **`AppDelegateTests`** (`SingleThreadTests/AppDelegateTests.swift`, `#if os(iOS)`): three tests drive `UserDefaults.standard` for `"allowsLandscape"` and call `delegate.application(_:supportedInterfaceOrientationsFor: nil)`, asserting `.allButUpsideDown` for `true`, `.portrait` for `false`, and `.allButUpsideDown` (default) when the key is removed (lines 8-36).
- **Other `ContentView` body-description tests**:
  - `SingleThreadTests/SingleThreadTests.swift:11-25`: `contentViewInitializesWithoutReminders` (non-empty `String(describing: bodyValue)`) and `contentViewBodyContainsRefreshableModifier` (description contains `"List"` or `"refreshable"`).
  - `SingleThreadTests/ReminderDictationTests.swift:134-152`: `contentViewCanInitWithFakeTranscriber` and `contentViewCanInitWithReminderStoreAndFakeTranscriber` (both assert non-empty body description).
- **UI accessibility audit** (`SingleThreadUITests/SingleThreadUITests.swift:15-42`): `testAccessibilityAudit` launches `XCUIApplication` with `--ui-testing` (so `ReminderStore` skips loading; see `SingleThreadApp.swift:18`), waits for a `staticText`, then on iOS runs `performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])` (skipping contrast and text-clipping as known false positives); on macOS runs the default categories.
- **Launch/UI boilerplate** (`SingleThreadUITests/SingleThreadUITestsLaunchTests.swift`): `testLaunch` attaches a screenshot, with `runsForEachTargetApplicationUIConfiguration = true`.
- **Previews vs tests for mock reminders**: tests build `EKReminder` via a `private func makeReminder(title:priority:dateComponents:)` helper (`SingleThreadTests/ReminderStoreTests.swift:321-323`); `ContentView`'s canvas mocks use the file-level `private let mockReminder` (`ContentView.swift:446-457`) and `#Preview`s "Empty"/"With Reminder"/"All Skipped"/"No Access" (459-484); the watch view uses `mockWatchReminder` + five `#Preview`s (`WatchReminderView.swift:208-258` area).
- Enum mapping tests (`AppearanceModeTests.swift`, `TextSizeTests.swift`) exhaustively assert the `nil`-for-`.system` mappings, `allCases` ordering, and human-readable `title`s.

## Cross-Cutting Observations
- The entire UI is a single-root, state-driven `ZStack` with no navigation container of any kind; "settings" is an overlaid `Menu`, and the only true modal UI in the whole repo is a `.confirmationDialog` in the watch app.
- `ContentView` is the only view that touches preferences: it both declares the four `@AppStorage` vars and applies them (`preferredColorScheme`, `TextSizeModifier`, orientation `onChange`). `AppDelegate` re-reads the raw `UserDefaults` key independently, using a `keyExists` check to supply a default.
- Platform gating is consistent: orientation/landscape and the UIKit delegate are iOS-only; complete/skip `actionButtons` are macOS-only in `ContentView` (with a separate `actionButtons` in the watch view and intent-driven buttons in the widget); appearance, text-size, microphone, and the base reminder list are cross-platform (iOS/macOS).
- View factoring has a clear escalation: inline private computed property → `private func` returning `some View` → file-bottom `private struct : ViewModifier` → standalone view file → separate enum/extension helper file, all held together by `// MARK:` sections auto-ordered by SwiftFormat.
- Testing of view structure relies on `String(describing: view.body)` string-matching rather than ViewInspector or snapshot testing; fakes are injected via protocol-based seams (`SpeechTranscribing`).

## Open Areas
- No snapshot or ViewInspector-style structural testing exists — the `String(describing:)` approach only inspects the `some View` description, so exact layout/placement (e.g., overlay alignment) is untested.
- The `@AppStorage` key strings are repeated literals with no single shared constant/source of truth (two sites for `"allowsLandscape"`: `ContentView.swift:98` and `AppDelegate.swift:34-36`).
- `WatchReminderView` explicitly sets no `.preferredColorScheme`, `.dynamicTypeSize`, or orientation handling — watch-side preferences are not mirrored.
- No link/URL-navigator beyond `@Environment(\.openURL)` used for a single "View in Reminders" context-menu deep link (`ContentView.swift:234-243`); there is no in-app URL routing.
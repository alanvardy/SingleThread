# Research Findings

Scope: how the SingleThread iOS main screen composes its action chrome today, how
the shared chrome modifiers and toolbar APIs are used, how the scene/window layer is
configured, and which tests cover that surface. All facts are code-as-is.

## Q1: How is the iOS main screen's view hierarchy composed?

### Findings
- Root: `ContentView.body` (`SingleThread/ContentView.swift:168`) is a `ZStack`
  (`:169`) of `Color.systemBackground.ignoresSafeArea()` (`:170`),
  `BackgroundPhotoLayer(...)` (`:171`), then a content dispatch
  `if viewModel.store.loadsReminders { authGatedContent } else { reminderList }`
  (`:174-178`).
- `authGatedContent` (`:409`) switches on `store.authorizationStatus`: `.notDetermined`
  → `ProgressView` (`:412`), `.fullAccess` → `reminderList` (`:414`), default →
  `ContentUnavailableView` (`:416-419`).
- `reminderList` (`:423`) wraps a `GeometryReader` (`:424`) and computes viewport height
  manually as `geometry.size.height - safeAreaInsets.top - safeAreaInsets.bottom`
  (`:425-427`). It switches on `viewModel.store.listContent` (`:428`):
  - `.allDone` (`:429`) → centered `ScrollView`/`EmptyStateCard` (`:431`).
  - `.empty` (`:445`) → `ZStack(alignment: .bottom)` (`:445`) with a `ScrollView`
    (`:446`) and `bottomBar` as its last child (`:456`).
  - `.reminder` (`:458`) → `ZStack(alignment: .bottom)` (`:462`) with a `List` (`:463`)
    and `bottomBar` (`:543`).
- Settings gear: top-trailing overlay attached to the root content,
  `.overlay(alignment: .topTrailing)` at `:181-197`. Label is
  `Image(systemName: "gearshape").font(.title3).controlPlate().contentShape(Rectangle())`
  (`:186-189`), wrapper `.singleThreadButton()` (`:191`), a11y label `"Settings"`
  (`:192`), id `"settingsButton"` (`:193`), `.padding(.top, 8).padding(.trailing, 12)`
  (`:195-196`). The button sets `settingsBag = makeSettingsBag(); isShowingSettings = true`.
- Other root overlays: macOS refresh `.overlay(.topLeading)` `:199-225`; iOS undo
  `.overlay(.topLeading)` `:228-249` (id `"undoButton"`, `.padding(.top,8).padding(.leading,12)`);
  `completionGlowOverlay` `:250-255`; `completionMomentumOverlay` `.overlay(.top)` with
  `.padding(.top, 72)` `:256-262`; notifications status overlay `:263-269`;
  AI-sort failure banner `:270` (defined `ContentView+iOS.swift:150-181`, `.padding(.top, 72)`).
- `bottomBar` (`:727`) is a `VStack(spacing: 8)` ending `.padding(.bottom, 16)`; it holds
  the macOS `actionButtons` (gated on `viewModel.showsActionButtons`), then dictation
  error / feedback / recording / processing / mic branches. iOS branch (`:748-757`)
  selects `EmptyView()` without entitlement, else `upgradePrompt`, else `actionCluster`
  when `showsActionButtons`, else `micButton`.
- `actionCluster` (`:571-577`, inside `#if os(iOS)` from `:554`) is
  `HStack(alignment: .center, spacing: 16) { completeButton; micButton; skipButton }`.
- `completeButton` (`:558-569`): `Label(completeAction, systemImage: "checkmark.circle.fill")`
  `.labelStyle(.iconOnly)` `.controlPlate()` (`:564`), id `"completeButton"`, no
  `.singleThreadButton()`.
- `micButton` (`:582-592`, shared iOS+macOS, no `#if os`): `mic.fill` `.title2`
  `.controlPlate()` (`:588`) + `.singleThreadButton()` (`:590`), id `"dictateButton"`.
- `recordingIndicator` (`:594-600`): `.controlPlate(fill: .red, glyph: .white)` +
  `.symbolEffect(.pulse, ...)`.
- iOS `skipButton` lives in `SingleThread/ContentView+ActionMenu.swift:71-93` (inside
  `#if os(iOS)` from `:53`); label swaps between `.more` and `.circle.slash`, uses
  `.controlPlate()` (`:77`), id `"skipButton"`, no `.singleThreadButton()`.
- `upgradePrompt` (iOS free-tier gate) `:705-724`, id `"upgradeButton"`.

## Q2: How are `controlPlate` and `singleThreadButton` defined and used per platform?

### Findings
- `ControlPlateModifier` — `SingleThread/ControlPlateModifier.swift:12`; stored overrides
  `fill` (`:16`) / `glyph` (`:18`); `body(content:)` (`:20`) resolves colors from
  `@Environment(\.colorScheme)` (`:39`): dark → black plate/white glyph, light →
  `Color(white: 0.92)` plate / `Color(white: 0.15)` glyph (`:21-22`); then
  `.foregroundStyle`, `.frame(width:height: 56)`, `.background(fill, in: Circle())`,
  `.shadow(radius: 4)` (`:24-28`). Public extension `controlPlate(fill:glyph:)` at `:42-56`.
- `SingleThreadButtonModifier` — `SingleThread/SingleThreadButtonModifier.swift:10`;
  `body(content:)` (`:11-13`) applies `content.buttonStyle(.borderless)`; extension
  `singleThreadButton()` (`:16-22`). Header doc (`:3-9`): the symbol exists explicitly to
  avoid `#if os` so the shared mic button can call one symbol; `.borderless` is a no-op
  on iOS and strips macOS's translucent bezel around a `.controlPlate()` label.
- Neither modifier contains `#if os`; all platform divergence lives at call sites.
- iOS call sites: gear `ContentView.swift:188` plate + `:191` borderless; undo `:235`
  plate only; complete `:564` plate only; mic `:588` plate + `:590` borderless;
  recordingIndicator `:599` plate with override; creationFeedbackView `:657` plate with
  override; skip `ContentView+ActionMenu.swift:77` plate only.
- macOS call sites: refresh `ContentView.swift:206`/`:210` plate + `:213` borderless;
  `macCompleteButton` `ContentView+ActionMenu.swift:126`+`:128`; `macSkipButton`
  `:153`+`:171`; `macDeleteButton` `:185`+`:187`; `macActionMenu` (a `Menu`, not `Button`)
  `:169` plate + `.menuStyle(.borderlessButton)` (`:172`) instead of the modifier.
- macOS actions live in `ContentView+ActionMenu.swift:104` `var actionButtons`
  (HStack spacing 32, `.padding(.bottom, 8)`), choosing `macCompleteButton`/`macActionMenu`
  when the action-menu toggle is on, else complete/skip/delete.
- Only the shared `micButton` is deliberately written cross-platform with no `#if os`.

## Q3: What SwiftUI toolbar APIs are used, and with what patterns?

### Findings
- Only `.toolbar { ToolbarItem(placement:) }` (5 sites) plus `navigationTitle` via a
  custom wrapper. No `ToolbarItemGroup`, no `.principal`/`.navigation`/`.bottomBar`/
  `.topBarLeading` placements, no `.toolbarBackground`, no `.toolbar(.hidden)`, no
  `.navigationBarTitleDisplayMode`, no `NavigationSplitView` (repo-wide greps returned zero).
- All `.toolbar` sites are a single `ToolbarItem` inside a sheet-root `NavigationStack`:
  - `ContentView+iOS.swift:75-78` — `.cancellationAction` `Button("Cancel")` (skip-nudge sheet).
  - `ContentView+ActionMenu.swift:216-219` — `.cancellationAction` `Button("Cancel")` (reschedule sheet).
  - `SettingsView.swift:203-209` — `.confirmationAction` `Button("Done")` with
    `.accessibilityIdentifier("settingsDoneButton")`.
  - `PurchaseSettingsView.swift:181-187` — `.confirmationAction` `Button("Done")`.
  - `SingleThreadWatch/WatchReminderView.swift:316-318` — `.cancellationAction` `Button("Cancel")`.
  - Pattern: `.confirmationAction` → "Done" dismiss; `.cancellationAction` → "Cancel" dismiss.
    Toolbar items attach to the sheet's content view, not the outer `NavigationStack`.
- `NavigationStack` is the only navigation container: `FilterSortSettingsView.swift:134`,
  `PrivacySettingsView.swift:37`, `NotificationsSettingsView.swift:44`,
  `FilteredRemindersListView.swift:35`, `InterfaceSettingsView.swift:164`,
  `PurchaseSettingsView.swift:179`, `AISortRulesView.swift:131`, `BackgroundSettingsView.swift:96`,
  `ReminderSettingsView.swift:115`, `SingleThreadApp.swift:30`. Only `SettingsView.swift:56`
  binds a path (`NavigationStack(path: $path)`).
- Titles use `localizedNavigationTitle(_:)` — `LocalizedNavigationTitle.swift:16-27`
  (a `ViewModifier` calling `content.navigationTitle(resource.resolved(in: locale))` at
  `:27`), applied at ~12 sites (`SettingsView.swift:202`, `FilterSortSettingsView.swift:126`,
  `PrivacySettingsView.swift:24`, `BackgroundSettingsView.swift:88`, `ExcludedListsView.swift:30`,
  `NotificationsSettingsView.swift:37`, `FilteredRemindersListView.swift:27`,
  `InterfaceSettingsView.swift:156`, `PurchaseSettingsView.swift:55`, `AISortRulesView.swift:92`,
  `ReminderSettingsView.swift:107`, `AboutView.swift:39`), always title-last.
- The main screen has no `NavigationStack` and no `.toolbar`; its chrome is overlays and an
  inline bottom bar. macOS "system chrome" is a `MenuBarExtra` scene
  (`SingleThreadApp.swift:47-56`), not a toolbar.
- No test constructs a `ToolbarItem`; title tests are string checks
  (`SingleThreadTests/SettingsViewTests.swift:326,364`; `SingleThreadUITests/SingleThreadUITests.swift:238-239`).

## Q4: How is the window/scene layer configured, and what external-display handling exists?

### Findings
- App entry: `SingleThreadApp.swift:9` `@main struct SingleThreadApp: App`; `body: some Scene`
  is a single `WindowGroup { ContentView(...) }` (`:19-26`). macOS additions: `.commands`
  (`:31-38`), an About `.sheet` (`:27-30`), and an always-present `MenuBarExtra` scene
  (`:47-56`, `.menuBarExtraStyle(.menu)`); comment `:44-46` records a Swift 6 `SceneBuilder`
  bug avoided by not making the scene conditional.
- Watch app: `SingleThreadWatch/SingleThreadWatchApp.swift:4`, single `WindowGroup` (`:12-16`).
- Delegates: `@UIApplicationDelegateAdaptor(AppDelegate.self)` under `#if os(iOS)`
  (`SingleThreadApp.swift:72-74`); `@NSApplicationDelegateAdaptor(MacAppDelegate.self)`
  under `#if os(macOS)` (`:75-78`). No `SceneDelegate`/`UIWindowSceneDelegate` exists.
- `AppDelegate.swift` (whole file `#if os(iOS)`): `applyAppearance` (`:16-24`) resolves
  targets from `windows ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)`;
  `applyLock(allowsLandscape:)` (`:32-46`) uses `connectedScenes.first as? UIWindowScene` and
  `scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))`;
  `application(_:supportedInterfaceOrientationsFor:)` (`:53-58`) reads
  `OrientationPreference().isLandscapeEnabled`. `MacAppDelegate` at `:60-88`.
- `SingleThread/Info.plist` contains only `SENTRY_DSN` (`:5-6`). No `UIApplicationSceneManifest`
  dict, no `UIApplicationSupportsMultipleScenes`. Scene manifest is auto-generated:
  `INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphoneos*|iphonesimulator*] = YES`
  (pbxproj `:773-774`, `:824-825`); orientations via generated keys (`:781-782`, `:832-833`);
  `TARGETED_DEVICE_FAMILY = "1,2"`, `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx` (`:793`, `:799`).
- Scene-phase handling only: `@Environment(\.scenePhase)` (`ContentView.swift:390-391`),
  `.onChange(of: scenePhase)` (`:277-279`), `handleScenePhaseChange` (`:675+`) scheduling/cancelling
  notifications and refreshing dictation authorization.
- External displays / multiple windows: **none found**. No `UIApplicationSupportsMultipleScenes`,
  no `UISceneSession`, no `UIWindowSceneSessionRoleExternalDisplay`, no `openWindow`,
  no `handlesExternalEvents`, no `supportsMultipleWindows`.
- Tests on this config: `SingleThreadTests/AppDelegateTests.swift` builds a scene-independent
  `UIWindow(frame: .zero)` (`:9-22`) and asserts orientation masks (`:28-54`); no scene-manifest
  or external-display test.

## Q5: Which tests assert on this chrome, and with what introspection?

### Findings
- Unit/reflection (`SingleThreadTests`, Swift Testing) introspect via
  `String(describing: view.body)` / `String(describing: subview)` — reflected generic type
  chains, not `Mirror` and not a11y values. Most structural assertions are `#if os(macOS)`-guarded
  and vacuously pass on iOS.
  - `SingleThreadTests.swift:75` `contentViewBodyContainsRefreshButtonOnMacOS`;
    `:109` `contentViewBodyContainsBorderlessSettingsGearOnMacOS` (gear signature =
    `Image.font().controlPlate().contentShape(Rectangle())` wrapped by `.singleThreadButton()`
    + `AccessibilityAttachmentModifier`; disambiguated from refresh by
    `_ContentShapeModifier<Rectangle>` vs `.disabled`); `:130`
    `contentViewBodyContainsBorderlessDictateButtonOnMacOS` (`.title2` + `.controlPlate()` +
    `.singleThreadButton()` + a11y attachment); `:149` `rescheduleSheetTextButtonsKeepNativeChrome`
    (contains "Cancel", not `"SingleThreadButtonModifier"`). Comments `:88-108`, `:116-124`,
    `:137-144` document that a11y identifiers/labels do NOT survive reflection.
  - `SingleThreadButtonModifierTests.swift:11` `composedViewCarriesSingleThreadButtonModifier`;
    `:20` `unmodifiedBorderedButtonDoesNotCarrySingleThreadButtonModifier`.
  - `MacOSActionButtonChromeTests.swift` (whole file `#if os(macOS)`): `:13`
    `actionClusterButtonsUseControlPlateAndBorderlessChrome`; `:22`
    `actionMenuUsesBorderlessMenuStyleAndControlPlate`; `:29` `actionClusterDoesNotTintItsButtons`
    (no `_EnvironmentKeyWritingModifier<Optional<Color>>`).
  - `CardPlateModifierTests.swift:14`, `:22` — card-plate reflection.
  - `MicrophoneToggleTests.swift:14` `settingsGearButtonIsPresent` asserts the `"Settings"` a11y
    label because `Image(systemName:)` reflects as `NamedImageProvider` (note `:19-23`);
    `:31` `micButtonHiddenWhenSpeechDenied`.
  - `ActionButtonTests.swift` (`#if os(iOS) || os(macOS)`) — header `:12-19` explains the cluster
    is a runtime `_ConditionalContent` branch that reflection cannot distinguish, so it asserts
    the gate `ContentViewModel.showsActionButtons` (`:28`, `:36`, `:49`, …).
- UI tests (`SingleThreadUITests/SingleThreadUITests.swift`, XCTest, id queries):
  `:31` `testLaunchAndRenderSmoke` (launches with `--ui-testing`; queries `app.buttons["completeButton"]`
  `:46`, `["skipButton"]` `:48`, `["dictateButton"]` `:50`, then `performAccessibilityAudit(for:
  [.sufficientElementDescription, .trait])` `:59-67`); `:207` `testLanguageSelectionChangesVisibleString`
  and `:276` `testUnsupportedStoredLanguageFallsBackToSystem` tap `app.buttons["settingsButton"]`
  (`:212`, `:280`); `:190` action-menu flow queries `rescheduleButton`/`deleteButton` (`:194-197`).
- Summary of techniques: reflection `String(describing:)` for chrome structure; ViewModel gate
  access where reflection fails; XCUI identifiers + accessibility audit for rendered UI.

## Q6: How is iOS- vs macOS-specific view code organized/gated, and what are the build entry points?

### Findings
- Whole-file `#if os(...)` files: `ContentView+iOS.swift` (three extensions, `:10`, `:54`, `:131`),
  `SingleThreadApp+Commands.swift:1`, `MenuBarExtraOptions.swift:1`, `MenuBarExtraPreference.swift:1`,
  `AppDelegate.swift:1` (+ `MacAppDelegate` `:60`), `Color+CrossPlatform.swift:3,16`,
  `AppearanceMode.swift:3,6,23,35`, `SettingsViewModel.swift:2,12,18`,
  `SentryBootstrap.swift:31,35` (`#if os(iOS)`).
- Shared files with inline `#if os(...)`: `ContentView.swift`
  (`:9,22,37,63,78,83,103,108,139,148,198,227,258,264,291,299,313,339,344,402,505,554,646,678,684,699,729,770,791`),
  `AppViewModel.swift` (`:4,8,34,37,41,57,72,76,86,134,210,250,429,445,460,478,543`),
  `SingleThreadApp.swift` (`:3,6,28,34,42,64,72,76`), `ContentViewModel.swift` (`:73,173,297,305`),
  `InterfaceSettingsView.swift` (`:15,23,27,31,74,79,117,130,165`),
  `BackgroundImageStore.swift` (`:3,235,329`), `SettingsSubscreenLayout.swift` (`:3,19`),
  `ContentView+ActionMenu.swift` (`:14,53` iOS, `:93` macOS),
  `ContentView+Settings.swift:24,49`. `ReminderDictation.swift:126,154`, `AboutView.swift:51`.
- The iOS action cluster and macOS action buttons are separate code paths: iOS cluster inside
  `#if os(iOS)` (`ContentView.swift:554`) and `ContentView+ActionMenu.swift:53`; the macOS cluster
  inside `#if os(macOS)` (`ContentView+ActionMenu.swift:93`). The only shared button builder is
  `micButton` (`ContentView.swift:582`).
- Only one availability annotation exists: `@available(iOS 26.0, macOS 26.0, *)` at
  `SingleThread/FoundationModelsReminderRanker.swift:96`; no `if #available` platform gates found.
- Entry points: `Makefile` — iOS `build` (build-for-testing, `SIM` from `.simulator_id` else
  `name=iPhone 17`), `test` → `./scripts/test.sh --unit-only`, `ui-test` → `--ui-only`,
  `check` → `./scripts/test.sh`; macOS `mac-build`/`mac-test`/`mac-run`/`mac-distribute` with
  `MAC_SIM := platform=macOS` (`:26`), `mac-test` runs `-only-testing:SingleThreadTests`
  against `MAC_SIM` (`:47`); watch `watch-build`/`watch-test`/`watch-ui-test`; `lint`
  (swiftformat --lint + swiftlint --strict), `format`, `periphery`.
- `scripts/test.sh`: `MAC_SIM="platform=macOS"` (`:18`), `WATCH_SIM`/`WATCH_TEST_SIM` (`:11-17`),
  destination precedence `SIM` > worktree `.simulator_id` > `name=iPhone 17` (`:10-72`),
  iOS UI `-only-testing:SingleThreadUITests` (`:287`), watch (`:296-297`, `:317`, `:325`),
  macOS unit `-only-testing:SingleThreadTests` (`:334`, `:349`), deployment-floor drift checks
  (`:102-215`). CI: iOS matrix `["iPhone 17", "iPad (A16)"]` (`.github/workflows/ci.yml:22-25`),
  separate `mac-tests` job (`:161`). Only `SingleThread.xcscheme` and `SingleThreadWatch.xcscheme`
  exist; macOS reuses the `SingleThread` scheme with `MAC_SIM`.

## Cross-Cutting Observations
- The iOS main screen has **no navigation container and no toolbar**; all of its chrome is
  `ZStack` layers, `.overlay(alignment:)` attachments, and an inline `bottomBar`/`actionCluster`.
  SwiftUI `.toolbar` in this repo is exclusively a sheet-dismiss mechanism (`Cancel`/`Done`),
  so there is no in-repo precedent for action toolbars on a root screen.
- `controlPlate`/`singleThreadButton` are intentionally platform-agnostic; platform differences
  are expressed by which call sites apply `singleThreadButton()` (macOS buttons + shared mic/gear
  vs iOS complete/skip/undo) and by separate `#if os` button clusters.
- Reflection tests sign the *modifier chain shape* of specific builders
  (`completeButton`, `micButton`, `skipButton`, gear) and are the main structural regression net;
  UI tests load the rendered buttons by accessibility identifier and run an a11y audit.
- The macOS cluster is gated by a user toggle (`ContentViewModel.showsActionButtons`) and reuses
  the same `controlPlate` chrome; anything that changes shared chrome has a macOS reflection test
  (`MacOSActionButtonChromeTests`, macOS-only cases in `SingleThreadTests`) watching it.
- No external-display, multi-window, or additional-scene machinery exists; the scene manifest is
  Xcode-generated from pbxproj build settings, and `Info.plist` is effectively empty apart from
  `SENTRY_DSN`.

## Open Areas
- No research answers what a physical "iPhone Duo" test device is or how it presents an external
  screen — the phrase appears nowhere in the codebase; nothing in `scripts/`, CI, or tests
  references an external display.
- The ticket's "vertical toolbar layout" concept has no counterpart in the codebase; there is no
  existing orientation/size-class-driven toolbar chrome to model it on (only
  `OrientationPreference` and `AppDelegate.applyLock` for supported orientations).
- Whether `.toolbar` placements other than `.cancellationAction`/`.confirmationAction` are
  viable on this app's root view (no `NavigationStack` there) is not answerable from the codebase
  alone — no in-repo usage exists to observe.
- `ContentView.swift`'s per-line `#if os` map is dense; the exact iOS-vs-macOS boundary of
  `bottomBar` (which branches render the cluster vs `micButton`) is described above but the full
  modifier chain of `bottomBar` was not enumerated in the research budget.

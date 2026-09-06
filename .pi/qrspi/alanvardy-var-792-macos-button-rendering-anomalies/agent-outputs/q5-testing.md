I have gathered all findings. Here is the complete survey document.

---

# Test Survey: Button Appearance & Platform-Specific Rendering Assertions

Repo root: `/Users/vardy/dev/alanvardy-var-792-macos-button-rendering-anomalies`. All line numbers verified by reading the files or via `rg`/`grep` output.

## 1) Unit tests — `SingleThreadTests/`

### SwipePromptTests.swift (no file-level platform gate)
Reflection technique: `String(describing: <View>.body)` substring matching.

- `promptShownWhenEnabled` (SwipePromptTests.swift:11) — builds `ReminderCardView` with `showSwipePrompt: true` via `makeCard` (57); asserts body description contains:
  - `"Swipe left to skip"` (:13), `"Swipe right to complete"` (:14), `"CardPlateModifier"` (:20), `"style: orange"` (:21), `"style: green"` (:22), `"Dismiss"` (:23). Comment (:16-19) explains the modifier presence pins the plate composition because SwiftUI does not inline a `ViewModifier`'s body.
- `promptHiddenWhenDisabled` (:27) — asserts absence of `"Swipe left to skip"` (:29).
- `promptBoxIsDarkGrey` (:37) — direct color equality: `CardPlate.promptBoxFill == Color(red: 0.16, green: 0.17, blue: 0.18)` (:38). Comment (:31-35): painted color can't be asserted headlessly, so the constant is asserted instead.
- `dismissButtonHasAccessibilityLabel` (:42) — reflection: body contains `"Button<"` (:50), `"BorderedProminentButtonStyle"` (:51), `"AccessibilityAttachmentModifier"` (:52). Comment (:44-49): SwiftUI never serializes the label *string*; the label value is left to UI test `app.buttons["Dismiss swipe prompt"]`.

### BackgroundCardTests.swift (whole file `#if os(iOS)` :8, `#endif` :147)
Technique: seam/decision assertions on `ContentViewModel` and `CardPlate` constants; no view reflection. Header comment (:9-17) says rendered look is verified manually/in review.

- `rowBackgroundClearWithPhotoStored` (:52) — `viewModel.rowChromeBackground == Color.clear` (:54).
- `rowBackgroundClearWithoutPhoto` (:60) — same assertion (:62).
- `plateFillOffWhiteInLightMode` (:69) — `CardPlate.plateFill(for: .light) == Color(red: 0.96, green: 0.95, blue: 0.94)` (:71).
- `plateFillBlackInDarkMode` (:76) — `== Color.black` (:77).
- `plateCornerRadiusIsTenPoints` (:85) — `CardPlate.cornerRadius == 10` (:86).
- Helpers: fake `SpeechTranscribing` (:19-29), seeded `BackgroundImageStore` on disk (:122-133), `InMemoryEventStore`-backed `ReminderStore` (:135-145).

### CardPlateTests.swift (no platform gate)
Direct constant equality (shared style decisions live on `CardPlate`; file doc :4-7):
- `cornerRadiusIsTenPoints` (:11), expect `CardPlate.cornerRadius == 10` (:12).
- `promptBoxFillIsDarkGrey` (:16), expect `== Color(red: 0.16, green: 0.17, blue: 0.18)` (:17).
- `plateFillOffWhiteInLightMode` (:21), expect `== Color(red: 0.96, green: 0.95, blue: 0.94)` (:23).
- `plateFillBlackInDarkMode` (:27), expect `== Color.black` (:28).
- `plateFillDarkDiffersFromLight` (:34), expect `dark != light` (:37).

### CardPlateModifierTests.swift (no platform gate)
Reflection of the modifier chain (doc :4-11 explains reflection cannot see the RoundedRectangle the modifier draws, only the modifier's presence):
- `cardPlateAppliesCardPlateModifier` (:14) — `Text("test").cardPlate(fill: .blue)`; description contains `"CardPlateModifier"` (:17).
- `restoresGeometryFlagChangesModifierChain` (:24) — serialized descriptions differ for `restoresGeometry: true` vs `false` (:27).

### ColorCrossPlatformTests.swift (no platform gate)
- `systemBackgroundResolves` (:9) — only asserts `String(describing: Color.systemBackground)` is non-empty (:11).

### AppearanceModeTests.swift
Per-platform import gates: `#if os(iOS) import UIKit` (:5-7), `#if os(macOS) import AppKit` (:8-10). Technique: direct value equality, parameterized.
- `windowOverrideStyleMaps` (:24, iOS-gated :18-27) — mapping `AppearanceMode → UIUserInterfaceStyle`: `.system→.unspecified`, `.light→.light`, `.dark→.dark` (:25).
- `appKitAppearanceMaps` (:37, macOS-gated :31-40) — mapping to `NSAppearance.Name?`: `.system→nil`, `.light→.aqua`, `.dark→.darkAqua` (:38).
- `colorSchemeMaps` (:49, all platforms) — mapping to `ColorScheme?` (:50).
- `loadReadsPersistedValue` (:56) — UserDefaults `"dark"` → `.dark` (:59).
- `loadFallsBackToSystemOnMissingOrUnknown` (:63) — `nil`/`"sepia"` → `.system` (:68-70).
- `allCasesAndTitlesAreHumanReadable` (:74) — `allCases` order + localized titles (:75-78).
- Private `freshUserDefaults()` (:86-88) gives each test its own suite to avoid parallel races.

### ActionButtonTests.swift (whole file `#if os(iOS)` :8, `#endif` :134)
Header doc (:10-17): the cluster is a runtime `_ConditionalContent` branch, reflection can't distinguish it, so the gate decision is asserted directly; rendered cluster exercised by UI tests. Technique: seam assertion on `ContentViewModel.showsActionButtons` (no UI introspection).
- `buttonsShowWhenToggleOnAndReminderVisible` (:25) — toggle key true → `#expect(viewModel.showsActionButtons)` (:31).
- `buttonsHiddenWhenToggleOff` (:35) — false → `!showsActionButtons` (:41).
- `buttonsHiddenWhenNoVisibleReminder` (:45) — empty store → false (:58).
- `buttonsHiddenWhenAllSkipped` (:62) — all skipped → false (:79).
- Fake transcriber `ActionButtonFakeTranscriber` (:114-133).

### SettingsSubscreenLayoutTests.swift
Per-platform both-direction assertions of the same helper:
- macOS (:13-21): `settingsSubscreenLayoutTopAlignedOnMacOS` (:15) — reflection of `Text("hi").settingsSubscreenLayout()` contains `"SettingsSubscreenLayout"` (:17-19).
- iOS (:25-34): `settingsSubscreenLayoutIsNoopOnIOS` (:27) — wrapped description equals unwrapped (:31) and does not contain the modifier (:32).

### EnableActionButtonsMigrationTests.swift (no appearance/rendering)
`@Suite(.serialized)`; asserts the one-shot migration of key `"enableActionButtons"` from `.standard` into `AppGroup.defaults`: `standardOnlyValueIsCopiedToAppGroup` (:14-22), `freshInstallLeavesAppGroupOff` (:23-31). Technique: real `UserDefaults` reads/writes.

### EnableActionButtonsSyncTests.swift (file gate `#if os(iOS) || os(watchOS)` :1)
WatchConnectivity payload assertions for the same preference key: `pushAllIncludesEnableActionButtons` (:16-29) and `receiveEnableActionButtonsPersistsAndFiresHook` (:31-44). Not visual.

### AboutViewTests.swift (skimed)
- `aboutViewRendersAttributionAndIdentity` (:10-29) — reflection body contains copyright/made-with-love/version/email strings; macOS-gated `SettingsSubscreenLayout` presence assertion (:26-28).
- `aboutViewRendersWithoutCrashingWhenVersionIsNil` (:31-39) — reflection with `StubBundle(info: [:])`.

### SettingsViewTests.swift (skimed; most platform-gated file)
All technique = `String(describing: view.body)` substring matching; `#if os(macOS)` gates at :69, :123, :158, :189, :219, :273, :292, :330 and `#if os(iOS)` at :66, :78, :100, :112.
- `settingsViewContainsNavigationLinkLabels` (:23) — 7 section labels + captions; iOS-only string "Get reminded when you have due reminders." (:66-68); macOS asserts root list must NOT contain `"SettingsSubscreenLayout"` (:69-73).
- `interfaceSettingsViewContainsExpectedRows` (:82) — the view is constructed with different initializer arity per platform (`#if os(iOS)` adds `allowsLandscape`, `enableActionButtons`, `showSwipePrompt`, `showUndoButton`; `#else` omits them, :85-96); iOS-only labels/captions (:100-123); macOS asserts `"SettingsSubscreenLayout"` presence (:123-126).
- `reminderSettingsViewContainsExpectedRows` (:128) — macOS `SettingsSubscreenLayout` presence (:158-161).
- `filterSortSettingsViewContainsExpectedRows` (:164) — same (:189-192).
- `backgroundSettingsViewContainsExpectedRows` (:194) / `backgroundSettingsViewContainsPinToggle` (:235) / `pinToggleVisibleWhenBackgroundDisabled` (:246) — same macOS gate (:219-222).
- `privacySettingsViewContainsExpectedContent` (:262) — same (:273-276).
- `excludedListsViewContainsTopAnchor` (:285) — same (:292-294).
- `notificationsSettingsViewContainsExpectedRows` (:301) — no platform gate.
- `purchaseSettingsViewContainsTopAnchor` (:323) — macOS gate (:330-332).
- `SeededFetcher` fake (:349-359) feeds the store without network.

### SingleThreadTests.swift (skimed for macOS branches)
- `contentViewEmptyStatesShowDistinctCopy` (:31) — per-platform copy assertions: `#if os(macOS)` "…press the refresh button in the top left corner." (:44-47) vs `#else` "…pull to refresh." (:48-50).
- `contentViewAllDoneShowsAllDoneCopy` (:55) — same split at :61-68.
- `contentViewBodyContainsRefreshButtonOnMacOS` (:71) — `#if os(macOS)` (:84-96): asserts the exact reflected type signature `"Button<ModifiedContent<ModifiedContent<Image, _EnvironmentKeyWritingModifier<Optional<Font>>>, ControlPlateModifier>>, _EnvironmentKeyTransformModifier<Bool>>, AccessibilityAttachmentModifier"` (:90-95, expect :96). Comment (:85-90) documents that the accessibility identifier is not printed by `String(describing:)`, so the structural signature pins the macOS refresh button (ControlPlate-wrapped Button + `.disabled` + accessibility attachment). This is the only unit test asserting a concrete button-style stack.

### MicrophoneToggleTests.swift (skimed, iOS branches)
- `micButtonHiddenWhenSpeechDenied` (:58) — asserts body description does NOT contain `"mic.fill"` (:77); comment (:70-71) notes `Image(systemName:)` boxes as `NamedImageProvider` so symbol names never appear.
- iOS-gated tests: `explanatoryLabelContainsSettingsButtonOnIOS` (`#if os(iOS)` :232) asserts `"Open Settings"` (:238); `processingIndicatorRendersWhenIsProcessingIsTrue` (`#if os(iOS)` :270) asserts `"Processing…"` present and `"mic.fill"` absent.
- `settingsGearButtonIsPresent` (:39) — asserts `"Settings"` label presence, noting SF symbol names don't serialize (:42-49).

### TextSizeTests.swift (skimed)
Direct enum-value equality: `TextSize.dynamicTypeSize` mappings (:8-26), `allCases` (:27-30), localized titles (:31-36). No rendering.

## 2) UI tests — `SingleThreadUITests/`

### SingleThreadUITestCase.swift
- `launchApp(arguments:)` (:13-20): single entry point; sets `app.launchArguments` and launches.
- `launchSeeded(_:extra:)` (:22-25): prepends `"--seed"` + JSON.
- `flipToggle(_:target:)` (:27-39): taps the inner switch of a SwiftUI Form row.
- `assertTogglePersists(...)` (:41-49): relaunches with `"--ui-testing"` and verifies a toggle value.
- `statusLabel(_:identifier:)` (:52-63): reads app-side seam status elements (`--ui-testing-notifications` seam documented :59-61).
- File doc (:1-2): "one launch path (seed vs --ui-testing), one toggle-flip helper, and one persistence-relaunch verifier."

### ActionButtonsUITests.swift (the button-appearance-focused UI suite)
- `runsForEachTargetApplicationUIConfiguration = false` (:6-13) with a comment: both methods render the same `--ui-testing` UI; the per-config multiplier only adds redundant cold launches.
- `testActionButtonsRenderAndSkipAdvancesCard` (:16-54): launches with `["--ui-testing"]` (:25); asserts `app.buttons["completeButton"]` (:28-30) and `["skipButton"]` (:31-33) exist; taps Skip → dialog `["Skip"]` (:39-46) → `emptyStateTitle` (:48-54). Comment (:19-21): `--ui-testing` seeds one reminder and turns the action-buttons toggle on.
- `testActionButtonsAccessibilityAudit` (:55-77): `--ui-testing` (:56); the accessibility-audit split:
  - `#if os(iOS)` (:70): `try app.performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])` (:71-73).
  - `#else` (:74): `try app.performAccessibilityAudit()` (:75) — comment (:68-69): "macOS offers a different audit set."

### ActionMenuUITests.swift
- Extends `SingleThreadUITestCase`; private seed `{"reminders":[{"title":"Buy groceries"}]}` (:10-12).
- Toggle-ON flows: `testActionMenuSkipAdvancesWhenToggleOn` (:19-39), `testActionMenuDeleteRemovesWhenToggleOn` (:44-65), `testActionMenuRescheduleShowsSheetWhenToggleOn` (:70-93) — all `launchSeeded(Self.seed)`; skip button → menu buttons → `emptyStateTitle`/`dueDateText`. Note (:52-53, :78-79): iOS confirmation-dialog buttons can appear twice in the a11y tree, so `.firstMatch` is used.
- Toggle-OFF flow `testSkipActsDirectlyWhenToggleOff` (:98-146): flips `showActionButtonsToggle` off via Settings (:106-117); asserts `XCTAssertFalse(app.buttons["skipButton"].exists)` (:125-127); swipe reveals direct `"Skip"` action (:129-137).

### SingleThreadUITestsAppearanceLaunchTests.swift
- `runsForEachTargetApplicationUIConfiguration = false` (:15-21).
- `testColdLaunchAppearance` (:30-46): launch args `["--no-reminders"]` (:35); asserts first staticText appears (app scene, not SpringBoard) (:38-40); screenshot attached `"SimVerify cold launch (--no-reminders)"` (:42-44). Doc (:24-29): the appearance *value* is unit-proven in `AppearanceModeTests`; this test only proves activation.
- `testRuntimeAppearanceToggle` (:58-86): `--no-reminders` (:62); taps `settingsButton` → `settingsInterfaceRow` → `appearancePicker` (:67-79); screenshots prove foreground liveness (:80, :82-84). Doc (:48-57): SwiftUI exposes the Appearance Picker headless as a single Button labeled "Appearance"; the picker's identifier varies (currently-selected mode's symbol), so it matches by label; the value flip is not headless-asserted (documented fallback).
- `testDeviceFollowingClearsOverride` (:92-118): same `--no-reminders` launch (:96) and picker flow (:100-111); screenshot `"SimVerify device-follow (.system)"` (:114-116).

### SingleThreadUITestsFlows.swift (skimed)
Header doc (:4-7): driven by the `--seed '<json>'` seam with an in-memory EventKit store.
- Launch-arg seams and their lines: `--seed` via `launchSeeded` at :24, :35, :44, :57, :76, :88, :118, :150, :168, :225, :262, :303, :367, :393, :607, :635, :668, :682, :705, :718, :730, :746; `extra: ["--url-opener-spy"]` at :186; `extra: ["--ui-testing-glow"]` at :469, :496; `--ui-testing` relaunches at :328, :351, :448, :546, :557; `--reset-glow-preference` at :426; `--reset-swipe-preference` at :518, :530.
- `testUpgradePromptAppearsWhenGated` (:681-697) — the only UI geometry assertion: `upgradeButton.frame` width > 200 (:692-694) and width > height ("wide pill, not the small circular control plate", :696-698). Seeded via `completionCount` = `EntitlementStore.freemiumCap`, `isEntitled: false` (:683-685).
- `testActionClusterAppearsWhenEntitledAtCap` (:700-711), `testUnresolvedEntitlementRendersNoUpgradeButton` (:713-724), `testSettingsHasPurchaseRow` (:726-734), `testPurchaseSheetHasRestoreButton` (:736-749) — existence-based button assertions.
- Completion-glow visibility assertions via `app.otherElements["completionGlowOverlay"]` (:486-488, :504-507) and swipe-prompt visibility via `app.buttons["Dismiss swipe prompt"]` (:519-524, :531-552, :558-600).

### SingleThreadUITests.swift
- `testAccessibilityAudit` (:27-66): launch args `["--ui-testing", "--reset-swipe-preference"]` (:32); waits for text (:39-41). The audit gate:
  - `#if os(iOS)` (:45): `if ProcessInfo.processInfo.environment["CI"] == "true"` (:53) → audit only `[.sufficientElementDescription, .trait]` (:54-56), else full `[.dynamicType, .hitRegion, .sufficientElementDescription, .trait]` (:58-60). Comments (:43-44, :46-52): contrast skipped as false-positive source; CI full traversal can hang on virtualized runners.
  - `#else` (:62): `try app.performAccessibilityAudit()` (:64) — "macOS offers a different set of audit categories; run the defaults."
- `runsForEachTargetApplicationUIConfiguration = false` (:12-19).

### SingleThreadUITestsLaunchTests.swift
- `testLaunch` (:24-38): `--ui-testing` (:31); screenshot attachment `"Launch Screen"` (:34-36). `runsForEachTargetApplicationUIConfiguration = false` (:12-17).

### NotificationsUITests.swift (skimed)
- Whole file `#if os(iOS)` (:1), `#endif` (:113).
- `try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])` (:110) — the only audit call that is not platform-gated inside the file (because the file itself is iOS-only).

### NotificationSchedulingUITests.swift (skimed)
- Whole file `#if os(iOS)` (:1), `#endif` (:135). No audit calls.

### Per-platform branch summary (UI tests)
- `#if os(...)`: ActionButtonsUITests.swift:70-76 (audit split), SingleThreadUITests.swift:45-64 (audit split), NotificationsUITests.swift:1/113, NotificationSchedulingUITests.swift:1/135 (whole-file iOS gates).
- `UI_USER_INTERFACE_IDIOM`: **no occurrences** anywhere in SingleThreadUITests (grep over the directory returned none).
- `ProcessInfo`: only SingleThreadUITests.swift:53 (`ProcessInfo.processInfo.environment["CI"] == "true"`).
- Launch-arg seams: `--ui-testing` (SingleThreadUITestCase.swift:15-18, :38; ActionButtonsUITests:25,56; SingleThreadUITests.swift:32; LaunchTests:31), `--seed` (launchSeeded SingleThreadUITestCase:22-25), `--no-reminders` (AppearanceLaunch:35,62,96), `--url-opener-spy`, `--ui-testing-glow`, `--reset-glow-preference`, `--reset-swipe-preference` (Flows:186,426,469,496,518,530,557).
- Target-config suppression: `runsForEachTargetApplicationUIConfiguration = false` in ActionButtonsUITests:6-13, SingleThreadUITests:12-19, AppearanceLaunchTests:15-21, LaunchTests:12-17.

## 3) Cross-platform consistency infrastructure that exists

- **Shared style constants asserted headlessly.** `CardPlate` enum (SingleThread/CardPlate.swift:11, `cornerRadius` :16, `promptBoxFill` :23, `plateFill(for:)` :33-44) is unit-asserted identically in three files: CardPlateTests.swift:11-37, BackgroundCardTests.swift:69-86, SwipePromptTests.swift:37-38.
- **Shared plate modifier.** `CardPlateModifier` (CardPlateModifier.swift:17, `cardPlate` :45) used by ReminderCardView.swift:44, :207 and EmptyStateCard.swift:34; presence through reflection pinned in CardPlateModifierTests.swift:14-17 and SwipePromptTests.swift:20.
- **Cross-platform color.** `Color.systemBackground` wrapper (Color+CrossPlatform.swift:12 maps to `UIColor`/`NSColor`) with ColorCrossPlatformTests.swift:9-11.
- **Per-platform appearance mappings.** AppearanceMode.swift:25 (`windowOverrideStyle`/UIUserInterfaceStyle), :37 (`appKitAppearance`/NSAppearance) unit-tested per platform in AppearanceModeTests.swift:18-40; the UI-test counterpart deliberately does not assert the value flip (AppearanceLaunchTests:48-57) and instead proves activation + screenshots.
- **Same helper, both behaviors pinned.** `settingsSubscreenLayout()` (SettingsSubscreenLayout.swift:16-18: iOS returns receiver unchanged, macOS wraps) asserted in BOTH directions — SettingsSubscreenLayoutTests.swift:13-34 and ~9 branches of SettingsViewTests.swift plus AboutViewTests.swift:26-28.
- **Same unit-test binary on both platforms in CI.** `.github/workflows/ci.yml`: `unit-tests` job runs `-only-testing:SingleThreadTests` on iPhone 17 and iPad (A16) simulators (:21-88, device matrix :25); `mac-tests` job runs the same `-only-testing:SingleThreadTests` against `platform=macOS` (:270-320, test command :298-305). So the platform-gated unit tests above execute on iOS and macOS.
- **Behaviors intended to be identical across iPhone/iPad.** UI test groups are matrixed over `device: ["iPhone 17", "iPad (A16)"]` (:25, :93, :154, :213) — same test source on both iOS device classes.
- **No macOS UI-test execution.** The UI-test sources compile `#else` macOS branches (audit default at ActionButtonsUITests:74-75, SingleThreadUITests:62-64), but CI runs UI groups only on iOS simulators. There is no macOS UI-test job in ci.yml.
- **No pixel/golden-image infrastructure.** Grep for `snapshot|golden|renderTest|consistent|screenshot` found only `XCTAttachment` screenshots (AppearanceLaunchTests:42-44, :82-84, :114-116; LaunchTests:34-36) — kept as artifacts, never compared.
- **Manual verification gate.** docs/SimulatorManualVerification.md documents the `make simverify` gate (Makefile:81-82, scripts/simverify.sh) that runs `-only-testing:SingleThreadUITestsAppearanceLaunchTests` on iOS simulators with screenshots; BackgroundCardTests.swift:9-17 explicitly defers rendered look to "manually / in review".
- **Terminology note.** ReminderCardView.swift:8 uses the term "string-snapshot tests" for the `String(describing:)` reflection technique — the repo's notion of snapshot testing is serialized-view-description comparison, not rendered pixels.

---

## Acceptance Report
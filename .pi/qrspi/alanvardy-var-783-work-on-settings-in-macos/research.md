# Research Findings

Settings surface on iOS + macOS, one app target (`SingleThread/`). All paths relative to repo root. Line numbers verified against the working tree.

## Q1: Full presentation path of the settings surface (gear → SettingsView)

### Findings
- Gear button: `.overlay(alignment: .topTrailing)` on the main content, `Button { settingsBag = makeSettingsBag(); isShowingSettings = true }` — `SingleThread/ContentView.swift:160-165`; label `Image(systemName: "gearshape")` with `.controlPlate()` at `ContentView.swift:167`; `.accessibilityIdentifier("settingsButton")` at `ContentView.swift:171`.
- State: `@State private var isShowingSettings = false` (`ContentView.swift:255`); `@State private var settingsBag: SettingsBindings?` (`ContentView.swift:265`), nilled on dismiss so a fresh bag is built every open — `.onChange(of: isShowingSettings)` → `settingsBag = nil` at `ContentView.swift:235-240`.
- Sheet: `.sheet(isPresented: $isShowingSettings) { settingsSheetContent }` at `ContentView.swift:243-244` (sibling purchase sheet at `ContentView.swift:246-248`). Presented from the main `WindowGroup` window (`SingleThreadApp.swift:20-24`).
- `settingsSheetContent` (`ContentView.swift:546-553`): `if let bag = settingsBag { settingsSheetWritebacks(bag) }` plus the **macOS-only** `.frame(minWidth: 400, minHeight: 500)` inside `#if os(macOS)` (`ContentView.swift:549-553`; frame at `:552`). Comment at `:550-551` states macOS sheets size by content ideal size and the settings List collapses to 0px without a floor.
- `settingsSheetWritebacks(bag)` (`SingleThread/ContentView+Settings.swift:8-43`) constructs `SettingsView(bindings:bag, backgroundImage:…, availableLists:…, excludedLists: excludedListsBinding, entitlementStore:…, viewModel: SettingsViewModel())` (`ContentView+Settings.swift:11-17`) and returns it with a 19-`onChange` write-back chain (iOS) / 13 (macOS).
- MacOS sheet sizing/positioning: **no app-authored window geometry** — no `.position`, `presentationDetents`, `presentationBackground`, `presentationCornerRadius`, or `NSWindow` code anywhere in `SingleThread/` (grep: zero hits). SwiftUI's sheet leaves the window centered by the framework; the app's only lever is the min-frame at `ContentView.swift:552`.
- Root height per platform:
  - macOS: `NavigationStack → List` (`SettingsView.swift:32-33`) reports no intrinsic height in a sheet → effective height = `minHeight: 500` floor from `ContentView.swift:552` (width `minWidth: 400`). No other min/fixed frame on the root; no `presentationDetents`.
  - iOS: the `#if os(macOS)` block compiles out, so the sheet body is just `settingsSheetWritebacks(bag)`; height = platform sheet area fill.
- Only fixed-frame in settings-land is in a sub-view: `ProductView` rows `.frame(minHeight: 66)` / `.frame(maxWidth: .infinity)` (`PurchaseSettingsView.swift:90, :122, :131-132`), unrelated to sheet sizing.

## Q2: SettingsView NavigationStack/List hierarchy and pushed sub-views

### Findings
Root (`SingleThread/SettingsView.swift:11` struct): `NavigationStack { List { … } }` (`:32-33`), `.navigationTitle("Settings")` (`:129`), `.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }` (`:130-137`, id `settingsDoneButton` `:135`), `.modifier(TextSizeModifier(textSize: bindings.textSize))` (`:139`). `@Environment(\.dismiss)` at `:145-147`.

Section 1 (`:34-110`):

| Row | NavigationLink | Platform gating | a11y id |
|---|---|---|---|
| Interface | `:35` | `#if os(iOS)` passes 7 bindings (`:36-45`) vs `#elseif os(macOS)` 3 (`:46-51`); `#endif` `:52` | `settingsInterfaceRow` `:56` |
| Notifications | `:58` | row entirely `#if os(iOS)` `:57-66` — **absent on macOS** | `settingsNotificationsRow` `:65` |
| Reminder | `:67` | none | `settingsReminderRow` `:78` |
| Filtering & Sorting | `:79` | none | `settingsFilterSortRow` `:88` |
| Background | `:89` | none | `settingsBackgroundRow` `:98` |
| Purchase | `:99` | none; dynamic label `isEntitled ? "Manage Purchase" : "Unlock"` `:101-104` | `settingsPurchaseRow` `:108` |

Section 2 (`:112-127`): Privacy Policy → `PrivacySettingsView` (link `:113`, id `:118`); About → `AboutView` (link `:119`, id `:125`). Both ungated.

Sub-view shape (all set their own `.navigationTitle`; **none except the root adds `.toolbar`**):

| View | Container | Title | Notes |
|---|---|---|---|
| InterfaceSettingsView | Form (`:26`) | "Interface" (`:74`) | iOS-only toggles + bindings (`:9-26`), iOS-only `viewModel.allowsLandscapeChanged` hook (`:39-40`) |
| BackgroundSettingsView | Form (`:15`) | "Background" (`:39`) | no `#if`; refresh button + photographer credit |
| FilterSortSettingsView | Form (`:29`) | "Filtering & Sorting" (`:49`) | contains nested `NavigationLink` → `ExcludedListsView` (`:39-45`) |
| ReminderSettingsView | Form (`:33`) | "Reminder" (`:54`) | `.onChange` hooks gated `#if os(iOS) || os(macOS)` (`:24-26, :31-33, :39-41`) |
| NotificationsSettingsView | Form (`:12`) | "Notifications" (`:25`) | compiles on all platforms; reachability gated only by the parent row (comment `:4`) |
| PurchaseSettingsView | **List** (`:18`) | "Unlock" (`:55`) | only sub-view using List; also hosts `UpgradePromptButton` (`:112`) + `PurchaseSheet` (`:115-126`) |
| PrivacySettingsView | Form (`:10`) | "Privacy Policy" (`:20`) | stateless; renders `PrivacyGuideContent.sections` (`:7-9`) |
| ExcludedListsView | Form (`:19`) | "Excluded Lists" (`:30`) | 2nd-level; per-row `Toggle` via `excludedBinding(for:)` (`:27-28, :39-49`) |
| AboutView | Form (`:22`) | "About" (`:39`) | body ungated; only `#Preview("About")` is `#if os(iOS)` (`:50`) |

## Q3: Stock macOS NavigationStack nav-bar rendering in a sheet

### Findings
- Framework behavior (not in this repo — no implementing SwiftUI): a sheet-hosted macOS `NavigationStack` renders its own nav bar (title + back button) inside the sheet content area, stacked above the pushed view; pushed content is top-anchored under the nav bar, and short content leaves the extra space below — the nav bar does not vertically center. No repo code overrides or repositions this.
- The only macOS-specific lever on the nav-bar/content vertical extent is the sheet min-frame `#if os(macOS) .frame(minWidth: 400, minHeight: 500) #endif` at `ContentView.swift:549-553` (per comment `:550-551` it stops the settings List collapsing to 0px inside the macOS sheet).
- Verified absences (grep): no `navigationBarTitleDisplayMode`/`navigationTitleDisplayMode` anywhere; no custom toolbar overlay repositions nav bars (only the two stock `.confirmationAction` Done toolbars at `SettingsView.swift:130-137` and `PurchaseSettingsView.swift:207-210`); no `ScrollView` wrapping in any pushed settings sub-view (the only ScrollViews are the main reminder list, `ContentView.swift:358, :373`).
- Other `#if os(macOS)` layout code exists but is **not** in the settings path: main-list centering `ScrollView { … .frame(maxWidth: .infinity, minHeight: viewHeight, alignment: .center) }` (`ContentView.swift:358-379`), macOS `actionButtons` HStack (no `controlPlate`) (`ContentView.swift:292-345`), bottomBar macOS branch (`ContentView.swift:551-604` region). macOS `#if` blocks elsewhere are data/model mapping (`Color+CrossPlatform.swift:3,16`; `AppearanceMode.swift:5,34`; `BackgroundImageStore.swift:244,289`; `ContentViewModel.swift:107`).
- Sub-views rely entirely on the framework default (content top-anchored under nav bar); no alignment/padding/Spacer/fixed-frame modifier on any pushed settings view changes content vertical position relative to the nav bar.

## Q4: Compile-time platform splits in the settings data flow

### Findings
- Source of truth: `@AppStorage` prefs on ContentView. iOS-only: `allowsLandscape` (`ContentView.swift:78-81`), `enableActionButtons` (`:88-91`), `showSwipePrompt` (`:91-94`), `showUndoButton`/`notificationsEnabled`/`notificationIntervalHours` (`:105-114`). Shared: `appearanceMode`/`textSize`, `showMicrophoneButton`, the six background/undated/sort/date/list/recurrence/alarms fields and `showCompletionGlow` (`:77, :83-84, :115-133`).
- `makeSettingsBag()` (`ContentView+Settings.swift:49`): `#if os(iOS)` builds the bag with all 19 fields; `#elseif os(macOS)` omits the 6 iOS-only (`allowsLandscape`, `enableActionButtons`, `showSwipePrompt`, `showUndoButton`, `notificationsEnabled`, `notificationIntervalHours`). Invoked from the gear button (`ContentView.swift:162`).
- `settingsSheetWritebacks` (`ContentView+Settings.swift:8`): shared `.onChange` writebacks for `appearanceMode`/`textSize` (`:19-20`); iOS branch adds 6 (`:22-28`); `#elseif os(macOS)` is a no-op passthrough `let withIOSPreferences = withAppearance` (`:29-31`); then 11 more shared `.onChange`s (`:33-43`) write every bag change back to the `@AppStorage` properties (so settings survive relaunch — doc `:12-15`).
- `SettingsBindings` (`SingleThread/SettingsBindings.swift:18`): one `@MainActor` `Observable` class holding all 19 fields, declared **unconditionally** (doc `:4-9` — `#if` cannot appear inside a parameter list); the 6 iOS-only fields exist on macOS but are never wired/read (doc `:10-13`). Defaults mirror ContentView (`:12-31`); stored vars `:64-82`. `excludedLists` is **not** in the bag — store-backed, passed separately as `Binding<Set<String>>` (`ContentView.swift:141-145`; doc `ContentView+Settings.swift:11-17`).
- `SettingsViewModel` (`SingleThread/SettingsViewModel.swift`): iOS-only `allowsLandscapeChanged` → `AppDelegate.applyLock` (`:7-10`); `showPreferenceChanged()` → `WidgetCenter.shared.reloadAllTimelines()` under `#if os(iOS) || os(macOS)` (`:13-17`).
- Binding delivery: `SettingsView` stores the whole bag as `@Bindable private var bindings` (`SettingsView.swift:149-151`) and threads **focused `$bindings.x` subsets** into each sub-view (full per-view list in Q2 table):
  - iOS Interface (7): `appearanceMode, textSize, allowsLandscape, showMicrophoneButton, enableActionButtons, showSwipePrompt, showUndoButton` (`SettingsView.swift:36-45`); macOS Interface (3): `appearanceMode, textSize, showMicrophoneButton` (`:46-51`).
  - Notifications (iOS row only): `notificationsEnabled, notificationIntervalHours` (`:58-64`).
  - Reminder (both): `showDate, showList, showRecurrence, showAlarms, showCompletionGlow` (`:67-76`).
  - FilterSort (both): `sortOption, showUndatedReminders` + `availableLists`, `$excludedLists` (`:79-87`); Background (both): `backgroundEnabled, backgroundFadePercent, backgroundPinned` + `backgroundImage` store (`:89-97`); Purchase: `entitlementStore` only (`:99-107`); Privacy/About: no bindings.
- Additional splits in the flow: `settingsSheetContent` macOS frame (`ContentView.swift:549-553`); whole-file `#if os(iOS)` in `ContentView+iOS.swift` (notification scheduling + seams); notifications side effect `.onChange(of: notificationsEnabled)` iOS-only (`ContentView.swift:229-233` → `ContentView+iOS.swift:24-35`).

## Q5: Shared card/plate containers and settings usage

### Findings
- All four containers live in the app target, **none in SingleThreadCore** (zero hits under `SingleThreadCore/`). None contains any `#if os(...)`.
- `CardPlate` (`SingleThread/CardPlate.swift:11`): constants only — `cornerRadius = 10` (`:15`), `promptBoxFill` (`:22`), `plateFill(for:)` dark → `.black`, light → `Color(red: 0.96, 0.95, 0.94)` (`:26-27`). No alignment/sizing/frame.
- `CardPlateModifier` (`SingleThread/CardPlateModifier.swift:17`): padding → `RoundedRectangle(cornerRadius:).fill(fill)` background → optional negative padding to restore geometry (`:20-31`); helper `cardPlate(fill:padding:restoresGeometry:)` defaults padding 12, `restoresGeometry: false` (`:45-49`). Pure shape/padding machine.
- `ControlPlateModifier` (`SingleThread/ControlPlateModifier.swift:12`): color-scheme-aware fill/glyph (`:21-22`), `.foregroundStyle`, `.frame(width: 56, height: 56)`, `.background(_, in: Circle())`, `.shadow` (`:25-28`); constants `plateSize 56, lightPlateWhite 0.92, darkGlyphWhite 0.15, shadowRadius 4` (`:33-36`); helper `controlPlate(fill:glyph:)` (`:51-54`).
- `EmptyStateCard` (`SingleThread/EmptyStateCard.swift:11`): `VStack(spacing: 8)` icon/title/description, description `.multilineTextAlignment(.center)` + `.frame(maxWidth: maxWidth)` (`:27-32`), then `.cardPlate(fill:…, padding: 20)` (`:34`); `maxContentWidth(viewportWidth:) = min(340, viewportWidth * 0.6)` (`:42-44`); centering delegated to the caller's `frame(maxWidth:.infinity, minHeight:, alignment:.center)`.
- Call sites — main reminder content only: `.cardPlate` at `ReminderCardView.swift:37` (card text plate, `restoresGeometry: true`) and `:170` (swipe prompt, `promptBoxFill`); `.cardPlate` inside `EmptyStateCard.swift:34`; `.controlPlate` at `ContentView.swift:167` (settings **gear button** — the only plate adjacent to the settings surface), `:184` (undo, iOS), `:468/:481` (complete/skip, iOS), `:510` (mic, both), `:520` (recording indicator, both), `:560` (creation feedback, both); `EmptyStateCard` at `ContentView.swift:359-363` (all-done) and `:374-378` (empty) in the reminder list.
- **Settings surface: zero plate/background styling.** Verified by grep: `SettingsView.swift` and all sub-settings views contain no `cardPlate`/`controlPlate`/`EmptyStateCard`/`RoundedRectangle`/`CardPlate` usage. Settings rows render stock `List`/`Form` chrome; main-content row chrome (`.listRowBackground(viewModel.rowChromeBackground)` = `.clear`, `.listStyle(.plain)`, `.scrollContentBackground(.hidden)`, `.background(Color.clear)`) applies only to the reminder list (`ContentView.swift:390-401, :428-433`; `ContentViewModel.swift:54-57`).
- Only non-List chrome in the settings bundle is `UpgradePromptButton`'s `.background(.blue, in: Capsule())` + `.shadow` (`PurchaseSettingsView.swift:187-188`) — presented in the main bottom bar, not the settings sheet.

## Q6: Settings test coverage

### Findings
- Unit tests (Swift Testing) on settings views: `SingleThreadTests/SettingsViewTests.swift` — `settingsBindingsCarriesShowCompletionGlow` `:13`, `settingsBindingsCarriesShowSwipePrompt` `:21`, `settingsBindingsCarriesShowUndoButton` `:29` (bag round-trips), `settingsViewContainsNavigationLinkLabels` `:37` (SwiftUI `String(describing: view.body)` asserts "Interface"/"Reminder"/… /"Done" `:41-51`), `interfaceSettingsViewContainsExpectedRows` `:56` (contains `#if os(iOS)` variants `:57, :79`), `reminderSettingsViewContainsExpectedRows` `:88`, `filterSortSettingsViewContainsExpectedRows` `:107`, `backgroundSettingsViewContainsExpectedRows` `:124`, `backgroundSettingsViewContainsPinToggle` `:140`, `pinToggleVisibleWhenBackgroundDisabled` `:155`, `privacySettingsViewContainsExpectedContent` `:170`. Helper `makeSeededStore()` `:192`. Related: `AboutViewTests.swift:11, :21`; `PrivacySettingsContentTests.swift:10, :27`; `SettingsViewModelTests.swift:11`; bag parser `UITestingSeedTests.swift` (`fromLaunchArguments` cases `:14, :29, :41, :53, :69, :80, :92, :103, :114, :125-127`, `:132`, reset cases `:147, :154, :161, :168`). **No unit test touches `NotificationsSettingsView`, `PurchaseSettingsView`, or `ExcludedListsView`.**
- UI tests (XCTest) driving the settings sheet: helpers in `SingleThreadUITests/SingleThreadUITestCase.swift` — `launchApp` `:24-27`, `launchSeeded` `:29-31`, `flipToggle` `:35-43`, `assertTogglePersists` `:45-52` (no callers). Settings flows in `SingleThreadUITestsFlows.swift`: `testSettingsOpensAndShowsControls` `:185` (row-by-row nav: Interface/Reminder/FilterSort/Privacy), `testAboutModalShowsAttribution` `:222`, `testBackgroundAndPinTogglesPersistAcrossRelaunch` `:262`, `testBackgroundRefreshButtonExists` `:327`, `testReminderTogglesPersistAcrossRelaunch` `:386`, `testCompletionGlowDoesNotAppearWhenDisabled` `:429`, `testSwipePromptToggleRoundTripsViaSettings` `:517`, `testUndoButtonHiddenWhenToggleOff` `:594`, `testSettingsHasPurchaseRow` `:689`, `testPurchaseSheetHasRestoreButton` `:704`. Notifications submenu: `NotificationsSettingsUITests.swift:6, :23`; `NotificationsUITests.swift:47, :103` (a11y audit on the Notifications sub-view); `NotificationSchedulingUITests.swift:40, :64, :113, :90`. Interface/appearance: `SingleThreadUITestsAppearanceLaunchTests.swift:60, :94`.
- Destinations: Makefile default `SIM ?= platform=iOS Simulator,name=iPhone 17` (`Makefile:1`), `MAC_SIM := platform=macOS` (`Makefile:8`); `mac-test` runs `test -only-testing:SingleThreadTests` on `platform=macOS` (`Makefile:26-27`). `scripts/test.sh`: `MAC_SIM="platform=macOS"` `:12`; iOS unit `-only-testing:SingleThreadTests` `:232-237`; iOS UI `-only-testing:SingleThreadUITests` `:242-245`; watch suites `:250-255`; macOS unit-only block `:288-292`. CI: iOS matrix `iPhone 17` + `iPad (A16)` for unit `ci.yml:25-27`, ui-flows `:93-95`, launch+appearance `:154-156`, audits `:213`; `mac-tests` job `ci.yml:270` builds/tests `-destination "platform=macOS"` `:297, :308` with `-only-testing:SingleThreadTests`. **macOS is a test destination for unit tests only; `SingleThreadUITests` never runs on macOS** in Makefile, test.sh, or CI. Native macOS, not Catalyst: `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` + `MACOSX_DEPLOYMENT_TARGET = 26.5` in pbxproj (`project.pbxproj:768-775, :818-825`).
- Launch-argument seams: `--seed <json>` parsed in `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift:44-56`, consumed at `SingleThread/AppViewModel.swift:235 → :290` — resets ALL persisted settings prefs (`UITestingSeed.swift:69-90` key list) for deterministic defaults, swaps in `InMemoryEventStore`, writes `completionCount` unclamped (`:298-301`), forces `enableActionButtons=true` (`:304-306`), builds entitlement store from seed `isEntitled` (`:309-313`) → drives the "Unlock"/"Manage Purchase" row label (`SettingsView.swift:101-104`). `--ui-testing` (`AppViewModel.swift:245-274`): `enableActionButtons=true`, single "Buy groceries" reminder, `loadsReminders = false`; companion flags `--reset-glow-preference`/`--reset-swipe-preference` (`:247-252`), `--ui-testing-glow` (`ContentView.swift:278-279` → glow 2.0s, `AppViewModel.swift:209`), `--ui-testing-notifications` (`ContentView+iOS.swift:13-14`), `--no-reminders` (`AppViewModel.swift:275`). **The settings sheet is never auto-presented by a launch arg** — every test taps `settingsButton` (`ContentView.swift:171`) / "Settings" text.

## Cross-Cutting Observations

- **In-memory bag + write-back chain pattern**: settings edits mutate the ephemeral `SettingsBindings` bag; `settingsSheetWritebacks` mirrors every change to the `@AppStorage` backing properties via `.onChange` (`ContentView+Settings.swift:19-43`). The chain is split into staged modifiers specifically to stay under the compiler's type-check budget (comment `ContentView+Settings.swift:5-7`).
- One app target serves iOS + macOS (single `WindowGroup` in `SingleThreadApp.swift:20-24`); platform divergence is handled with `#if os(...)` at the row level (Interface args, Notifications row) and the macOS min-frame, not separate targets.
- Settings surface has zero shared-plate styling — plates are a main-content (reminder card) visual language only; the settings sheet on both platforms looks like stock macOS/iOS form chrome.
- macOS is CI-tested via unit tests only (including on-device `SettingsViewTests` body-string assertions); all UI-driven settings behavior is validated on iOS simulators only.
- The sheets (settings + purchase) rely on content ideal sizing on macOS; only the settings sheet gets a min-frame floor; `PurchaseSheet` gets none (`ContentView.swift:246-248`, no min-frame).
- `swipeActions`/`contextMenu` are iOS-only; the swipe-prompt binding returns a constant `false` outside iOS (`ContentView.swift:279-286`), so `ReminderCardView` prompt rendering is iOS-only in practice.

## Open Areas

- Q3's nav-bar placement rules are **framework behavior** — no repo code addresses pushed-view nav-bar vertical positioning; nothing in the codebase confirms or disproves framework-level behavior on the actual macOS runtime.
- No unit tests for `NotificationsSettingsView`, `PurchaseSettingsView`, `ExcludedListsView`; the freemium purchase sheet is UI-test-only.
- The three notification UI test classes run in CI's `ui-tests` env? **No** — CI `-only-testing:` fragments (ci.yml `:16-18`) cover LaunchTests, AppearanceLaunchTests, Flows, `SingleThreadUITests`, ActionButtonsUITests; `NotificationsUITests`, `NotificationsSettingsUITests`, `NotificationSchedulingUITests` run only via local `make ui-test` (`scripts/test.sh` `--ui-only` runs the whole target).
- No macOS UI tests exist at all; macOS-specific rendering (settings sheet sizing, nav-bar placement, form appearance) is untested by automated UI checks.
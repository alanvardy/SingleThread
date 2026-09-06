All findings verified. Here is the complete deliverable (written to the configured output path by the runtime).

---

# Q3 — Cross-Platform View Conventions: Dense Inventory

**Repo root:** `/Users/vardy/dev/alanvardy-var-792-macos-button-rendering-anomalies`
**Scope:** `SingleThread/` (shared iPhone/iPad/macOS source set), `SingleThreadWatch/`, `SingleThreadWidget/`; adjacent `SingleThreadCore/` noted at the end.
**Method:** `rg`/`grep` for `#if os(`, `#elseif os(`, `#else`, `#endif` across all three app dirs; full reads of every file containing a branch and of each named helper. All line numbers verified against the files on disk.

---

## 1 — Complete `#if os(` branch inventory

### 1a. `SingleThreadWatch/` — zero conditional-compilation sites

No `#if` / `#else` / `#endif` occurs in any of the 10 Swift files (`SingleThreadWatchApp.swift`, `WatchAppViewModel.swift`, `WatchReminderView.swift`, `WatchReminderViewModel.swift`, `ShowAlarmsState.swift`, `ShowCompletionGlowState.swift`, `ShowDateState.swift`, `ShowEnableActionButtonsState.swift`, `ShowListState.swift`, `ShowRecurrenceState.swift`). Platform separation is by separate source files, not by conditional compilation — e.g. the watch builds its own `WindowGroup { WatchReminderView(viewModel:) }` in `SingleThreadWatch/SingleThreadWatchApp.swift:7-13`, and the watch keeps its own App Group–backed flags such as `ShowEnableActionButtonsState` (`SingleThreadWatch/ShowEnableActionButtonsState.swift:1-2`, reads `AppGroup.defaults.bool(forKey: "enableActionButtons")`, `ShowEnableActionButtonsState.swift:10`).

### 1b. `SingleThreadWidget/` — zero conditional-compilation sites

No `#if` / `#else` / `#endif` in `NextThingWidget.swift` or `SingleThreadWidgetBundle.swift` (only `Info.plist` plus resources otherwise).

### 1c. `SingleThread/` — 83 `#if os(` sites across 18 files

Tally (verified from the line lists below): 60 sites gate `os(iOS)` only; 16 gate `os(macOS)` only; 7 gate `os(iOS) || os(macOS)`; 6 additional `#elseif os(macOS)` riders; 8 bare `#else` branches. Files: ContentView.swift, ContentView+iOS.swift, ContentView+ActionMenu.swift, ContentView+Settings.swift, SettingsView.swift, InterfaceSettingsView.swift, SettingsViewModel.swift, ReminderSettingsView.swift, SettingsSubscreenLayout.swift, AppearanceMode.swift, Color+CrossPlatform.swift, SingleThreadApp.swift, AppDelegate.swift, AppViewModel.swift, ContentViewModel.swift, BackgroundImageStore.swift, ReminderDictation.swift, AboutView.swift.

#### `SingleThread/ContentView.swift` — 25 sites (22 iOS, 3 macOS)

| Lines | Gate | What it separates |
|---|---|---|
| 9–11 | `os(iOS)` | `import UIKit` (file-level) |
| 22–24 | `os(iOS)` | First `init(viewModel:appViewModel:)`: stores `appViewModel` |
| 37–39 | `os(iOS)` | Second init (canvas previews): `appViewModel = nil` |
| 63–65 | `os(iOS)` | Third init (previews): `appViewModel = nil` |
| 78–81 | `os(iOS)` | `@AppStorage("allowsLandscape")` property |
| 95–98 | `os(iOS)` | `@AppStorage("enableActionButtons", store: AppGroup.defaults)` property |
| 100–103 | `os(iOS)` | `@AppStorage("showSwipePrompt")` property |
| 105–114 | `os(iOS)` | `@AppStorage("showUndoButton")`, `notificationsEnabled`, `notificationIntervalHours` properties |
| 142–151 | `os(iOS)` | `@State isShowingActionMenu` (146) + `@State actionMenuReminder` (150) |
| 157–159 | `os(iOS)` | `@State lastOpenedURL` — `--url-opener-spy` UI-test seam |
| 161–163 | `os(iOS)` | `let appViewModel: AppViewModel?` stored property |
| 210–226 | `os(macOS)` | Top-leading refresh button overlay in `body` (`arrow.clockwise`, calls `viewModel.refreshManual()`) — the macOS counterpart of the iOS undo overlay |
| 227–245 | `os(iOS)` | Top-leading undo-completion button overlay (`arrow.uturn.backward`, gated on `undoStore.hasUndoableReminder && showUndoButton && canMutate`) |
| 252–256 | `os(iOS)` | `notificationStatusOverlay` (`--ui-testing-notifications` seam) inside `body`’s `.overlay(alignment: .topLeading)` |
| 280–284 | `os(iOS)` | `.onChange(of: notificationsEnabled)` → `handleNotificationsEnabledChange` |
| 305–319 | `os(iOS)` | `.sheet(isPresented: $isShowingNudgeSheet)` + the URL-spy accessibility overlay at the end of `body` |
| 351–355 | `os(iOS)` ↔ `#else` | `swipePromptBinding`: `$showSwipePrompt` (iOS) vs `.constant(false)` (353–354, all other platforms) |
| 436–456 | `os(iOS)` | `.contextMenu` on the reminder card row: "View in Reminders" + Delete |
| 497–526 | `os(iOS)` | `completeButton` (501), `actionCluster` (514), `upgradePrompt` (523) — the iOS complete/skip/mic bottom cluster |
| 577–579 | `os(macOS)` | `settingsSheetContent`: `.frame(minWidth: 400, minHeight: 500)` — macOS sheets size from content ideal size |
| 609–613 | `os(iOS)` | `handleScenePhaseChange` `.background` case → `scheduleNotificationIfNeeded()` |
| 615–619 | `os(iOS)` | `handleScenePhaseChange` `.active` case → `cancelNotifications()` |
| 632–636 | `os(macOS)` | `bottomBar`: render `actionButtons` only when `viewModel.store.visibleReminders.first != nil` |
| 673–685 | `os(iOS)` ↔ `#else`(683) | `bottomBar` mic branch: iOS entitlement-resolution chain (`hasResolvedEntitlement`→`EmptyView` / `canMutate`→`upgradePrompt` / `showsActionButtons`→`actionCluster` / else `micButton`, 674–682) vs plain `micButton` on non-iOS (684) |
| 694–701 | `os(iOS)` | "Open Settings" button in the speech-unavailable block (`UIApplication.openSettingsURLString`) |

Shared (ungated) state nearby: `@State isShowingNudgeSheet` at `ContentView.swift:137` (doc at 135–136 marks it "iOS only") and `@State isShowingRescheduleSheet = false` at `ContentView.swift:140` (doc at 138–139 marks it "iOS + macOS"); the `.sheet(isPresented: $isShowingRescheduleSheet)` presentation at `ContentView.swift:302` is unconditional.

#### `SingleThread/ContentView+iOS.swift` — 2 whole-file sites

| Lines | Gate | What it separates |
|---|---|---|
| 10–46 | `os(iOS)` | Entire first extension: `isNotificationsUITesting` (17), `notificationStatusOverlay` (27), `handleNotificationsEnabledChange` (41) |
| 54–124 | `os(iOS)` | Entire second extension: `nudgeSheetContent` (59), `nudgedReminder` (78), `nudgeViewInRemindersButton` (87), `nudgeDeleteButton` (108) |

Comment at `ContentView+iOS.swift:5-7` explains the split exists so `ContentView` stays inside SwiftLint's `type_body_length` budget.

#### `SingleThread/ContentView+ActionMenu.swift` — 2 sites

| Lines | Gate | What it separates |
|---|---|---|
| 14–68 | `os(iOS)` | `showActionMenu` (18), `skipButton` (30) with `.confirmationDialog("Reminder", …)` (at 51ff), `actionMenuRescheduleReminder` (65); all gated on `ActionMenuGate.showsActionMenu(...)` (19–23) |
| 70–170 | `os(macOS)` | `actionButtons` (75) — `HStack(spacing: 32)` choosing `macCompleteButton + macActionMenu` (toggle ON) or `macCompleteButton + macSkipButton + macDeleteButton` (toggle OFF) at 83–86; `macShowActionMenu` (89, reads `AppGroup.defaults.bool(forKey: "enableActionButtons")`); `macCompleteButton` (96, `.keyboardShortcut("c", modifiers: [])`); `macActionMenu` (111, `Menu` with `[.delete]` shortcut and `"s"` shortcut); `macSkipButton` (135); `macDeleteButton` (150); `actionMenuRescheduleReminder` (167, uses visible reminder directly — "macOS has no captured reminder (the Menu has no tap-through)") |

Ungated after the two blocks: `actionMenuRescheduleSheet`… precisely, `actionMenuRescheduleSheet` (175–213) — the shared `NavigationStack`- wrapped `RescheduleSheet` used by both platforms (presented from `ContentView.swift:302`). `isShowingRescheduleSheet = true` is set from the iOS dialog at `ContentView+ActionMenu.swift:52` and from the macOS Menu at `:117`. Header comment at `ContentView+ActionMenu.swift:7-10` states the file split is for SwiftLint `type_body_length`; the iOS `skipButton` is `internal` so `actionCluster` in `ContentView.swift:514` can reference it across files (`ContentView+ActionMenu.swift:27-29`).

#### `SingleThread/ContentView+Settings.swift` — 2 sites with `#elseif`

| Lines | Gate | What it separates |
|---|---|---|
| 21–31 | `os(iOS)` / `#elseif os(macOS)` | `settingsSheetWritebacks`: iOS adds 6 extra `.onChange` write-backs (`allowsLandscape`, `enableActionButtons`, `showSwipePrompt`, `showUndoButton`, `notificationsEnabled`, `notificationIntervalHours` at 23–28); macOS (`#elseif` at 29) passes `withAppearance` through unchanged, then the 8→13 shared write-backs (35–46) apply on both |
| 50–86 | `os(iOS)` / `#elseif os(macOS)` | `makeSettingsBag`: iOS builds the full 19-argument `SettingsBindings` (51–64); macOS (`#elseif` at 71) builds the 12-argument variant (72–84) |

#### `SingleThread/SettingsView.swift` — 2 sites (1 with `#elseif`)

| Lines | Gate | What it separates |
|---|---|
| 40–56 | `os(iOS)`(40)/`#elseif os(macOS)`(50) | Interface `NavigationLink`: iOS constructs `InterfaceSettingsView` with 8 arguments — `appearanceMode, textSize, allowsLandscape, showMicrophoneButton, enableActionButtons, showSwipePrompt, showUndoButton, viewModel` (41–48); macOS constructs it with 3 — `appearanceMode, textSize, showMicrophoneButton, viewModel` (51–55) |
| 64–76 | `os(iOS)` | Notifications `NavigationLink` → `NotificationsSettingsView` (iOS-only row; not present in the macOS row list) |

Doc comment at `SettingsView.swift:12-13` requires every navigation destination to end with `.settingsSubscreenLayout()` so pushed settings screens top-align on macOS.

#### `SingleThread/InterfaceSettingsView.swift` — 9 sites (all iOS)

| Lines | Gate | What it separates |
|---|---|---|
| 13–15 | `os(iOS)` | `@Binding var allowsLandscape` |
| | 19–21 | `os(iOS)` | `@Binding var enableActionButtons` |
| 23–25 | `os(iOS)` | `@Binding var showSwipePrompt` |
| 27–29 | `os(iOS)` | `@Binding var showUndoButton` |
| 59–74 | `os(iOS)` | "Allow landscape" `Toggle` row + `.onChange(of: allowsLandscape) → viewModel.allowsLandscapeChanged(newValue)` (71–73) |
| 86–121 | `os(iOS)` | Three toggles: "Show action buttons" (87–101), "Show swipe prompt" (102–112), "Show undo button" (113–120) |
| 132–148 | `os(iOS)` ↔ `#else`(142) | `#Preview("Default")`: iOS 8-arg initializer call (133–141) vs non-iOS 3-arg call (143–147) |

#### `SingleThread/SettingsViewModel.swift` — 3 sites

| Lines | Gate | What it separates |
|---|---|---|
| 2–4 | `os(iOS) \|\| os(macOS)` | `import WidgetKit` |
| 12–16 | `os(iOS)` | `allowsLandscapeChanged(_:) → AppDelegate.applyLock(allowsLandscape:)` (orientation lock) |
| 18–24 | `os(iOS) \|\| os(macOS)` | `showPreferenceChanged() → WidgetCenter.shared.reloadAllTimelines()` |

#### `SingleThread/ReminderSettingsView.swift` — 3 sites

| Lines | Gate | What it separates |
|---|---|---|
| 34–38 | `os(iOS) \|\| os(macOS)` | `.onChange(of: showDate)` → `viewModel.showPreferenceChanged()` |
| 61–65 | `os(iOS) \|\| os(macOS)` | `.onChange(of: showRecurrence)` → `viewModel.showPreferenceChanged()` |
| 77–81 | `os(iOS) \|\| os(macOS)` | `.onChange(of: showAlarms)` → `viewModel.showPreferenceChanged()` |

(The `showList` and `showCompletionGlow` toggles at `ReminderSettingsView.swift:39-59, 82-94` have no widget-reload hook.)

#### `SingleThread/SingleThreadApp.swift` — 4 sites

| Lines | Gate | What it separates |
|---|---|---|
| 2–4 | `os(iOS)` | `import UIKit` |
| 5–7 | `os(macOS)` | `import AppKit` |
| 32–35 | `os(iOS)` | `@UIApplicationDelegateAdaptor(AppDelegate.self)` |
| 36–39 | `os(macOS)` | `@NSApplicationDelegateAdaptor(MacAppDelegate.self)` |

The `WindowGroup { ContentView(viewModel: appViewModel) }` scene body (`SingleThreadApp.swift:16-21`) is shared with no branch.

#### `SingleThread/AppDelegate.swift` — 2 sites (two complete app-delegate classes in one file)

| Lines | Gate | What it separates |
|---|---|---|
| 1–60 | `os(iOS)` | Whole `AppDelegate: NSObject, UIApplicationDelegate` (`AppDelegate.swift:10`): `applyAppearance(mode:to:)` setting `window.overrideUserInterfaceStyle` on every window (13–25); `applyLock(allowsLandscape:)` orientation-mask + `scene.requestGeometryUpdate(.iOS(...))` (30–46); `applicationDidBecomeActive` re-applying appearance (48–51); `supportedInterfaceOrientationsFor` reading persisted `allowsLandscape` (54–59) |
| 62–92 | `os(macOS)` | Whole `MacAppDelegate: NSObject, NSApplicationDelegate` (`AppDelegate.swift:67`): `applyAppearance(mode:)` setting `window.appearance = mode.appKitAppearance` on `NSApp.windows` (71–76); `applicationDidFinishLaunching` + `applicationDidBecomeActive` re-applying via `applyLaunchAppearance()` (78–90) |

#### `SingleThread/AppViewModel.swift` — 11 sites

| Lines | Gate | What it separates |
|---|---|---|
| 4–8 | `os(iOS)` | `import EventKit`, `import UserNotifications`, `import WatchConnectivity` |
| 9–11 | `os(iOS) \|\| os(macOS)` | `import WidgetKit` |
| 30–32 | `os(iOS)` | `init`: `setupSyncService(with: store)` |
| | 33–37 | `os(iOS) \|\| os(macOS)` | `init`: `store.onRemindersChanged = { WidgetCenter.shared.reloadAllTimelines() }` |
| 41–44 | `os(iOS)` | `init`: `setupSyncObservation()` + `setupEntitlementObservation()` |
| 49–149 | `os(iOS)` | `enum NotificationKeys` (54–60); static `idleReminderIdentifier` (65); `pendingSummary`/`lastScheduleSummary` (70–76); `scheduleNotificationIfNeeded()` (78–106); `cancelNotifications()` (110–115); `requestNotificationPermissionIfNeeded()` (119–148) |
| 154–156 | `os(iOS)` | Stored `private(set) var syncService: SkippedReminderSyncService?` |
| 250–286 | `os(iOS)` | `makeStore`: the `--ui-testing` deterministic single-reminder seam (writes AppGroup `enableActionButtons=true`, builds `InMemoryEventStore` reminder "Buy groceries") |
| 350–407 | `os(iOS)` | `setupSyncService(with:)`: full WatchConnectivity wiring — receive handlers `onCompleteReminderReceived`/`onDelete…`/`onReschedule…`/`onExcludedListTitles…`/`onSkipCounts…`, then `service.activate()` and store hook assignments (350–407) |
| | 409–427 | `os(iOS)` | `refreshPendingSummary()` (UI-test seam, 412–418) + `static summary(requests:)` (421–426) |
| 429–515 | `os(iOS)` | `setupEntitlementObservation` (433–442); `setupSyncObservation` (446–456); `handlePreferencesChanged` (459–484); `lastShowDate`…`lastEnableActionButtons` observed state (488–510); `syncDefaultsObserver` (513) |

Ungated shared members: `let store`, `let backgroundImage`, `let usesInMemoryStore` (`AppViewModel.swift:152-153`), `registerDefaults()` (`:160-170`, migrates `enableActionButtons` from `.standard` to `AppGroup.defaults`), `showPreferenceStore(_:fallback:)` (`:174-183`), `makeContentViewModel(openURLAction:)` (`:187-225`), `makeStore(arguments:)` (`:232-299`), `seededStore(_:)` (`:302-331`).

#### `SingleThread/ContentViewModel.swift` — 4 `#if` sites (1 with `#elseif`, 2 with `#else`)

| Lines | Gate | What it separates |
|---|---|---|
| 59–68 | `os(iOS)` | `showsActionButtons`: `AppGroup.defaults.bool(forKey: "enableActionButtons") && store.visibleReminders.first != nil` |
| 131–135 | `os(iOS)` / `#elseif os(macOS)` (133) | `handleAppearanceMode(mode:)`: `AppDelegate.applyAppearance(mode)` vs `MacAppDelegate.applyAppearance(mode)` |
| 250–254 | `os(macOS)` ↔ `#else`(252) | `hiddenRemindersDescription` localized copy: "press the refresh button in the top left corner" (macOS) vs "pull to refresh" (else) |
| 258–262 | `os(macOS)` ↔ `#else`(260) | `allDoneDescription` localized copy: same macOS-refresh-button vs pull-to-refresh divergence |

#### `SingleThread/BackgroundImageStore.swift` — 3 sites (2 with `#elseif`)

| Lines | Gate | What it separates |
|---|---|---|
| 3–7 | `os(iOS)` / `#elseif os(macOS)` (5) | `import UIKit` vs `import AppKit` |
| 242–246 | `os(iOS)` / `#elseif os(macOS)` (244) | `isDecodableImage(_ data:)`: `UIImage(data:) != nil` vs `NSImage(data:) != nil` |
| 289–293 | `os(macOS)` ↔ `#else`(291) | `BackgroundPhotoLayer.image(from:)`: `Image.init(nsImage:)` vs `Image.init(uiImage:)` |

#### `SingleThread/AppearanceMode.swift` — 4 sites

| Lines | Gate | What it separates |
|---|---|---|
| 2–4 | `os(iOS)` | `import UIKit` |
| 5–7 | `os(macOS)` | `import AppKit` |
| 22–32 | `os(iOS)` | `windowOverrideStyle: UIUserInterfaceStyle` — `.system → .unspecified`, `.light → .light`, `.dark → .dark` |
| 34–44 | `os(macOS)` | `appKitAppearance: NSAppearance?` — `.system → nil`, `.light → NSAppearance(named: .aqua)`, `.dark → NSAppearance(named: .darkAqua)` |

Ungated shared members: `colorScheme: ColorScheme?` (`AppearanceMode.swift:50-56`), `systemImage` (`:59-65`), `title` (`:68-73`), `load(from:)` (`:80-85`).

#### `SingleThread/Color+CrossPlatform.swift` — 2 sites

| Lines | Gate | What it separates |
|---|---|---|
| 3–7 | `os(macOS)` / `#else` (5) | `import AppKit` vs `import UIKit` |
| 16–20 | `os(macOS)` / `#else` (18) | `Color.systemBackground`: `Color(nsColor: .windowBackgColor)` vs `Color(uiColor: .systemBackgound)` |

#### `SingleThread/SettingsSubscreenLayout.swift` — 2 sites

| Lines | Gate | What it separates |
|---|---|---|
| 3–12 | `os(macOS)` | Whole private `SettingsSubscreenLayout: ViewModifier` (7): `content.frame(maxHeight: .infinity, alignment: .top)` — fixes the macOS sheet's vertical-centering for pushed settings sub-views |
| 19–23 | `os(macOS)` / `#else` (21) | `settingsSubscreenLayout()`: applies the modifier on macOS, returns `self` unchanged on iOS |

#### `SingleThread/ReminderDictation.swift` — 2 sites

| Lines | Gate | What it separates |
|---|---|---|
| 126–130 | `os(iOS)` | `prepareRecording()`: `AVAudioSession` setCategory `.record`/`.measurement`/`.duckOthers` + `setActive(true)` |
| 154–156 | `os(iOS)` | `tearDownRecording()`: `AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)` |

#### `SingleThread/AboutView.swift` — 1 site

| Lines | Gate | What it separates |
|---|---|---|
| 51–55 | `os(iOS)` | `#Preview("About")` is iOS-only |

#### `SingleThread/NotificationsSettingsView.swift` — 0 actual sites

No conditional directive; its own doc comment at `NotificationsSettingsView.swift:4` states the `NavigationLink` into it is `#if os(iOS)` gated in `SettingsView` (actual gate at `SettingsView.swift:64-76`).

---

## 2 — The seven named cross-platform helpers

**`SingleThread/Color+CrossPlatform.swift`** — one shared symbol, internal `#if`. `extension Color` with `static var systemBackground: Color` (`:15-21`) mapping `NSColor.windowBackgroundColor` (macOS, `:17`) vs `UIColor.systemBackground` (all others, `:19`); imports split at `:3-7`. Consumers call the single symbol with no per-platform guard, e.g. `ContentView.swift:183` (`Color.systemBackground.ignoresSafeArea()`). Doc at `:11-14` states the mapping is so shared views reference one symbol instead of guarding inline.

**`SingleThread/SettingsSubscreenLayout.swift`** — platform-gated modifier + neutral extension. The `ViewModifier` exists only under `#if os(macOS)` (`:3-12`); the public `View.settingsSubscreenLayout()` (`:15-24`) applies the modifier on macOS and is a pass-through (`self` at `:22`) on iOS. Call sites (all settings sub-screens, as required by `SettingsView.swift:12-13`): `InterfaceSettingsView.swift:124`, `ReminderSettingsView.swift:95`, `AboutView.swift:40`, `BackgroundSettingsView.swift:88`, `PurchaseSettingsView.swift:56`, `PrivacySettingsView.swift:21`, `ExcludedListsView.swift:31`, `FilterSortSettingsView.swift:59`.

**`SingleThread/AppearanceMode.swift`** — shared enum with per-platform properties. One `enum AppearanceMode: String, CaseIterable` (`:10-11`) with four platform-neutral members (`colorScheme` `:50-56`, `systemImage` `:59-65`, `title` `:68-73`, `load(from:)` `:80-85`) and two `#if`-gated accessors: `windowOverrideStyle: UIUserInterfaceStyle` (iOS, `:22-32`) and `appKitAppearance: NSAppearance?` (macOS, `:34-44`). Consumed platform-selectively at `ContentViewModel.swift:131-135` and via `AppDelegate.applyAppearance`/`MacAppDelegate.applyAppearance` (`AppDelegate.swift:13-25`, `:71-76`).

**`SingleThread/SettingsBindings.swift`** — **zero platform branches**; the platform divergence is deliberately not compiled out. `@MainActor @Observable final class SettingsBindings` (`:16-18`) declares all 19 preferences unconditionally, including the iOS-only `allowsLandscape`, `enableActionButtons`, `showSwipePrompt`, `showUndoButton`, `notificationsEnabled`, `notificationIntervalHours` (init params `:29-37`, stored vars `:54-72`). Doc comment at `:9-14` explains the compiler does not support `#if` inside a parameter list (`:12`), so these are declared unconditionally and "On macOS they are harmless: the values are simply never wired or read" (`:13`). The iOS/macOS split happens at the two construction sites in `ContentView+Settings.swift:50-86` (see above).

**`SingleThread/URLOpening.swift`** — **zero platform branches**. `@MainActor protocol URLOpening: AnyObject` (`:9-12`), production wrapper `SystemURLOpener` wrapping `OpenURLAction` (`:16-37`, static `noop` at `:29-33`), and test spy `URLOpeningSpy` (`:42-51`). Doc at `:5-8` motivates the `AnyObject` constraint. No `#if` of any kind; it is a platform-neutral seam used by `ContentViewViewModel.openInReminders` (`ContentViewModel.swift:226-241`) and wired in `AppViewModel.makeContentViewModel` (`AppViewModel.swift:187-225`).

**`SingleThread/SettingsCaption.swift`** — **zero platform branches**. `SettingsCaption: View` styling `.font(.caption).foregroundStyle(.secondary)` (`:11-17`); `SettingsLinkLabel: View` (`:20-31`) composing title + `SettingsCaption` + `Image(systemName:)`. Used exclusively as the eight root-settings row labels in `SettingsView.swift:44-46, 59-61, 67-69, 79-81, 91-93, 115-117, 123-125` and inside `InterfaceSettingsView`/`ReminderSettingsView` captions.

**`SingleThread/TextSize.swift`** — **zero platform branches**. `enum TextSize: String, CaseIterable` (`:7-8`) with `system/small/medium/large/extraLarge`; `dynamicTypeSize` mapping (`:15-24`, note `.large → .xLarge` and `.extraLarge → .xxxLarge`), `systemImage` (`:27-34`), `title` (`:37-44`). Applied by the also-branch-free `TextSizeModifier` (`TextSizeModifier.swift:6-14`) at `ContentView.swift:285` and `SettingsView.swift:168`.

---

## 3 — iOS vs macOS implementation pairs (same control, two platform versions)

### Pair A — Bottom-bar action buttons (biggest divergence)
Structured as: shared shell in `ContentView.swift` + one shared extension file (`ContentView+ActionMenu.swift`) containing parallel `#if` blocks, plus an iOS-only block inside `ContentView.swift`, plus two iOS-only blocks in `ContentView+iOS.swift`.

- Shared shell: `ContentView.bottomBar` at `ContentView.swift:630-697` (VStack of dictation status / feedback / mic). macOS renders the action cluster only when a reminder is visible (`:632-636`); iOS substitutes the whole mic branch with an entitlement/action-button decision tree (`:673-685`).
- **iOS version (three separate controls in an HStack):** `completeButton` `ContentView.swift:501-511` (`.controlPlate()` icon-only); `actionCluster` `:514-519` = `completeButton + micButton + skipButton` with `spacing: 16`; `skipButton` `ContentView+ActionMenu.swift:30-64` — a `Button` that either skips directly or, when `showActionMenu` (`:18-24`) is true, captures `actionMenuReminder` and presents `.confirmationDialog("Reminder",…)` with Skip/Reschedule/Delete (`:51-64`). `isShowingActionMenu`/`actionMenuReminder` state live only on iOS (`ContentView.swift:142-151`).
- **macOS version (Menu + separate buttons):** `actionButtons` `ContentView+ActionMenu.swift:75-87` — `HStack(spacing:32)` selecting between `macCompleteButton + macActionMenu` (toggle ON) or `macCompleteButton + macSkipButton + macDeleteButton` (toggle OFF) at `:83-86`; `macCompleteButton` `:96-109` with `.keyboardShortcut("c")`; `macActionMenu` `:111-133` a SwiftUI `Menu` (label = `circle.slash`) with shortcut `"s"` and a destructive item shortcut `.delete` (`:123`); `macSkipButton` `:135-148`; `macDeleteButton` `:150-164`. Note macOS buttons drop `.controlPlate()` and use `.font(.title)` instead (`:103`, `:124`, `:141`, `:157`).
- **Shared reschedule sheet:** `actionMenuRescheduleSheet` `ContentView+ActionMenu.swift:175-213` (un gated), a `NavigationStack`- wrapped `RescheduleSheet` — reached from iOS Skip-dialog (`:52`) and macOS Menu (`:117`), presented from `ContentView.swift:302`. Shared state `isShowingRescheduleSheet` at `ContentView.swift:140`.
- **iOS-only extras:** `upgradePrompt` `ContentView.swift:523-525` (`UpgradePromptButton`) only reachable in the iOS branch of the mic tree (`:673-685`); the skip-nudge sheet + Delete/View-in-Reminders flow exists only on iOS (`ContentView+iOS.swift:54-124`).

### Pair B — App entry point & app delegate
Same `App` struct on all platforms (`SingleThreadApp.swift:13-41`), with the delegate adaptor selected by `#if`: `@UIApplicationDelegateAdaptor(AppDelegate.self)` iOS (`:32-35`) vs `@NSApplicationDelegateAdaptor(MacAppDelegate.self)` macOS (`:36-39`). Both delegate classes live in **one file** `AppDelegate.swift` behind two top-level `#if` blocks (`:1-60` iOS, `:62-92` macOS). The two implementations of `applyAppearance` are parallel: iOS writes `window.overrideUserInterfaceStyle` on all scened windows (`AppDelegate.swift:13-25`), macOS writes `window.appearance` on `NSApp.windows` (`:71-76`).

### Pair C — Appearance application (settings → window)
Shared preference enum (`AppearanceMode.swift`), shared setter in `ContentViewViewModel.handleAppearanceMode` gateing inside one function: `#if os(iOS) AppDelegate.applyAppearance(mode)` vs `#elseif os(macOS) MacAppDelegate.applyAppearance(mode)` (`ContentViewModel.swift:131-135`). Also `SettingsViewModel.allowsLandscapeChanged` is iOS-only (`SettingsViewModel.swift:12-16`).

### Pair D — Interface settings screen (same view, per-platform arguments/rows)
One shared `InterfaceSettingsView` with `#if` per-@property bindings (`InterfaceSettingsView.swift:13-29`) so the **init signature/sarity differs per platform**: `SettingsView.swift:40-56` calls it with 8 arguments on iOS vs 3 on macOS. Rows gated the same way: "Allow landscape" (`:59-74`), "Show action buttons", "show swipe prompt", "show undo button" (`:86-121`) iOS-only; Appearance/Text-Size pickers (`:31-58`) and "Show microphone" (`:76-85`) shared. Preview branches accordingly (`:132-148`).

### Pair E — Top-left corner control (same position, different purpose per platform)
macOS shows a Refresh button; iOS shows an Undo button — both in `body`’s `.overlay(alignment: .topLeading)`, `#if os(macOS)` at `ContentView.swift:210-226` vs `#if os(iOS)` at `:227-245`. Different glyph (`arrow.clockwise` vs `arrow.uturn.backward`), different trigger (`refreshManual()` vs `undoLastCompletion()`), macOS one has `.disabled(isRefreshing)` (`:224`).

### Pair F — Settings sheet chrome
macOS adds `.frame(minWidth:400, minHeight:500)` to the sheet content because macOS sheets size to ideal content and the List would collapse (`ContentView.swift:575-579`); iOS has no equivalent frame. Everything else in `settingsSheetContent`/`settingsSheetWritebacks` is shared (`ContentView+Settings.swift:8-46`).

### Structural pattern summary
- **Whole-file gating (iOS-only files):** `ContentView+iOS.swift` (both extensions wrapped `#if os(iOS)`, `:10`, `:54`).
- **Within-one-file `#if` blocks (the dominant pattern)**: `ContentView.swift` (25 sites), `ContentView+ActionMenu.swift` (parallel iOS/macOS blocks `:14-68`/`:70-170`, shared tail `:175-213`), `AppDelegate.swift` (two whole-class blocks `:1-60`/`:62-92`), `AppearanceMode.swift` (property-pair `:22-32`/`:34-44`).
- **Shared-abstraction for cross-platform differences:** `Color.systemBackground` (`Color+CrossPlatform.swift:15-21`), `settingsSubscreenLayout()` (`SettingsSubscreenLayout.swift:15-24`), `AppearanceMode`/`TextSize` enums (no platform members except the two AppearanceMode accessors), `URLOpening` protocol + `SystemURLOpener`/`URLOpeningSpy` (no platforms), `SettingsBindings` bag (no `#if` by design, see `:9-14`), `ReminderSettingsView` widget-reload hooks (shared iOS+macOS `#if os(iOS) || os(macOS)` at `:34-38, :61-65, :77-81`).
- **Separate source files per platform (no `#if` at all)**: the whole `SingleThreadWatch/` and `SingleThreadWidget/` targets (see §1a/§1b).

---

### 4 — Adjacent (outside the three app dirs, same repo): `SingleThreadCore` uses `canImport` instead of `os()`
`SingleThreadCore/Sources/SingleThreadCore/CodeSpanFormatter.swift:3` `#if canImport(SwiftUI)` around the image-attributes-only code; `:122` re-cheks `canImport(SwiftUI)` inside `applyCodeAttributes`; `:137-147` `platformSecondaryBackgound()` branches `#if os(watchOS)` (gray.opacity fallback `:139-140`), `#elseif canImport(UIKit)` (`UIColor.secondarySystemBackgound`, `:143-144`), `#elseif canImport(AppKit)` (`NSColor.underPageBackgoundColor`, `:146-147`), `#else` gray fallback (`:149-150`).

---
*End of inventory. All findings verified against working-tree files at commit time; no files were modified.*
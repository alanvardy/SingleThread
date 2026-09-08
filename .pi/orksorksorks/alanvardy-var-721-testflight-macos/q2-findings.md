# Q2 — Platform-specific framework usage in SingleThread (iOS/watchOS/macOS)

Scope: whole repo. The main scheme is a multiplatform macOS-native build: pbxproj sets
`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` + `SDKROOT = auto` +
`MACOSX_DEPLOYMENT_TARGET = 26.5` for SingleThread, SingleThreadTests, SingleThreadUITests
and SingleThreadWidget (SingleThread.xcodeproj/project.pbxproj:762-778, 812-828, 842-856,
897-928, 1016-1052); watch targets are `SDKROOT = watchos` + `"watchos watchsimulator"`
(project.pbxproj:953-962, 981-990, 1066-1096, 1111-1120). The Makefile runs the app and unit
tests on macOS via `MAC_SIM := platform=macOS` (Makefile:8, 24, 27). SingleThreadCore declares
`.iOS("18.7"), .watchOS("26.5"), .macOS("26.5")` (SingleThreadCore/Package.swift:6-9).

## 1. WatchConnectivity — fully iOS/watchOS-gated; nothing compiles on macOS

- iOS app: `import WatchConnectivity` under `#if os(iOS)` (SingleThread/AppViewModel.swift:4-9 guard, :7 import). All usage is inside the same guard: `WCSession.isSupported()` + `WCSession.default` + `SkippedReminderSyncService(...)` + `.activate()` + push hooks (AppViewModel.swift:28-74); `syncService` property under `#if os(iOS)` (AppViewModel.swift:198-200).
- Package: the whole file is inside `#if os(iOS) || os(watchOS)` — SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift:4-6 (import at :5), closing `#endif` at :282. `WCSession: SkipSyncSession` :17, `WCSessionDelegate` :23, `didReceiveApplicationContext` :232, `didReceiveMessage` :237. The two iOS-only delegate callbacks (`sessionDidBecomeInactive`, `sessionDidDeactivate`) are additionally gated `#if os(iOS)` (SkippedReminderSyncService.swift:258-261).
- Watch app: `import WatchConnectivity` is NOT `#if`-gated (SingleThreadWatch/WatchAppViewModel.swift:4); usage `WCSession.isSupported()` :150, `WCSession.default` :153 and :244. Safe only because the watch target is watchOS-only (SDKROOT=watchos); never reaches macOS.
- Tests: unguarded `import WatchConnectivity` in watch-only SingleThreadWatchTests/WatchSyncPipelineTests.swift:4 (`WCSession.default` at :92, :140, :163, :196, :223, :255, :278, :300, :344). The iOS-scheme tests are file-gated `#if os(iOS) || os(watchOS)` with the import inside the guard: SingleThreadTests/EntitlementSyncTests.swift:1-4 and SingleThreadTests/SkippedReminderSyncServiceTests.swift:1-5 (all `WCSession.default` uses at :119, :140-480) — these files do not compile on macOS.
- Runtime guard inside the gated code: `WCSession.isSupported()` (AppViewModel.swift:29; WatchAppViewModel.swift:150).

## 2. WidgetKit — macOS explicitly INCLUDED (`#if os(iOS) || os(macOS)`)

- App: `import WidgetKit` under `#if os(iOS) || os(macOS)` (SingleThread/AppViewModel.swift:10); `WidgetCenter.shared.reloadAllTimelines()` under the same guard (AppViewModel.swift:75-79).
- Settings: `import WidgetKit` under `#if os(iOS) || os(macOS)` (SingleThread/SettingsViewModel.swift:3); `WidgetCenter.shared.reloadAllTimelines()` under the same guard (SettingsViewModel.swift:18-21).
- Widget extension (target also builds for macOS per pbxproj): unguarded `import WidgetKit` (SingleThreadWidget/SingleThreadWidgetBundle.swift:2; SingleThreadWidget/NextThingWidget.swift:5). `Widget` + `StaticConfiguration` + `supportedFamilies([.systemSmall,.systemMedium,.systemLarge])` (NextThingWidget.swift:153-171), `TimelineProvider` placeholder/getSnapshot/getTimeline with `Timeline(entries:policy:)` (NextThingWidget.swift:42-80) — not gated.
- No `#available`/`canImport` guard around any WidgetKit use; macOS behavior relies on the framework being present (widget deployment target 26.5).

## 3. Speech + AVFoundation (dictation) — imports NOT gated; only AVAudioSession is iOS-gated

- Unguarded imports (compile on macOS): `@preconcurrency import AVFoundation` + `@preconcurrency import Speech` (SingleThread/ReminderDictation.swift:1, :3); `import Speech` (SingleThread/ContentView.swift:14, SingleThread/ContentViewModel.swift:2, SingleThread/DictationViewModel.swift:2, SingleThread/AuthorizationRequiring.swift:1).
- The whole dictation pipeline is unguarded and available on macOS: `SFSpeechRecognizer(locale:)` (ReminderDictation.swift:103), `AVAudioEngine()` (:104), `SFSpeechAudioBufferRecognitionRequest` + `requiresOnDeviceRecognition` (:132-133), `SFSpeechRecognitionTask`/`recognitionTask(with:)` (:106, :170), `AVCaptureDevice.authorizationStatus(for: .audio)` / `requestAccess` (:112-120) — NOT gated.
- The only `#if os(iOS)` gates are the `AVAudioSession` calls (an iOS-only API; macOS skips the session-setup step): ReminderDictation.swift:126-130 (`setCategory(.record, mode: .measurement, options: .duckOthers)` + `setActive(true, options: .notifyOthersOnDeactivation)`) and :154-156 (`setActive(false, …)`). This is the key macOS behavioral difference: recording runs without an audio-session category/activation on macOS.
- UI: mic button, recording indicator, dictation error text render on all platforms (ContentView.swift:506-525, :601-635). Bottom-bar cluster branches per OS: `#if os(iOS) { upgradePrompt / actionCluster / micButton } #else { micButton }` (ContentView.swift:625-635). The speech-denied “Open Settings” button uses `UIApplication.openSettingsURLString`/`UIApplication.shared.open` inside `#if os(iOS)` (ContentView.swift:644-651); on macOS only the “Speech recognition is unavailable.” text shows.
- `SpeechTranscribing` protocol + `ReminderDictation` live unguarded in the multi-platform app target (ReminderDictation.swift:10-236); `AuthorizationRequiring`/`SpeechAuthorizationRequiring` unguarded (AuthorizationRequiring.swift:7-21). Scene-phase re-read of speech authorization is NOT gated (ContentView.swift:591).
- Tests import Speech unguarded (SingleThreadTests/ActionButtonTests.swift:4, ReminderDictationTests.swift:4, BackgroundCardTests.swift:4, CompletionGlowTests.swift:4, MicrophoneToggleTests.swift:3) and use fake `SpeechTranscribing`/`SFSpeechRecognizerAuthorizationStatus` values, so they compile on macOS. Only the iOS-specific assertion `#if os(iOS)` in MicrophoneToggleTests.swift:232-244 covers the “Open Settings” button. ActionButtonTests.swift:1-7 and BackgroundCardTests.swift:1-7 are file-gated `#if os(iOS)` (they exercise the iOS-only action cluster), so they compile out on macOS.
- No `#if canImport` on Speech/AVFoundation anywhere.

## 4. UserNotifications — 100% iOS-gated; feature absent on macOS

- `import UserNotifications` under `#if os(iOS)` only: SingleThread/AppViewModel.swift:4-9 (import at :6).
- Every API use is inside `#if os(iOS)` blocks: `UNUserNotificationCenter.current()` (AppViewModel.swift:124, :164, :175, :326), `removeAllPendingNotificationRequests()` (:125, :164), `UNMutableNotificationContent`/`UNTimeIntervalNotificationTrigger`/`UNNotificationRequest`/`center.add` (:138-152), `requestAuthorization(options:)` (:179), `notificationSettings()` (:176). The `NotificationKeys`/`idleReminderIdentifier`/`scheduleNotificationIfNeeded`/`cancelNotifications`/`requestNotificationPermissionIfNeeded`/`refreshPendingSummary`/`summary` members are all in `#if os(iOS)` (AppViewModel.swift:93-197, :320-338).
- Scene-phase scheduling/cancellation is iOS-gated: SingleThread/ContentView.swift:578-588 (`handleScenePhaseChange` calls `scheduleNotificationIfNeeded`/`cancelNotifications` under `#if os(iOS)`).
- Notification preferences are iOS-gated: `@AppStorage` keys in ContentView.swift:105-113; `.onChange(of: notificationsEnabled)` :584-588; Notifications row `#if os(iOS)` in SettingsView.swift:57-61; NotificationsSettingsView.swift is SwiftUI bindings only (no UN API); ContentView+iOS.swift is a whole-file `#if os(iOS)` extension (ContentView+iOS.swift:5-27).
- UI tests: whole-file `#if os(iOS)` at SingleThreadUITests/NotificationsUITests.swift:1 and SingleThreadUITests/NotificationSchedulingUITests.swift:1; they drive the iOS-only `com.apple.springboard` for the “Allow” prompt (NotificationsUITests.swift:32-35, NotificationSchedulingUITests.swift:22-25) — compiled out on macOS.

## 5. EventKit — unguarded everywhere; gating is watchOS-only (read-only EventKit on watch)

- SingleThreadCore imports EventKit unguarded: ReminderStore.swift:1, EventKitStoring.swift:1, InMemoryEventStore.swift:1, ReminderDisplay.swift:1, ReminderRecurrenceFormatter.swift:1, ReminderDateFilter.swift:1, ReminderSort.swift:1, PendingCompletionLogic.swift:1, UndoStore.swift:1, UITestingSeed.swift:1, ReminderDictationParser.swift:1.
- App target: unguarded `import EventKit` in ContentView.swift:12 (preview-helper inits use `EKEventStore()`, `EKReminder`, `EKAuthorizationStatus` at ContentView.swift:30, :45); `#if os(iOS)` gated import in AppViewModel.swift:5.
- Watch target: unguarded imports in SingleThreadWatch/WatchAppViewModel.swift:1, WatchReminderView.swift:1, WatchReminderViewModel.swift:1.
- Widget: unguarded (SingleThreadWidget/NextThingWidget.swift:2); `EKEventStore.authorizationStatus(for: .reminder)` switch on `.fullAccess` (NextThingWidget.swift:92-99).
- All platform gating in Core is `#if os(watchOS)` / `#if !os(watchOS)`:
  - Write API surface (EventKitStoring protocol) `#if !os(watchOS)`: `refreshSourcesIfNecessary`, `save`, `remove`, `makeReminder` (EventKitStoring.swift:22-36, :39-56). InMemoryEventStore mirrors the same gate (InMemoryEventStore.swift:96-136, plus scratch `sharedStore` `EKEventStore()` at :127-130).
  - `ReminderStore.undoStore` `#if !os(watchOS)` (ReminderStore.swift:103-106).
  - watchOS read-only branches: `completeReminder` `#if os(watchOS)` (ReminderStore.swift:181-200) vs `#else` EventKit-save path (:201-217); `deleteReminder` (:240-253 watch vs :254-267 iOS/macOS); `addReminder` watchOS `return false` (:276-281); `reload()` calls `eventStore.refreshSourcesIfNecessary()` under `#if !os(watchOS)` (:355-357).
  - Authorization: `start()` compares `authorizationStatus == .fullAccess`, else `requestAccess()` → `eventStore.requestFullAccessToReminders()` (ReminderStore.swift:166-173, :431-441). This compiles and runs identically on macOS (same `.fullAccess` model; macOS differences are entitlements/prompt behavior, not code-gated).
- Tests with `#if !os(watchOS)` gates (these compile and run on macOS): SingleThreadTests/EventKitStoringTests.swift:96, :134, :146-293 (write-path fake + tests), :312-314; SingleThreadTests/ReminderStoreTests.swift:507-628 (UndoCompletionTests), :672-683 (fake-write methods), :793-879 (MakeReminderTests). Watch-only tests import EventKit unguarded (SingleThreadWatchTests/ReminderStoreWatchTests.swift:1, ShowCompletionGlowStateTests.swift:1, WatchReminderViewRegressionTests.swift:1, WatchSyncPipelineTests.swift:1).

## 6. SwiftUI / UIKit / AppKit

- SwiftUI: imported unguarded in every target (app, watch, widget, tests) — single cross-platform UI codebase; e.g. ContentView.swift:15, SingleThreadWatch/SingleThreadWatchApp.swift:1, SingleThreadWidget/SingleThreadWidgetBundle.swift:1. Platform-adaptive SwiftUI-only code is ungated (`.refreshable`, `.scrollContentBackground(.hidden)`, `.containerBackground`, and the macOS-only `.keyboardShortcut` buttons in `#if os(macOS)` ContentView.swift:294-337).
- UIKit imports exist only under `#if os(iOS)`: ContentView.swift:9-11; AppDelegate.swift:1-3 (whole iOS `AppDelegate` :1-60); SingleThreadApp.swift:2-4 (`@UIApplicationDelegateAdaptor(AppDelegate.self)` at :28-30); AppearanceMode.swift:2-4 (`UIUserInterfaceStyle` mapping :19-29); BackgroundImageStore.swift:4 (UIImage validation :110-113 and the iOS-only `BackgroundPhotoLayer` view :153-181); Color+CrossPlatform.swift:6 (`#else import UIKit` — covers iOS + watchOS, `UIColor.systemBackground` :21-25). Tests: AppDelegateTests.swift:1-4 (entire file `#if os(iOS)`; `UIApplication.shared`/`UIWindow`/orientations :29-51); AppearanceModeTests.swift:5-7 (iOS test section :15-27).
- AppKit imports exist only under `#if os(macOS)`: AppDelegate.swift:62-64 (whole `MacAppDelegate` :62-92 — `NSApp.windows` :74, `NSApplicationDelegate` :67); SingleThreadApp.swift:5-7 (`@NSApplicationDelegateAdaptor(MacAppDelegate.self)` :32-34); AppearanceMode.swift:5-7 (`NSAppearance(named: .aqua/.darkAqua)` :35-45); BackgroundImageStore.swift:6 (`NSImage(data:)` :115, via `#elseif os(macOS)`); Color+CrossPlatform.swift:4 (`NSColor.windowBackgroundColor` :13-20). Tests: AppearanceModeTests.swift:8-10 (macOS test section :31-43).
- UIApplication/UIWindowScene vs NSApplication usage: all `UIApplication`/`UIWindowScene` uses are iOS-gated — AppDelegate.swift:10, :17-18, :35, :45, :51 (`connectedScenes`, `keyWindow?.rootViewController`, `supportedInterfaceOrientationsFor`, `requestGeometryUpdate`) and ContentView.swift:646-647 (openSettingsURLString). `NSApplication` appears only in macOS-gated AppDelegate.swift:74 (`NSApp.windows`). Cross-platform appearance dispatch: `#if os(iOS) AppDelegate.applyAppearance #elseif os(macOS) MacAppDelegate.applyAppearance` (ContentViewModel.swift:50-58).
- Other iOS-only UI gating (absent on macOS): undo overlay + iOS @AppStorage (ContentView.swift:178-196, :95-113), swipe-prompt binding (ContentView.swift:285-291), action cluster/upgrade prompt (ContentView.swift:463-502, :625-635), contextMenu deep-link (ContentView.swift:406-427), background photo layer (ContentView.swift:150-155), InterfaceSettingsView iOS rows — landscape/action-buttons/swipe-prompt/undo toggles (InterfaceSettingsView.swift:18-27, :42-75), Notifications row (SettingsView.swift:57-61), previews (ContentView+Previews.swift, AboutView.swift:50-54).

## 7. AppIntents, StoreKit, Combine, OSLog

- AppIntents: unguarded. Core `import AppIntents` (SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift:1) — `CompleteReminderIntent`/`SkipReminderIntent` (:8-41), invoked by the widget `Button(intent:)` (NextThingWidget.swift:200-215). Widget import unguarded (NextThingWidget.swift:1). Tests: SingleThreadTests/ReminderIntentsTests.swift:1 (unguarded). Available macOS 13+; no os guard anywhere.
- StoreKit (StoreKit 2): unguarded — SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift:3 (`Transaction.updates`, `AppStore.sync()`, `Transaction.currentEntitlements` at :58-91) and SingleThread/PurchaseSettingsView.swift:2 (`Product.products(for:)`, purchase/restore UI). Tests use `import StoreKitTest` (SingleThreadTests/EntitlementStoreTests.swift:2) — iOS/macOS test framework, not os-gated. Watch side deliberately avoids StoreKit (EntitlementStore.swift:9); the flag arrives via WatchConnectivity.
- Combine: NO `import Combine` anywhere in the repo (`@Observable`/observation replaces it).
- OSLog/`import os`: unguarded and cross-platform (SingleThread/BackgroundImageStore.swift:8; SingleThreadCore EntitlementStore.swift:2, ReminderStore.swift:3, SkippedReminderSyncService.swift:2).

## 8. NOT platform-gated uses (compile & do run/behave on macOS)

- **Speech/SFSpeechRecognizer/AVAudioEngine/AVCaptureDevice dictation stack**: no os guard except the two AVAudioSession call sites (ReminderDictation.swift:126-130, :154-156). On macOS, mic recording runs without AVAudioSession category/activation.
- **EventKit write path + `.fullAccess` + `requestFullAccessToReminders`** (Core, app, widget): the `#if !os(watchOS)` guards keep the same code for macOS as for iOS; no macOS-specific split.
- **WidgetKit reload + whole widget extension** (AppViewModel.swift:75-79, SettingsViewModel.swift:18-21, both SingleThreadWidget files): macOS explicitly included.
- **AppIntents intents** (ReminderIntents.swift, NextThingWidget.swift): unguarded.
- **StoreKit 2** (EntitlementStore.swift, PurchaseSettingsView.swift): unguarded.
- **SwiftUI common UI** (mic button, reminder list, settings, widget views, watch views): unguarded.
- Fully gated / never on macOS: WatchConnectivity (all uses), UserNotifications (all uses), UIKit/UIApplication/UIWindowScene (all uses) — or isolated to the watchOS-only targets (SingleThreadWatch/*, SingleThreadWatchTests/*, SingleThreadWatchUITests/...:38-41).

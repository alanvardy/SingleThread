# Q3 Findings - Entry Points & Composition Root per Platform

Scope: SingleThread app target (SingleThreadApp, AppDelegate/MacAppDelegate, AppViewModel, ContentView*), AppearanceMode, ReminderStore/InMemoryEventStore/UITestingSeed in SingleThreadCore, watch app wiring, and build config. All paths are relative to repo root. Line numbers were captured by reading the files verbatim.

## 0. Build topology - one multiplatform app target

- The SingleThread target has SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx" in all Debug/Release configs (project.pbxproj:772, 822, 847, 876, 904, 928). There is NO separate macOS target and NO file named *Mac* anywhere in the repo; MacAppDelegate lives inside SingleThread/AppDelegate.swift behind #if os(macOS).
- macOS-only build settings for that same target: MACOSX_DEPLOYMENT_TARGET = 26.5 (project.pbxproj:765, 815, 870, 898, 922), CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = SingleThread/SingleThread.entitlements (project.pbxproj:757-758, 807-808), CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development", ENABLE_APP_SANDBOX = YES, ENABLE_HARDENED_RUNTIME = YES, ENABLE_USER_SELECTED_FILES = readonly, LD_RUNPATH_SEARCH_PATHS[sdk=macosx*] = "@executable_path/../Frameworks" (project.pbxproj target-config block, lines ~751-762).
- macOS sandbox entitlements grant: app-sandbox, application-group group.app.alanvardy.SingleThread, com.apple.security.device.audio-input, com.apple.security.personal-information.calendars (SingleThread/SingleThread.entitlements).
- iOS uses SingleThread/AppGroup.entitlements (CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*] / [sdk=iphonesimulator*], project.pbxproj:756-757).
- The widget target also declares SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx" (project.pbxproj:1016, 1047) but only IPHONEOS_DEPLOYMENT_TARGET = 18.7; watch targets are "watchos watchsimulator" only (project.pbxproj:956, 984, 1068, 1090, 1113, 1137).
- CI builds/tests macOS from the same scheme: xcodebuild -scheme SingleThread -destination "platform=macOS" ... CODE_SIGNING_ALLOWED=NO build then test -only-testing:SingleThreadTests (.github/workflows/ci.yml, mac-tests job). Local equivalents: make mac-build / make mac-test (Makefile:46-51).

## 1. SingleThreadApp entry point (SingleThread/SingleThreadApp.swift)

- @main struct SingleThreadApp: App (SingleThreadApp.swift:9-10). init() eagerly constructs viewModel = AppViewModel() (SingleThreadApp.swift:13-15), i.e. the composition root runs before any scene renders.
- body is a bare WindowGroup { ContentView(viewModel: viewModel.contentViewModel, appViewModel: viewModel) } (SingleThreadApp.swift:19-23). No .commands, no MenuBarExtra, no window-style modifiers in this file.
- Delegate adaptors, both platform-gated:
  - #if os(iOS) -> @UIApplicationDelegateAdaptor(AppDelegate.self) (SingleThreadApp.swift:27-30).
  - #if os(macOS) -> @NSApplicationDelegateAdaptor(MacAppDelegate.self) (SingleThreadApp.swift:31-34).
  - private let viewModel: AppViewModel (SingleThreadApp.swift:36). AppViewModel is a plain stored let (Observable class), not @State/@StateObject.

## 2. AppDelegate / MacAppDelegate appearance bridging (SingleThread/AppDelegate.swift)

Both classes are in the same file, each fully wrapped in #if os(...).

### iOS AppDelegate (AppDelegate.swift:1-60)
- final class AppDelegate: NSObject, UIApplicationDelegate (AppDelegate.swift:13).
- static func applyAppearance(_:to:) (AppDelegate.swift:18-28): sets window.overrideUserInterfaceStyle = mode.windowOverrideStyle on every window of every connected UIWindowScene (or explicit windows). .system maps to .unspecified sentinel to clear the override (comment at AppDelegate.swift:15-17).
- static func applyLock(allowsLandscape:) (AppDelegate.swift:31-44): orientation mask .allButUpsideDown vs .portrait via setNeedsUpdateOfSupportedInterfaceOrientations + requestGeometryUpdate.
- applicationDidBecomeActive calls Self.applyAppearance(AppearanceMode.load()) (AppDelegate.swift:51-53) - re-applies at launch and foreground.
- application(_:supportedInterfaceOrientationsFor:) (AppDelegate.swift:55-60) reads allowsLandscape from UserDefaults directly.

### macOS MacAppDelegate (AppDelegate.swift:62-89)
- final class MacAppDelegate: NSObject, NSApplicationDelegate (AppDelegate.swift:67).
- static func applyAppearance(_ mode: AppearanceMode) (AppDelegate.swift:70-74): for window in NSApp.windows { window.appearance = mode.appKitAppearance }. .system sets nil (clears override -> follows system; comment AppDelegate.swift:68-69).
- applicationDidFinishLaunching (AppDelegate.swift:76-78) and applicationDidBecomeActive (AppDelegate.swift:80-82) both call applyLaunchAppearance() -> Self.applyAppearance(AppearanceMode.load()) (AppDelegate.swift:84-87).
- No orientation-related code on macOS.

### AppearanceMode per-platform mapping (SingleThread/AppearanceMode.swift)
- enum system/light/dark, raw String, persisted as "appearanceMode" (AppearanceMode.swift:10-13).
- iOS: windowOverrideStyle: UIUserInterfaceStyle - .system -> .unspecified, .light -> .light, .dark -> .dark (AppearanceMode.swift:22-31).
- macOS: appKitAppearance: NSAppearance? - .system -> nil, .light -> NSAppearance(named: .aqua), .dark -> NSAppearance(named: .darkAqua) (AppearanceMode.swift:34-42).
- colorScheme: ColorScheme? for previews (AppearanceMode.swift:44-50), systemImage (52-57), title (59-65).
- static func load(from:) (AppearanceMode.swift:67-73): reads "appearanceMode" key, defaults to .system.
- Runtime re-application on change: ContentViewModel.handleAppearanceMode(_:) (SingleThread/ContentViewModel.swift:117-123): #if os(iOS) -> AppDelegate.applyAppearance(mode); #elseif os(macOS) -> MacAppDelegate.applyAppearance(mode). Wired from ContentView .onChange(of: appearanceMode) (ContentView.swift:287-289).
- Tests cover both mappings (SingleThreadTests/AppearanceModeTests.swift:31-37 macOS appKitAppearanceMaps; 18-29 iOS).

## 3. AppViewModel composition root (SingleThread/AppViewModel.swift)

- @MainActor @Observable final class AppViewModel (AppViewModel.swift:12-15). init(arguments: [String] = ProcessInfo.processInfo.arguments) (AppViewModel.swift:21).
- Launch arguments arrive via ProcessInfo.processInfo.arguments (default param) and are parsed in Self.makeStore(arguments:) (AppViewModel.swift:22-23).

### Store construction - makeStore (AppViewModel.swift:226-278)
- if let seed = UITestingSeed.fromLaunchArguments(arguments) { return (seededStore(seed), true) } (AppViewModel.swift:228-230). The --seed path is NOT platform-gated (works on iOS and macOS).
- #if os(iOS) block (AppViewModel.swift:231-272): for --ui-testing without --seed, builds a deterministic single-reminder store: resets showCompletionGlow/showSwipePrompt on --reset-glow-preference/--reset-swipe-preference, sets "enableActionButtons" = true in .standard, creates InMemoryEventStore(reminders: [], calendars: []) and makeReminder(title: "Buy groceries", notes: "Do not forget the milk"...), priority 5, returns ReminderStore(eventStore: inMemoryStore, loadsReminders: false, reminders: [reminder], skippedIDs: [], authorizationStatus: .fullAccess) with usesInMemory: false (AppViewModel.swift:238-271). This branch is compiled OUT on macOS - on macOS --ui-testing alone falls through to the production store with loading suppressed.
- Non-test fallback, all platforms (AppViewModel.swift:273-278): let loads = !arguments.contains("--ui-testing") && !arguments.contains("--no-reminders"); return (ReminderStore(loadsReminders: loads), false). So macOS production (no flags) creates ReminderStore(loadsReminders: true), which defaults eventStore: any EventKitStoring = EKEventStore() (SingleThreadCore/.../ReminderStore.swift:18-19).
- seededStore(_:) (AppViewModel.swift:281-312): UITestingSeed.resetPersistedState(); InMemoryEventStore(reminders:calendars:defaultCalendar:); seeds "completionCount" into AppGroup.defaults; "enableActionButtons"=true; entitlement store from seed.isEntitled (EntitlementStore(testingWithEntitled:) vs EntitlementStore()); ReminderStore(eventStore:, loadsReminders: !emptyWithHidden, hasHidden:, completionCounter: CompletionCounterStore(defaults: AppGroup.defaults, key: "completionCount"), entitlementStore:); then store.setExcludedListTitles(seed.excludedListTitles).
- usesInMemoryStore property (AppViewModel.swift:197) is true only for --seed; the iOS --ui-testing branch returns usesInMemory: false (AppViewModel.swift:270).

### UITestingSeed parsing (SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift)
- fromLaunchArguments (UITestingSeed.swift:29-37): finds "--seed", JSON-decodes SeedPayload, returns nil when absent or malformed. Not platform-gated.
- SeedPayload.materialize() (UITestingSeed.swift:76-96): creates a real EKEventStore(), EKCalendar(for: .reminder, ...) and EKReminder(eventStore:) instances. Wire format: reminders (title/notes/priority), calendars, excludedLists, completionCount, isEntitled, hasHidden (UITestingSeed.swift:14-27, 58-65).
- resetPersistedState() (UITestingSeed.swift:39-50) clears ~23 persisted UserDefaults keys in both AppGroup.defaults and .standard.

### WatchConnectivity wiring - iOS only
- Imports: EventKit, UserNotifications, WatchConnectivity under #if os(iOS) (AppViewModel.swift:4-7); WidgetKit under #if os(iOS) || os(macOS) (AppViewModel.swift:9-11) - so WidgetCenter reload hooks exist on macOS but WatchConnectivity never compiles there.
- init, #if os(iOS) (AppViewModel.swift:28-74): if WCSession.isSupported(), !usesInMemoryStore (AppViewModel.swift:29) creates SkippedReminderSyncService(session: WCSession.default, skipStore:..., entitlementStore: store.entitlementStore, sendsShowDate: true, sendsEntitled: true); assigns onCompleteReminderReceived / onDeleteReminderReceived / onExcludedListTitlesReceived closures capturing [weak store] (AppViewModel.swift:37-56); service.activate() (AppViewModel.swift:68); then store hooks onSkipSetChanged, onShowUndatedRemindersChanged, onExcludedListsChanged, onCompleteReminder, onDeleteReminder, onSortOptionChanged wired to service.pushAll()/request relays (AppViewModel.swift:69-73, with SortOptionStore().save(option) inline in onSortOptionChanged).
- syncService is an iOS-only stored property (AppViewModel.swift:199-201); setupSyncObservation() / setupEntitlementObservation() under #if os(iOS) (AppViewModel.swift:340-403) push fresh snapshots when AppGroup defaults or entitlement changes. Nothing of this exists on macOS.
- The sync service file itself is compiled only under #if os(iOS) || os(watchOS) (SingleThreadCore/.../SkippedReminderSyncService.swift:4), with an iOS-only WCSessionDelegate method at SkippedReminderSyncService.swift:257. Compiling for macOS makes the file effectively empty - there is no WCSession support on macOS.

### Widget timeline hook (iOS + macOS)
- init, #if os(iOS) || os(macOS) (AppViewModel.swift:75-79): store.onRemindersChanged = { WidgetCenter.shared.reloadAllTimelines() }. This is the only macOS-active wiring in AppViewModel besides store construction.
- contentViewModel (AppViewModel.swift:203-212): builds ContentViewModel(store:, backgroundImage:, speechTranscriber: ReminderDictation()) on demand; --ui-testing-glow extends viewModel.completionGlow.duration = 2.0 (AppViewModel.swift:208-211). Not platform-gated.
- registerDefaults() (AppViewModel.swift:214-217): registers ["showMicrophoneButton": true].
- Notification scheduling/permission code is entirely inside #if os(iOS) (AppViewModel.swift:93-193 and 320-338) - no macOS notifications.

## 4. ContentView platform branches (SingleThread/ContentView.swift, +iOS/+Settings/+Previews)

### Stored state
- #if os(iOS) import UIKit at top (ContentView.swift:9).
- init(viewModel:appViewModel:) stores appViewModel only under #if os(iOS) (ContentView.swift:22-25). Preview inits set appViewModel = nil under #if os(iOS) (ContentView.swift:37, 63).
- @AppStorage: appearanceMode, textSize (both platforms, ContentView.swift:78-83); iOS-only allowsLandscape (84-87), enableActionButtons (92-95), showSwipePrompt (98-101), showUndoButton + notification keys (103-109); App-Group-backed showUndatedReminders, sortOption, showDate, showList, showRecurrence, showAlarms, showCompletionGlow (111-132). let viewModel: ContentViewModel (135); iOS-only let appViewModel: AppViewModel? (133-134).

### body
- body (ContentView.swift:137-206): ZStack { Color.systemBackground.ignoresSafeArea(); BackgroundPhotoLayer iOS-only (ContentView.swift:149-153; BackgroundPhotoLayer itself is macOS-excluded - BackgroundImageStore.swift:258 #if os(iOS)); then authGatedContent if store.loadsReminders else reminderList (ContentView.swift:154-158) }.
- Settings gear overlay, all platforms (ContentView.swift:160-177); undo button #if os(iOS) (178-190); completion-glow overlay (all, 191-196); notifications status overlay #if os(iOS) (197-203).
- .task (ContentView.swift:214-216): await viewModel.backgroundImage.setPinned(backgroundPinned); await viewModel.task(showUndatedReminders:) - this is what kicks off ReminderStore.start() on every platform.
- .onChange chains: backgroundPinned, showUndatedReminders, sortOption, appearanceMode, and iOS-only notificationsEnabled (ContentView.swift:218-292). TextSizeModifier (296). Settings + Purchase sheets (298-306).

### macOS-specific views
- #if os(macOS) private var actionButtons: some View (ContentView.swift:294-334): bottom HStack of Complete / Skip / Delete buttons with macOS-only keyboard shortcuts .keyboardShortcut("c", modifiers: []) (ContentView.swift:305) and .keyboardShortcut("s", modifiers: []) (ContentView.swift:318). Delete has no shortcut.
- bottomBar renders actionButtons only under #if os(macOS) and only when a visible reminder exists (ContentView.swift:601-604).
- bottomBar mic branch: #if os(iOS) chooses upgradePrompt / actionCluster / micButton based on canMutate + showsActionButtons; #else (macOS/watchOS) always shows plain micButton (ContentView.swift:625-644). The "Speech recognition is unavailable" message shows on all platforms, but the "Open Settings" button is #if os(iOS) only (ContentView.swift:643-656).
- swipePromptBinding: $showSwipePrompt on iOS, .constant(false) otherwise (ContentView.swift:220-228, gated at 221).
- Context menu with deep link ("View in Reminders") is #if os(iOS) (ContentView.swift:406-427). Swipe actions (leading complete / trailing skip) are NOT gated - they also compile onto the macOS List rows (ContentView.swift:429-443).
- authGatedContent (ContentView.swift:348-359): .notDetermined -> ProgressView("Requesting access"); .fullAccess -> reminderList; default -> ContentUnavailableView with lock.shield reminder-access message. All platforms.
- Scene phase (extension at ContentView.swift:492-515): .background schedules iOS notifications (497-500); .active cancels iOS notifications (502-505) and always calls viewModel.dictation.refreshAuthorizationStatus() (506-507) on every platform.
- iOS-only helpers completeButton/skipButton/actionCluster/upgradePrompt (ContentView.swift:463-498).

### ContentView+iOS.swift - all iOS-gated
- Entire file wrapped #if os(iOS) (ContentView+iOS.swift:1-46): isNotificationsUITesting via --ui-testing-notifications (13-17), notificationStatusOverlay (19-32), handleNotificationsEnabledChange (35-40).

### ContentView+Settings.swift - platform-split settings bag
- settingsSheetWritebacks (ContentView+Settings.swift:7-46): iOS adds .onChange write-backs for allowsLandscape/enableActionButtons/showSwipePrompt/showUndoButton/notificationsEnabled/notificationIntervalHours inside #if os(iOS) (21-29); #else is a passthrough (30-32).
- makeSettingsBag() (ContentView+Settings.swift:48-80): iOS variant includes the 7 iOS-only fields (50-69); #else variant omits them (71-79).

### ContentView+Previews.swift - no #if os
- mockPreviewEventStore = EKEventStore() retained at file scope (ContentView+Previews.swift:11); mockReminder/mockReminderInList built against it (14-37); seven #Preview views (44-92) use InMemoryEventStore and AppearanceMode.dark.colorScheme; "No Access" preview uses loadsReminders: true + .denied.

### ContentViewModel / DictationViewModel (both platforms)
- ContentViewModel.init builds DictationViewModel(speechTranscriber:store:) (ContentViewModel.swift:29-33); #if os(iOS) showsActionButtons (ContentViewModel.swift:40-46); task(showUndatedReminders:) -> store.showsUndatedReminders = ...; await store.start(); await backgroundImage.refreshIfNeeded() (ContentViewModel.swift:97-101).
- DictationViewModel (SingleThread/DictationViewModel.swift) is platform-neutral. ReminderDictation (SingleThread/ReminderDictation.swift) is platform-neutral except audio-session setup/teardown: #if os(iOS) sets/un-sets AVAudioSession .record category in prepareRecording()/tearDownRecording() (ReminderDictation.swift:126, 154); on macOS dictation runs on plain AVAudioEngine + SFSpeechRecognizer (requiresOnDeviceRecognition = true, ReminderDictation.swift:133).
- AuthorizationRequiring (SingleThread/AuthorizationRequiring.swift:14-23) platform-neutral; SpeechAuthorizationRequiring wraps SFSpeechRecognizer.requestAuthorization.

## 5. macOS end-to-end launch -> first rendered view (incl. EventKit authorization)

1. @main SingleThreadApp init (SingleThreadApp.swift:13-15): AppViewModel() runs makeStore(ProcessInfo.processInfo.arguments) (AppViewModel.swift:22-23). No launch args => no seed, no iOS --ui-testing branch => ReminderStore(loadsReminders: true) with default real EKEventStore() (AppViewModel.swift:275-278; ReminderStore.swift:18-19). store.sortOption = SortOptionStore().load() (AppViewModel.swift:24); Self.registerDefaults() (25); WidgetCenter hook store.onRemindersChanged (AppViewModel.swift:75-79, compiled on macOS); backgroundImage = BackgroundImageStore() (AppViewModel.swift:81). No WatchConnectivity, no notifications on macOS.
2. @NSApplicationDelegateAdaptor(MacAppDelegate.self) instantiates the macOS delegate (SingleThreadApp.swift:31-34). applicationDidFinishLaunching -> applyLaunchAppearance() -> MacAppDelegate.applyAppearance(AppearanceMode.load()) sets NSApp.windows[].appearance (AppDelegate.swift:76-78, 84-87, 70-74).
3. WindowGroup presents ContentView(viewModel: viewModel.contentViewModel, appViewModel: viewModel) (SingleThreadApp.swift:19-23); contentViewModel builds ContentViewModel(store: ReminderStore, backgroundImage:, speechTranscriber: ReminderDictation()) (AppViewModel.swift:203-206).
4. ContentView.body: ZStack with Color.systemBackground (macOS -> NSColor.windowBackgroundColor via Color+CrossPlatform.swift:9-12); no BackgroundPhotoLayer on macOS (ContentView.swift:149-153 gated iOS); store.loadsReminders == true so authGatedContent is shown (ContentView.swift:154-158, 348-359).
5. .task fires viewModel.task(showUndatedReminders:) -> store.start() (ContentViewModel.swift:97-101; ContentView.swift:214-216).
6. ReminderStore.start() (ReminderStore.swift:159-167): authorizationStatus = eventStore.authorizationStatus(for: .reminder); if .fullAccess -> reload(); else -> requestAccess().
7. requestAccess() (ReminderStore.swift:428-440): let granted = try await eventStore.requestFullAccessToReminders() - the protocol method is declared in EventKitStoring.swift:14 and implemented by the real EKEventStore conformance (EventKitStoring.swift:20-37). On grant: authorizationStatus = .fullAccess then reload(); else re-reads OS status; on throw re-reads OS status. On macOS the TCC permission is gated by INFOPLIST_KEY_NSRemindersUsageDescription (project.pbxproj target-config block) plus the sandbox entitlement com.apple.security.personal-information.calendars (SingleThread/SingleThread.entitlements).
8. reload() (ReminderStore.swift:306-370): refreshSourcesIfNecessary() (skipped only on watchOS, ReminderStore.swift:352) -> date-window predicate built from ReminderDateFilter.overdueCutoff()/endOfToday() (unless showsUndatedReminders) -> predicateForIncompleteReminders -> fetchReminders(matching:) bridged through ResumptionGate + resumeOnMainActor (ReminderStore.swift:411-419; SingleThreadCore/.../ResumptionGate.swift:12-50) -> derives reminders/hasHidden/availableLists, reconciles skip/excluded, prunes pending completions, fires onRemindersChanged -> widget timeline reload.
9. First rendered list: authGatedContent .fullAccess -> reminderList (ContentView.swift:348-359), a GeometryReader + List with ReminderCardView rows (ContentView.swift:361-444), and bottomBar (ContentView.swift:600-658) that on macOS shows the actionButtons cluster (Complete/Skip/Delete with c/s shortcuts, ContentView.swift:601-604, 294-334) and the plain micButton (625-644). Status .notDetermined renders ProgressView(SharedStrings.requestingAccess) until TCC resolves; .denied/.restricted/other renders the lock ContentUnavailableView.

## 6. Complete #if os(...) inventory in the asked files

- SingleThreadApp.swift: imports iOS (2-4) / macOS (5-7); @UIApplicationDelegateAdaptor (27-30); @NSApplicationDelegateAdaptor (31-34).
- AppDelegate.swift: #if os(iOS) wraps entire AppDelegate (1-60); #if os(macOS) wraps entire MacAppDelegate (62-89).
- AppViewModel.swift: imports (4-7 iOS; 9-11 iOS||macOS); WCSession wiring (28-74 iOS); widget hook (75-79 iOS||macOS); setupSyncObservation/setupEntitlementObservation call (85-88 iOS); NotificationKeys enum + notifications + pendingSummary + schedule/cancel/request-permission (93-193 iOS); syncService property (198-200 iOS); --ui-testing single-reminder branch in makeStore (231-272 iOS); refreshPendingSummary/summary (320-338 iOS); setupEntitlementObservation/setupSyncObservation/handlePreferencesChanged + last-observed prefs (340-403 iOS).
- ContentView.swift: import (9); iOS appViewModel storage in three inits (22-25, 37, 63); iOS @AppStorage (84-87, 92-95, 98-101, 103-109); iOS appViewModel property (133-134); BackgroundPhotoLayer (149-153); undo button (178-190); notifications overlay (197-203); swipePromptBinding (220-228); macOS actionButtons (294-334); context menu (406-427); iOS completeButton/skipButton/actionCluster/upgradePrompt (463-498); scene-phase iOS notification bits (497-500, 502-505); macOS actionButtons in bottomBar (601-604); iOS cluster vs #else mic (625-644); iOS "Open Settings" (643-656).
- ContentView+iOS.swift: whole file (8-46).
- ContentView+Settings.swift: iOS write-back chain (21-29) vs #else (30-32); iOS bag fields (50-69) vs #else (71-79).
- ContentView+Previews.swift: none. AuthorizationRequiring.swift: none. DictationViewModel.swift: none.
- AppearanceMode.swift: iOS import (2-4); macOS import (5-7); windowOverrideStyle (22-31 iOS); appKitAppearance (34-42 macOS).
- ContentViewModel.swift: showsActionButtons (40-46 iOS); handleAppearanceMode #if os(iOS)/#elseif os(macOS) (105-110).
- ReminderDictation.swift: AVAudioSession category in prepareRecording (126 iOS); AVAudioSession deactivate in tearDownRecording (154 iOS).
- BackgroundImageStore.swift: imports (2-6 iOS-vs-macOS); isDecodableImage branch (242); BackgroundPhotoLayer wrapping (258 iOS+).
- Color+CrossPlatform.swift: import (3) and systemBackground mapping (9-12) macOS-vs-(iOS/watchOS).
- SettingsView.swift: InterfaceSettingsView iOS vs macOS parameter lists (36-49); Notifications row iOS-only (50-58).
- InterfaceSettingsView.swift: allowsLandscape binding (13-14); body iOS-only controls (58-72, 79-94); preview split (103-123).
- ReminderSettingsView.swift: widget-reload .onChange write-backs for showDate/showRecurrence/showAlarms (27-29, 40-42, 49-51 iOS||macOS).
- SettingsViewModel.swift: allowsLandscapeChanged (12-15 iOS); showPreferenceChanged (18-21 iOS||macOS).
- AboutView.swift: preview gating (50 iOS).
- SingleThreadCore/ReminderStore.swift: undoStore #if !os(watchOS) (112); watchOS branch in completeReminder (183); undoLastCompletion #if !os(watchOS) (224); watchOS branch in deleteReminder (257); watchOS branch in addReminder (287); refreshSourcesIfNecessary #if !os(watchOS) (352).
- SingleThreadCore/SkippedReminderSyncService.swift: whole file #if os(iOS) || os(watchOS) (4); iOS-only WCSessionDelegate method (257).
- SingleThreadCore/EventKitStoring.swift: makeReminder/save/remove/refreshSourcesIfNecessary #if !os(watchOS) (36-52).

## 7. Existing macOS-specific behavior (all present today)

- MacAppDelegate with NSApp.windows appearance bridging, fired on applicationDidFinishLaunching and applicationDidBecomeActive (AppDelegate.swift:62-89).
- AppearanceMode.appKitAppearance mapping (AppearanceMode.swift:34-42) and runtime re-apply via MacAppDelegate.applyAppearance(mode) on the appearance picker change (ContentViewModel.swift:117-123).
- macOS actionButtons cluster with keyboard shortcuts "c"/"s" (ContentView.swift:294-334) rendered in bottomBar while a reminder is visible (601-604).
- Widget timeline reloads work on macOS via the iOS||macOS-gated onRemindersChanged hook (AppViewModel.swift:75-79) and SettingsViewModel.showPreferenceChanged (SettingsViewModel.swift:18-21) wired from ReminderSettingsView (ReminderSettingsView.swift:27-29, 40-42, 49-51).
- macOS app-sandbox + hardened runtime + Mac entitlements file (project.pbxproj macosx-sdk settings; SingleThread/SingleThread.entitlements).
- make mac-build / mac-test (Makefile:46-51) and CI mac-tests job (.github/workflows/ci.yml).
- Absent on macOS (deliberate platform gaps): no MenuBarExtra, no .commands/CommandMenu keyboard commands, no WCSession/WatchConnectivity (service compiled only iOS||watchOS; AppViewModel pulls it only under #if os(iOS)), no local notifications, no BackgroundPhotoLayer, no action-buttons toggle/swipe-prompt/undo-button/landscape settings, no notifications settings row, no "Open Settings" shortcut in the speech-unavailable message.

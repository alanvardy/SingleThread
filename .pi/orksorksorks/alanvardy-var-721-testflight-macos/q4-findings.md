# Q4 — Persisted stores & entitlement comparison

## 1. App Group UserDefaults suite (the shared store)

- `SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:8` — `public static let suiteName = "group.app.alanvardy.SingleThread"`.
- `SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:13-15` — `AppGroup.defaults` = `UserDefaults(suiteName: suiteName) ?? .standard`; doc comment (:10-12) states the `.standard` fallback applies "when the group is unavailable (watchOS, unregistered simulators, and previews)".
- `AppGroup.defaults` is the default `defaults:` argument for every Core store below (each `init(defaults: UserDefaults = AppGroup.defaults, ...)`), so iOS app, macOS app, and widget read/write the same suite unless overridden. Watch writes override to `.standard` (see §3).

## 2. Every persisted store and its keys

### A. Stores in SingleThreadCore (all default to `AppGroup.defaults`)

| Store | File:line (init / key) | Key | Absent-key default |
|---|---|---|---|
| `SkippedReminderStore` (skipped reminders) | `ReminderSkip.swift:124` | `"skippedReminderIdentifiers"` | `[]` (load :131) |
| `ExcludedListStore` (excluded list titles) | `ExcludedListStore.swift:7` | `"excludedListTitles"` | `[]` (load :11) |
| `ShowDatePreference` | `ShowDatePreference.swift:12` | `"showDate"` | `true` (isEnabled :19-21) |
| `ShowListPreference` | `ShowListPreference.swift:12` | `"showList"` | `false` (isEnabled :19-21) |
| `ShowRecurrencePreference` | `ShowRecurrencePreference.swift:10-11` | `"showRecurrence"` | `true` (isEnabled :19-21) |
| `ShowAlarmsPreference` | `ShowAlarmsPreference.swift:10-11` | `"showAlarms"` | `true` (isEnabled :19-21) |
| `ShowCompletionGlowPreference` | `ShowCompletionGlowPreference.swift:12` | `"showCompletionGlow"` | `true` (isEnabled :19-21) |
| `ShowUndatedRemindersPreference` | `ShowUndatedRemindersPreference.swift:10-11` | `"showUndatedReminders"` | `false` (load :17-18) |
| `SortOptionStore` (sort) | `SortOption.swift:24-25` (key = `SortOption.defaultsKey`, `SortOption.swift:18` = `"sortOption"`) | `"sortOption"` | `.priority` (load :35-38) |
| `CompletionCounterStore` (freemium lifetime count) | `CompletionCounterStore.swift:13-14` | `"completionCount"` | 0 (count :24) |
| `PendingCompletionStore` (watch-only relay bookkeeping) | `PendingCompletionStore.swift:21-23` | `"pendingCompletionIdentifiers"` (dictionary of identifier→timestamp, expiry 300 s, :22) | empty set |

- `UITestingSeed.swift:63-86` lists the full canonical key set wiped by UI tests: `skippedReminderIdentifiers, excludedListTitles, showDate, showList, showRecurrence, showAlarms, showCompletionGlow, showUndatedReminders, sortOption, completionCount, isEntitled` (App Group keys) plus standard-suite keys `enableActionButtons, showMicrophoneButton, showSwipePrompt, showUndoButton, backgroundEnabled, backgroundFadePercent, backgroundPinned, allowsLandscape, textSize, appearanceMode, notificationsEnabled, notificationIntervalHours`. No separate key exists on either tier beyond this list.

### B. Phone/macOS app `@AppStorage` preferences (ContentView.swift)

- **`.standard` suite (device-local cosmetics), shared across iOS+macOS:** `appearanceMode` (:72), `textSize` (:75), `showMicrophoneButton` (:83), `backgroundEnabled` (:86), `backgroundFadePercent` (:89), `backgroundPinned` (:92). Explicit `store: .standard` only on the background keys (:86/:89/:92); the others use SwiftUIs implicit standard suite.
- **`.standard`, iOS-gated (`#if os(iOS)`):** `allowsLandscape` (:79), `enableActionButtons` (:96), `showSwipePrompt` (:101), `showUndoButton` (:106), `notificationsEnabled` (:109), `notificationIntervalHours` (:112) — so these keys exist only in iOS builds of the same target.
- **`store: AppGroup.defaults` (synced/shared), not platform-gated:** `showUndatedReminders` (:115), `sortOption` (:118), `showDate` (:121), `showList` (:124), `showRecurrence` (:127), `showAlarms` (:129), `showCompletionGlow` (:132).
- Notification keys defined centrally in `AppViewModel.swift:94-97` (`NotificationKeys.enabled = "notificationsEnabled"`, `.intervalHours = "notificationIntervalHours"`); read from `UserDefaults.standard` at `AppViewModel.swift:127,131`, written to `.standard` at :183,:187. `AppViewModel.registerDefaults()` (:221) registers `showMicrophoneButton: true` in `.standard`.
- `AppearanceMode.load()` reads `.standard` key `"appearanceMode"` (`AppearanceMode.swift:79-85`); `AppDelegate` reads `.standard` key `"allowsLandscape"` at launch (`AppDelegate.swift:52-58`), same key as the `@AppStorage` property.
- **No privacy/analytics preference store exists:** `PrivacySettingsView.swift:8-20` / `PrivacySettingsContent.swift:21-51` are static text content only (no UserDefaults keys).

### C. Freemium / purchase state

- `EntitlementStore` (`EntitlementStore.swift:41-46`) is an in-memory `@Observable` StoreKit-driven flag (`isEntitled`, product id `app.alanvardy.SingleThread.unlimited` at :41). It is NOT persisted to UserDefaults in production; entitlement persists through Apples StoreKit transaction store (`Transaction.currentEntitlements`, :80-92). The `"isEntitled"` UserDefaults key appears only in the UI-test wipe list (`UITestingSeed.swift:70`) and in the WatchConnectivity payload key (`SkippedReminderSyncService.swift:281`), and the watchs `EntitlementState.swift:3-15` is explicitly in-memory only.
- Freemium gate is `canMutate = entitlementStore.isEntitled || completionCounter.count < 100` (`ReminderStore.swift:145`); `completionCounter.increment()` on iOS complete (`ReminderStore.swift:205`), `decrement()` on undo (:236).

### D. Files on disk (non-UserDefaults persistence)

- `BackgroundImageStore` photo bytes + sidecar: `background.jpg` / `background.json` under `<Application Support>/SingleThread` (`BackgroundImageStore.swift:132-136` default dir, URLs :78-84). `backgroundPinned` toggle is the only UserDefaults piece (:28-33, :80 doc).

## 3. Platform gating — who writes where

- **iOS app:** App Group suite real (entitled, see §4). All Core stores + the 7 `@AppStorage(store: AppGroup.defaults)` prefs land in `group.app.alanvardy.SingleThread`. `.standard` holds the cosmetics (background/appearance/textSize etc.) and notification keys.
- **macOS app:** same target compiles for macOS (single target, `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, `SDKROOT = auto` — `project.pbxproj:772,822`, `:770,820`), so the same `.standard` + `AppGroup` split applies; the app-group entitlement in `SingleThread.entitlements` makes `AppGroup.defaults` resolve to the real suite. The iOS-only `#if os(iOS)` keys (:79,:96,:101,:106,:109,:112) and the watch-specific `#if os(watchOS)` branch in `ReminderStore.completeReminder` (`ReminderStore.swift:185-216`) do not exist on macOS.
- **watchOS app (SingleThreadWatch):** has NO entitlements file (see §4), so `AppGroup.defaults` falls back to `.standard` (`AppGroup.swift:13-15`). Watch explicitly overrides every store to `.standard`:
  - Sync service stores: `WatchAppViewModel.swift:110-118` (`ShowUndatedRemindersPreference(defaults: .standard)`, `ShowDatePreference(defaults: .standard)`, ..., `CompletionCounterStore(defaults: .standard)`).
  - State holders: `ShowDateState.swift:27`, `ShowRecurrenceState.swift:27`, `ShowAlarmsState.swift:27`, `ShowListState.swift:27`, `ShowCompletionGlowState.swift:27` — all `...Preference(defaults: .standard)`.
  - Sort + show-undated restored from `.standard`: `WatchAppViewModel.swift:30-33`.
  - `completionCount` writes on watch also go through `AppGroup.defaults` → `.standard` (`WatchAppViewModel.swift:20-24`, :91-93).
  - `PendingCompletionStore.record` is watch-only (`ReminderStore.swift:189-196`), device-local.
- **Widget (SingleThreadWidget, iOS + macOS, `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` — `project.pbxproj:1016,1047`):** real App Group. Reads prefs via the defaulting stores (`NextThingWidget.swift:80-83`) and `AppGroup.defaults.bool(forKey: "showUndatedReminders")` (:86), `SortOptionStore().load()` (:87); writes skips/completions through `ReminderStore` whose stores default to `AppGroup.defaults` (`ReminderIntents.swift:28-49`). WatchConnectivity sync code is compiled out (guarded `#if os(iOS) || os(watchOS)`, `SkippedReminderSyncService.swift:5`).
- Cross-device propagation (phone↔watch) is NOT shared storage: `SkippedReminderSyncService.pushAll()` (`SkippedReminderSyncService.swift:236-268`) serializes skip list, exclusions, sort, show-*, completion count, isEntitled as a WCSession application context; the receive path persists into each sides suite and persists `.standard` on the watch (:282-360).

## 4. Entitlement diff — AppGroup.entitlements vs SingleThread.entitlements

`SingleThread/AppGroup.entitlements` (entire file):
- `com.apple.security.application-groups` → `["group.app.alanvardy.SingleThread"]` (lines 5-9).

`SingleThread/SingleThread.entitlements` (entire file):
- `com.apple.security.app-sandbox` → `true` (line 5)
- `com.apple.security.application-groups` → `["group.app.alanvardy.SingleThread"]` (lines 6-10)
- `com.apple.security.device.audio-input` → `true` (line 11)
- `com.apple.security.personal-information.calendars` → `true` (line 12)

Differences (macOS file − iOS file): `app-sandbox`, `device.audio-input`, `personal-information.calendars` are present ONLY in `SingleThread.entitlements`. Both files carry the identical app-group identifier.

## 5. pbxproj wiring — which entitlement for which platform

- The app is ONE target (`SingleThread`, product `app.alanvardy.SingleThread`, `project.pbxproj:767,817`) with `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (`pbxproj:772,822`).
- Per-sdk `CODE_SIGN_ENTITLEMENTS` in both Debug and Release of the app target (`project.pbxproj:737-739` and `:787-789`):
  - `[sdk=iphoneos*]` → `SingleThread/AppGroup.entitlements`
  - `[sdk=iphonesimulator*]` → `SingleThread/AppGroup.entitlements`
  - `[sdk=macosx*]` → `SingleThread/SingleThread.entitlements`
- App target also sets `REGISTER_APP_GROUPS = YES` (`pbxproj:769,819`), `ENABLE_APP_SANDBOX = YES` (`pbxproj:744,794`), `ENABLE_HARDENED_RUNTIME = YES` (`:745,795`), `ENABLE_USER_SELECTED_FILES = readonly` (`:747,797`).
- Widget target (`SingleThreadWidget`, bundle `app.alanvardy.SingleThread.widget`, `pbxproj:1012,1043`): `CODE_SIGN_ENTITLEMENTS = SingleThread/AppGroup.entitlements` unconditionally (`pbxproj:997` Debug, `:1028` Release; SUPPORTED_PLATFORMS incl. macosx at `:1016,1047`). Embedded into the app via "Embed Foundation Extensions" phase (`pbxproj:76-84`).
- Watch target (`SingleThreadWatch`, bundle `app.alanvardy.SingleThread.watchkitapp`, `pbxproj:951,979`): **no `CODE_SIGN_ENTITLEMENTS` at all** in either config (`pbxproj:940-990`; configs `51AA3F2B.../51AA3F2C...`, `SDKROOT = watchos` `:953,981`). Therefore watchOS is NOT a member of the app group; on watch, `UserDefaults(suiteName:)` returns nil and `AppGroup.defaults` falls back to `.standard` (`AppGroup.swift:13-15`), which the watchs explicit `defaults: .standard` wiring exploits.
- So the same group identifier `group.app.alanvardy.SingleThread` is deployed on iOS (app + widget, AppGroup.entitlements), macOS (app via SingleThread.entitlements, widget via AppGroup.entitlements), and NOT on watchOS (sync over WatchConnectivity instead).

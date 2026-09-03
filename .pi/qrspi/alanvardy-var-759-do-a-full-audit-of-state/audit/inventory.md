# State Inventory

## Suite Accessor

| Component | Value | Source |
|---|---|---|
| suiteName | `group.app.alanvardy.SingleThread` | `AppGroup.swift:8` |
| defaults accessor | `UserDefaults(suiteName:) ?? .standard` (un-cached, recomputed per access) | `AppGroup.swift:13-14` |

Notes:
- The accessor occupies `AppGroup.swift:13-14` (plan/research cited `:10-14`; lines 10-12 are the doc comment). When the group entitlement is absent (watchOS, previews, unregistered simulators) `UserDefaults(suiteName:)` returns `nil` and group keys collapse into `.standard`.
- Suite doc comment names only skipped-reminder identifiers; the suite actually carries 11 group keys.

## `.standard` Keys (12)

| Key | Default | Encoding | Declaration | Reads | Writes | Dual-Read? | Targets |
|---|---|---|---|---|---|---|---|
| `appearanceMode` | `.system` | String rawValue | `ContentView.swift:72` | `ContentView.swift:72`, `AppearanceMode.swift:80`, `AppDelegate.swift:47` | `ContentView+Settings.swift:19` (bag→@AppStorage), `UITestingSeed.swift:84` (reset) | yes | ios |
| `textSize` | `.system` | String rawValue | `ContentView.swift:75` | `ContentView.swift:75`, `ContentView.swift:236` | `ContentView+Settings.swift:20` (bag→@AppStorage) | no | ios |
| `allowsLandscape` | `true` | Bool | `ContentView.swift:79` | `ContentView.swift:79`, `AppDelegate.swift:53,55` | `ContentView+Settings.swift:23` (bag→@AppStorage) | yes | ios |
| `showMicrophoneButton` | `true` | Bool | `ContentView.swift:83` | `ContentView.swift:83`, `ContentView.swift:624` | `ContentView+Settings.swift:33` (bag→@AppStorage); registerDefaults `AppViewModel.swift:221` | no | ios |
| `backgroundEnabled` | `true` | Bool | `ContentView.swift:86` | `ContentView.swift:86`, `ContentView.swift:153` | `ContentView+Settings.swift:34` (bag→@AppStorage) | no | ios |
| `backgroundFadePercent` | `BackgroundFade.defaultValue` (50) | Int | `ContentView.swift:89` | `ContentView.swift:89`, `ContentView.swift:154` | `ContentView+Settings.swift:35` (bag→@AppStorage) | no | ios |
| `backgroundPinned` | `false` | Bool | `ContentView.swift:92` | `ContentView.swift:92`, `ContentView.swift:216` | `ContentView+Settings.swift:36` (bag→@AppStorage); mirror `BackgroundImageStore.swift:142` | no | ios |
| `enableActionButtons` | `false` | Bool | `ContentView.swift:96` | `ContentView.swift:96`, `ContentViewModel.swift:45-49`, `ContentView.swift:630` | `ContentView+Settings.swift:24` (bag→@AppStorage); seams `AppViewModel.swift:252,298` | yes | ios |
| `showSwipePrompt` | `true` | Bool | `ContentView.swift:101` | `ContentView.swift:101`, `ContentView.swift:397` | `ContentView+Settings.swift:25` (bag→@AppStorage); reset seam `AppViewModel.swift:250` | no | ios |
| `showUndoButton` | `true` | Bool | `ContentView.swift:106` | `ContentView.swift:106`, `ContentView.swift:180` | `ContentView+Settings.swift:26` (bag→@AppStorage) | no | ios |
| `notificationsEnabled` | `false` | Bool | `ContentView.swift:109` | `ContentView.swift:109`, `AppViewModel.swift:127` | `ContentView+Settings.swift:27` (bag→@AppStorage); denial writes `AppViewModel.swift:183,187` | yes | ios |
| `notificationIntervalHours` | `48` | Int | `ContentView.swift:112` | `ContentView.swift:112`, `AppViewModel.swift:131-132` | `ContentView+Settings.swift:28` (bag→@AppStorage) | yes | ios |

Notes:
- `notificationsEnabled`/`notificationIntervalHours` are declared via `AppViewModel.NotificationKeys.enabled`/`.intervalHours` (raw literals `"notificationsEnabled"`/`"notificationIntervalHours"`).
- None of the 12 `.standard` keys are referenced by the watch or widget targets (verified by grep) — targets are iOS-only.

## App Group Keys (11)

| Key | Default | Encoding | Declaration | Reads | Writes | Dual-Read? | Targets |
|---|---|---|---|---|---|---|---|
| `showUndatedReminders` | `false` | `object as? Bool ?? false` | `ContentView.swift:115` | `ContentView.swift:115`, `ShowUndatedRemindersPreference.swift:19`, `NextThingWidget.swift:71`, `WatchAppViewModel.swift:34` | `ContentView+Settings.swift:37` (bag→@AppStorage), `ContentViewModel.swift:90,96`, `ShowUndatedRemindersPreference.swift:23`, `SkippedReminderSyncService.swift:328` | yes | ios, watchOS, widget |
| `sortOption` | `.priority` | String rawValue | `ContentView.swift:118`; key constant `SortOption.swift:18` | `ContentView.swift:118`, `SortOption.swift:35`, `AppViewModel.swift:25`, `NextThingWidget.swift:72`, `WatchAppViewModel.swift:31` | `ContentView+Settings.swift:38` (bag→@AppStorage), `SortOption.swift:42`, `SkippedReminderSyncService.swift:334`, `ReminderIntents.swift:20,43` | yes | ios, watchOS, widget |
| `showDate` | `true` | `object as? Bool ?? true` | `ContentView.swift:121` | `ContentView.swift:121`, `ShowDatePreference.swift:20`, `AppViewModel.swift:381` | `ContentView+Settings.swift:39` (bag→@AppStorage), `SkippedReminderSyncService.swift:339`; shadow cache `AppViewModel.swift:391` | yes | ios, watchOS, widget |
| `showList` | `false` | `object as? Bool ?? false` | `ContentView.swift:124` | `ContentView.swift:124`, `ShowListPreference.swift:20` | `ContentView+Settings.swift:40` (bag→@AppStorage), `SkippedReminderSyncService.swift:354`; shadow cache `AppViewModel.swift:394` | yes | ios, watchOS, widget |
| `showRecurrence` | `true` | `object as? Bool ?? true` | `ContentView.swift:127` | `ContentView.swift:127`, `ShowRecurrencePreference.swift:20` | `ContentView+Settings.swift:41` (bag→@AppStorage), `SkippedReminderSyncService.swift:344`; shadow cache `AppViewModel.swift:392` | yes | ios, watchOS, widget |
| `showAlarms` | `true` | `object as? Bool ?? true` | `ContentView.swift:129` | `ContentView.swift:129`, `ShowAlarmsPreference.swift:20` | `ContentView+Settings.swift:42` (bag→@AppStorage), `SkippedReminderSyncService.swift:349`; shadow cache `AppViewModel.swift:393` | yes | ios, watchOS, widget |
| `showCompletionGlow` | `true` | `object as? Bool ?? true` | `ContentView.swift:132` | `ContentView.swift:132`, `ShowCompletionGlowPreference.swift:20`, `ContentViewModel.swift:118` | `ContentView+Settings.swift:43` (bag→@AppStorage), `SkippedReminderSyncService.swift:359`; reset seam `AppViewModel.swift:247` (removes from `.standard`) | yes | ios, watchOS, widget |
| `skippedReminderIdentifiers` | `[]` | `stringArray ?? []` | `ReminderSkip.swift:124` | `ReminderSkip.swift:132`, `ReminderStore.swift:558` | `ReminderSkip.swift:136`, `ReminderStore.swift:484,499,561`; wcPayload `SkippedReminderSyncService.swift:170` | no | ios, watchOS, widget |
| `excludedListTitles` | `[]` | `stringArray ?? []` | `ExcludedListStore.swift:7` | `ExcludedListStore.swift:15`, `ReminderStore.swift:560` | `ExcludedListStore.swift:19`, `ReminderStore.swift:417`; wcPayload `SkippedReminderSyncService.swift:171` | no | ios, watchOS, widget |
| `completionCount` | `0` | Int (0-defaulted) | `CompletionCounterStore.swift:23` | `CompletionCounterStore.swift:24`, `ReminderStore.swift:145` | `CompletionCounterStore.swift:29,36`, `ReminderStore.swift:213,244`; seams `AppViewModel.swift:294`, `WatchAppViewModel.swift:27,186` | no | ios, watchOS, widget |
| `pendingCompletionIdentifiers` | `[:]` | dictionary String→TimeInterval (300 s expiry) | `PendingCompletionStore.swift:21` | `PendingCompletionStore.swift:70`, `ReminderStore.swift:525` | `PendingCompletionStore.swift:83`, `ReminderStore.swift:202,542` | no | watchOS |

Notes:
- `AppViewModel.handlePreferencesChanged` (`AppViewModel.swift:380-395`) shadow-reads the five show*-date/recurrence/alarms/list/glow keys on `UserDefaults.didChangeNotification` for the `pushAll()` trigger (`lastShow*` caches `AppViewModel.swift:401-405`).
- On watchOS the sync service persists received values into `.standard`-pinned stores (`WatchAppViewModel.swift:155-161`) while the phone writes the same keys into the App Group — the same logical key spans both containers depending on the process.

## Dual-Read-Path Keys

Keys declared as `@AppStorage` *and* read through an independent raw `UserDefaults` read:

| Key | @AppStorage Site | Raw Read Site(s) |
|---|---|---|
| `enableActionButtons` | `ContentView.swift:96` | `ContentViewModel.swift:45-49` |
| `notificationsEnabled` | `ContentView.swift:109` | `AppViewModel.swift:127` |
| `notificationIntervalHours` | `ContentView.swift:112` | `AppViewModel.swift:131-132` |
| `allowsLandscape` | `ContentView.swift:79` | `AppDelegate.swift:53-56` |
| `appearanceMode` | `ContentView.swift:72` | `AppearanceMode.swift:80` via `AppDelegate.swift:47` |
| `showDate` | `ContentView.swift:121` | `ShowDatePreference.swift:20` |
| `showList` | `ContentView.swift:124` | `ShowListPreference.swift:20` |
| `showRecurrence` | `ContentView.swift:127` | `ShowRecurrencePreference.swift:20` |
| `showAlarms` | `ContentView.swift:129` | `ShowAlarmsPreference.swift:20` |
| `showCompletionGlow` | `ContentView.swift:132` | `ShowCompletionGlowPreference.swift:20` |
| `sortOption` | `ContentView.swift:118` | `SortOption.swift:35` |
| `showUndatedReminders` | `ContentView.swift:115` | `ShowUndatedRemindersPreference.swift:19` |

Exactly 12 keys — matches research Q1's verified dual-read set.
(Plan-drift fixes re-verified against source: the raw `appearanceMode` read is `AppearanceMode.swift:80`; the `showCompletionGlow` raw read is `ShowCompletionGlowPreference.swift:20`; the sort raw read inside `SortOptionStore.load()` is pinned at `SortOption.swift:35`.)

## Single-Path Keys

| Key | Path | Site |
|---|---|---|
| `textSize` | @AppStorage only | `ContentView.swift:75` |
| `showMicrophoneButton` | @AppStorage (+registerDefaults only) | `ContentView.swift:83` |
| `backgroundEnabled` | @AppStorage only | `ContentView.swift:86` |
| `backgroundFadePercent` | @AppStorage only | `ContentView.swift:89` |
| `backgroundPinned` | @AppStorage + BackgroundImageStore mirror | `ContentView.swift:92` |
| `showSwipePrompt` | @AppStorage only | `ContentView.swift:101` |
| `showUndoButton` | @AppStorage only | `ContentView.swift:106` |
| `skippedReminderIdentifiers` | store read/write only (App Group) | `ReminderSkip.swift:124,132,136` |
| `excludedListTitles` | store read/write only (App Group) | `ExcludedListStore.swift:7,15,19` |
| `completionCount` | store read/write only (App Group) | `CompletionCounterStore.swift:23,24-47` |
| `pendingCompletionIdentifiers` | store read/write only (App Group, watch-only) | `PendingCompletionStore.swift:21,70,83` |

## Store Mirror Table

For every observable store below: `@Observable final class`. Verified by grep: the codebase no longer uses the older Combine-based observable-class pattern anywhere. Exceptions: `WatchAppViewModel` and `ResumptionGate` are plain classes (no observation); the widget target has no view model at all (`NextThingWidget.swift` / `SingleThreadWidgetBundle.swift` are views only).

| Store | Property | Mirrors Key | Kind | Notes |
|---|---|---|---|---|
| `ReminderStore` | `sortOption` (:70) | `sortOption` | persisted | Direct assignment bypasses hooks (documented above the declaration); use `setSortOption` |
| `ReminderStore` | `showsUndatedReminders` (:122-127) | `showUndatedReminders` | persisted | `didSet` fires `onShowUndatedRemindersChanged` |
| `ReminderStore` | `skippedIDs` (:56) | `skippedReminderIdentifiers` | persisted | private(set) |
| `ReminderStore` | `excludedListTitles` (:57) | `excludedListTitles` | persisted | private(set) |
| `ReminderStore` | `completionCounter` (:106) | `completionCount` | persisted | let; counter store reads/writes `AppGroup.defaults` internally |
| `ReminderStore` | `pendingCompletions` (:464) | `pendingCompletionIdentifiers` | persisted | private; watch-only relay valve |
| `ReminderStore` | `reminders` (:55) | — | transient | private(set); populated by `reload()` |
| `ReminderStore` | `hasHidden` (:62) | — | transient | private(set); set in `reload()` |
| `ReminderStore` | `availableLists` (:64) | — | transient | private(set) |
| `ReminderStore` | `authorizationStatus` (:65) | — | transient | private(set) |
| `ReminderStore` | `skipGeneration` (:468) | — | transient | private |
| `ReminderStore` | `loadsReminders` (:66) | — | immutable | let |
| `ReminderStore` | `entitlementStore` (:110) | — | value ref | let; see `EntitlementStore` |
| `ReminderStore` | `undoStore` (:115) | — | transient | let; `#if !os(watchOS)` |
| `ReminderStore` | `visibleReminders` (:129) | — | computed | filters skip/exclude, sorts by `sortOption` |
| `ReminderStore` | `allSkipped` (:138-140) | — | computed | `!reminders.isEmpty && visibleReminders.isEmpty` |
| `ReminderStore` | `canMutate` (:144-145) | — | computed | `isEntitled \|\| completionCounter.count < 100` |
| `ReminderStore` | `hasResolvedEntitlement` (:151) | — | computed | forwards `entitlementStore.hasResolvedEntitlement` |
| `EntitlementStore` | `isEntitled` (:54) | — | transient | StoreKit-derived, never persisted |
| `EntitlementStore` | `hasResolvedEntitlement` (:60) | — | transient | set adjacently with `isEntitled` (`EntitlementStore.swift:104-105`) |
| `EntitlementState` (watch) | `isEnabled` (:17) | — | transient | set from WC context only |
| `WatchReminderViewModel` | `isShowingCompletionTransition` (:47) | — | transient | set with `transitionReminder` |
| `WatchReminderViewModel` | `transitionReminder` (:51) | — | transient | `EKReminder?` |
| `WatchReminderViewModel` | `completionTransitionBuffer` (:55) | — | transient | 0.5 s |
| `CompletionGlow` | `isActive` (:21) | — | transient | |
| `CompletionGlow` | `duration` (:27) | — | transient | default 0.50 (plan/research cited `:26`; actual declaration is `:27`) |
| `DictationViewModel` | `isDictating` (:22) | — | transient | |
| `DictationViewModel` | `dictationText` (:23) | — | transient | |
| `DictationViewModel` | `dictationError` (:24) | — | transient | |
| `DictationViewModel` | `creationFeedback` (:25) | — | transient | `.success`/`.failure`; auto-clears after 1 s |
| `ReminderDictation` | `isRecording` (:107) | — | transient | `@ObservationIgnored` members nearby |
| `UndoStore` | `lastCompletedReminder` (:19) | — | transient | iOS-only; in-memory |
| `UndoStore` | `hasUndoableReminder` (:21) | — | computed | |
| `BackgroundImageStore` | `imageData` (:69) | — | transient | mirrors photo files on disk, not UserDefaults |
| `BackgroundImageStore` | `photographer` (:71) | — | transient | |
| `BackgroundImageStore` | `photographerURL` (:73) | — | transient | |
| `BackgroundImageStore` | `isRefreshing` (:76) | — | transient | |
| `BackgroundImageStore` | `isPinned` (:81) | `backgroundPinned` | persisted | mirrors @AppStorage key |
| `BackgroundImageStore` | `isFetching` (:198) | — | transient | |
| `ResumptionGate` | `hasResumed` (:28) | — | transient | plain `@unchecked Sendable` class, no observation |
| `ShowDateState` (watch) | `isEnabled` (:18) | `showDate` | persisted | double-persisted (service store + `.apply()`); `.standard` |
| `ShowListState` (watch) | `isEnabled` (:18) | `showList` | persisted | double-persisted (service store + `.apply()`); `.standard` |
| `ShowRecurrenceState` (watch) | `isEnabled` (:18) | `showRecurrence` | persisted | double-persisted (service store + `.apply()`); `.standard` |
| `ShowAlarmsState` (watch) | `isEnabled` (:18) | `showAlarms` | persisted | double-persisted (service store + `.apply()`); `.standard` |
| `ShowCompletionGlowState` (watch) | `isEnabled` (:17) | `showCompletionGlow` | persisted | double-persisted (service store + `.apply()`); `.standard`; declaration at `:17` (one doc line shorter) |
| `SettingsBindings` | 19 mutable props (:63-81) | mirrors 19 @AppStorage | transient | per-sheet bag; never writes `UserDefaults` directly (`.onChange` write-back in `ContentView+Settings.swift`) |
| `AppViewModel` | `lastShow*` shadow caches (:401-405) | show-* (×5) | transient | diffed for `pushAll()` trigger |
| `AppViewModel` | `pendingSummary` (:108) | — | transient | test-only |
| `AppViewModel` | `lastScheduleSummary` (:112) | — | transient | test-only |
| `ContentViewModel` | `showsActionButtons` (:45-49) | `enableActionButtons` | computed | live raw `UserDefaults.standard.bool` read |

Store mirror row count: 50 (research Q2's ~35 property rows plus the per-store transient/computed/immutable properties the report deliberately mirrors; the plan's single `Show*State (×5)` row is split into five rows so the `ShowCompletionGlowState` `:17` vs `:18` difference is explicit).

## Notable Transient State (Acknowledged, Not Exhaustive)

- `ContentView.@State isShowingSettings` (:257), `isShowingPurchase` (:261) — sheet presentation flags
- `WatchReminderViewModel.isRefreshing` (:42), `isShowingRefreshConfirmation` (:43) — refresh UI state (plan cited `:43/:44`; actual declarations are `:42/:43`)
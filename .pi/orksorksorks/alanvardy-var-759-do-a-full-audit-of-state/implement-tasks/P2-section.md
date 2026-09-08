
### Changes

#### 1. Create `audit/inventory.md`
**File**: `.pi/qrspi/<branch>/audit/inventory.md`
**Action**: create

**Content structure**:

```markdown
# State Inventory

## Suite Accessor

| Component | Value | Source |
|---|---|---|
| suiteName | `group.app.alanvardy.SingleThread` | `AppGroup.swift:8` |
| defaults accessor | `UserDefaults(suiteName:) ?? .standard` (un-cached, recomputed per access) | `AppGroup.swift:10-14` |

## `.standard` Keys (12)

| Key | Default | Encoding | Declaration | Reads | Writes | Dual-Read? | Targets |
|---|---|---|---|---|---|---|---|
| `appearanceMode` | `.system` | String rawValue | `ContentView.swift:72` | `ContentView.swift:72`, `AppearanceMode.swift:79-86`, `AppDelegate.swift:44-46` | `ContentView+Settings.swift` (bag→@AppStorage), `UITestingSeed.swift:63-85` (reset) | yes | ios, widget |
| ... | ... | ... | ... | ... | ... | ... | ... |

## App Group Keys (11)

| Key | Default | Encoding | Declaration | Reads | Writes | Dual-Read? | Targets |
|---|---|---|---|---|---|---|---|
| `showUndatedReminders` | `false` | `object as? Bool ?? false` | `ContentView.swift:115` | ... | ... | yes | ios, watchOS, widget |
| ... | ... | ... | ... | ... | ... | ... | ... |

## Dual-Read-Path Keys

List of keys with `@AppStorage` plus an independent raw read, with both read sites cited:

| Key | @AppStorage Site | Raw Read Site(s) |
|---|---|---|
| `enableActionButtons` | `ContentView.swift:96` | `ContentViewModel.swift:45-49` |
| `notificationsEnabled` | `ContentView.swift:109` | `AppViewModel.swift:127` |
| `notificationIntervalHours` | `ContentView.swift:112` | `AppViewModel.swift:131-132` |
| `allowsLandscape` | `ContentView.swift:79` | `AppDelegate.swift:53-56` |
| `appearanceMode` | `ContentView.swift:72` | `AppearanceMode.swift:79-86` via `AppDelegate.swift:44-46` |
| `showDate` | `ContentView.swift:121` | `ShowDatePreference.swift:20` |
| `showList` | `ContentView.swift:124` | `ShowListPreference.swift:20` |
| `showRecurrence` | `ContentView.swift:127` | `ShowRecurrencePreference.swift:20` |
| `showAlarms` | `ContentView.swift:129` | `ShowAlarmsPreference.swift:20` |
| `showCompletionGlow` | `ContentView.swift:132` | `ShowCompletionGlowPreference.swift:19-21` |
| `sortOption` | `ContentView.swift:118` | `SortOptionStore.swift:34-39` |
| `showUndatedReminders` | `ContentView.swift:115` | `ShowUndatedRemindersPreference.swift:19` |

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
| `completionCount` | store read/write only (App Group) | `CompletionCounterStore.swift:11,24-47` |
| `pendingCompletionIdentifiers` | store read/write only (App Group, watch-only) | `PendingCompletionStore.swift:21,70,83` |

## Store Mirror Table

| Store | Property | Mirrors Key | Kind | Notes |
|---|---|---|---|---|
| `ReminderStore` | `sortOption` (:70) | `sortOption` | persisted | Direct assignment bypasses hooks (:68-69 doc) |
| `ReminderStore` | `showsUndatedReminders` (:122-127) | `showUndatedReminders` | persisted | `didSet` fires `onShowUndatedRemindersChanged` |
| `ReminderStore` | `skippedIDs` (:56) | `skippedReminderIdentifiers` | persisted | private(set) |
| `ReminderStore` | `excludedListTitles` (:57) | `excludedListTitles` | persisted | private(set) |
| `ReminderStore` | `completionCounter` (:106) | `completionCount` | persisted | let; counter store reads/writes internally |
| `ReminderStore` | `pendingCompletions` (:464) | `pendingCompletionIdentifiers` | persisted | private; watch-only |
| `ReminderStore` | `reminders` (:55) | — | transient | private(set); populated by `reload()` |
| `ReminderStore` | `hasHidden` (:62) | — | transient | private(set); set in `reload()` |
| `ReminderStore` | `availableLists` (:64) | — | transient | private(set) |
| `ReminderStore` | `authorizationStatus` (:65) | — | transient | private(set) |
| `ReminderStore` | `skipGeneration` (:468) | — | transient | private |
| `ReminderStore` | `loadsReminders` (:66) | — | immutable | let |
| `ReminderStore` | `entitlementStore` (:110) | — | value ref | let; see `EntitlementStore` |
| `ReminderStore` | `undoStore` (:115) | — | transient | let; `#if !os(watchOS)` |
| `ReminderStore` | `visibleReminders` (:129) | — | computed | |
| `ReminderStore` | `allSkipped` (:138-140) | — | computed | `!reminders.isEmpty && visibleReminders.isEmpty` |
| `ReminderStore` | `canMutate` (:144-145) | — | computed | `isEntitled \|\| completionCounter.count < 100` |
| `ReminderStore` | `hasResolvedEntitlement` (:151) | — | computed | forwards `entitlementStore.hasResolvedEntitlement` |
| `EntitlementStore` | `isEntitled` (:54) | — | transient | StoreKit-derived, never persisted |
| `EntitlementStore` | `hasResolvedEntitlement` (:60) | — | transient | set adjacently with `isEntitled` (:104-105) |
| `EntitlementState` (watch) | `isEnabled` (:17) | — | transient | set from WC context only |
| `WatchReminderViewModel` | `isShowingCompletionTransition` (:47) | — | transient | set with `transitionReminder` |
| `WatchReminderViewModel` | `transitionReminder` (:51) | — | transient | `EKReminder?` |
| `WatchReminderViewModel` | `completionTransitionBuffer` (:55) | — | transient | 0.5 s |
| `CompletionGlow` | `isActive` (:21) | — | transient | |
| `CompletionGlow` | `duration` (:26) | — | transient | default 0.50 |
| `DictationViewModel` | `isDictating` (:22) | — | transient | |
| `DictationViewModel` | `dictationText` (:23) | — | transient | |
| `DictationViewModel` | `dictationError` (:24) | — | transient | |
| `DictationViewModel` | `creationFeedback` (:25) | — | transient | `.success`/`.failure`; auto-clears |
| `ReminderDictation` | `isRecording` (:107) | — | transient | `@ObservationIgnored` members nearby |
| `UndoStore` | `lastCompletedReminder` (:19) | — | transient | iOS-only |
| `UndoStore` | `hasUndoableReminder` (:21) | — | computed | |
| `BackgroundImageStore` | `imageData` (:69) | — | transient | mirrors photo files on disk |
| `BackgroundImageStore` | `photographer` (:71) | — | transient | |
| `BackgroundImageStore` | `photographerURL` (:73) | — | transient | |
| `BackgroundImageStore` | `isRefreshing` (:76) | — | transient | |
| `BackgroundImageStore` | `isPinned` (:81) | `backgroundPinned` | persisted | mirrors @AppStorage key |
| `BackgroundImageStore` | `isFetching` (:198) | — | transient | |
| `ResumptionGate` | `hasResumed` (:28) | — | transient | plain class, no observation |
| Watch `Show*State` (×5) | `isEnabled` (:18) | show-* (×5) | persisted | double-persisted (service + `.apply()`); `.standard` |
| `SettingsBindings` | 19 mutable props (:63-81) | mirrors 19 @AppStorage | transient | per-sheet bag; never writes directly |
| `AppViewModel` | `lastShow*` shadow caches (:401-405) | show-* (×5) | transient | diffed for `pushAll()` trigger |
| `AppViewModel` | `pendingSummary` (:108) | — | transient | test-only |
| `AppViewModel` | `lastScheduleSummary` (:112) | — | transient | test-only |
| `ContentViewModel` | `showsActionButtons` (:45-49) | `enableActionButtons` | computed | live raw `UserDefaults.standard.bool` read |

## Notable Transient State (Acknowledged, Not Exhaustive)

- `ContentView.@State isShowingSettings` (:257), `isShowingPurchase` (:261) — sheet presentation flags
- `WatchReminderViewModel.isRefreshing` (:43), `isShowingRefreshConfirmation` (:44) — refresh UI state
```

**Key constraints**:
- Every `file:line` citation in inventory.md must exist in `factbase.tsv` (cite-check via grep)
- Dual-read-path set must match exactly the 12 keys from research Q1 (re-verified at implementation time): `enableActionButtons`, `notificationsEnabled`, `notificationIntervalHours`, `allowsLandscape`, `appearanceMode`, `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow`, `sortOption`, `showUndatedReminders`
- Store mirror table must confirm: no `ObservableObject` exists; every store is `@Observable final class` except `WatchAppViewModel`/`ResumptionGate` (plain classes) and the widget (no view model)

### Verification

#### Automated
- [ ] Cite-check: every `*.swift:<line>` citation string in `audit/inventory.md` appears as a row in `audit/factbase.tsv` — `grep -oE '[A-Za-z]+\.swift:[0-9]+' audit/inventory.md | sort -u | while read cite; do grep -q "$cite" audit/factbase.tsv || echo "MISSING: $cite"; done` produces no output
- [ ] `bash audit/verify-citations.sh` still exits 0 (fact base remains clean)
- [ ] 23-key split: count `.standard` key rows = 12, count App Group key rows = 11 in `inventory.md`
- [ ] Store mirror table row count matches research Q2's enumerated stores (approximately 35 rows)

#### Manual
- [ ] Dual-read-path set enumerated in `inventory.md` matches the list above (12 keys) — no more, no fewer
- [ ] Store mirror table confirms no `ObservableObject` reference exists — `grep ObservableObject audit/inventory.md` produces no matches
- [ ] Every store in the mirror table is `@Observable final class` or explicitly noted as plain class / no view model

---


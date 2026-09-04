# Research Findings

All paths relative to repo root `SingleThread/`. Branch
`alanvardy-var-765-add-skip-pattern-nudge`. Note: the current commit
(`dda10ec "Add skip pattern nudge"`) only added a one-line `DELETEME`
placeholder — no skip-mechanics code exists on the feature branch yet; all
findings below describe the **existing committed** skip/reminder machinery.

---

## Q1: Skip mechanics — end-to-end

### Findings
- **State shape** is a set of calendar item identifiers at every layer:
  - In-memory `skippedIDs: Set<String>` (calendarItemIdentifier) —
    `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:56`.
  - Persisted `[String]` in `UserDefaults` suite `group.app.alanvardy.SingleThread`
    (falls back to `.standard`), key `"skippedReminderIdentifiers"` —
    `SkippedReminderStore.init` (`ReminderSkip.swift:124`), `AppGroup.swift:11,16-18`.
  - WatchConnectivity payload `[String]` under `PayloadKey.skippedReminderIdentifiers`
    (`"skippedReminderIdentifiers"`) — `SkippedReminderSyncService.swift:269,317`.
- **Pure logic** in `ReminderSkip.swift`: `resolve(fetched:skipped:)` =
  `Array(Set(fetched).intersection(skipped))` (`:12-14`); `skipping(_:fetched:skipped:)`
  = `resolve(skipped + [identifier])` (`:19-24`). Store I/O: `SkippedReminderStore.load()`
  = `defaults.stringArray(forKey:) ?? []`, `save(_:)` = `defaults.set(..., forKey:)`
  (`ReminderSkip.swift:131-137`).
- **`skipCurrentReminder()`** (`ReminderStore.swift:314-327`): guards `canMutate`
  (`:315`, `canMutate` at `:144-146`), guards `visibleReminders.first` (`:316`),
  computes updated set via `updatedSkipSet` → `ReminderSkipLogic.skipping` (`:472-477`),
  captures `skipGeneration` (`:318`), then spawns a `Task`: `await settle()` (200 ms sleep,
  `:28-33`) then `applySkipSet(updated, generation:)`; only if it returns `true`, `await reload()` (`:319-325`).
- **`applySkipSet`** (`:493-502`) is the single mutation point for skip and clear:
  `skippedIDs = Set(updated)`, `skipStore.save(updated)`, `onSkipSetChanged?(updated)`, `onRemindersChanged?()`.
- **`clearSkippedState`** (`:481-486`): `skipGeneration &+= 1`, `skippedIDs=[]`,
  `skipStore.save([])`, `onSkipSetChanged?([])`.
- **`reconcileSkipState`** (`:551-562`) runs at end of every `reload()` (`:405`):
  if `clearSkipped` → `clearSkippedState()`, else re-resolves from `skipStore.load()`
  pruned against `visibleShown` ids, re-assigns `skippedIDs`, re-persists pruned array (`:561`).
- **`visibleReminders`** (`:129-135`) = `reminders` filtered by `!skippedIDs.contains(id)`
  and excluded-list titles, then sorted. Skip takes effect for rendering immediately on
  `applySkipSet`; the follow-up `reload()` refetches EventKit (drops reminders completed on
  another device — tested `ReminderStoreTests.swift:283-313`).
- **`allSkipped`** (`:138-139`): `!reminders.isEmpty && visibleReminders.isEmpty` — drives
  all-done UI on all three surfaces.
- **Generation race**: `skipGeneration: Int = 0` (`:468`); interactive skip captures it
  (`:318`); `applySkipSet` discards the apply (returns false, no reload) when
  `generation != skipGeneration` (`:494-496`). Pull-to-refresh all-done calls
  `reload(clearSkipped: true)` → `clearSkippedState` bumps generation
  (test `ReminderStoreTests.swift:344-360`).
- **Call sites**:
  - iOS all funnel through `ContentViewModel.skipCurrentReminder()` (`SingleThread/ContentViewModel.swift:123-124`):
    trailing swipe (`ContentView.swift:438`), bottom-bar `skipButton` (`:479`), macOS shortcut "s" (`:311`).
    Hooks: `onSkipSetChanged → service.pushAll()` (`AppViewModel.swift:58`), `onRemindersChanged → WidgetCenter.shared.reloadAllTimelines()` (`:76-78`).
  - watch calls `store.skipCurrentReminder()` directly (`WatchReminderView.swift:120`);
    `onSkipSetChanged → service.pushAll()` (`WatchAppViewModel.swift:194`).
  - widget: `NextThingWidget.swift:177` `Button(intent: SkipReminderIntent())`;
    `ReminderIntents.swift:30-56` builds a fresh `ReminderStore(loadsReminders:true)`, calls
    `skipCurrentReminderImmediately()` (`:49`).
- **`skipCurrentReminderImmediately()`** (`ReminderStore.swift:345-352`) is the synchronous
  widget variant: same guards, computes new set, `applySkipSet(updated)` with **no settle sleep
  and no reload** (WidgetKit may suspend right after `perform()` returns, doc `:342-344`).
  Hooks fire before the intent returns; widget `.allDone`/next state refreshes via WidgetKit
  reload and the iOS app's `reloadAllTimelines`.

---

## Q2: Per-reminder state persistence

### Findings
- **App Group suite**: `AppGroup.suiteName = "group.app.alanvardy.SingleThread"`
  (`AppGroup.swift:11`); `AppGroup.defaults = UserDefaults(suiteName:) ?? .standard` (`:16-18`).
  Watch has no App Group entitlement → falls back to `.standard`. Shared by app, watch, widget.
- **Only shallow `[String]` forms exist — no full reminder-object serialization.** The Q2
  "shallow/full" phrasing is a prompt, not an existing distinction.
- **`SkippedReminderStore`** (`ReminderSkip.swift:121-137`): shallow `[String]` under
  `"skippedReminderIdentifiers"`. `load()` = `stringArray ?? []`; `save()` = `set`.
- **Other stores share the `defaults: UserDefaults = AppGroup.defaults, key:` pattern**:
  - `ExcludedListStore` (`ExcludedListStore.swift:4-15`) — `[String]` under `"excludedListTitles"`.
  - `SortOptionStore` (`SortOption.swift:22-45`) — single `String` under `"sortOption"`.
  - Bool prefs (nil-default): `"showDate"`, `"showRecurrence"`, `"showAlarms"`,
    `"showCompletionGlow"` (absent→`true`); `"showList"`, `"showUndatedReminders"` (absent→`false`).
  - `CompletionCounterStore` — `Int` under `"completionCount"` (0-default) (`CompletionCounterStore.swift:16-...`).
  - `PendingCompletionStore` — dictionary `[String: TimeInterval]` under
    `"pendingCompletionIdentifiers"`, 300 s expiry in `liveEntries()` (`PendingCompletionStore.swift:17-...`).
  - `EntitlementStore` — **not** UserDefaults-persisted; in-memory `isEntitled`/`hasResolvedEntitlement`
    with compile-time seams `init(testingWithEntitled:)`/`init(testingWithEntitlementUnresolved:)` (`EntitlementStore.swift:30,39`).
- **Read/write points** for skip state: `ReminderStore.swift:20` (skipStore init param),
  `:484,499` (save), `:500` (onSkipSetChanged), `:550-563` (reconcile/prune),
  `:131` (visibleReminders filter). Widget reads same key (`NextThingWidget.swift:70`).
- **Launch-arg seams** (`SingleThreadApp.swift:22`, `WatchAppViewModel.swift:11-13` default
  `arguments: ProcessInfo.processInfo.arguments`):
  - **`--seed '<json>'`** (iOS, `AppViewModel.makeStore:234-237`): `UITestingSeed.fromLaunchArguments`
    (`UITestingSeed.swift:44-56`) parses `--seed`, `materialize()` builds real `EKReminder`/
    `EKCalendar` off a local `EKEventStore()` (`:131`). Sets `usesInMemory=true` (`:236`).
  - **`seededStore(_:)`** (`AppViewModel.swift:290-336`): calls `UITestingSeed.resetPersistedState()`
    (`:291`), builds `InMemoryEventStore(reminders:, calendars:, defaultCalendar:)` (`:292-297`),
    sets `completionCount` unclamped into `AppGroup.defaults` (`:301`), sets
    `enableActionButtons=true` on `.standard` (`:304`), picks entitlement from seed flags (`:306-315`),
    applies `seed.excludedListTitles` (`:334-336`).
  - **`UITestingSeed.resetPersistedState()`** (`UITestingSeed.swift:58-66`) clears 23-24 keys from
    **both** `AppGroup.defaults` and `.standard` (`persistedKeys` `:69-92`). This is why
    persistence-across-relaunch UI tests use `--ui-testing`, not `--seed`.
  - **`--ui-testing`** (iOS `AppViewModel.makeStore:245-267`): does **not** call `resetPersistedState()`;
    honors `--reset-glow-preference`/`--reset-swipe-preference` (removes those `.standard` keys, `:246-251`);
    sets `enableActionButtons`, builds `InMemoryEventStore` with one `"Buy groceries"` reminder
    (`priority = 5`), returns `usesInMemory=false` (`:266-274`).
  - **`--ui-testing`** (watch `WatchAppViewModel.swift:14-28,94-143`): `uiTestingStore` one-reminder store;
    `--ui-testing-priority <n>` (`:107`), `--ui-testing-excluded-list`/`--ui-testing-live-excluded` (`:120-143`),
    `--ui-testing-gated` seeds `completionCount=100` into `AppGroup.defaults` (`:26`).
  - **`InMemoryEventStore`** (`SingleThreadCore/.../InMemoryEventStore.swift:13,18-37,91-151`): in-memory
    `EventKitStoring`; reports `.fullAccess`; save/remove/makeReminder only under `#if !os(watchOS)`;
    shared process-wide `EKEventStore` as `sharedStore` (`:97`).

---

## Q3: Prompt / multi-choice UI idioms & localization

### Findings
iOS (`SingleThread/`):
- **In-card dismissible swipe prompt** — `ReminderCardView.swift:127-172`: `VStack` with
  `Text("Swipe left to skip")` (:132) and `Text("Swipe right to complete")` (:140) plus `Dismiss`
  button (:141-150). Hints are `.accessibilityHidden(true)` (:128); Dismiss has
  `.accessibilityLabel("Dismiss swipe prompt")`/`accessibilityIdentifier("swipePromptDismissButton")` (:166-167).
  Gated on `showSwipePrompt` (default true) — `ContentView.swift:101-102` (`@AppStorage("showSwipePrompt")`),
  iOS-only `swipePromptBinding` (:284-291).
- **Swipe actions on list rows** — `ContentView.swift:428-441`: `.swipeActions(edge:.leading)` Complete
  (green), `.swipeActions(edge:.trailing)` Skip (orange). One action per swipe edge.
- **Context menu (long-press)** — `ContentView.swift:407-425`, `#if os(iOS)`: "View in Reminders"
  deep-link button + Delete button (`SharedStrings.deleteAction`, `.tint(.red)`).
- **Sheets (modal)** — `ContentView.swift:245-250`: `.sheet(isPresented: $isShowingSettings)` /
  `.sheet(isPresented: $isShowingPurchase)`, driven by `@State` booleans.
- **Freemium upgrade prompt → purchase sheet** — `PurchaseSettingsView.swift:174-196`
  (`UpgradePromptButton` labeled "Upgrade to unlimited"), `PurchaseSheet` wraps
  `PurchaseSettingsView` in `NavigationStack` with a `Done` confirmation toolbar button (:199-214).
  Rendered from bottom bar when free tier gated — `ContentView.swift:499-500,629`.

watchOS (`SingleThreadWatch/`):
- **True system `confirmationDialog`** — `WatchReminderView.swift:206-221`: tapping the card sets
  `isShowingRefreshConfirmation=true` (:188-189); `.confirmationDialog("Reminder", ...)` (:207) with
  `Button("Refresh")` (:212-215) and `Button(SharedStrings.deleteAction, role:.destructive)` (:216-219).
  This is the watch's explicit multi-action prompt.
- **Persistent on-canvas action-button pair** — `WatchReminderView.swift:103-137`: Complete/Skip
  buttons under the card when not gated.
- **In-band upgrade prompt (not a dialog)** — `WatchReminderView.swift:135-150`: `VStack` with
  `Image(systemName:"lock.fill")` + `Text("Upgrade on\nyour iPhone")`, `accessibilityIdentifier("upgradePrompt")`.
- **In-band empty states** — `WatchReminderView.swift:154-184`: `allDoneState`/`noRemindersState`
  with a single `Refresh` button (:177-184).
- iOS empty states — `ContentViewModel.swift:58-81` builds `EmptyStateCopy`; `"Nothing due"` localized
  inline via `String(localized:, table:"Localizable", bundle:.main)` (:61).

Localization:
- **One source `.xcstrings` per target**: `SingleThread/Resources/Localizable.xcstrings` (4003 lines),
  `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings` (1435),
  `SingleThreadWatch/Resources/Localizable.xcstrings` (49), widget catalog.
- Keys are the full English literal; each entry carries 6 languages (en, zh-Hans, es, ja, de, fr).
- **Shared keys** via `LocalizedString+Shared.swift` `enum SharedStrings` (completeAction/skipAction/
  deleteAction/accessibility labels/repeats/alert/allDone/noReminders/priorityAccessibilityLabel), each
  `String(localized:, table:"Localizable", bundle:.module)`.
- **Target-specific copy** = inline SwiftUI string literals auto-extracted to the target catalog
  (e.g. `Text("Swipe left to skip")` → app catalog `Localizable.xcstrings:2546`).
- **Two mechanisms coexist**: `SharedStrings` enum (Core bundle) vs per-target inline literals.
- **Validation**: `SingleThreadTests/LocalizationTests.swift` — every catalog parses, English non-empty,
  all 6 languages resolve, `%lld` plural variations, per-target `InfoPlist.strings` keys.
- Only the watch uses a true system `confirmationDialog`; iOS uses custom in-band/plate/sheet compositions.
  Some prompt copy is `accessibilityHidden` (swipe hints) — localized but deliberately not screen-reader-reachable.

---

## Q4: Existing reminder operations

### Findings
Operations on `ReminderStore.swift` (all production mutations):
- **Complete** — `completeReminder(identifier:)` `:188-266`, dual-branch:
  - iOS (`#else`): `reminder.isCompleted=true`, `eventStore.save(commit:true)`, `completionCounter.increment()`,
    `undoStore.retain(...)`, settle, reload (`:251-266`).
  - watchOS (`#if os(watchOS)`): removes locally, adds ID to `pendingCompletions`+`pendingCompletionStore`,
    fires `onCompleteReminder(identifier)` (`:235-253`).
  - `completeCurrentReminder()` `:270` operates on `visibleReminders.first`.
- **Undo completion (iOS-only)** — `undoLastCompletion()` `:277`, `#if !os(watchOS)`.
- **Delete** — `deleteReminder(identifier:)` `:262`:
  - watchOS: removes locally, fires `onDeleteReminder(identifier)` (`:300-302`).
  - iOS: `eventStore.remove(commit:true)`, settle, reload (`:304-311`).
  - `deleteCurrentReminder()` `:313`.
- **Add (iOS-only)** — `addReminder(title, notes, dueDate, recurrenceRule)` `:333` (creates via
  `eventStore.makeReminder`, saves, reload; watch returns `false`).
- **Skip** — `skipCurrentReminder()` `:314`, `skipCurrentReminderImmediately()` `:345` (sets skipped-ID
  list; does not mutate the EKReminder).
- **Sort/excluded** — `setSortOption` `:398`, `setExcludedListTitles` `:444`, `refreshExcludedListTitles` `:460`.
- **Not present:** no operation edits an existing reminder's due date, recurrence, or splits a reminder
  into parts. Searches for `dueDateComponents =`/`recurrenceRule =`/snooze/postpone confirm zero production
  mutation sites in `SingleThread/` and `SingleThreadWatch/` (only fixtures/tests/InMemoryEventStore/parser).
  The **only edit surface** is the "View in Reminders" deep link into Apple's Reminders app.

iOS call sites:
- Forwarding layer `ContentViewModel.swift`: `completeCurrentReminder` (:117), `skipCurrentReminder` (:123),
  `deleteCurrentReminder` (:127), `undoLastCompletion` (:133), `handleSortOption→setSortOption` (:101),
  reload/setExcludedListTitles (:139-147).
- Add flow: `DictationViewModel.swift:71` `store.addReminder(...)`.
- Hook wiring `AppViewModel.swift`: receive `onCompleteReminderReceived`→`completeReminder` (:44-47),
  `onDeleteReminderReceived`→`deleteReminder` (:49-52); send `onCompleteReminder`→`requestCompleteReminder`
  (:61), `onDeleteReminder`→`requestDeleteReminder` (:63-66).
- UI: Undo button overlay (:172-183, `#if !os(watchOS)` branch), per-row swipe/context Complete/Skip/Delete
  (:417-442), macOS action bar Complete(:295-306)/Skip(:309-320)/Delete(:323-332), iOS bottom-bar
  `actionCluster` Complete/mic/Skip (:480-493, gated `store.showsActionButtons` :629-634).

watchOS call sites:
- `WatchReminderView.swift`: actionButtons Complete (:106-112)→`viewModel.completeCurrentReminder()`,
  Skip (:118-122)→`store.skipCurrentReminder()`; Delete via tap→confirmationDialog→"Delete"
  (`role:.destructive`, :214-219)→`store.deleteCurrentReminder()`.
- `WatchReminderViewModel.swift:65` completeCurrentReminder (glow/ghost-card transition).
- `WatchAppViewModel.swift`: send `onCompleteReminder`→`requestCompleteReminder` (:175),
  `onDeleteReminder`→`requestDeleteReminder` (:176); receive sort/pref/skip/excluded hooks (:179+).

**Delete flows surfaced**: iOS long-press row→context menu→red Delete→`deleteCurrentReminder()`→
`eventStore.remove`+reload. macOS bar Delete. Phone delete relayed to watch via `onDeleteReminder`→
`requestDeleteReminder` (inert on iOS per comment `AppViewModel.swift:63`). WatchOS tap card→confirmation
dialog→Delete→local remove + `onDeleteReminder`→WatchConnectivity→iPhone `deleteReminder` removes from EventKit.

---

## Q5: Ordering, cycling, time windows

### Findings
- **"Current" reminder = `visibleReminders.first`** — there is no cursor/index. `visibleReminders`
  (`ReminderStore.swift:129-133`) = `reminders` `.filter(!skippedIDs.contains(id))`
  `.filter(!excludedListTitles.contains(title))` `.sorted(ReminderSort.areInIncreasingOrder(..., using: sortOption))`.
  `.first` read (not stored) at every mutation: complete (:226-227), delete (:280), skip (:316,347),
  render (`ContentView.swift:397`).
- **`ReminderDateFilter` is applied at fetch time inside `reload()`, not in `visibleReminders`.**
  `visibleReminders` never references the date filter. `reload()` (`:357-408`): if `showsUndatedReminders`,
  startDate/endDate = nil; else `startDate = ReminderDateFilter.overdueCutoff()`,
  `endDate = ReminderDateFilter.endOfToday()`; `predicateForIncompleteReminders(withDueDateStarting:, ending:, calendars:nil)`;
  if `showsUndatedReminders`, post-filters `isInCurrentWindow` (`:362-377`).
- Window math `ReminderDateFilter.swift`: `endOfToday` (`:28`) = `startOfDay`+1day−1s (23:59:59);
  `overdueCutoff` (`:41`) = 30 days back by default; `isInCurrentWindow` (`:54-60`) =
  `overdueCutoff <= date <= endOfToday`, and `true` for undated (nil). So incomplete AND inside
  `[overdueCutoff, endOfToday]` (default `showsUndatedReminders=false`) → `reminders` → `visibleReminders`.
- **Sorting** `ReminderSort.swift:9-33`: `.priority` = priority rank→due date→title
  (rank `ReminderPriority.rank`, `ReminderSkip.swift:82-90`); `.dueDate` = date→title;
  `.title` = case-insensitive title→date. `sortOption` default `.priority` (`ReminderStore.swift:70`);
  `setSortOption` fires `onSortOptionChanged`+`onRemindersChanged` (`:332-337`).
- **No explicit cycle counter** — "current" advances because mutations remove `.first` from the visible
  pool. Skip adds `.first`'s id to `skippedIDs` (drops out); Complete marks `isCompleted` (excluded by
  incomplete predicate + `applyingPendingCompletionFilter` `:527-531` refetches).
- **All-done + refresh** (`allSkipped` `:138-139`):
  - All-done pull-to-refresh → `ContentView.swift:358-371` renders `allDoneStateCopy`
    ("All Done" / "Pull to refresh to see all your reminders again.", `ContentViewModel.swift:77-85`),
    `.refreshable { viewModel.reload(clearSkipped: true) }` (:369-370) → `reconcileSkipState(clearSkipped:true)`
    → `clearSkippedState()` → skip set stays **empty** while `reload` refetches → skipped reminders
    reappear.
  - Ordinary refresh on populated list (`ContentView.swift:454-455` `.refreshable { viewModel.reload() }`)
    and empty-source branch (`:382-383`) re-resolve the skip set against freshly fetched in-window ids
    (non-clear path `reconcileSkipState`, `:557-562`): valid skips kept, stale (completed/deleted-while-skipped)
    pruned + re-persisted, skipped reminders remain hidden.
  - watch: both refresh paths pass `clearSkipped: viewModel.store.allSkipped` (`WatchReminderView.swift:189,209`)
    → `WatchReminderViewModel.refresh(clearSkipped:)` (`:135-149`) → `store.reload(clearSkipped:)`.
  - widget: no user-facing clear path.

---

## Q6: Cross-device sync

### Findings
- **All WatchConnectivity centralized in `SkippedReminderSyncService.swift`** (only `#if os(iOS) || os(watchOS)`,
  `:4`). No other production file calls `WCSession` APIs.
- **Test seam**: `SkipSyncSession` protocol (`:8-16`: `activate()`, `updateApplicationContext(_:) throws`,
  `sendMessage(_:replyHandler:errorHandler:)`); `WCSession` conformance (`:17`); `activate()` (`:156`)
  assigns `wcSession.delegate = self`.
- **Push = one latest-wins snapshot.** `pushAll()` (`:167-202`) builds a single combined context
  (`updateApplicationContext`). Always-present keys: `skippedReminderIdentifiers` `[String]`,
  `excludedListTitles` `[String]`, `showUndatedReminders` Bool, `sortOption` String, `completionCount` Int;
  flag-gated (`sends*`): `showDate`/`showRecurrence`/`showAlarms`/`showList`/`showCompletionGlow`/`isEntitled`
  (phone-only, `sendsEntitled: true`). Design doc `:20-22`: "`updateApplicationContext` for skip sync —
  latest-wins, auto-delivers on (re)connect — and `sendMessage` for interactive completion requests."
- **Payload key contract**: private `PayloadKey` enum (`:268-283`) — `"skippedReminderIdentifiers"` +
  12 other keys, shared sender/receiver "so the two sides of the wire protocol cannot drift."
- **Fire-and-forget messages**: `requestCompleteReminder` (`:210`, key `"completeReminderIdentifier"`),
  `requestDeleteReminder` (`:220`, `"deleteReminderIdentifier"`) — watch→phone relay of actions, not skip state.
- **Receive**: `session(didReceiveApplicationContext:)` (`:232-235`) → `apply(context:)` (`:308`).
  Latest-wins explicit (`:309-316`): "received values are authoritative. Replacing (rather than unioning)
  local values makes a 'clear' update (`[]`) propagate." Skip: `skipStore.save(receivedIDs)` **then**
  `onSkippedIdentifiersReceived` (`:317-323`). Absent keys are no-ops (empty payload no-op).
- **Hooks**:
  - `ReminderStore.onSkipSetChanged` (`:78`) — "passes the full skip ID array." Fired from `applySkipSet`
    (`:500`) and `clearSkippedState` (`:485`).
  - iPhone wiring: `AppViewModel.swift:58` `onSkipSetChanged = { _ in service.pushAll() }`, inside
    `if WCSession.isSupported(), !usesInMemoryStore` (`:29`).
  - Watch wiring: `WatchAppViewModel.swift:194` `store.onSkipSetChanged = { _ in service.pushAll() }`.
  - Remote receive hook `onSkippedIdentifiersReceived` (`SkippedReminderSyncService.swift:143`):
    watch wires `WatchAppViewModel.swift:174-178` → `Task { await store?.reload() }` (re-reads persisted
    store, prunes). iPhone does **not** wire it (only complete/delete/excluded receive hooks
    `AppViewModel.swift:45,49,53`) — phone's in-memory `skippedIDs` converges on next `reload()`.
- **Watch `.standard` fallback**: watch has no App Group entitlement; `WatchAppViewModel.swift:158-165`
  explicitly passes `defaults: .standard` into the service's stores.
- **Widget sync is App Group–only**: widget's `ReminderStore.reload()` reads skip list at timeline build
  (`NextThingWidget.swift:60-81`); `SkipReminderIntent` writes via `skipCurrentReminderImmediately()`
  (`ReminderIntents.swift:49`) — no WCSession wiring, so a widget skip is **not** pushed live to the watch.
- **Flow**: phone skip → `applySkipSet` → save App Group + `onSkipSetChanged` → `pushAll()` →
  `updateApplicationContext` → watch `didReceiveApplicationContext` → `apply` → `skipStore.save` →
  `onSkippedIdentifiersReceived` → `store.reload()` → `reconcileSkipState` prune. Reverse = same path,
  phone as receiver.
- **Tests**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift` (`FakeSession: SkipSyncSession`
  `:12-34`): push tests `:55-109`, receive skip tests `:162-243`, relays `:281-331`, other keys `:332-566`.
  `EntitlementSyncTests.swift` (entitled/completion-count, `:23-108`). Watch-native
  `SingleThreadWatchTests/WatchSyncPipelineTests.swift` (`WatchFakeSession` `:8-29`): omits phone-only keys
  (`:33-58,305-327`), receive-every-key (`:65-151`), relaunch-keep (`:153-173`).
- **Residual risks**: no real-WCSession end-to-end test (all inject fakes); phone receive of watch pushes is
  store-only (in-memory convergans on next reload); widget skips don't reach watch live.

---

## Q7: Testing infrastructure

### Findings
Unit tests (Swift Testing, `SingleThreadTests/`):
- **Core seams** compiled into test targets: `InMemoryEventStore` (`InMemoryEventStore.swift:13`),
  single `ReminderStore` init with `settle:` seam defaulting to 200 ms real sleep (`ReminderStore.swift:31-33,455`);
  pure `ReminderSkipLogic`/`SkippedReminderStore` (`ReminderSkip.swift:5-24,121-137`).
- **Deterministic settle**: inject no-op settle — `ReminderStoreTests.swift:12`, `ReminderStoreGateTests.swift:8`.
- **Deterministic rendezvous on hooks**: `withCheckedContinuation` resumed from `onSkipSetChanged`/`onRemindersChanged`
  (two-fire) — `ReminderStoreTests.swift:60-75`.
- **Skip logic** `ReminderSkipTests.swift:12-96` (parameterized `@Test(arguments:)`); gating
  `ReminderStoreGateTests.swift` (`canMutate` via `.seededCounter` writes 100, `:137`; skip gating `:79-124`);
  `EventKitStoringTests.swift` `FakeEventStore` (`:8-135`), `deleteReminderWhileSkippedPrunesSkipIDOnReload` (`:276`),
  `testStore` helper (`:495`).
- **Sync unit tests**: `SkippedReminderSyncServiceTests.swift`, `EntitlementSyncTests.swift` (see Q6).
- **Companion stores**: `PendingCompletionStoreTests.swift`, `PendingCompletionLogicTests.swift`,
  `CompletionCounterStoreTests.swift`, `ExcludedListStoreTests.swift`, `UndoStoreTests.swift` — isolation by UUID key.
- **App Group**: `AppGroupTests.swift` (`:9-19`); skip logic `ReminderSkipTests.swift`.

Deterministic iOS UI flows:
- **Seed schema** (`UITestingSeed.swift:31`, documented at top): `reminders [{title, notes, priority}]`,
  `calendars`, `excludedLists`, `completionCount` (default 0, unclamped), `isEntitled` (default false),
  `hasHidden`, `entitlementUnresolved`. `fromLaunchArguments` (`:44`), `materialize` (`:131`).
- **Launch entry**: `SingleThreadUITestCase.swift:19` `launchApp(arguments:)`; `:37` `launchSeeded(_ json:extra:)`.

Accessibility audit:
- iOS main: `SingleThreadUITests.swift:54-65` `testAccessibilityAudit`, `["--ui-testing","--reset-swipe-preference"]`;
  CI audits `[.sufficientElementDescription,.trait]`, local adds `[.dynamicType,.hitRegion]`. `ActionButtonsUITests.swift:63-67`.
- watch: `SingleThreadWatchUITests.swift:39` `performAccessibilityAudit(for:[.dynamicType,.hitRegion,.sufficientElementDescription,.trait])`.
- Identifiers defined in app views (`accessibilityIdentifier`): `settingsButton`/`settings*Row`,
  `completeButton`/`skipButton`/`deleteButton`/`undoButton` (`ContentView.swift:190,307,320,332,473,486`),
  `emptyStateTitle` (`EmptyStateCard.swift:26`), `priorityMarker`/`dueDateText`/`notesText`
  (`ReminderCardView.swift:71-114`), `completionGlowOverlay` (`ContentView.swift:539`), etc.

Skip-flow tests:
- iOS `SingleThreadUITestsFlows.swift`: `testSkipAdvancesToNextReminder` (:72), `testSkipAllShowsAllDoneState` (:108),
  `testSkipWithCrossDeviceCompletionShowsOnlyRemainingReminder` (:130, cross-device comment :125),
  `testPriorityMarkerRendersForMidRangeValue` (:96). `ActionButtonsUITests.swift:27` taps `skipButton` → All Done.
- watch `SingleThreadWatchUITestsFlows.swift`: `testSkipShowsAllDoneState` (:76), `launchApp()` helper (:132,
  `["--ui-testing"]`), `--ui-testing-priority` (:31), excluded-list/live-excluded (:47, :61), `--ui-testing-gated` (:113).
- Watch seam `WatchAppViewModel.swift:13-53,94` `uiTestingStore`; `scheduleUITestLiveExcludedDelivery` (`:236-253`)
  delivers real `session(...)` 5 s after launch; asserted `SingleThreadWatchUITestsFlows.swift:55-71`.

Test targets & commands:
- 7 targets (`project.pbxproj:238-406`): `SingleThread`, `SingleThreadTests`, `SingleThreadUITests`,
  `SingleThreadWatch`, `SingleThreadWidget`, `SingleThreadWatchUITests`, `SingleThreadWatchTests`.
- `Makefile`: `test`=`./scripts/test.sh --unit-only` (:60); `ui-test`=`--ui-only` (:63); `watch-ui-test`
  scheme `SingleThreadWatch -only-testing:SingleThreadWatchUITests` (:70); `watch-test`
  `-only-testing:SingleThreadWatchTests` (:78); coverage targets (:34-58).
- `scripts/test.sh`: `--unit-only`/`--ui-only`/`full`; full builds both schemes, unit
  (`-only-testing:SingleThreadTests`, :161), iOS UI (:169), watch UI (:180), watch unit (:188), macOS unit (:194).
  `.github/workflows/ci.yml:16-18` splits iOS UI into 3 disjoint `-only-testing:` groups.

---

## Cross-Cutting Observations
- **One skip mutation point** — `applySkipSet` (`ReminderStore.swift:493-502`) is the sole writer of
  `skippedIDs` + `skipStore` + `onSkipSetChanged`; both sync directions and the widget reuse it, gated by
  `skipGeneration` for race safety.
- **Shallow `[String]` persistence everywhere** — no reminder objects are serialized; only identifier sets
  (skips, excluded), simple scalars (completionCount, sortOption), or prefs (bools). Everything goes through
  `AppGroup.defaults` (shared suite) → `.standard` on watch/unregistered sims.
- **Watch/iPhone intentional asymmetry**: phone wires few receive-hooks (relies on next `reload()` to
  reconcile); watch re-reads + reloads on skip receive. Phone omits phone-only keys from its own pushes on
  the watch side off (flag-gated).
- **Edge-triggered progression**: no cursor; cycling is "remove `.first` from visible pool" emergent from
  sort order. All-done is detected from `allSkipped` and cleared via `reload(clearSkipped:true)`.
- **Launch-arg seam split**: `--seed` = full reset + deterministic multi-reminder (write flows);
  `--ui-testing` = no reset, one `"Buy groceries"` reminder, persistence-across-relaunch tests.
- **Determinism pattern**: inject `settle:` + `InMemoryEventStore` + `SkippedReminderStore` (or isolated
  UUID-keyed `UserDefaults`) to remove 200 ms sleeps and shared App Group state; hooks are awaited via
  `withCheckedContinuation`.
- **Localization**: shared `SharedStrings` enum (Core bundle) vs per-target inline literals; only watch uses
  a native `confirmationDialog`.

## Open Areas
- **No real-WCSession end-to-end transport test** — only injected fake sessions; real paired-device
  delivery/queuing (reconnect re-delivery) is unverified (Q6).
- **iPhone does not wire `onSkippedIdentifiersReceived`**, so a watch-originated skip converges in phone
  memory only on the next `reload()` — timing of that reload is implicit (Q6).
- **Widget skip reach to watch** relies on later App Group reads; no live push (Q6).
- **No UI or unit coverage uses abbreviated window boundaries** beyond the default 30-day overdue / end-of-today;
  `ReminderDateFilter` window is configurable by constructor but fixed at call sites (Q5).
- **Feature branch is empty**: current commit `dda10ec` adds no skip-mechanics code — nothing skip-related
  has been implemented behind this ticket yet.
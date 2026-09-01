# Research Findings

All paths are relative to the repo root. Verified against the working tree at HEAD (`543ca7a`).

## Q1: Fetch/reload path

### Findings
- Single fetch path: `ReminderStore.reload(clearSkipped: Bool = false) async` — `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:320-376`. Guards on `loadsReminders` (`:321`); iOS-only `eventStore.refreshSourcesIfNecessary()` (`:324`); builds a date-window predicate via `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` (`:325-337`) using `ReminderDateFilter.overdueCutoff()`/`endOfToday()` when `showsUndatedReminders` is off, nil/nil when on.
- Low-level bridge: `fetchReminders(matching:)` — `ReminderStore.swift:465-475` — wraps EventKit's completion-handler API in `withCheckedContinuation`, resumes via `resumeOnMainActor(gate)` (`ResumptionGate.swift:44-50`), one-shot gate `tryResume()` (`:31-38`). Doc comments say EventKit delivers off-main (`ReminderStore.swift:462-464`).
- `reload()` result path: assigns `reminders = shown` (`:356`), rebuilds `availableLists` (`:357-362`), then `clearSkipped` → `clearSkippedState()` or `ReminderSkipLogic.resolve(fetched:skipped:)` against `skipStore.load()` with re-save (`:363-374`); ends with `onRemindersChanged?()` (`:375`) → iOS widget timeline reload.

### Timing guarantees
- `eventKitSettleDelay: UInt64 = 200_000_000` (200 ms) — `ReminderStore.swift:419` (doc `:416-418`: "EventKit may not reflect an in-flight save immediately; settle briefly before re-fetching").
- Every EventKit-write mutation sleeps 200 ms **before** `await reload()`: complete `:189-190` (sleep `:189`, reload `:190`), undo `:218-219`, delete `:243-244`, add `:276-277`. Sleep is `try? await` (`:189`, `:218`, `:243`, `:276`) — cancellation tolerated; reload is skipped only on EventKit-write failure.
- Skip uses the same 200 ms as a *deferred write* — not a pre-reload settle (`:292-294`, see Q3).

### EventKit change notifications
- **None.** Grep across `SingleThreadCore/` and `SingleThread/` for `EKEventStoreChanged`, `addObserver`, `NotificationCenter` finds only `AppViewModel.swift:345-347` (`UserDefaults.didChangeNotification` on `AppGroup.defaults` → `handlePreferencesChanged()` → `syncService?.pushAll()`; no reload). Every refetch is an explicit `reload()` call site.

### Every `reload()` call site
Core (`ReminderStore.swift`): `start()` `:152`; `requestAccess()` grant `:406`; complete/undo/delete/add iOS branches `:190`, `:219`, `:244`, `:277`.
iOS app:
- Initial `.task` → `ContentViewModel.task` → `store.start()` — `SingleThread/ContentView.swift:135-140`, `SingleThread/ContentViewModel.swift:77-84` (reload via `start`).
- `.onChange(of: showUndatedReminders)` → `handleShowUndatedReminders` → `Task { await store.reload() }` — `ContentView.swift:142-143`, `ContentViewModel.swift:86-89`.
- `.refreshable` ×3 → `ContentViewModel.reload` → `store.reload` — `ContentView.swift:362-364` (all-skipped, `clearSkipped: true`), `:376-377` (empty), `:446-448` (has-list); forwarder `ContentViewModel.swift:128-129`.
watchOS:
- Initial `.task` → `WatchReminderViewModel.task` → `store.start()` — `SingleThreadWatch/WatchReminderView.swift:57-59`, `WatchReminderViewModel.swift:57-66`.
- Refresh button + confirmation dialog → `viewModel.refresh(clearSkipped: store.allSkipped)` — `WatchReminderView.swift:182-186`, `:203`; `WatchReminderViewModel.refresh` reload at `:90-96` (1 s minimum spinner).
- Sync receive: `onShowUndatedRemindersReceived` → set + `await store?.reload()` — `WatchAppViewModel.swift:165-170`; `onSkippedIdentifiersReceived` → `await store?.reload()` — `WatchAppViewModel.swift:171-175`.
Widget/intents (fresh store per invocation):
- `NextThingProvider.makeEntry()` — `SingleThreadWidget/NextThingWidget.swift:67-96`, reload at `:73`.
- `CompleteReminderIntent.perform()` — `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift:18-25` (reload `:21`); `SkipReminderIntent.perform()` — `ReminderIntents.swift:41-49` (reload `:44`).
Not a direct reload but re-enters the above: phone receive of watch complete/delete → `store.completeReminder/deleteReminder` → iOS-branch reload (`AppViewModel.swift:44-50`).

## Q2: Completion flow across devices

### Findings
- Single entry point `completeReminder(identifier:) async -> Bool` — `ReminderStore.swift:169-195` — `#if os(watchOS)` branch. `canMutate` gate `:170` (`:132-134`: `entitlementStore.isEntitled || completionCounter.count < 100`). `completeCurrentReminder()` forwards `visibleReminders.first` — `:198-201`.

### iOS branch (EventKit save + reload) — `ReminderStore.swift:179-194`
1. `reminder.isCompleted = true` (`:185`) — flag on the in-memory `EKReminder`.
2. `try eventStore.save(reminder, commit: true)` (`:186`) — persists to EventKit.
3. `completionCounter.increment()` (`:187`) — App Group-backed `"completionCount"` key (`CompletionCounterStore.swift:21-35`; suite `AppGroup.defaults`, `AppGroup.swift:5-16`).
4. `undoStore.retain(reminder)` (`:188`) — transient iOS-only undo slot (`UndoStore.swift:24-30`, `lastCompletedReminder`).
5. `try? await Task.sleep(eventKitSettleDelay)` (`:189`) → `await reload()` (`:190`) — completed reminder drops from the re-fetched incomplete list.
- Call sites into the iOS branch: iPhone swipe `ContentView.swift:422`, bottom-bar button `:500`, macOS button `:295` → `ContentViewModel.completeCurrentReminder` (`ContentViewModel.swift:104-111`); widget intent `ReminderIntents.swift:22`; **phone-relayed watch completion** (`AppViewModel.swift:44-46`, below).
- Undo: `undoLastCompletion()` — `ReminderStore.swift:203-227` — flips `isCompleted = false`, saves, `completionCounter.decrement()`, `undoStore.clear()`, sleep + reload (`:213-221`). Undo UI gated on `undoStore.hasUndoableReminder` (`ContentView.swift:165-175`).

### watchOS branch (in-memory removal + relay) — `ReminderStore.swift:171-177`
1. `reminders.removeAll { calendarItemIdentifier == identifier }` (`:173`). **No EventKit write** (watch uses read-only `EKEventStore`; protocol exposes no save/makeReminder, `EventKitStoring.swift:24-33`).
2. `onCompleteReminder?(identifier)` (`:175`) → relay hook.
3. **No** counter increment, **no** undo-store retain (`undoStore` is `#if !os(watchOS)`, `:100-104`).
- Watch UI: `WatchReminderView.swift` Complete button → `WatchReminderViewModel.completeCurrentReminder()` — `SingleThreadWatch/WatchReminderViewModel.swift:65-90` — transition gate `isShowingCompletionTransition`, glow trigger, snapshot held until glow completes.
- Relay: `store.onCompleteReminder` wired in `WatchAppViewModel.swift:197` → `service.requestCompleteReminder(identifier)` — `SkippedReminderSyncService.swift:210-217` — `session.sendMessage(…, replyHandler: nil)` (**fire-and-forget, no ack**).

### Phone receiving a relayed completion
- `SkippedReminderSyncService.didReceiveMessage` — `SkippedReminderSyncService.swift:236-247` — decodes `completeReminderIdentifier` → `onCompleteReminderReceived(identifier)`.
- iPhone wiring — `AppViewModel.swift:44-46`: `Task { await store?.completeReminder(identifier: identifier) }` → **re-enters the iOS branch** (EventKit save + counter increment + undo retain + reload). Deleting mirrors this (`AppViewModel.swift:48-50`).

### Where the same reminder can be completed more than once
- **No completed-identifier dedupe exists anywhere** (grep for completed-ID sets: none). Guards are only `canMutate` (`:170`), the in-memory identifier lookup (`:179-181`), and the watch glow gate (`WatchReminderViewModel.swift:66`).
- **Watch re-appearance window**: watch completion is local-array removal only; the reminder stays incomplete in the shared Reminders DB until the phone's relayed save lands. A watch `reload()` before propagation (pull-refresh `WatchReminderView.swift:182-186`; received-skip reload `WatchAppViewModel.swift:171-175`; relaunch via `start()`) re-fetches the still-incomplete reminder → user can Complete again → second relay → second iOS save + **second `completionCounter.increment()`** + undo-store overwrite.
- **Fire-and-forget relay**: `replyHandler: nil` (`SkippedReminderSyncService.swift:212-215`), no message dedupe — a duplicate/retried message triggers a second independent iOS completion (second increment).
- **iOS settle window**: two `completeReminder` calls for the same id arriving before the 200 ms reload both match `reminders.first` (line `:180`) → both save + both `increment()`.
- Counter is incremented **only** on the iOS branch (`:187`); `pushAll()` is not hooked to completion on the phone (its iOS hooks are skip/exclusions/undated/sort/entitlement/preferences, `AppViewModel.swift:57-74`), so the watch's copy of the count updates only on the next sync push.

## Q3: Skip flow and skip-state persistence

### Findings
- Pure logic: `ReminderSkipLogic.resolve(fetched:skipped:)` — `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift:10-16` — returns `Array(Set(fetched).intersection(skipped))` (prunes stale IDs on every reload). `skipping(_:fetched:skipped:)` — `:19-23` — append-then-resolve for writes.
- `SkippedReminderStore` — `ReminderSkip.swift:119-138` — thin `UserDefaults` wrapper (init `:122-127`, `load()` `:129-131`, `save(_:)` `:133-135`), default suite `AppGroup.defaults`.

### Two skip entry points (both in `ReminderStore.swift`)
- `skipCurrentReminder()` — `:286-296` (deferred): gates `canMutate` `:287`, targets `visibleReminders.first` `:288`, computes list via `updatedSkipSet(afterSkipping:)` `:433-437` → `ReminderSkipLogic.skipping`, captures `skipGeneration` `:291`, then a fire-and-forget `Task` sleeps 200 ms (`:293`) and calls `applySkipSet(updated, generation: capturedGeneration)` (`:294`). **No reload** — the skip is a list-identity filter, never a refetch.
- `skipCurrentReminderImmediately()` — `:313-317` (synchronous): same but no sleep/generation capture; doc (`:307-312`) says it exists for the widget's `SkipReminderIntent` because the widget process may be suspended right after `perform()`.
- `applySkipSet(_:generation:)` — `:452-460` — the single write point: generation gate (`:453-455`), `skippedIDs = Set(updated)` (`:456`), `skipStore.save(updated)` (`:457`), `onSkipSetChanged?(updated)` (`:458`), `onRemindersChanged?()` (`:459`). Persists to the App Group suite `"group.app.alanvardy.SingleThread"` (`AppGroup.swift:7`; falls back to `.standard` where no suite exists, `:13-16`).

### Reload-time pruning — `reload()` body `ReminderStore.swift:363-374`
- With `clearSkipped: false`: `reminders = shown` → `skippedIDs = Set(ReminderSkipLogic.resolve(fetched: shown.map(\.calendarItemIdentifier), skipped: skipStore.load()))` (`:365-367`), `excludedListTitles = Set(excludeStore.load())` (`:368`), then **re-saves the pruned list** (`skipStore.save(resolved)`, `:373`) so on-disk matches memory. `clearSkipped: true` → `clearSkippedState()` (`:442-447`): `skipGeneration &+= 1`, empties set, saves `[]`, fires `onSkipSetChanged?([])`.

### Sync of skipped identifiers
- Send: `pushAll()` — `SkippedReminderSyncService.swift:167-205` — one latest-wins application context including `PayloadKey.skippedReminderIdentifiers: skipStore.load()` (`:170`). Hooks wired: phone `store.onSkipSetChanged = { _ in service.pushAll() }` (`AppViewModel.swift:57`); watch `store.onSkipSetChanged = { _ in service.pushAll() }` (`WatchAppViewModel.swift:194`).
- Receive: `apply(context:)` — `SkippedReminderSyncService.swift:308-344` — skip branch `:314-320`: `skipStore.save(receivedIDs)` **then** snapshots + fires `onSkippedIdentifiersReceived(receivedIDs)`. Comment (`:311-313`): replacing (not unioning) makes a clear (`[]`) propagate; "`ReminderStore.reload()` prunes stale skip IDs on the next fetch."
- **Handlers wired per platform**:
  - iPhone — `AppViewModel.swift:28-77` wires **only** `onCompleteReminderReceived` (`:44-46`), `onDeleteReminderReceived` (`:48-50`), `onExcludedListTitlesReceived` (`:52-54`). **`onSkippedIdentifiersReceived` is NOT wired on the phone.** A watch-pushed skip still persists into the shared App Group suite (`SkippedReminderSyncService.swift:318`), but there is no immediate reload — in-memory `skippedIDs`/`visibleReminders` absorb it at the next explicit `reload()` (pull-refresh, show-undated toggle, any mutation path, relaunch), where `resolve` prunes.
  - Watch — `WatchAppViewModel.swift:148-199` wires `onShowUndatedRemindersReceived` (`:165-170`, set + reload), `onSkippedIdentifiersReceived` (`:171-175`, reload only), `onSortOptionReceived` (`:178-179`), `onCompletionCountReceived` (`:185-189`, writes `AppGroup.defaults`), `onExcludedListTitlesReceived` (`:191-194`), plus show-* state hooks (`:200-224`). **Watch does not wire** `onCompleteReminderReceived`/`onDeleteReminderReceived`.
- End-to-end: phone skip → deferred `applySkipSet` → App Group + `pushAll` → watch `apply` persists → `onSkippedIdentifiersReceived` → reload → `resolve` prunes. Watch skip → same on watch → `pushAll` → phone persists to App Group, nil handler; list reconciles at next phone reload.
- Widget skip: `SkipReminderIntent.perform` — `ReminderIntents.swift:40-50` — fresh store, `reload()` (`:44`), `skipCurrentReminderImmediately()` (`:49`). Comment (`:45-48`): routes through the store so persistence + hooks fire rather than writing UserDefaults directly.

## Q4: State observation and list refresh triggers

### Findings
- `ReminderStore` is `@MainActor @Observable` (`ReminderStore.swift:5-7`); `reminders`/`skippedIDs`/`excludedListTitles` are `public private(set)` (`:41-43`). `visibleReminders` is a **computed path**, not stored state — de-skip → de-exclude → sort, recomputed per access (`ReminderStore.swift:117-122`). `allSkipped` = `!reminders.isEmpty && visibleReminders.isEmpty` (`:124-126`).
- No `@StateObject`/`@ObservedObject`/`EnvironmentObject` anywhere. iOS: `SingleThreadApp` → `AppViewModel` (`SingleThreadApp.swift:31`); `ContentViewModel` is `@MainActor @Observable` (`ContentViewModel.swift:10-11`) holding `let store` (`:30`); `ContentView` holds it as a plain `private let viewModel` (`ContentView.swift:264`). Watch: `WatchAppViewModel` (plain `@MainActor final class`, `WatchAppViewModel.swift:15`) composes `ReminderStore` + `WatchReminderViewModel` (`@MainActor @Observable`, `WatchReminderViewModel.swift:9-10`) held by plain `let` (`WatchReminderView.swift:83`).
- Widget does not observe: builds a fresh store per timeline entry (`NextThingWidget.swift:57-96`).

### Complete trigger inventory (re-fetch or in-memory change)
| Trigger | Re-fetch? | Reference |
|---|---|---|
| iOS `.task` appear → `store.start()` | yes | `ContentView.swift:135-140`; `ReminderStore.swift:152` (or `:406` via `requestAccess`) |
| Watch `.task` appear → `store.start()` | yes | `WatchReminderView.swift:57-59`; `WatchReminderViewModel.swift:64-66` |
| iOS pull-to-refresh (all-done / empty / list) | yes (all-done passes `clearSkipped: true`) | `ContentView.swift:362-364`, `:376-377`, `:446-448` |
| Watch Refresh button / dialog | yes | `WatchReminderView.swift:182-186`, `:203`; `WatchReminderViewModel.swift:89-100` |
| iOS complete / undo / delete / add | yes (save + settle + reload) | `ReminderStore.swift:190, 219, 244, 277` |
| Skip (both platforms) | **no** — in-memory `skippedIDs` filter only | `ReminderStore.swift:286-296, 313-317, 452-460` |
| Phone receives watch complete/delete | yes (re-enters iOS branch) | `AppViewModel.swift:44-50` |
| Phone receives excluded titles | no reload; live re-filter | `AppViewModel.swift:52-54`; `ReminderStore.swift:388-395` |
| Watch receives skip IDs | yes (reload, prunes) | `WatchAppViewModel.swift:171-175` |
| Watch receives show-undated | yes (set + reload) | `WatchAppViewModel.swift:165-170` |
| Watch receives sort | re-sort only | `WatchAppViewModel.swift:178-179` |
| iOS show-undated toggle | yes | `ContentViewModel.swift:86-89` |
| Widget timeline | 15-min `.after` + `reloadAllTimelines` + intent auto-reload | `NextThingWidget.swift:45-47`; `AppViewModel.swift:75-77`; `SettingsViewModel.swift:21-23` |
| Notification schedule/cancel (scene phase, active) | **no** | `ContentView.swift:714-724`; `AppDelegate.swift:42-50, 76-83` |

### Mechanisms that do not exist
- **No scene-phase refetch**: `.onChange(of: scenePhase)` (`ContentView.swift:131-134`) only schedules/cancels the idle notification (`handleScenePhaseChange`, `:714-724`).
- **No on-foreground refetch**: `applicationDidBecomeActive` re-applies appearance only (`AppDelegate.swift:42-50`).
- **No EventKit change observation** (grep verified); **no interval/timer in app or watch** (widget's 15-min policy is the only interval); **no notification-driven refresh** (notification tap can only relaunch the app, re-running `.task`).
- `onRemindersChanged` fires on every `reload()` (`:375`) plus `setSortOption` (`:306`), `setExcludedListTitles` (`:384`), `refreshExcludedListTitles` (`:393`), `applySkipSet` (`:459`), `clearSkippedState` (`:447`) → wired to `WidgetCenter.shared.reloadAllTimelines()` (`AppViewModel.swift:75-77`).

## Q5: Concurrency model

### Findings
- **Language/isolation settings**: Swift 6 everywhere. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the iOS app target (`SingleThread.xcodeproj/project.pbxproj:769, 819`) and the watchOS app target (`:953, 981`) only — grep confirms the setting appears at exactly those four lines. The Core package (`SingleThreadCore/Package.swift:1`, `swift-tools-version: 6.0`, no `defaultIsolation` override), widget target, and all test targets are nonisolated-default. Note: the comment at `ReminderDateFilter.swift:16-17` ("watch/widget targets do not opt in") is stale for the watch app target; AGENTS.md matches the pbxproj (both app targets set it).
- **Actor isolation of the store**: `ReminderStore` is `@MainActor @Observable` (`ReminderStore.swift:5-7`); no `nonisolated` members. Collaborators: `EventKitStoring` protocol `@MainActor` (`EventKitStoring.swift:7`); `InMemoryEventStore` `@MainActor` (`InMemoryEventStore.swift:12`); `EntitlementStore` `@MainActor @Observable` (`EntitlementStore.swift:9-10`); view models `@MainActor` (`AppViewModel.swift:11-13`, `ContentViewModel.swift:10-11`, `WatchAppViewModel.swift:15`, `WatchReminderViewModel.swift:13-15`). The one nonisolated type is `SkippedReminderSyncService` (`SkippedReminderSyncService.swift:47`) — WCSession-delegate-queue driven; its `nonisolated(unsafe)` hooks are written once from the main actor before `activate()` (`:77-154`) and it uses `MainActor.assumeIsolated` for `EntitlementStore` reads (`:59, :193-199`).
- **EventKit bridging**: `fetchReminders` — `ReminderStore.swift:465-475` — `withCheckedContinuation<[EKReminder], Never>` + `ResumptionGate` (`ResumptionGate.swift:19-38`, `@unchecked Sendable`, single-resume invariant documented `:5-17`) + `resumeOnMainActor` (`:44-50`, hops a `Task { @MainActor in }`). The continuation payload requires `EKReminder: @retroactive @unchecked Sendable` (`ReminderDateFilter.swift:23`) with the invariant that `EKReminder` is created/mutated/read only on the main actor (`:9-18`). `requestAccess()` uses the protocol's native async `requestFullAccessToReminders()` (`ReminderStore.swift:397-411`), no continuation.
- **Race guards**:
  - `canMutate` gate (`:132-134`) re-checked at every mutation entry (`:170, :210, :235, :287, :314`).
  - Settle-then-reload write pattern (`:189-190, :218-219, :243-244, :276-277`): all on the main actor; `await reload()` suspends but store writes remain serialized by the actor.
  - `skipGeneration` (`:429`): captured in the deferred skip task (`:291`), bumped `&+= 1` on clear (`:444`), checked in `applySkipSet` (`:453-455` — discard when stale). Regression test: `skipCurrentReminderDiscardedAfterClearSkipped` (`SingleThreadTests/ReminderStoreTests.swift:322-337`: skip, `reload(clearSkipped: true)`, 400 ms, assert empty). The tests sleep 400 ms to beat the 200 ms deferral (`ReminderStoreGateTests.swift:113-116`).
  - Reload re-derives `skippedIDs` from the persisted store (`:365-373`) so a deferred-but-not-yet-applied skip and a raced reload converge.
  - Watch refresh re-entrancy: `isRefreshing` guard in `WatchReminderViewModel.refresh` (`WatchReminderViewModel.swift:89-100`).
  - Off-main delivery reproduced in tests via `InMemoryEventStore.deliverCompletionOffMain` (`InMemoryEventStore.swift:26, :59-77`).

## Q6: Test infrastructure for store mutations

### Findings
- **`InMemoryEventStore`** (`SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift`, `@MainActor`): `fetchReminders` returns `allReminders.filter { !$0.isCompleted }` (`:60`) — mirrors `predicateForIncompleteReminders` (the predicate itself is inert `NSPredicate(value: true)`, `:52`). `save` appends (`:88`), `remove` filters by id (`:92`) — both reflected on the next fetch. Completed reminders stay in `allReminders` for observation (`:33-35`). Always `.fullAccess` (`:38`); `requestFullAccessToReminders` returns `true` (`:44-46`); `makeReminder` is backed by a retained `EKEventStore` (`:96-108`); `deliverCompletionOffMain` (`:26, :59-77`) simulates EventKit's off-main callback.
- **`--seed '<json>'`** (iOS UI tests; write-path seam, `loadsReminders: true`): parsed by `UITestingSeed.fromLaunchArguments` (`SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift:31-40`); `resetPersistedState()` (`:45-52`) clears the 25 `persistedKeys` (`:56-78`). Store built in `AppViewModel.seededStore` (`SingleThread/AppViewModel.swift:272-303`): `InMemoryEventStore(reminders:calendars:defaultCalendar:)` (`:274-276`), seeded `completionCount` written into `AppGroup.defaults` (`:283`), entitlement seeded (`:285-287`), `loadsReminders: true` (`:292`), exclusions applied (`:298-300`). Because `loadsReminders: true`, mutations run the real save → 200 ms settle → `reload()` round-trip against the in-memory store.
- **`--ui-testing`** (display seam; both platforms, `loadsReminders: false`): iOS branch of `makeStore` (`AppViewModel.swift:234-261`) — single "Buy groceries" reminder made via `InMemoryEventStore.makeReminder` (`:246-253`), `loadsReminders: false` (`:254-259`); default path falls back to a real `EKEventStore` with `loads = !("--ui-testing" || "--no-reminders")` (`:263-265`). Watch: `WatchAppViewModel.uiTestingStore` (`SingleThreadWatch/WatchAppViewModel.swift:96-142`), `loadsReminders: false` (`:136-141`), with `--ui-testing-priority`/`--ui-testing-excluded-list`/`--ui-testing-live-excluded`/`--ui-testing-gated` (counter=100, `:26-29`)/`--ui-testing-glow` variants. Under `loadsReminders: false`, `start()`/`reload()` are no-ops (`ReminderStore.swift:149-153`, `:321`), so the list is the pre-seeded array filtered through `visibleReminders` only.
- **Unit tests** (`SingleThreadTests/`, all stores use `InMemoryEventStore()` unless noted):
  - `ReminderStoreTests.swift`: skip — `skipCurrentReminderDoesNothingWhenNoVisibleReminders` `:278`, `skipCurrentReminderUpdatesSkippedIDs` `:290` (asserts `skippedIDs.contains(id)` only; list untouched), `skipCurrentReminderFiresRemindersChangedHook` `:306`, `skipCurrentReminderDiscardedAfterClearSkipped` `:322` (the **only** skip test with `loadsReminders: true`, `:326`). Complete — `completeCurrentReminderDoesNothingWhenNoReminders` `:342`, `...WhenAllSkipped` `:354`, `completeCurrentReminderWithVisibleReminderReturnsTrue` `:368` (asserts return + `rem.isCompleted`; with `loadsReminders: false` the completed reminder **stays** in `store.reminders`), `...IdentifierNotFound` `:384`. Undo suite `:529-632` (`completeRetainsInUndoStore` `:529`, `undoLastCompletionRevertsReminder` `:543`, `secondCompleteOverwritesUndoStore` `:577` — asserts `remA.isCompleted` stays true `:589`). Off-main reload `reloadResumesOnMainActorWhenFetchCompletesOffMain` `:397-404` (`loadsReminders: true` + `deliverCompletionOffMain`; asserts `store.reminders == ["A"]`). `loadsReminders: false` no-op guards `:413, :420, :427`.
  - `ReminderSkipTests.swift:13-58`: pure `resolve`/`skipping` logic only, no store.
  - `SkippedReminderSyncServiceTests.swift`: `receiveContextFiresSkippedIdentifiersHandlerAfterPersisting` `:161`, `receiveContextReplacesLocalIDs` `:193`, `receiveContextClearPropagates` `:209`, `requestCompleteReminderSendsMessage` `:282`, `receiveMessageTriggersCompletionHook` `:293`, `receivedExclusionRefreshFiltersVisibleReminders` `:398` (`loadsReminders: false` in-memory store). `ReminderStoreGateTests.swift`: `completeReminderIncrementsCounterOnSuccess` `:53` (asserts counter == 51), `skipCurrentReminderNoOpsWhenGated` `:75`, `deleteReminderNoOpsWhenGated` `:117`.
  - Note: the `InMemoryEventStore` completed-filter (`:60`) has **no dedicated unit test** — it is exercised end-to-end only by `--seed` UI tests (see below). `EventKitStoringTests` uses a recording `FakeEventStore` for write-path behavior (`completeReminderMarksSavedAndReloads` `:150`: `fake.saved.count == 1`, `fetchCallCount == before + 2`).
- **UI tests**:
  - iOS (`SingleThreadUITestsFlows.swift`, launched with `--seed`): `testSkipAdvancesToNextReminder` `:56` (asserts "Second" visible after skipping "First"), `testSkipAllShowsAllDoneState` `:89` (asserts "All Done"), `testCompleteViaSwipeRemovesReminder` `:106` (asserts **"No Reminders"** — the completed-filter + reload round-trip), `testDeleteViaContextMenuRemovesReminder` `:124` ("No Reminders"), `testUndo...` suite `:595-656`, glow tests `:448, :475`. `ActionButtonsUITests.swift` (`--ui-testing`, `loadsReminders: false`): `testActionButtonsRenderAndSkipAdvancesCard` `:20` (skip empties via `skippedIDs` only; seam comment `:24-26`).
  - Watch (`SingleThreadWatchUITestsFlows.swift`, `--ui-testing`, `loadsReminders: false`): `testCompleteRemovesReminder` `:76` ("No Reminders" via local removal + relay), `testSkipShowsAllDoneState` `:92`, `testDeleteViaConfirmationDialogRemovesReminder` `:108`, `testRefreshPresentOnNoRemindersState` `:126`, `testCompleteHoldsCardDuringGlow` `:202`. Glow unit-twin: `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift`.

## Cross-Cutting Observations
- **Refetch is push-only and explicit**: no EventKit change notifications, no scene-phase/foreground/timer refresh — the list changes only at explicit `reload()` call sites and in-memory mutations. iOS completion/undo/delete/add end in a reload; **skip never does** (it is purely the `skippedIDs` filter over the last-fetched array), and the watch reconciles remote skip pushes by reloading through `ReminderSkipLogic.resolve`.
- **Phone is the single writer to EventKit**: the watch is read-only-EventKit; watch-originated complete/delete are relayed (`sendMessage`) and executed by the phone's iOS branch — which is why the completion counter and undo store are iOS-only side effects that also run for watch-initiated actions.
- **App Group `UserDefaults` is the cross-process source of truth**: skip list (`"skippedReminderIdentifiers"`), completion count, show-*/preferences all round-trip phone↔watch↔widget through `AppGroup.defaults`; sync replaces (never unions), and `reload()` re-prunes/re-persists.
- **Latest-wins context, fire-and-forget messages**: skip state travels in combined application contexts (`pushAll`, no ack); complete/delete travel as unacked interactive messages with no dedupe.
- **200 ms settle is load-bearing**: every EventKit write sleeps before refetch (production) and every deferral-based test sleeps 400 ms to out-wait it.
- **Current tree state**: the branch's VAR-750 commit `0318965` ("Do a refetch for reminders after skip and completion") added only a `DELETEME` placeholder (since removed by `543ca7a`); at HEAD the skip path still does **not** refetch after a skip on either platform, and the watch still removes completed reminders locally without any post-relay refetch.

## Open Areas
- **Real-EventKit write semantics**: whether `EKEventStore.save(isCompleted = true)` synchronously removes the reminder from subsequent `predicateForIncompleteReminders` fetches is only proxied by `InMemoryEventStore`'s filter — not directly observable from the code.
- **WCSession duplicate delivery**: whether the OS can re-deliver `sendMessage` payloads in practice is untestable here; no dedupe exists either way.
- **Watch-side post-completion state**: exactly when the watch's list converges after a relayed completion (it relies on the next reload) is a behavioral gap the current tests do not pin (`loadsReminders: false` tests never re-fetch).
- Some test line numbers (`SkippedReminderSyncServiceTests`, watch UI tests) are cited from agent reports and spot-checked rather than fully re-verified.
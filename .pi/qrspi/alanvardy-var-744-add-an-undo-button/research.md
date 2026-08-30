# Research Findings

Source repo: SingleThread (iOS + watchOS + widget). Paths below are relative to the repo root.

## Q1: Completion flow

### Entry points (all funnel to one Core method)
- iOS leading swipe action: `.swipeActions(edge: .leading)` → `Task { await viewModel.completeCurrentReminder() }` — `SingleThread/ContentView.swift:372-378` (row also has trailing Skip swipe :380-385 and Delete context menu :353-370).
- iOS bottom **action cluster**: bottom-bar decision chain `if !viewModel.store.canMutate { upgradePrompt } else if viewModel.showsActionButtons { actionCluster } else { micButton }` — `ContentView.swift:430-441`; cluster = `HStack { completeButton; micButton; skipButton }` — `ContentView.swift:475-482`; `completeButton` at :450-458.
- macOS action buttons with keyboard shortcut "c" — `ContentView.swift:244-255`.
- Watch `Complete` button → `WatchReminderViewModel.completeCurrentReminder()` — `SingleThreadWatch/WatchReminderView.swift:103-125`, `WatchReminderViewModel.swift:51-55`.
- Watch→phone relay: watch `completeReminder` watchOS branch fires `onCompleteReminder` (`ReminderStore.swift:165-171`) → `service.requestCompleteReminder` (`WatchAppViewModel.swift:187`) → `session.sendMessage([completeReminderIdentifier: id], replyHandler: nil)` (`SkippedReminderSyncService.swift:210-217`) → phone `session(_:didReceiveMessage:)` (:237-245) → `onCompleteReminderReceived` (`AppViewModel.swift:43-45`) → phone `store.completeReminder(identifier:)` executes the real EventKit save.
- Widget: `CompleteReminderIntent.perform()` builds a fresh `ReminderStore(loadsReminders: true)`, reloads, then `completeCurrentReminder()` — `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift:13-26`.

### `ReminderStore.completeReminder(identifier:)` — the single mutation point (ReminderStore.swift:163-187)
1. `guard canMutate else { return false }` (:164).
2. `#if os(watchOS)` branch (:166-170): removes from in-memory `reminders` by `calendarItemIdentifier`, fires `onCompleteReminder?(identifier)` if removed. No reload, no counter increment, no settle delay.
3. iOS branch (:171-185): find reminder in `reminders` → `reminder.isCompleted = true` → `try eventStore.save(reminder, commit: true)` → `completionCounter.increment()` (:179) → `try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)` (:180) → `await reload()` (:181). Throw → `.error` log, return `false`.
4. `completeCurrentReminder()` (:191-194) = `visibleReminders.first` then delegate; all five surfaces funnel through it.

### State changes
- **List contents**: unchanged during the 200 ms settle; only `reload()` drops the completed reminder because the fetch uses `predicateForIncompleteReminders` (`ReminderStore.swift:301`, `InMemoryEventStore.swift:57-61` mirrors this with an `isCompleted` filter).
- **Counters**: `completionCounter.increment()` → App Group `"completionCount"` +1 (`ReminderStore.swift:179`, `CompletionCounterStore.swift:26-30`). `canMutate` = `entitlementStore.isEntitled || completionCounter.count < 100` (`ReminderStore.swift:126-128`) — a 100th completion flips the gate off for non-entitled users.
- **Persisted IDs**: `reload()` prunes `skippedIDs` against the fresh fetch via `ReminderSkipLogic.resolve` (intersection) and writes the pruned list back — `ReminderStore.swift:325-341`, `ReminderSkip.swift:12-24`. Completing never touches `skippedIDs` (the reminder wasn't skipped); a stale skip ID for a completed-while-skipped reminder would be silently pruned.
- **`hasHidden`**: recomputed in reload (:307-322) via `hasHiddenFor` (:131-137); affects empty-state copy.
- **`visibleReminders`** (`ReminderStore.swift:111-118`): filters only `skippedIDs` + `excludedListTitles`, sorts via `ReminderSort` — it does **not** filter `isCompleted`. Removal is indirect (post-reload refetch); during the 200 ms settle the completed reminder is still present in the array.

### Hooks
- watchOS branch fires `onCompleteReminder` (only there — `ReminderStore.swift:169`).
- iOS fires `onRemindersChanged` at end of reload (:343) → `WidgetCenter.shared.reloadAllTimelines()` (`AppViewModel.swift:74-76`). Not wired on watch.
- iOS wires `store.onCompleteReminder` → `requestCompleteReminder` (`AppViewModel.swift:59`) but it is **inert on iOS**: only the watchOS branch of `completeReminder` fires it. Same pattern for delete (:64).

### Settle-delay / reload
- `private static let eventKitSettleDelay: UInt64 = 200_000_000` — `ReminderStore.swift:387`; used by complete (:180), delete (:210), add (:243), skip (:258).
- Skip additionally wraps its apply in `Task { sleep 200ms; applySkipSet }` (:256-259); widget uses `skipCurrentReminderImmediately()` without sleep (:270-284).
- Watch spinner enforces a ≥ 1 s minimum display via `MinimumDisplayDuration.remainingSleep` — `WatchReminderViewModel.swift:57-78`, `MinimumDisplayDuration.swift:16-19`.
- `fetchReminders` bridges EventKit's callback API with a `ResumptionGate` that resumes exactly once on the main actor — `ReminderStore.swift:415-427`, `ResumptionGate.swift`.

### Gate UI asymmetry
- Bottom cluster swaps to `UpgradePromptButton` (full-width capsule) when `!canMutate` — `ContentView.swift:430-441`, pill defined in `PurchaseSettingsView.swift:173-194`. But swipe Complete/Skip are **not** gated visually — a gated swipe silently no-ops.
- Watch gates its buttons on the **synced** `entitlementState` + `store.canMutate` — `WatchReminderView.swift:208-211` (watch has no StoreKit surface; `EntitlementState.swift:3-21`).

## Q2: Settings toggle plumbing

### Where toggles actually live (question premise correction)
- "Show action buttons" (`enableActionButtons`) renders in `InterfaceSettingsView.swift:54-63`; `.standard`-backed; **not** watch-synced.
- "Show completion glow" (`showCompletionGlow`) renders in `ReminderSettingsView.swift:53-56`, not InterfaceSettingsView; App-Group-backed and synced phone→watch.

### `@AppStorage` declarations (ContentView.swift:151-199)
- App-Group-backed (`store: AppGroup.defaults`): `showUndatedReminders = false` (:181-182), `sortOption = SortOption.priority` (:184-185), `showDate = true` (:187-188), `showList = false` (:190-191), `showRecurrence = true` (:193-194), `showAlarms = true` (:195-196), `showCompletionGlow = true` (:198-199).
- `.standard`-backed: `appearanceMode = .system` (:151-152), `textSize = .system` (:154-155), `allowsLandscape = true` iOS-only (:158-159), `showMicrophoneButton = true` (:162-163), `backgroundEnabled = true` (:165-166), `backgroundFadePercent` (:168-169), `enableActionButtons = false` iOS-only (:172-173), `showSwipePrompt = true` iOS-only (:177-178).

### SettingsBindings bag — the setter side
- `SettingsBindings.swift:14-77`: `@MainActor @Observable final class`, one bag of all 15 values; init defaults mirror the `@AppStorage` defaults exactly (documented :7-9). `excludedLists` deliberately NOT here (store-backed, passed as `Binding<Set<String>>`).
- Gear button builds the bag fresh: `settingsBag = makeSettingsBag()` (`ContentView.swift:65-69`); `@State settingsBag` (:211); bag niled on sheet dismiss (:106-109).
- `.onChange(of: bag.X)` on the sheet writes each changed value back to `@AppStorage` (`ContentView.swift:121-137`), e.g. `bag.enableActionButtons → enableActionButtons` (:125), `bag.showCompletionGlow → showCompletionGlow` (:137).

### SettingsViewModel side effects
- `SettingsViewModel.swift:12-32`: stateless; only `allowsLandscapeChanged → AppDelegate.applyLock` (:17-19) and `showPreferenceChanged → WidgetCenter.reloadAllTimelines()` (:22-26). Glow/action-buttons toggles trigger **no** SettingsViewModel method; persistence is solely the bag→@AppStorage write-back.

### Core preference stores — two API conventions
- Newer toggles use `isEnabled` (computed) + `set(_:)`, NOT load/save: `ShowCompletionGlowPreference.swift:8-27` (`init(defaults: UserDefaults = AppGroup.defaults, key: String = "showCompletionGlow")`, `isEnabled = defaults.object(forKey: key) as? Bool ?? true`, `set(_:)` writes). Same shape: `ShowAlarmsPreference`, `ShowDatePreference`, `ShowRecurrencePreference` (missing → true), `ShowListPreference` (missing → `false`).
- Older stores use `load()`/`save(_:)`: `ShowUndatedRemindersPreference.swift:7-24`, `SortOptionStore` (`SortOption.swift:24-45`), `SkippedReminderStore`, `ExcludedListStore`.

### Conventions for a new toggle
- Key naming: camelCase literal identical to the property name, duplicated in up to four places — `@AppStorage`, Core store default key, `SkippedReminderSyncService.PayloadKey` (enum values at `SkippedReminderSyncService.swift:268-282`), and `UITestingSeed.persistedKeys` (`UITestingSeed.swift:56-75`). `SortOption.defaultsKey` is the only shared constant (`SortOption.swift:17-19`). Sync of literals is by convention only.
- Default values mirrored in three places per key: `@AppStorage` init, `SettingsBindings` init default, Core store `?? true/false` fallback.
- Watch sync: pushed via `AppViewModel.setupSyncObservation()` (`AppViewModel.swift:262-270`) observing `UserDefaults.didChangeNotification` on `AppGroup.defaults`; `handlePreferencesChanged()` (:242-259) diffs `lastShow*` ivars and calls `pushAll()`. Receive side persists via `showXStore.set(...)` before firing `onXReceived` (`SkippedReminderSyncService.swift:338-361`) → `ShowXState.apply(value)` (`WatchAppViewModel.swift:196-221`).
- `UITestingSeed.resetPersistedState()` wipes 19 keys from both suites (`UITestingSeed.swift:45-75`); new persisted keys must be added to `persistedKeys`.

## Q3: App Group persistence patterns

### Container mechanics
- `AppGroup.suiteName = "group.app.alanvardy.SingleThread"`; `AppGroup.defaults` = `UserDefaults(suiteName:) ?? .standard` — `AppGroup.swift:8-15`; fallback documented for watchOS/unregistered simulators/previews. Doc comment (:3-4) is stale (names only skipped IDs; suite also carries exclusions, sort, show-*, completionCount).

### Collection store pattern (two string-array stores)
- `SkippedReminderStore` — `ReminderSkip.swift:121-139`: `init(defaults: UserDefaults = AppGroup.defaults, key: String = "skippedReminderIdentifiers")`; `load()` = `defaults.stringArray(forKey:) ?? []`; `save(_:)` = `defaults.set(identifiers, forKey:)`. Values are `calendarItemIdentifier` strings.
- `ExcludedListStore` — `ExcludedListStore.swift`: same shape, key `"excludedListTitles"`.
- Save is whole-value replace, never merge (pinned by `ExcludedListStoreTests`).
- Scalar siblings: `CompletionCounterStore` (`integer(forKey:)`, `increment()`, test-only `resetForTesting()` — `CompletionCounterStore.swift:20-33`), `SortOptionStore`, `Show*Preference`.

### Pruning/consistency in `ReminderStore.reload()`
- `reload(clearSkipped: Bool = false)` — `ReminderStore.swift:287`; `clearSkipped` branch sets `skippedIDs = []`, `skipStore.save([])`, fires `onSkipSetChanged([])` (:328-331).
- Normal branch: `ReminderSkipLogic.resolve(fetched:skipped:)` = `Set(fetched).intersection(skipped)` as Array; `skipStore.save(resolved)` writes the pruned list back so on-disk matches memory (:333-341). Skip writes route through private `applySkipSet` (:405-409).
- Exclusion titles are refreshed in memory only (`refreshExcludedListTitles`, :360-366, deliberately no hook); persisted value is written only at mutation or sync receive — pruning asymmetry vs the skip list.

### `.standard` fallback
- Automatic via every default `init(defaults: UserDefaults = AppGroup.defaults)`.
- Watch explicitly injects `.standard` for sync-service stores (`WatchAppViewModel.swift:144-151`) but uses `AppGroup.defaults.set(count, forKey: "completionCount")` directly (:160-163) for the count receive path.

### Test reset paths
- `UITestingSeed.resetPersistedState()` removes all `persistedKeys` (19 keys) from **both** `AppGroup.defaults` and `UserDefaults.standard` — `UITestingSeed.swift:45-75`; called only from `AppViewModel.seededStore` (`AppViewModel.swift:173`), i.e. only on `--seed` launches.
- Persistence-across-relaunch UI tests relaunch with plain `--ui-testing` (NOT `--seed`) so the key under test isn't wiped — `SingleThreadUITestsFlows.swift:214-216, 287-290, 342-344, 455-457`.
- Targeted single-key resets: `--reset-glow-preference` / `--reset-swipe-preference` (`AppViewModel.swift:126-131`).

## Q4: Main-screen UI composition

### Root ZStack (ContentView.swift:50-64)
Three layers, bottom→top: `Color.systemBackground.ignoresSafeArea()` (:52) → iOS-only `BackgroundPhotoLayer` (:53-58) → content (:59-63: `loadsReminders ? authGatedContent : reminderList`). `authGatedContent` (:285-298) switches on `authorizationStatus` (.notDetermined → ProgressView, .fullAccess → reminderList, else ContentUnavailableView). `reminderList` (:299-405) is a GeometryReader with three branches (allSkipped/empty/list), each `ZStack(alignment: .bottom)` with `bottomBar` (:407-447).

Modifier chain after the ZStack: gear overlay (:65) → glow overlay (:80-84) → `.animation(.easeInOut(duration: 0.4), value: completionGlow.isActive)` (:85-87, disabled under `accessibilityReduceMotion`) → `.task` (:88-90) → `.onChange` × several (:91-103) → `TextSizeModifier` (:100) → sheets (:109, :140).

### Gear overlay (the main-screen control precedent)
- `.overlay(alignment: .topTrailing) { Button { settingsBag = makeSettingsBag(); isShowingSettings = true } label: { Image(systemName: "gearshape").font(.title3).controlPlate().contentShape(Rectangle()) } .accessibilityLabel("Settings").accessibilityAddTraits(.isButton).padding(.top, 8).padding(.trailing, 12) }` — `ContentView.swift:65-79`. UI tests address `app.buttons["Settings"]`.
- `controlPlate()` — `ControlPlateModifier.swift:12-56`: 56×56 frame, `Circle()` fill, `.shadow(radius: 4)`; dark = black plate/white glyph, light = off-white plate (`Color(white: 0.92)`) / dark glyph (`Color(white: 0.15)`). Note: doc claims a contrasting stroke; the implemented modifier has no stroke.

### Corner occupancy
- **topTrailing** — occupied (gear). **topLeading** — free (no `.topLeading` overlay anywhere in ContentView). **bottom center span** — occupied by `bottomBar` (VStack, `.padding(.bottom, 16)`, :446). **bottomLeading / bottomTrailing** — free. Center — full-screen glow overlay over everything (:514-523) but decorative (`.allowsHitTesting(false)`).

### Conventions for a new main-screen control
- Plate + SF Symbol + `.font(.title2/.title3)` + `.accessibilityLabel` + `.accessibilityAddTraits(.isButton)` (every control does this: gear :75-76, `Complete reminder` :458-459, `Skip reminder` :470-471, `Dictate reminder` :498-499).
- Placement: either `.overlay(alignment:)` fixed-point control (gear precedent) or a `bottomBar` child.
- iOS-only chrome wrapped in `#if os(iOS)` (e.g. cluster :453-485).

### completionGlow trigger/dismiss/gating
- `CompletionGlow.swift:13-49`: `@MainActor @Observable final class`; `isActive` private(set); `duration` default 0.50 s; `trigger()` sets active, cancels prior `dismissTask`, spawns task sleeping `duration` then clearing — auto-dismiss is the only dismissal path, retrigger resets the timer.
- Trigger on iOS: `if await store.completeCurrentReminder(), showCompletionGlow.isEnabled { completionGlow.trigger() }` — `ContentViewModel.swift:108-111`; preference injected via ctor and read at trigger time (`ShowCompletionGlowPreference`, absent → true).
- Overlay: `Color.green.opacity(0.1).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(!isGlowUITesting).accessibilityIdentifier("completionGlowOverlay").transition(.opacity)` — `ContentView.swift:514-523`; `isGlowUITesting` = launch arg `--ui-testing-glow` (:229-231), which also extends `duration = 2.0` (`AppViewModel.swift:105-110`).
- Parallel transient: `creationFeedbackView` (:526-531), triggered by `DictationViewModel` on dictation save success/failure with 1 s auto-clear (`DictationViewModel.swift:59-64`, `CreationFeedback.swift`).

## Q5: Transient in-memory state patterns

### CompletionGlow
- `@MainActor @Observable final class`, per-view-model instance, not persisted — `CompletionGlow.swift:11-13`. Injectable `duration` (0.50 default; tests shrink to ~0.05) with doc explaining the 0.4 s animation envelope on watchOS.
- `trigger()`: set active → cancel `dismissTask` → `Task` sleeping `duration` then clear; cancellation leaves `isActive` untouched ("that trigger owns the timer") — `CompletionGlow.swift:32-45`.
- Injection: `ContentViewModel` owns `let completionGlow = CompletionGlow()` (`ContentViewModel.swift:38`, not ctor-injectable); watch VM owns one too (`WatchReminderViewModel.swift:39`). `AppViewModel` extends duration under `--ui-testing-glow` (`AppViewModel.swift:105-110`).

### CompletionCounterStore
- `public struct` wrapping UserDefaults — persisted/lifetime, not memory-transient; monotonic +1, never decremented in production; `resetForTesting()` documented test-only — `CompletionCounterStore.swift:8-33`.
- Injected into `ReminderStore` (`ReminderStore.swift:24`, `:94`); incremented exactly once per successful iOS EventKit save (:179); read by `canMutate` (:126-128). WatchOS branch never increments.

### Other transient/instance state in the package
- `ResumptionGate` — one-shot claim-once flag (`ResumptionGate.swift:14-51`), instantiated per operation in `fetchReminders` (`ReminderStore.swift:416-424`) and dictation authorization.
- `MinimumDisplayDuration.remainingSleep(elapsed:minimum:)` — pure static, used for the watch's ≥1 s spinner (`MinimumDisplayDuration.swift:16-19`).
- `WatchReminderViewModel.isRefreshing`/`isShowingRefreshConfirmation` re-entry guards (`WatchReminderViewModel.swift:42-44, 61-78`); `BackgroundImageStore.isRefreshing` with `defer` reset (`BackgroundImageStore.swift:76, 108-110`).
- `EntitlementStore.observationTask` — stored `Task<Void, Never>?` started in init, cancelled in deinit (`EntitlementStore.swift:30-34, 78-82`) — the only other stored task besides `CompletionGlow.dismissTask`.
- Test idiom: injectable `defaults` + `key` at ctor with production defaults; tests swap in UUID-keyed `.standard` stores.

## Q6: Phone↔watch sync

### Two WatchConnectivity channels (SkippedReminderSyncService.swift)
- **Channel A — `updateApplicationContext` (latest-wins snapshot)**: `pushAll()` (:167-207) writes one combined context (5 unconditional keys :169-175: skipped IDs, excluded titles, showUndated, sortOption, completionCount; 6 gated keys :176-201: showDate/showRecurrence/showAlarms/showList/showCompletionGlow/entitled, each behind a `sendsX` flag defaulting true); received in `session(_:didReceiveApplicationContext:)` (:231-235) → `apply(context:)` (:308-364). Latest-wins semantics documented at :309-316 — received values authoritative, replacing not unioning, so `[]` "clear" propagates. No `sendMessage` echo emanating from the apply path (diff'ed on phone via `lastShow*`).
- **Channel B — `sendMessage` (one-way relay, no reply handler anywhere)**: `requestCompleteReminder` (:210-217) and `requestDeleteReminder` (:220-227), both `replyHandler: nil` (fire-and-forget; the class doc's "interactive completion requests" :21-22 is the only request/response framing). Received in `session(_:didReceiveMessage:)` (:237-246), dispatched purely by key presence.

### `PayloadKey` enum (private, :268-282)
- `skippedReminderIdentifiers`, `excludedListTitles`, `completeReminderIdentifier`, `deleteReminderIdentifier`, `showUndatedReminders`, `sortOption`, `showDate`, `showRecurrence`, `showAlarms`, `showList`, `showCompletionGlow`, `completionCount`, `entitled` = `"isEntitled"`. Doc says shared "so the two sides cannot drift" (:264-267) but the enum is `private`; tests and the watch UI-test seam duplicate raw literals.

### Hook wiring — phone (AppViewModel.swift)
- Receive hooks (:43-53): `onCompleteReminderReceived` → `store.completeReminder` (:43-45), `onDeleteReminderReceived` → `store.deleteReminder` (:47-49), `onExcludedListTitlesReceived` → `store.refreshExcludedListTitles` (:51-53). **Phone does not wire** skip/sort/show-*/count/entitlement receive hooks — values still persist (service `apply` writes stores) but take effect only at the phone's next `reload()`.
- Send hooks (:56-70): `onSkipSetChanged`/`onShowUndatedRemindersChanged`/`onExcludedListsChanged` → `pushAll()`; `onCompleteReminder`/`onDeleteReminder` → request methods (inert on iOS, documented :60-63); `onSortOptionChanged` → `SortOptionStore().save` + `pushAll()`.
- Preference observation: `setupEntitlementObservation` uses `withObservationTracking` on `isEntitled` (:208-217); `setupSyncObservation` observes `UserDefaults.didChangeNotification` on `AppGroup.defaults` with `lastShow*` diff (:224-263). `onRemindersChanged` → `WidgetCenter.reloadAllTimelines()` (:74-76).
- All handlers assigned before `service.activate()` (`AppViewModel.swift:43-52`); sync hooks are `nonisolated(unsafe)`, write-once-before-activate (`SkippedReminderSyncService.swift:74-82`).

### Hook wiring — watch (WatchAppViewModel.swift)
- Launch-time restore from `.standard` stores (:29-34).
- `setupSyncService` (:139-154): all stores `.standard`-backed; `sendsShowDate/.../sendsEntitled: false` — watch pushes only the unconditional five keys.
- Receive hooks (:155-182): showUndated → assign + `reload()`; skipped → `reload()` only (:164-165, persist already done); sort → `setSortOption`; completionCount → raw `AppGroup.defaults.set(count, forKey: "completionCount")` (:160-163); exclusions → `refreshExcludedListTitles`; `wireStateReceiveHooks` (:196-221) → `ShowXState.apply(value)` for the five show-* + entitlement.
- Send hooks (:183-188): `onSkipSetChanged` → `pushAll()`; `onCompleteReminder`/`onDeleteReminder` → request methods. No exclusion push hook (phone→watch only, comment :185-186).

### Patterns for syncing new state
- **Pattern A (persisted/latest-wins)**: Core defaults struct (load/save or isEnabled/set) → `PayloadKey` case + `sendsX` flag → `pushAll()` entry (gated if per-platform) → decode+persist branch + `onXReceived` hook in `apply()` → sender wires `onXChanged → pushAll()` (or defaults-diff/observation) → receiver applies live (watch state holders) and restores at launch from `.standard`.
- **Pattern B (per-reminder mutation relay)**: `PayloadKey` case + request method (`sendMessage`, nil reply) → dispatch in `didReceiveMessage` + `onXReceived` hook → producer fires `onX` inside the platform-gated store branch (watchOS only) → consumer does the real EventKit work in a `Task` on `@MainActor`.

### Asymmetries observed
- Phone receive hooks apply only complete/delete/exclusions live; everything else waits for the next reload.
- `completionCount` receive path on the watch bypasses the store type with a hand-typed key write.
- Idle `onCompleteReminder`/`onDeleteReminder` on iOS (defensive wiring).

## Q7: Test infrastructure

### Unit-test style (Swift Testing)
- `import Testing`, `@Test`, `#expect(==)`, no XCTest — `ReminderStoreTests.swift:1-6`. `@MainActor` where `EKReminder`/`ReminderStore` constructed; `@Suite(.serialized)` where shared `UserDefaults.standard` keys are touched (`ReminderStoreTests.swift:6`, `ReminderStoreGateTests.swift:6`, `UITestingSeedTests.swift:8`, `CompletionCounterStoreTests.swift:5`).
- `withCheckedContinuation` awaits hook callbacks without sleeps (`ReminderStoreTests.swift:232-253`); one intentional `Task.sleep` where production settles (`ReminderStoreGateTests.swift:119-121`).
- Fixtures: `InMemoryEventStore` + `loadsReminders: false` + explicit `reminders:`/`skippedIDs:` arrays; `makeReminder(title:priority:dateComponents:)` backed by a shared module-level `EKEventStore` purely for construction (`ReminderStoreTests.swift:477-499`, `ReminderStoreGateTests.swift:145-170`). `InMemoryEventStore.fetchReminders` filters `isCompleted` (:57-61); `deliverCompletionOffMain` flag reproduces off-main completion delivery (:61-77).

### Gate tests with seeded counters
- `seededCounter` pre-writes a UUID-keyed `.standard` value then wraps in `CompletionCounterStore`; `makeStore(count:entitled:)` pairs it with `EntitlementStore(testingWithEntitled:)` — `ReminderStoreGateTests.swift:145-163`.
- Coverage: canMutate truth table (50/100 × entitled), `completeReminderReturnsFalseWhenGated`, `completeReminderIncrementsCounterOnSuccess` (50→51), skip/delete gating.

### iOS UI-test style — `--seed '<json>'` seam
- `UITestingSeed.fromLaunchArguments` (`UITestingSeed.swift:31-40`) grabs `--seed`, JSON-decodes. JSON shape (doc :7-18): `{"reminders":[{"title","notes","priority"}],"calendars":[String],"excludedLists":[String],"completionCount":Int,"isEntitled":Bool}` — only `reminders` required, others `decodeIfPresent` with 0/false defaults.
- `materialize()` builds real `EKReminder`/`EKCalendar` off an `EKEventStore` (construction only) — `UITestingSeed.swift:109-127`.
- `AppViewModel.makeStore` → `seededStore` (`AppViewModel.swift:123-125`): calls `resetPersistedState()` (:173), builds `InMemoryEventStore(reminders:calendars:defaultCalendar:)`, writes seeded count into App Group (:177), sets `enableActionButtons = true` (:178), picks `EntitlementStore(testingWithEntitled:)` vs production (:188-189). Result: deterministic mutations with `.fullAccess`, no EventKit/TCC.
- `--ui-testing` fallback seam: single "Buy groceries" reminder, `enableActionButtons = true`, `loadsReminders: false` (`AppViewModel.swift:128-161`).
- Helpers: `launchApp(seedJSON:)` (`SingleThreadUITestsFlows.swift:21-27`); `flipToggle(_:target:)` (:326-339) taps the inner `switches.firstMatch` of a SwiftUI Form row, retries 3×1 s, polls `value` for "0"/"1".
- Persistence-relaunch pattern: launch, flip, terminate, relaunch with plain `--ui-testing` — NOT `--seed` (would call `resetPersistedState()` and wipe the key).
- Accessibility audit: `testAccessibilityAudit` (`SingleThreadUITests.swift:26-66`) with `[.dynamicType, .hitRegion, .sufficientElementDescription, .trait]` locally, cheaper set on CI; a second cluster audit in `ActionButtonsUITests.swift:45-70`.
- `runsForEachTargetApplicationUIConfiguration = false` on all four UI classes.

### Suites affected by a completion-flow change
- Unit: `ReminderStoreTests.swift` (completeCurrentReminder* :316-369, reload-off-main :374-382), `ReminderStoreGateTests.swift`, `CompletionCounterStoreTests.swift`, `UITestingSeedTests.swift`, `EventKitStoringTests.swift` (:151-180), `CompletionGlowTests.swift` (:60-119), `EntitlementSyncTests.swift`, `ReminderIntentsTests.swift` (:8-23), `SwipePromptTests.swift`.
- UI: `SingleThreadUITestsFlows.swift` (`testCompleteViaSwipeRemovesReminder` :90-107, gated/entitled cluster tests :517-546, glow tests :374-416), `ActionButtonsUITests.swift`, watch flows (`testCompleteRemovesReminder`, `--ui-testing-gated`).

### Suites affected by an interface-settings-menu change
- Unit: `SettingsViewTests.swift` (:19-67), `SettingsViewModelTests.swift`, per-preference suites (`ShowCompletionGlowPreferenceTests`, `ShowDatePreferenceTests`, `ShowListPreferenceTests`…), `AppGroupTests`.
- UI: `SingleThreadUITestsFlows.swift` (`testSettingsOpensAndShowsControls` :126-159, persistence-relaunch tests :199-231/287-321/345-371/472-512), `SingleThreadUITestsAppearanceLaunchTests.swift` (:54-80), accessibility audit only insofar as the main screen is covered.

## Cross-Cutting Observations

- **Single Core mutation point**: all five completion surfaces (iOS swipe, iOS cluster, macOS buttons, watch button, widget intent) funnel through `ReminderStore.completeCurrentReminder()` → `completeReminder(identifier:)`. Completion `Bool` return gates success-only feedback (glow) on both platforms.
- **Two persistence API conventions coexist**: newer toggles expose `isEnabled`/`set(_:)` (missing→true); older stores expose `load()`/`save(_:)`. Both are tiny structs with injectable `defaults` + `key` defaulting to `AppGroup.defaults`.
- **Key literals duplicated by convention** across four surfaces (`@AppStorage`, Core store default, `PayloadKey`, `persistedKeys`); only `sortOption` has a shared constant. A new key must be added in all four places.
- **Hook-based decoupling**: Core never reads UserDefaults for sync; each app layer wires `on*` hooks (assigned before `service.activate()`, `nonisolated(unsafe)` on the service).
- **Watch is EventKit read-only**: watch mutations remove locally + relay via `sendMessage`; the phone performs the real EventKit write (and the only `completionCounter.increment()`).
- **Preference sync mechanism**: settings write-back → `@AppStorage`/AppGroup defaults → `UserDefaults.didChangeNotification` diff (`lastShow*`) → `pushAll()` → watch `apply` persists-then-notifies → `ShowXState.apply`.
- **Test seams are layered**: `UITestingSeed` (launch-arg → EKReminder objects) → `InMemoryEventStore` (protocol conformance) → `ReminderStore`; seats extended by `--ui-testing`, `--ui-testing-glow[-disabled]`, `--ui-testing-gated`, `--reset-*-preference`.
- **`resetPersistedState()` is the reset chokepoint** for UI-test state; only called on `--seed` launches; persisted-relaunch UI tests deliberately avoid it.

## Open Areas

- **Question premise corrections**: "Show completion glow" lives in `ReminderSettingsView`, not `InterfaceSettingsView`; an "interface-settings toggle" change affects both sub-menus. Core toggle stores expose `isEnabled`/`set(_:)`, not `load()`/`save()`.
- **No undo exists anywhere**: the completion mutation is one-way (EventKit `isCompleted = true` + save); a reversion would need the reminder's EventKit object or its identifier retained, since the completed reminder leaves `reminders` at the next reload and only refetching "incomplete" reminders is supported (`predicateForIncompleteReminders`, `ReminderStore.swift:301`). No documented precedents in the codebase.
- **Stale comments/docs observed**: `AppGroup.swift:3-4` (suite contents), `AppViewModel.swift:107` (glow "0.25 s" vs actual 0.50 s), `SkippedReminderSyncService.swift:21-22` ("interactive/request-response" vs nil reply handlers), `ControlPlateModifier.swift:43-44` (stroke claim vs no stroke), `SkippedReminderSyncService.swift:303-306` (excluded-list transport comment).
- **`"isEntitled"` in `persistedKeys` is a dead key**: `EntitlementStore.isEntitled` derives from StoreKit, never stored in UserDefaults.
- **`resetPersistedState()` omits `backgroundFadePercent`** (a `.standard` @AppStorage key) — 19 of 20 keys covered.
- **`PayloadKey.entitled` documented/shared enumeration mismatch**: enum is `private`, tests and watch seam duplicate raw literals; wire string is `"isEntitled"` though the case is `entitled`.
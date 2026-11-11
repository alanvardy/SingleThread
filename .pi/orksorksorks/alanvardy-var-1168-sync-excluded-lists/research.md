# Research Findings — iCloud sync for excluded lists (VAR-1168)

## Q1: How are the skipped-reminder and excluded-list stores implemented (types, keys, load/save shape, defaulting/injection), and where are all their read/write call sites?

### Findings
- Both are tiny non-observable `public struct` value types in `SingleThreadCore`:
  - `SkippedReminderStore` — `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift:121-150`. `init(defaults: UserDefaults = AppGroup.defaults, key: String = defaultsKey)` (`:124`), `defaultsKey = "skippedReminderIdentifiers"` (`:132`), `load() = defaults.stringArray(forKey:) ?? []` (`:135-137`), `save() = defaults.set` (`:139-141`).
  - `ExcludedListStore` — `SingleThreadCore/Sources/SingleThreadCore/ExcludedListStore.swift:4-30`. Same shape: `init(defaults:key:)` (`:7`), `defaultsKey = "excludedListTitles"` (`:15`), `load()` (`:18-20`), `save()` (`:22-24`).
- Backing store is the single cached App Group suite: `AppGroup.suiteName = "group.app.alanvardy.SingleThread"`, `AppGroup.defaults = .init(suiteName:) ?? .standard` — `SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:10,26-27`.
- Both keys are duplicated as sync payload string literals, deliberately the same text: `SkippedReminderSyncService.swift:371-373`. Also listed in the UI-test seed key set: `UITestingSeed.swift:84-86`.
- Save is always a whole-array **replace**, never a union (proven by `SingleThreadTests/ExcludedListStoreTests.swift:15`). `load()` defaults to `[]` when the key is absent.
- `ReminderStore` injects both stores with default arguments: `skipStore: SkippedReminderStore = SkippedReminderStore()` (`ReminderStore.swift:25`), `excludeStore: ExcludedListStore = ExcludedListStore()` (`:28`); stored `:630,:633`.
- Skipped store **writes**: `clearSkippedState()` (`ReminderStore.swift:687`), `applySkipSet` (`:702`), `reconcileSkipState` (`:763`), sync receive (`SkippedReminderSyncService.swift:472`). **Reads**: `reconcileSkipState` (`:760`), `pushAll` snapshot (`SkippedReminderSyncService.swift:241`).
- Excluded store **writes**: `setExcludedListTitles(_:)` (`ReminderStore.swift:582`), sync receive (`SkippedReminderSyncService.swift:477`). **Reads**: `reconcileSkipState` (`ReminderStore.swift:762`), `pushAll` (`SkippedReminderSyncService.swift:243`).
- In-memory-only excluded update with no persist and no push hook: `refreshExcludedListTitles(_:)` — `ReminderStore.swift:589-594`, deliberately omits `onExcludedListsChanged` so a received push does not echo back (`:586-588`).
- Structural parallel: `ExcludedListStore` is the mirror of `SkippedReminderStore`; the excluded-list path is the simpler one (no pruning, fires `onExcludedListsChanged` only from `setExcludedListTitles`).

## Q2: How does the WatchConnectivity sync service build, push, and apply its payloads, and how are the phone and watch sides wired to it?

### Findings
- `SkippedReminderSyncService: NSObject, WCSessionDelegate` — `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift:48`, whole file gated `#if os(iOS) || os(watchOS)` (`:15`); a macOS stub protocol exists at `:11`.
- Transport seam `SkipSyncSession` (`:18-34`): `isReachable`, `activate()`, `updateApplicationContext(_:) throws`, `sendMessage(...)`, `queueUserInfo(_:) -> Bool`. `extension WCSession: SkipSyncSession` (`:36-42`) maps `queueUserInfo` to `transferUserInfo`.
- Init (`:52-108`) injects `session`, `skipStore`, `countStore`, `excludeStore`, `sortStore`, several `BoolPreferenceStore`s, `completionCounter`, `entitlementStore`, `appLanguageStore`, plus sender-role booleans `sendsShowDate/appLanguage/showRecurrence/showAlarms/showList/showCompletionGlow/entitled` (`:101-107`) gating which optional keys a side pushes.
- `PayloadKey` enum (`:370-388`) contains `skippedReminderIdentifiers`, `excludedListTitles`, and all preference/command keys. Both list keys are always present in the context.
- Push: `pushAll()` (`:238-292`) builds ONE combined `[String: Any]` snapshot, then `session.updateApplicationContext(context)`. Doc (`:236-237`): single latest-wins snapshot avoids interleaved partial shapes.
- Receive: `didReceiveApplicationContext` → `apply(context:)` (`:334-336`); `didReceiveMessage`/`didReceiveUserInfo` → `apply(request:)` (`:339,:346`). `apply(context:)` (`:462-524`) per key: decode → persist to store → fire hook; absent key = no-op. Skipped IDs `:471-474`; excluded titles `:476-479`. Remaining keys in `applyRemaining(context:)` (`:526-549`).
- Hooks are `public nonisolated(unsafe) var` closures (`:190-225`), written once from the main actor before `activate()` (`:112-118`).
- Phone wiring `SingleThread/AppViewModel.swift:486-539`: builds service with `WCSession.default`, `SkippedReminderStore()`, `sendsShowDate: true`, `sendsAppLanguage: true`, `sendsEntitled: true`; receive hooks assigned before `activate()`: `onExcludedListTitlesReceived` → `store.refreshExcludedListTitles(Set(titles))` (`:517`), `onSkipCountsReceived` → `store.reload()` (`:520`). Phone does NOT assign `onSkippedIdentifiersReceived` (received skip IDs only persist). Push hooks `:525-527`: `onSkipSetChanged`/`onExcludedListsChanged`/`onShowUndatedRemindersChanged` → `service.pushAll()`.
- Watch wiring `SingleThreadWatch/WatchAppViewModel.swift:190-244`: `makeSyncService()` (`:246-272`) builds with `SkippedReminderStore()` and all `sends*: false` (watch receives, never pushes settings). Receive hooks: `onSkippedIdentifiersReceived`→`reload` (`:203`), `onExcludedListTitlesReceived`→`refreshExcludedListTitles` (`:220`). `wireStoreSyncHooks` (`:234-244`) only wires `onSkipSetChanged`→`pushAll`; comment `:229-233` states exclusions sync **phone→watch only**.

## Q3: How does `ReminderStore` hold, filter, mutate, and persist skip/excluded state, and how does it notify observers?

### Findings
- `@MainActor @Observable final class` (SingleThreadCore). Published mirrors `public private(set) var skippedIDs: Set<String>` and `excludedListTitles: Set<String>` — `ReminderStore.swift:65-66`; both seedable via init params (`:31,:34,:49,:52`).
- Filtering (read-only, no notification): `filteredReminders` (`:167`) drops `skippedIDs` by `calendarItemIdentifier` then drops `excludedListTitles` compared against `reminder.calendar?.title ?? ""`. `visibleReminders` (`:173`) sorts; `allSkipped` (`:214`).
- Skip mutation: `skipCurrentReminder()` (`:463`) guards `canMutate` + first visible, increments count, computes `updatedSkipSet(afterSkipping:)` (`:645`, via `ReminderSkipLogic.skipping`, which prunes), captures `skipGeneration`, then `Task { settle(); if applySkipSet(updated, generation:) { reload() } }`. Widget variant `skipCurrentReminderImmediately()` (`:504`) writes synchronously.
- `applySkipSet(_:generation:)` (`:697-706`): generation gate (discards stale apply after a clear), sets `skippedIDs`, `skipStore.save(updated)`, fires `onSkipSetChanged?(updated)` then `onRemindersChanged?()`.
- `clearSkippedState()` (`:684-689`): bumps `skipGeneration`, `skippedIDs = []`, `skipStore.save([])`, fires `onSkipSetChanged?([])` (no `onRemindersChanged`).
- Excluded mutation: `setExcludedListTitles(_:)` (`:577-585`): assigns, `excludeStore.save(array)`, fires `onExcludedListsChanged?(array)` then `onRemindersChanged?()`. Remote `refreshExcludedListTitles(_:)` (`:589-594`): assigns, fires only `onRemindersChanged?()`.
- Reload reconcile: `reload(clearSkipped:)` (`:559-611`) → `reconcileSkipState(clearSkipped:visibleShown:)` (`:751-766`): on clear → `clearSkippedState()`; else `skippedIDs = Set(ReminderSkipLogic.resolve(fetched: skipStore.load()))`, `excludedListTitles = Set(excludeStore.load())`, `skipStore.save(resolved)`. Reconcile fires **no** `onSkipSetChanged`/`onExcludedListsChanged` — only the wrapping `onRemindersChanged?()` (`:576`).
- Observer hooks: `onSkipSetChanged: (([String]) -> Void)?` (`:87`), `onExcludedListsChanged: (([String]) -> Void)?` (`:92`), `onRemindersChanged` (`:120ff`, widget reload). Wired to `pushAll()` by both app layers (`AppViewModel.swift:525,527`; `WatchAppViewModel.swift:235`).
- `@Observable` drives SwiftUI invalidation for view readers independently of the imperative hooks.

## Q4: What app and extension targets exist, which entitlements and capabilities files do they declare, and how is that configuration represented in the Xcode project?

### Findings
- Targets (all in `SingleThread.xcodeproj/project.pbxproj`): `SingleThread` app (`:256-282`), `SingleThreadTests` (`:284-307`), `SingleThreadUITests` (`:309-331`), `SingleThreadWatch` (`:333-354`), `SingleThreadWidget` extension (`:356-377`), `SingleThreadWatchUITests` (`:379-400`), `SingleThreadWatchTests` (`:402-424`).
- Embedded products: `Embed Watch Content` (`pbxproj:74-84`) and `Embed Foundation Extensions` (`:85-95`) are copy phases on the iOS app target.
- Only two entitlements files exist: `SingleThread/SingleThread.entitlements` (macOS: in-app-purchases, app-sandbox, application-groups `group.app.alanvardy.SingleThread`, audio-input, calendars) and `SingleThread/AppGroup.entitlements` (application-groups only).
- Per-SDK selection on the app target (`pbxproj:757-759` Debug, `:808-810` Release): `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]` and `[sdk=iphonesimulator*]` = `AppGroup.entitlements`; `[sdk=macosx*]` = `SingleThread.entitlements`.
- Widget target: unconditional `CODE_SIGN_ENTITLEMENTS = SingleThread/AppGroup.entitlements` (`pbxproj:1019` Debug, `:1050` Release).
- **Watch target has no `CODE_SIGN_ENTITLEMENTS` at all** (`pbxproj:926-1006`) and no entitlements plist; watch keys are all `INFOPLIST_KEY_*`.
- `PBXProject` `TargetAttributes` (`pbxproj:434-457`) carry only `CreatedOnToolsVersion` — **no `SystemCapabilities` blocks**. Capabilities are declared solely via entitlements files + `INFOPLIST_KEY_*`, not as pbxproj capability records.
- No `.xcconfig` files anywhere. All wiring lives in `project.pbxproj`.
- `GENERATE_INFOPLIST_FILE = YES` throughout; only `SingleThread/Info.plist` (SENTRY_DSN) and `SingleThreadWidget/Info.plist` (NSExtension point) are real files.
- Signing: `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = 6NWX2DHB9Q` on every target; `exportOptions.plist` app-store-connect.
- **No iCloud / CloudKit / `NSUbiquitousKeyValueStore` usage or entitlements anywhere** (locator survey; "iCloud" appears only in privacy strings).

## Q5: How are refresh, pruning, conflict resolution, and change notification currently handled across the App Group + WatchConnectivity path?

### Findings
- Pruning primitive: `ReminderSkipLogic.resolve(fetched:skipped:) = Set(fetched).intersection(skipped)` — `ReminderSkip.swift:14-18`; `skipping(_:fetched:skipped:)` calls `resolve` with the new ID appended (`:22-27`). Every skip prunes; order not guaranteed (Array).
- Reconcile prunes both in memory and on disk on every non-clearing reload (`ReminderStore.swift:756-763`); `clearSkipped` path calls `clearSkippedState()`.
- Conflict model is **last-wins full-snapshot replace, never union** — doc comments at `SkippedReminderSyncService.swift:459-472` and `:235-241`. Replacing (rather than unioning) is what lets a `[]` clear propagate.
- `updateApplicationContext` auto-delivers on (re)connect (`SkippedReminderSyncService.swift:57-59`); it is the only one-transport for state.
- Interactive complete/delete/reschedule go through `apply(request:)` (`:430-455`) and `deliver()` (`:494-511`): exactly one of `sendMessage` if reachable else queued `queueUserInfo`.
- Receive handlers fire AFTER the store is persisted, so a handler can simply reload (`:459-472`).
- Race handling: `skipGeneration` gate for skip/clear races (`ReminderStore.swift:631-634,715-724`); device-local pending-completion set hides watch-relayed completions until the phone processes them, then reload prunes (`:296-309,726-750`); empty fetch skipped so a transient empty result cannot resurrect relays (`:742-744`).
- No cross-device merge/conflict resolution beyond last-wins full replace; receiver `reload()` reconciles stale IDs on next fetch.
- Observer registration: `UserDefaults.didChangeNotification` with `object: AppGroup.defaults` (requires the single cached instance) → `handlePreferencesChanged` diffs against last-seen values → `pushAll` (`AppViewModel.swift:565-573,579-616`); `setupAIRankingObservation` (`:450-457`) and `setupEntitlementObservation` (`:540-557`) use the same object-filtered notification / `withObservationTracking`. `EventStoreChangedObserver.swift:18-35` feeds `StaleReminderRechecker.swift:133-145` → `store.reload()`.
- Direction guarantees: exclusions phone→watch only (watch `sends*: false`); skip-set mutates both directions; settings phone→watch.

## Q6: What test patterns and seams exist for persistence and sync?

### Findings
- **UserDefaults injection seam**: every store takes `defaults:` and `key:`; tests use `.standard` with UUID-suffixed keys for isolation (`ExcludedListStoreTests.swift:6-7,14-15`; `SkippedReminderSyncServiceTests.swift:25-27,64-66,71-73`). Production defaults to `AppGroup.defaults`.
- `AppGroup` contract guarded by `SingleThreadTests/AppGroupTests.swift:26-72`: `suiteNameIsConfigured`, `defaultsIsAStableInstance`, `objectFilteredObserverSeesAppGroupWrites`, `defaultsRoundTripsValues`.
- Some suites write real shared keys via `AppGroup.defaults` + `defer { removeObject }`, serialized to avoid races (`WatchSyncPipelineTests.swift`, `UITestingSeedTests.swift:135,172`).
- **Fakes**: `FakeSession: SkipSyncSession` records `activated/lastContext/lastMessage/queuedUserInfo` with knobs `pushShouldThrow/isReachable/queueSucceeds/errorToThrow` — `SingleThreadTests/TestFixtures.swift:70-115` (`#if os(iOS)||os(watchOS)`); parallel `WatchFakeSession` — `SingleThreadWatchTests/TestFixtures.swift:16-60`. `InMemoryEventStore: EventKitStoring` — `SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift:13`.
- `ReminderStore` accepts injected `eventStore:`, `reminders:`, `skippedIDs:`, `excludedListTitles:`, and `loadsReminders:false` (`ReminderStoreTests.swift:149,542`).
- **Launch-arg seams**: `--seed '<json>'` → `UITestingSeed.fromLaunchArguments` (reminders/calendars/`excludedLists`/completion/entitlement) into an `InMemoryEventStore`-backed store; `resetPersistedState()` clears App Group + standard keys (`UITestingSeedTests.swift:8-`, `:24-33`). `--ui-testing`, `--ui-testing-open-settings`, `-reminder`, `--ui-testing-noop-settle` (`LaunchArgumentTests.swift:6-62`). `AppViewModelSyncWiringTests` drives real delegate wiring with an injected `FakeSession` (`AppViewModelSyncWiringTests.swift:1,21-27,54-55`, `#if os(iOS)`).
- Existing sync suites: `SkippedReminderSyncServiceTests.swift` (main service, includes `SkipCountSyncTests`, `AISortOptionTravelTests`), `WatchSyncPipelineTests.swift` (watch side, nested `WatchEnableActionButtonsSyncTests`, `WatchAppLanguageSyncTests`), `EnableActionButtonsSyncTests`, `AppLanguageSyncTests`, `EntitlementSyncTests`, `RescheduleSyncTests` — all `#if os(iOS)||os(watchOS)`.
- Persistence-adjacent suites: `ExcludedListStoreTests.swift`, `ReminderStoreTests.swift` (serialized, `:19`), `ReminderStoreGateTests.swift`, `EventStoreChangedObserverTests.swift`, `CompletionCounterStoreTests`, `SkipCountStoreTests`.
- See `conventions.md` for the full per-file suite inventory and gating.

## Cross-Cutting Observations
- The excluded-list path is a strict subset of the skipped-reminder path: same store shape, same App Group key namespace, same WatchConnectivity payload handling; it differs in that it has no pruning logic, is phone→watch only, and has the deliberate no-echo `refreshExcludedListTitles`.
- The whole shared-persistence contract rests on `AppGroup.defaults` being a single cached `UserDefaults` instance; object-filtered `didChangeNotification` observers silently fail if it is recomputed (`AGENTS.md`; `AppGroupTests`).
- The sync service is the single choke point for cross-device state: state via `updateApplicationContext` (latest-wins snapshot), commands via `sendMessage`/`queueUserInfo` (exactly one transport). Any new cross-device channel would need to slot into `pushAll`/`apply(context:)` and the sender-role flags.
- The receive path persists to the stores before firing handlers, and handlers on the phone/watch either `refreshExcludedListTitles` (no echo) or `reload` (reconcile + prune).
- No iCloud/CloudKit/ubiquity code or entitlements exist; the capabilities story is entirely entitlements-file + `INFOPLIST_KEY_*`, with no `SystemCapabilities` pbxproj records and no `.xcconfig`. The watch target currently has no entitlements file.
- Persistence unit tests rely on constructor injection (`defaults`/`key`) rather than a protocol seam; sync tests rely on the `SkipSyncSession` protocol seam and fake sessions.

## Open Areas
- Whether the widget extension reads either excluded/skipped key directly: no hits for the key strings under `SingleThreadWidget` (Q1 "not determined").
- Exact enclosing functions of the `applySkipSet` call sites at `ReminderStore.swift:482`/`:514` beyond "generation-guarded async skip path" vs "immediate apply" (Q1).
- The watch target has no App Group entitlement wired, so the shared suite is not actually used on watchOS even though `SkippedReminderStore()` defaults to `AppGroup.defaults`; how the watch's suite resolves at runtime was not verified.
- No research question covered App Store / provisioning-profile implications of adding an iCloud container, nor any existing CI signing configuration for iCloud (out of the questions' scope).
- Not enumerated: every `defaults: AppGroup.defaults`-vs-`.standard` call site (Q6).

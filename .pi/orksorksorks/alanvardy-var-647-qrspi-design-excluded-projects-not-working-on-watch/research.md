# Research Findings

## Q1: Watch-side `SkippedReminderSyncService.didReceiveApplicationContext` handling of `excludedProjectTitles`

### Findings
- `SkippedReminderSyncService` is defined in `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`.
- The delegate method is `session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any])` at `SkippedReminderSyncService.swift:143`. For `PayloadKey.excludedProjectTitles` it does exactly one thing:
  ```swift
  if let receivedTitles = applicationContext[PayloadKey.excludedProjectTitles] as? [String] {
      excludeStore.save(receivedTitles)
  }
  ```
  (`SkippedReminderSyncService.swift:152-154`)
- It does **not** touch `ReminderStore.excludedProjectTitles`, does **not** call `ReminderStore.reload()`, and does **not** set any `ReminderStore` field or fire any store hook. `excludeStore` is an `ExcludedProjectStore` bound to UserDefaults (`SkippedReminderSyncService.swift:41`), so the received titles are written straight to UserDefaults.
- Contrast with the other receive branches in the same method: `showUndatedReminders` fires `onShowUndatedRemindersReceived` (`:157-158`), and `sortOption` fires `onSortOptionReceived` (`:161-166`). These are the only two excluded-title-adjacent cases that notify the store layer. There is no `onExcludedTitlesReceived` hook on the service (the `nonisolated(unsafe)` hook vars are documented at `SkippedReminderSyncService.swift:70-93` and none is for exclusions).
- Consequence: a received exclusion value sits in UserDefaults unread by the in-memory store until some later `reload()` (see Q2). The receive path is persistence-only by design; the header comment at `SkippedReminderSyncService.swift:141-142` describes the keys as "independent", and the in-function comment (`SkippedReminderSyncService.swift:148`) notes `ReminderStore.reload()` prunes on the next fetch — i.e. reload is assumed to happen, but not triggered by this path.

## Q2: When `ReminderStore.excludedProjectTitles` is loaded / refreshed

### Findings
- `ReminderStore` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`) declares `excludedProjectTitles: Set<String> = []` as a property with `private(set)` (`ReminderStore.swift:58`).
- It is assigned in exactly three places:
  1. Preview/test init: `ReminderStore.swift:42` sets it directly from an injected `excludedProjectTitles` parameter.
  2. `reload()`, in the `else` branch (when `clearSkipped` is false): `excludedProjectTitles = Set(excludeStore.load())` (`ReminderStore.swift:230`). This is the only production path that refreshes in-memory exclusions from `ExcludedProjectStore`.
  3. `setExcludedProjectTitles(_ titles)` at `ReminderStore.swift:252-260`: assigns `excludedProjectTitles = titles`, immediately `excludeStore.save(array)`, then fires `onExcludedProjectsChanged?(array)` and `onRemindersChanged?()`.
- So `excludedProjectTitles` is **only** (re)loaded from UserDefaults during `reload()` (`ReminderStore.swift:241`). There is no getter that reads `excludeStore.load()` lazily and no separate "refresh excluded" method.
- `visibleReminders` reads the in-memory set every time it is evaluated: `.filter { !excludedProjectTitles.contains($0.calendar?.title ?? "") }` (`ReminderStore.swift:84-90`). It does not consult `ExcludedProjectStore`.
- **Watch `reload()` triggers (externally vs on-device):** All callers of `store.reload()` / `store.start()`:
  - `SingleThreadWatch/WatchReminderView.swift:43` — `store.start()` from the body `.task` (startup / auth).
  - `SingleThreadWatch/SingleThreadWatchApp.swift:31` — `await store?.reload()` inside `onShowUndatedRemindersReceived`, i.e. the watch reloads only when a combined context carries `showUndatedReminders`. 
  - `SingleThreadWatch/WatchReminderView.swift:195` — `reload(clearSkipped:)` from the `refresh()` user-gesture spinner (`WatchReminderView.swift:186-205`).
  - No periodic timer and no WatchConnectivity receive handler calls `reload()` for excluded titles.
- Net: An excluded-titles payload that arrives via WatchConnectivity triggers `excludeStore.save` only. On the watch, in-memory exclusions refresh only when a later reload occurs via **(a)** watch launch/`start()`, **(b)** a subsequent `showUndatedReminders` key arriving in some later combined context (`SingleThreadWatchApp.swift:28-31`), or **(c)** a user pull-to-refresh gesture (`WatchReminderView.swift:186-205`). If the phone pushes exclusions but then sends nothing further, the watch's live `visibleReminders` never re-filters — the received set is saved but effectively dormant.

## Q3: Phone-side emit when a project is toggled

### Findings
- Settings UI: `SingleThread/SettingsView.swift` — the settings grid iterates projects and builds per-project `Binding<Bool>` toggles via `excludedBinding(for:)` (`SettingsView.swift:44-50`):
  ```swift
  Binding(
      get: { excludedProjects.contains(project) },
      set: { isExcluded in
          if isExcluded { excludedProjects.insert(project) }
          else          { excludedProjects.remove(project) }
      })
  ```
  where `excludedProjects` is the `@Binding private var excludedProjects: Set<String>` (`SettingsView.swift:39`) passed in from ContentView.
- `ContentView` wires the binding: `excludedProjectsBinding` at `ContentView.swift:223-227`:
  ```swift
  Binding(get: { store.excludedProjectTitles },
          set: { store.setExcludedProjectTitles($0) })
  ```
  It is passed into `SettingsView` as `excludedProjects:` at `ContentView.swift:117` (iOS) and `ContentView.swift:126` (macOS).
- So toggling a project resolves to `ReminderStore.setExcludedProjectTitles(_ titles)` (`ReminderStore.swift:254-260`), which mutates the in-memory set, saves to `excludeStore`, and then fires `onExcludedProjectsChanged` and `onRemindersChanged` — the former passes the full `[String]` array.
- Hook wiring (phone): `SingleThread/SingleThreadApp.swift:52`:
  ```swift
  store.onExcludedProjectsChanged = { titles in service.pushExcludedProjectTitles(titles) }
  ```
- The push body: `SkippedReminderSyncService.swift:98-108`, `pushExcludedProjectTitles(_ titles: [String])` sends exactly one key:
  ```swift
  session.updateApplicationContext([PayloadKey.excludedProjectTitles: titles])
  ```
  `PayloadKey.excludedProjectTitles = "excludedProjectTitles"` (`SkippedReminderSyncService.swift:189-196`).
- Full chain (user → payload): `SettingsView.excludedBinding` setter → `@Binding excludedProjects` setter → the `Binding<Set<String>>` setter at `ContentView.swift:226` → `ReminderStore.setExcludedProjectTitles` (`ReminderStore.swift:254`) → `onExcludedProjectsChanged` → `SingleThreadApp.swift:52` → `pushExcludedProjectTitles` (`SkippedReminderSyncService.swift:98`) → `updateApplicationContext(["excludedProjectTitles": titles])`.
- Note: `pushExcludedProjectTitles` sends **only** `excludedProjectTitles` — it does not re-send `skipIDs`, `showUndatedReminders`, `sortOption`, or `showDate` (compare `push(...)` at `SkippedReminderSyncService.swift:64-81`).

## Q4: WatchConnectivity push semantics — `updateApplicationContext` latest-wins + single-key push

### Findings
- `updateApplicationContext` is described as latest-wins replacing the whole context; the class doc comment at `SkippedReminderSyncService.swift:17-22` states push and receive use `updateApplicationContext` for skip sync, "latest-wins, auto-with on (re)connect". The same method carries `excludedProjectTitles`, `showUndatedReminders`, `sortOption`, and `showDate` keys (see `push(...)` at 64-89, `pushSortOption` 111-127, `pushShowDate` 129-140, `pushExcludedProjectTitles` 98-108).
- Each push builds a fresh `[String: Any]` dict and calls `updateApplicationContext(...)` once. There is **no** accumulation/merge on the send side — whatever dict the method builds is the whole context:
  - `push(...)` sends `skippedReminderIdentifiers`, `showUndatedReminders`, `sortOption`, and (if `sendsShowDate`) `showDate` — but **not** `excludedProjectTitles`.
  - `pushExcludedProjectTitles` sends only `excludedProjectTitles`.
  - Documented warning for the combined context in `pushShowDate` doc comment (`SkippedReminderSyncService.swift:133-139`): "updateApplicationContext replaces the whole context, so both keys must travel together or one clobbers the other."
- Because the receive side gates every key with `if let ... cast` (Q1) and reads **only** the keys that are present, an absent key is a no-op and never clobbers the receiver's preference — `SkippedReminderSyncService.swift:148-153` ("The keys are independent... any key may be present without the others"). So the design reconcilable the two facts: latest-wins replace + per-key pushes is safe for **in-memory receive values**, but has the side effect that a later single-key push replaces the previous combined context on the wire.
- **Startup / (re)connect seeding:**
  - In `SingleThreadApp.init` (iOS), after wiring the hooks it calls `service.activate()` (`SingleThreadApp.swift:62`), which only assigns the session delegate and calls `session.activate()` (`SkippedReminderSyncService.swift:99-96`). It does **not** push the current excluded set (or any current store state) at startup.
  - Same on watch: `service.activate()` at `SingleThreadWatchApp.swift:33` in eventkit `activate()`, but no startup `push`/seeding call. The watch explicitly "Restore the last-received sort (persisted to .standard on receive)" via `store.sortOption = SortOptionStore().load()` (`SingleThreadWatchApp.swift:20`), and the phone sets `store.sortOption = SortOptionStore().load()` (`SingleThreadApp.swift:14`) — these rely on the *persisted* value, not a fresh push.
  - Excluded titles: there is no startup `pushExcludedProjectTitles` in either app init. The only emit for exclusions is `onExcludedProjectsChanged` hooked at `SingleThreadApp.swift:52` / `SingleThreadWatchApp.swift:43`, which fires only on a user `setExcludedProjectTitles` / Settings toggle. So the excluded-project set is transmitted **only on a change**; nothing seeds it at startup or on reconnect. The store pulls exclusions from `ExcludedProjectStore` on the receiver's start/reload (receiver-side), not via an explicit push.

## Q5: Test coverage of the excluded-titles round trip

### Findings
- `SingleThreadTests/SkippedReminderSyncServiceTests.swift` — three excluded-related tests, all unit-scoped to the service, using a `FakeSession`:
  - `pushExcludedProjectTitlesUpdatesApplicationContext` (`SkippedReminderSyncServiceTests.swift:309-321`) — asserts payload: `#expect(Set(titles) == ["Work", "Home"])` for `context["excludedProjectTitles"]` on `fake.lastContext`. Covers **push payload inspection** only.
  - `receiveContextReplacesLocalExcludedTitles` (`SkippedReminderSyncServiceTests.swift:322-336`) — feeds `didReceiveApplicationContext: ["excludedProjectTitles": ["B","C"]]`, asserts `Set(excludeStore.load()) == ["B","C"]`. Covers **receive-then-save persistence to UserDefaults** only.
  - `receiveContextMissingExcludedTitleKeyIsNoOp` (`:338-351`) — skip-only payload, asserts `excludeStore.load() == ["A"]` unchanged. Covers independent-key no-op.
- `SingleThreadTests/ExcludedProjectStoreTests.swift` — persistence-level tests for `load/save/replace/clear/isolation` (empty roundtrip `:8-11`, roundtrip `:14-17`, replace `:21-24`), but these never touch `SkippedReminderSyncService` or `ReminderStore`.
- `ReminderStoreTests.swift`:
  - `visibleRemindersFiltersOutExcludedProjectTitles` (`:75-92`), `visibleRemindersKeepsNilCalendarReminders` (`:93-101`), `visibleRemindersEmptyWhenAllProjectsExcluded` (`:102-110`) — these construct a store with `excludedProjectTitles` seeded via the preview init and assert on `visibleReminders`. They cover **filtering given an already-in-memory set**, not the receive→store round trip, and they bypass `SkippedReminderSyncService`.
  - `setExcludedProjectTitlesPersistsAndFiresHooks` (`:124-140`) — asserts in-memory value, `excludeStore.load()`, and both hooks (`changedTitles`, `remindersChanged`) fire. Again no sync-service involvement.
  - `reload*` guards (`:344-375`) cover reload-from-EventKit / `loadsReminders:false` behavior; none asserts `reload()` refreshing `excludedProjectTitles` from `ExcludedProjectStore`.
- **Gap (documented as fact):** No test composes the sync layer with the store layer. There is no test that (1) receives `excludedProjectTitles` into a `SkippedReminderSyncService` whose `excludeStore`/`ReminderStore` are shared, and (2) asserts the counterpart's live `visibleReminders` re-filters. The receive-side unit tests all assert only on `excludeStore.load()` (`SkippedReminderSyncServiceTests.swift:334`), not on any delivered `ReminderStore` state or hook. No UI test covers excluded projects (search of `SingleThreadUITests/**` and `SingleThreadWatchUITests/**` returns zero matches for "exclude" / "project").

## Cross-Cutting Observations
- The `SkippedReminderSyncService` abstracts `WCSession` behind the `SkipSyncSession` mockable protocol (`SkippedReminderSyncService.swift:11-21`), yet all receive-path tests still call the delegate method with `WCSession.default` directly rather than a mock session, so the receive tests only exercise the persistence branch (`excludeStore.save`), never a store mutation.
- The catalog of receive "do something" keys on the service is restricted to: `skippedReminderIdentifiers` (skipStore.save), `excludedProjectTitles` (excludeStore.save), `showUndatedReminders` (hook), `sortOption` (store.save + hook), `showDate` (showDateStore). Each is key-gated. `excludedProjectTitles` is the only membership-change key that lands purely in UserDefaults with **no** in-memory-notifying hook.
- `setExcludedProjectTitles` (ReminderStore) both persists and fires `onExcludedProjectsChanged`; the service receive slope only saves — the two updates share `excludeStore` but not store mutation semantics.
- Watch and phone app-sides both wire `onExcludedProjectsChanged → pushExcludedProjectTitles` symmetrically (`SingleThreadApp.swift:52`, `SingleThreadWatchApp.swift:43`), meaning a watch-side toggle also emits a single-key push to the phone; the phone receive path would have the same dormant-behavior gap (no store reload/hook for exclusions on iOS either — iOS only wires `onCompleteReminderReceived`/`onDeleteReminderReceived`).
- User-set-excluded `setExcludedProjectTitles` fires `onRemDemoChanged` after `onThreadAndroidChanged`, so the phone re-renders locally; the watch's received `excludeStore` has no such re-render — it waits for the next reload.

## Open Areas
- Whether WCSession's documented "auto-delivery on (re)connect" re-delivers the *last single-key context* (only exclusions) or the original combined context on the watch; the service code trusts re-delivery semantics but never pushes a full snapshot at startup, so a watch that reconnects after a phone-only-exclusion push receives only the last context dict it was sent (which, if `excludedProjectTitles` was the last push, carries no skip/sort/showDate).
- Whether the phone's body `.task` (`ContentView.swift:87-91`) and watch's `.task` (`WatchReminderView.swift:43`) guarantee a `start()`→`reload()` that pulls exclusions from UserDefaults shortly after launch for its own store — that covers local init, but not live peer- received changes.
- The test count: no UI or integration-level round trip; actual WatchConnectivity end-to-end behavior is exercised only via the delegate-object-level unit tests, so real-device `WCSession` delivery decisions are untested.
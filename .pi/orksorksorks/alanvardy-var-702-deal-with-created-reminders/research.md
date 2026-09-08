# Research Findings

Branch: `alanvardy-var-702-deal-with-created-reminders`

## Q1: Which test suites instantiate a real `EKEventStore`/`EKReminder`, which code paths call `save`/`addReminder`, and under what authorization could writes land in a real Reminders DB?

### Findings
- `ReminderStore` owns the only EventKit write surface, behind the `EventKitStoring` seam.
  - Production init defaults to a **real** store: `eventStore: any EventKitStoring = EKEventStore()` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:13-19`).
  - The pre-populate init (`loadsReminders:reminders:skippedIDs:authorizationStatus:...`) hardcodes `eventStore = EKEventStore()` (`ReminderStore.swift:38`) — it does **not** accept an injected fake.
- Write paths (`#if !os(watchOS)`): `completeReminder` → `eventStore.save(commit: true)` (`ReminderStore.swift:149`), `deleteReminder` → `eventStore.remove(commit: true)` (`ReminderStore.swift:175`), `addReminder` → `makeReminder(...)` + `save(commit: true)` (`ReminderStore.swift:194-208`). Each is followed by `Task.sleep(eventKitSettleDelay)` then `reload()` (`ReminderStore.swift:150,176,209`; delay at `:351`).
- Only authorization API used anywhere is full access (`requestFullAccessToReminders`, `.fullAccess`, `ReminderStore.swift:333-341`); no `requestWriteOnlyAccessToReminders` exists in the repo. Saves do not re-check authorization; they hit whatever backing store is present.
- **Real-store + real-save path (the only one):** `SingleThreadTests/ReminderStoreTests.swift` uses the pre-populate init throughout → every instance backs onto a real `EKEventStore()`. These tests invoke writes against it with no fake injection:
  - `addReminderDoesNotCrashWithoutAccess` (`ReminderStoreTests.swift:221,225`)
  - `addReminderReturnsFalseWithoutAccess` (`:236,238`)
  - `addReminderKeepsExistingRemindersUntouched` (`:244,250`)
  - `addReminderWithRecurrenceRuleDoesNotCrash` (`:256,259`)
  - `completeCurrentReminderDoesNotCrashWithVisibleReminder` (`:337,345`) → save at `ReminderStore.swift:149`
  - A code comment acknowledges macOS hosts may already hold Reminders access so the no-access path can't be exercised deterministically (`ReminderStoreTests.swift:231-235`); saves can land in the real DB when the host process already holds `.fullAccess`. With `loadsReminders: false`, `start()` never runs and no TCC prompt is raised by the test itself.
- **Fake-injected unit tests:** `EventKitStoringTests.swift` write tests inject a recording `FakeEventStore` (`EventKitStoringTests.swift:8-98`) via `testStore(eventStore:)` (`:455-461`); their saves/removes never touch EventKit.
- **UI tests:** all `--seed '<json>'` flows back the app with `InMemoryEventStore` (`SingleThreadApp.swift:113-132`) — complete/delete flows run in memory only. `--ui-testing` / `--no-reminders` launches build a real `EKEventStore()` + one hardcoded `EKReminder("Buy groceries")` but with `loadsReminders: false` and never trigger a write path (`SingleThreadApp.swift:135-153`; `SingleThreadUITestsFlows.swift:105-108,130-148`; appearance tests use `--no-reminders`, `SingleThreadUITestsAppearanceLaunchTests.swift:24,56,92`).
- **Watch:** on watchOS `addReminder` returns `false` immediately and complete/delete take read-only local-mutation branches (`ReminderStore.swift:142-147,169-173,198-200`); watch UI tests (`--ui-testing`, `SingleThreadWatchApp.swift:98+`) therefore cannot write to a Reminders DB at all.

## Q2: How is `EventKitStoring` designed, what does `InMemoryEventStore` implement vs omit, where do tests fall back to the real store?

### Findings
- Protocol declared at `SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:8-42`: `@MainActor public protocol EventKitStoring: AnyObject` with requirements `authorizationStatus(for:)` (:10), `calendars(for:)` (:12), `requestFullAccessToReminders()` (:14), `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` (:16-21), `fetchReminders(matching:completion:) -> Any` (:22-25); gated behind `#if !os(watchOS)` (:26): `refreshSourcesIfNecessary()` (:27), `save(_:commit:)` (:29-31), `remove(_:commit:)` (:33-35, deletes whole series), `makeReminder(title:notes:dueDate:recurrenceRule:)` (:37-41).
- Production conformance `extension EKEventStore: EventKitStoring` lives in the same file (`EventKitStoring.swift:45`); only `authorizationStatus` (:46-48) and `makeReminder` (:51-63) get explicit bodies — the rest inherit SDK methods. `makeReminder` sets `reminder.calendar = defaultCalendarForNewReminders()` (`:60`).
- `InMemoryEventStore` (`InMemoryEventStore.swift:13`) implements **all** protocol requirements — no conformance gap:
  - `authorizationStatus` → hardcoded `.fullAccess` (:33-35); `requestFullAccessToReminders` → `true` (:41-43)
  - `fetchReminders` ignores the predicate entirely, returns `allReminders.filter { !$0.isCompleted }` (:53-79) — post-fetch filtering happens in `ReminderStore.reload()`
  - `save` appends to `allReminders` (:83-85); `remove` filters by `calendarItemIdentifier` (:87-89); both in-memory only
  - `makeReminder` constructs `EKReminder(eventStore: EKEventStore())` (a real store, for object construction only) and assigns `calendar = calendars.first` (:91-107), i.e. **not** `defaultCalendarForNewReminders()`
- **The behavioral gap:** default-calendar semantics of `makeReminder`. Tests needing that cast a real store directly — `MakeReminderTests` call `(EKEventStore() as any EventKitStoring).makeReminder(...)` at `ReminderStoreTests.swift:444,454,465,477,490,502`; `makeReminderSetsDefaultCalendar` asserts equality with `defaultCalendarForNewReminders()` (`:502-509`). No other path falls back because of an unimplemented member.
- All remaining real-`EKEventStore()` uses are fixture construction (`EKReminder`/`EKCalendar` cannot be created without a store): `ReminderStoreTests.swift:515-528`, `ReminderSkipTests.swift:330`, `ReminderDisplayTests.swift:65,97`, `ActionButtonTests.swift:95,113`, `BackgroundCardTests.swift:128`, `SkippedReminderSyncServiceTests.swift:513`, `WatchSyncPipelineTests.swift:197`; preview mocks (`ContentView.swift:569,580`, `WatchReminderView.swift:222`); `--ui-testing` seams (`SingleThreadApp.swift:139-149`, `SingleThreadWatchApp.swift:98+`); and seed materialization (`UITestingSeed.swift:95,103`).

## Q3: Teardown/cleanup patterns across test targets; CI matrix simulator-state isolation

### Findings
- **UI tests have no teardown at all.** Every UI class overrides only `setUpWithError()` setting `continueAfterFailure = false` (`SingleThreadUITests.swift:21-23`, `SingleThreadUITestsFlows.swift:16-18`, `SingleThreadUITestsLaunchTests.swift:21-23`, `SingleThreadUITestsAppearanceLaunchTests.swift:21-23`, `ActionButtonsUITests.swift:15-17`, `SingleThreadWatchUITests.swift:4-6`, `SingleThreadWatchUITestsFlows.swift:6-8`, `SingleThreadWatchUITestsLaunchTests.swift:12-14`). No `tearDown`/`deinit` exists in either UI target.
- Cleanup is seam-driven per launch: `--seed` triggers `UITestingSeed.resetPersistedState()`, which removes a fixed key list (`skippedReminderIdentifiers, excludedListTitles, showDate, showList, showUndatedReminders, sortOption, showMicrophoneButton, backgroundEnabled, allowsLandscape, textSize, appearanceMode`) from both `AppGroup.defaults` and `UserDefaults.standard` (`UITestingSeed.swift:31-42`, invoked from `SingleThreadApp.swift:118`). The two persistence-relaunch tests deliberately relaunch with `--ui-testing` rather than `--seed` to avoid wiping state under test (`SingleThreadUITestsFlows.swift:156-163,190-194`). `app.terminate()` appears only in those two tests.
- `--ui-testing` does **not** reset persisted state; it additionally writes a persistent `enableActionButtons=true` to `.standard` on iOS (`SingleThreadApp.swift:137-142`, comment notes isolation to the test destination).
- Unit tests (Swift Testing structs) clean up via per-test `defer { UserDefaults.removeObject }` blocks, e.g. `ActionButtonTests.swift:54,65,77,93`, `AppGroupTests.swift:16`, `ShowDatePreferenceTests.swift:9,17,26,35`, `MicrophoneToggleTests.swift:55,73,86`, `AppDelegateTests.swift:48`.
- No `resetAuthorizationStatus`, keychain, or `SecItem` usage exists anywhere in the repo; authorization is always injected/mocked.
- `scripts/test.sh:31-61` has `cleanup_xctest_runtimes()` — disk-space pruning of stale `$HOME/Library/Developer/XCTestDevices` dirs (>1h old) only; not state reset.
- **CI (`.github/workflows/ci.yml`):** four iOS jobs (`unit-tests`, `ui-tests-flows`, `ui-tests-launch-appearance`, `ui-tests-audits`) each run a device matrix `["iPhone 17", "iPad (A16)"]` on `macos-26` runners — each matrix cell is an independent VM, so no state sharing across jobs. Each job boots the image's **pre-provisioned** simulator by name (`simctl boot` + `bootstatus`, ci.yml:50-52,111-113,171-173,229-231); no `create`/`erase` for iOS. Freshness comes from the fresh VM, not simulator recreation.
- UI suites disable parallel clones explicitly: `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -maximum-test-execution-time-allowance 900` (ci.yml:137,195,255) due to instruments lockdown timeouts on virtualized runners; suites are split into disjoint `-only-testing` groups (A: Launch/AppearanceLaunch, B: Flows, C: SingleThreadUITests+ActionButtons) defined in one shared `env` block. The unit job has no parallel flags.
- **Watch is the exception:** `watch-ui-tests` creates a standalone simulator per run (`xcrun simctl create "CI Watch S11" ...`, ci.yml:389-396).
- DerivedData is cached via `actions/cache` (build products only, no simulator data).

## Q4: How does `ReminderStore.addReminder` construct/persist an `EKReminder`; what fetch/remove APIs exist?

### Findings
- `addReminder(title:notes:dueDate:recurrenceRule:) async -> Bool` at `ReminderStore.swift:194-215`: returns `false` on watchOS (:198-200); otherwise `eventStore.makeReminder(...)` (:199-204) → `eventStore.save(reminder, commit: true)` (:206) → settle sleep + `reload()` (:207-208) → `true`; on throw logs `"Failed to add reminder"` and returns `false` (:209-212).
- Real construction in `extension EKEventStore` (`EventKitStoring.swift:51-63`): creates `EKReminder(eventStore: self)` (:53), sets `title` (:55), `notes` (:56), `dueDateComponents` (:57), adds `recurrenceRule` if non-nil (:58-60), sets `calendar = defaultCalendarForNewReminders()` (:63). **Not set:** priority, startDateComponents, alarms, url, location, or explicit source.
- Fetch APIs: only predicate-based — `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` (`EventKitStoring.swift:16-21`) and `@discardableResult fetchReminders(matching:completion:) -> Any` (:22-25), bridged by `ReminderStore.reload(clearSkipped:)` (`ReminderStore.swift:469`, bridge at `:527`). There is **no** fetch-by-title or fetch-by-creation-date API on `EventKitStoring` or `ReminderStore`.
- Remove/complete APIs are identifier-only: `deleteReminder(identifier:)` looks up by `calendarItemIdentifier` and calls `eventStore.remove(_:commit:)` (`ReminderStore.swift:168,175`); `completeReminder(identifier:)` marks completed and saves (`:141,149`). All lookups key on `EKReminder.calendarItemIdentifier`. `deleteCurrentReminder()`/`completeCurrentReminder()` wrap these (`:195-197,231-233`).
- Other relevant `ReminderStore` API: `skipCurrentReminder()` (`:419`), `setSortOption(_:)` (`:426`), `skipCurrentReminderImmediately()` (`:438`), `setExcludedListTitles`/`refreshExcludedListTitles` (`:508,520`).

## Q5: `--seed` / `--ui-testing` launch-arg seams; applicability to watch/widget/unit tests

### Findings
- **iOS trace:** `SingleThreadApp.init()` reads `ProcessInfo.processInfo.arguments` → `Self.makeStore(arguments:)` (`SingleThreadApp.swift:19,116-163`):
  - `--seed '<json>'` → `UITestingSeed.fromLaunchArguments` decodes JSON and `materialize()`s fixtures off a scratch `EKEventStore()` (`UITestingSeed.swift:27-39,94-117`); calls `resetPersistedState()`; builds `InMemoryEventStore(reminders:calendars:)`; wraps in `ReminderStore(eventStore:, loadsReminders: true)`; applies `seed.excludedListTitles` (`SingleThreadApp.swift:117-126`); sets `usesInMemoryStore = true`, which also gates WatchConnectivity activation (`SingleThreadApp.swift:21,25`).
  - `--ui-testing` → real `EKEventStore()` + hardcoded reminder through the **pre-populate init**, not `InMemoryEventStore` (`SingleThreadApp.swift:137-150`).
  - Default → `ReminderStore(loadsReminders: loads)` where `loads` is false for `--ui-testing`/`--no-reminders` (`SingleThreadApp.swift:151-162`).
- **Watch:** same shape minus `--seed` — `SingleThreadWatchApp.init()` branches on `--ui-testing` into `uiTestingStore(arguments:)`, which uses the pre-populate init with a real `EKEventStore()` plus `--ui-testing-excluded-list` / `--ui-testing-live-excluded` flags and a delayed WatchConnectivity context injection (`SingleThreadWatchApp.swift:11-17,97-135,158-162`). `InMemoryEventStore` compiles on watchOS but drops `save`/`remove`/`makeReminder` under `#if !os(watchOS)` (`InMemoryEventStore.swift:68`) — nothing structural prevents using it there, it just isn't wired.
- **Widget:** no seam. `NextThingWidget.makeEntry()` always builds `ReminderStore(loadsReminders: true)` per timeline refresh after checking real authorization status (`NextThingWidget.swift:59-62`); widget extensions don't receive host-app launch arguments and nothing in `SingleThreadWidget/` reads `ProcessInfo`.
- **Unit-test initialization patterns:**
  - Pattern A — `eventStore:` injection with a fake: `ReminderStoreTests.swift:367-368` (`InMemoryEventStore(reminders:, deliverCompletionOffMain:true)`), `UITestingSeedTests.swift:53-57` (mirrors app wiring + `start()`), and `EventKitStoringTests.swift:463-467` helper injecting the recording `FakeEventStore`.
  - Pattern B — pre-populate init (`loadsReminders:false, reminders:...`, internally still a real `EKEventStore()`): used pervasively (`ReminderStoreTests.swift:14,27,...`; `ActionButtonTests.swift:79,98,117`; etc.). It takes **no** eventStore parameter (`ReminderStore.swift:24-39`).

## Cross-Cutting Observations
- Two distinct deterministic-testing mechanisms coexist: the **`--seed` → `InMemoryEventStore` injection** (full write-capable fake, iOS only) and the **pre-populate init** (real store underneath, `loadsReminders: false`, render-only). `--ui-testing` on both platforms uses the latter.
- The pre-populate init cannot accept an event store (`ReminderStore.swift:24-39` hardcodes `EKEventStore()`), which is why `ReminderStoreTests` add/complete tests run against a real store — the single place test-driven `eventStore.save` can reach a real Reminders DB (host must already hold `.fullAccess`; acknowledged at `ReminderStoreTests.swift:231-235`).
- On watchOS EventKit is strictly read-only in this codebase (`#if os(watchOS)` branches in `completeReminder`/`deleteReminder`/`addReminder`); watch tests physically cannot persist to Reminders.
- CI isolation relies on per-job fresh VMs + launch-argument seams, not simulator erasure; iOS simulators are pre-provisioned and booted, the watch sim is created fresh each run.
- No keychain usage exists; App Group defaults are reset only via `resetPersistedState()` on `--seed` launches.

## Open Areas
- No test today exercises `InMemoryEventStore`'s `makeReminder` calendar behavior vs the real store's `defaultCalendarForNewReminders()` beyond `MakeReminderTests` on the real store (`ReminderStoreTests.swift:502-509`).
- Whether GitHub-hosted `macos-26` runner users/granted Reminders TCC grants persist across VM images was not determinable from the repo (runtime environment question, not a code fact).
- Widget timeline testing does not exist in any target; no widget UI/unit tests were found.

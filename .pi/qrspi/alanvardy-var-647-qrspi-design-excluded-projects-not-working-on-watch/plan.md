# Implementation Plan

## Overview

Fix the receive/refresh gap in `SkippedReminderSyncService`: a pushed `excludedProjectTitles`
payload currently lands only in the receiver's `ExcludedProjectStore` (UserDefaults) and is never
pushed into the live in-memory `ReminderStore.excludedProjectTitles`, so the counterpart's
`visibleReminders` never re-filters. Mirror the existing `showUndatedReminders` hook pattern: fire a
new service hook after `excludeStore.save(...)`, wire both app layers to a new non-pushing store
refresh, and cover the store→UI half with a watch UI test. This change is **receive-only** — the
receive path must NOT call `setExcludedProjectTitles` (which fires `onExcludedProjectsChanged` and
would echo a push back to the sender).

---

## Phase 1: Received-exclusion round trip through the model layer

Delivers the end-to-end receive→re-render behavior at the store/service boundary: a received
exclusion payload is saved, surfaced through the new hook, refreshed into the in-memory set, and
`visibleReminders` re-filters — without refetching EventKit and without pushing back to the sender.

### Changes

#### 1. `SkippedReminderSyncService` — new receive hook
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

Add the hook property in the existing hook block (near `onShowUndatedRemindersReceived`,
`SkippedReminderSyncService.swift:66-75`), with the same write-once-before-`activate()` /
`nonisolated(unsafe)` doc rationale:

```swift
/// Hook invoked on the counterpart watch/phone when excluded-project titles
/// arrive in an application context. Passes the received title array. Same
/// write-once-before-activate / `nonisolated(unsafe)` rationale as
/// `onShowUndatedRemindersReceived`.
public nonisolated(unsafe) var onExcludedProjectTitlesReceived: (([String]) -> Void)?
```

In `session(_: WCSession, didReceiveApplicationContext:)`, extend the existing
`excludedProjectTitles` branch (currently `excludeStore.save(receivedTitles)` only) to fire the new
hook after saving. Keep the branch key-gated (`if let` cast); an absent key stays a no-op:

```swift
if let receivedTitles = applicationContext[PayloadKey.excludedProjectTitles] as? [String] {
    excludeStore.save(receivedTitles)
    let handler = onExcludedProjectTitlesReceived
    handler?(receivedTitles)
}
```

> Reads `let handler` into a local first (mirrors the `showUndatedReminders`/`sortOption` branches)
> so a concurrent hook reassignment cannot produce a torn read.

#### 2. `ReminderStore` — new non-pushing refresh primitive
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add a new `@MainActor` public method alongside `setExcludedProjectTitles`
(`ReminderStore.swift:311`, below `setExcludedProjectTitles`). It assigns the `@Observable` `excludedProjectTitles` set from the
wire-provided titles and fires `onRemindersChanged?()`. It deliberately does **not** fire
`onExcludedProjectsChanged` — that would route back through the app's emit wiring and echo a push to
the sender.

```swift
/// Refreshes the live excluded-project set from titles received over
/// WatchConnectivity. Does NOT fire `onExcludedProjectsChanged`, so
/// the receive path never echoes a push back to the sender (that hook is only
/// for local `setExcludedProjectTitles` changes).
public func refreshExcludedProjectTitles(_ titles: Set<String>) {
    excludedProjectTitles = titles
    onRemindersChanged?()
}
```

Do **not** route the receive path through `setExcludedProjectTitles` (no echo). Do **not** call full
`reload()` on receive (heavy EventKit refetch + skip pruning for a change that only needs the
in-memory exclusion set).

#### 3. `ReminderStoreTests` — unit test for the new primitive
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Add a `@Test` under a new `// MARK: - refreshExcludedProjectTitles` section (near the existing
`setExcludedProjectTitles` section at `ReminderStoreTests.swift:124-140`):

```swift
@Test
func refreshExcludedProjectTitlesUpdatesSetAndFiresRemindersChangedOnly() {
    let store = ReminderStore(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    var remindersChanged = false
    var excludedChanged = false
    store.onRemindersChanged = { remindersChanged = true }
    store.onExcludedProjectsChanged = { _ in excludedChanged = true }

    store.refreshExcludedProjectTitles(["Work"])

    #expect(store.excludedProjectTitles == ["Work"])
    #expect(remindersChanged)
    #expect(!excludedChanged)
}
```

#### 4. `SkippedReminderSyncServiceTests` — composition test
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify

Add a composition test in the existing `// MARK: - Excluded-Project push/receive` section
(`SkippedReminderSyncServiceTests.swift:307-351`) that links a service + shared `ReminderStore`,
wires the receive hook directly to the store (the app-layer wiring being tested), feeds a received
context, and asserts the store's `visibleReminders` re-filters. Add it after
`receiveContextMissingExcludedTitleKeyIsNoOp`:

```swift
@Test
func receivedExclusionRefreshFiltersVisibleReminders() {
    let fake = FakeSession()
    let store = ReminderStore(
        loadsReminders: false,
        reminders: [
            inProjectReminder(title: "A", project: "Work"),
            inProjectReminder(title: "B", project: "Personal")
        ],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "test-excl-comp-skip-\(UUID().uuidString)"),
        excludeStore: ExcludedProjectStore(defaults: .standard, key: "test-excl-comp-excl-\(UUID().uuidString)"))
    // Wire the service's receive hook into the shared store, mirroring the app-layer wiring.
    service.onExcludedProjectTitlesReceived = { titles in
        store.refreshExcludedProjectTitles(Set(titles))
    }

    #expect(Set(store.visibleReminders.map(\.title)) == ["A", "B"]) // both visible before

    service.session(
        WCSession.default,
        didReceiveApplicationContext: ["excludedProjectTitles": ["Work"]])

    #expect(Set(store.visibleReminders.map(\.title)) == ["B"]) // "A" (Work) filtered
    #expect(Set(store.excludedProjectTitles) == ["Work"])
}
```

Add a file-scope fixture inside the `#if os(iOS) || os(watchOS)` block (the file's fixtures are
file-private, so a distinct name avoids colliding with `ReminderStoreTests.makeReminder`):

```swift
/// Builds a reminder that lives in a calendar titled `project`, so exclusion
/// filtering (which matches `calendar.title`) can be exercised.
private func inProjectReminder(title: String, project: String) -> EKReminder {
    let eventStore = EKEventStore()
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = title
    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = project
    reminder.calendar = calendar
    return reminder
}
```

This test does not require a `WCSession` because the receive delegate is invoked directly on the test
actor (exactly like the existing receive tests, which pass `WCSession.default`).

### Verification

#### Automated
- [x] `make test` passes (unit tests / Swift Testing) — covers `refreshExcludedProjectTitles` updates the set, fires `onRemindersChanged?()`, does **not** fire `onExcludedProjectsChanged`.
- [x] `make test` passes — composition test proves a received `excludedProjectTitles` context round-trips through the service hook into the store and re-filters `visibleReminders` (no EventKit refetch, no echo).
- [x] `make build` succeeds (SPM `SingleThreadCore` package recompiles with the new primitive and hook).

#### Manual
- [ ] Sanity: `excludedProjectTitles` receive empty list `[]` still propagates as a "clear" (guard produces no crash; store set becomes empty).

---

## Phase 2: Wire the hook into both app layers

Delivers the live end-to-end connection: a peer's exclusion push now re-renders the local
`visibleReminders` on **both** iPhone and watch (the phone had the same dormant gap — iOS currently
wires no exclusion receive handler at all).

### Changes

#### 1. iOS app — wire `onExcludedProjectTitlesReceived`
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

Inside the `#if os(iOS)` / `if WCSession.isSupported(), !usesInMemoryStore` block, after the
`onDeleteReminderReceived` wiring and **before** `service.activate()` (the write-once-before-activate
invariant), add:

```swift
// Receive-side: a watch exclusion toggle arrives and re-filters the local list.
service.onExcludedProjectTitlesReceived = { [weak store] titles in
    store?.refreshExcludedProjectTitles(Set(titles))
}
```

Do **not** change the existing emit wiring `store.onExcludedProjectsChanged = { titles in
service.pushExcludedProjectTitles(titles) }` (`SingleThreadApp.swift:52`).

#### 2. Watch app — wire `onExcludedProjectTitlesReceived`
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

Inside the `if WCSession.isSupported()` block, next to `onShowUndatedRemindersReceived` and **before**
`service.activate()`, add the identical closure:

```swift
// A phone-side exclusion toggle arrives and re-filters this watch's live list.
// Same write-once-before-activate invariant as onShowUndatedRemindersReceived.
service.onExcludedProjectTitlesReceived = { [weak store] titles in
    store?.refreshExcludedProjectTitles(Set(titles))
}
```

`[weak store]` keeps the retain-cycle discipline; `store?.` (optional chaining) resists a
deallocated store. Do **not** change the emit wiring `store.onExcludedProjectsChanged = { titles in
service.pushExcludedProjectTitles(titles) }` (`SingleThreadWatchApp.swift:43`).

### Verification

#### Automated
- [ ] `make build` builds iOS scheme (iPhone 17) with the new closure.
- [ ] `make watch-build` builds watch scheme.
- [ ] `./scripts/test.sh` full CI passes (format, lint, build, watch build, periphery, unit + UI + watch UI tests, macOS build/test).

#### Manual
- [ ] On a real iPhone 17 + Apple Watch simulator pair: toggle a project exclusion **on the phone** and confirm the **watch's** card disappears immediately — no relaunch, no shows-undated key, no pull-to-refresh.
- [ ] Toggle a project exclusion **on the watch** and confirm the **phone's** list re-filters.
- [ ] Confirm the toggling device itself still shows its own exclusion immediately (local `setExcludedProjectTitles` path unaffected).
- [ ] In the PR, flag that end-to-end receive→UI is not unit-provable without a `WCSession` mock seam.

---

## Phase 3: Watch UI regression test for exclusion filtering

Proves the store's live exclusion set drives the on-screen results on the watch, guarding the
Phase 1 store behavior at the UI layer. (The receive→UI gap is covered by Phase 1's composition
test; this covers the store→UI half.)

> **Deviation from structure**: "excludes it through the store" is not feasible at the watch UI
> layer — there is no `WCSession` mock (out of scope) and no watch settings UI for toggling
> exclusions. Instead the `--ui-testing` seam is extended with an optional launch arg that gates a
> store whose sample reminder belongs to a project that is **also pre-excluded in the store**, and the
> test asserts that project's card does not render. This touches `SingleThreadWatchApp.swift` (already
> a Phase 2 file) via a small, additive seam — not a refactor of existing behavior.

### Changes

#### 1. Watch `--ui-testing` seam — seed an excluded project
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

Change `uiTestingStore()` to accept the launch arguments and, when `--ui-testing-excluded <project>`
is present, place the sample reminder in a calendar of that title and pre-populate the store's
`excludedProjectTitles`. Update the single call site in `init()` to pass `arguments`.

```swift
private static func uiTestingStore(arguments: [String]) -> ReminderStore {
    let eventStore = EKEventStore()
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = "Buy groceries"
    reminder.priority = 5
    reminder.notes = "Don't forget the milk"
    // --ui-testing-excluded "<project>" gives the sample reminder a calendar of
    // that title and pre-populates the store's exclusion set, so an XCTest can
    // assert a project's current card is suppressed (store's live exclusion set
    // drives the rendered result).
    if let index = arguments.firstIndex(of: "--ui-testing-excluded"),
       index + 1 < arguments.count {
        let project = arguments[index + 1]
        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = project
        reminder.calendar = calendar
        return ReminderStore(
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            excludedProjectTitles: [project])
    }
    return ReminderStore(
        loadsReminders: false,
        reminders: [reminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
}
```

And update the call site in `init()`:

```swift
let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
let store: ReminderStore = if isUITesting {
    Self.uiTestingStore(ProcessInfo.processInfo.arguments)
} else {
    ReminderStore(loadsReminders: true)
}
```

(Keep all existing behavior when `--ui-testing-excluded` is absent so the other watch UI/launch tests
still see "Buy groceries".)

#### 2. New XCTest for exclusion filtering
**File**: `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`
**Action**: modify (add one `@MainActor` test, style-matching the existing `launchApp()` tests).

```swift
@MainActor
func testExcludedProjectDoesNotRenderReminder() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-excluded", "Work"]
    app.launch()

    // The seeded reminder lives in the excluded "Work" project, so its card must
    // not render — "Buy groceries" stays concealed. With nothing visible, the
    // watch shows the All Done state (visibleReminders empty but reminders non-empty).
    XCTAssertFalse(
        app.staticTexts["Buy groceries"].waitForExistence(timeout: 3),
        "Excluded project should suppress the reminder card")
    XCTAssertTrue(
        app.staticTexts["All Done"].waitForExistence(timeout: 5),
        "With the only reminder excluded, the All Done state should show")
}
```

(Optional: also assert the absence is not merely an empty store by asserting the "All Done" state,
which only appears when `reminders` is **non-empty** but none are visible — that is what guards the
exclusion-filtering path specifically.)

Place it in the `// MARK: - View` section. No other watch UX test is affected (they launch with
`--ui-testing` only, so the default seam path is preserved).

### Verification

#### Automated
- [ ] `make watch-ui-test` passes (runs `-only-testing:SingleThreadWatchUITests` against `WATCH_TEST_SIM`).
- [ ] Existing watch UI tests (`testCardShowsReminderTitleAndNotes`, `.testLaunch`, accessibility audit) still pass — the default seam path is unchanged.
- [ ] `./scripts/test.sh` full CI is green (including accessibility audit in `SingleThreadUITests`).

#### Manual
- [ ] Launch the watch app with `--ui-testing --ui-testing-excluded "Work"` and confirm "Buy groceries" does not render and the "All Done" state appears; launch a second time without the arg to confirm "Buy groceries" still renders (guards the seam's default path).

---

## Testing Checkpoints

- **After Phase 1** — composition unit test proves a received-exclusion round-trips through the
  service hook into the store and re-filters `visibleReminders` (no EventKit refetch, no echo), and
  the new `refreshExcludedProjectTitles` primitive is isolated. The SPM package rebuild compiles.
- **After Phase 2** — iOS and watch builds succeed; iPhone and watch Apps each wire
  `onExcludedProjectTitlesReceived` before `activate()`; no regression in the full `./scripts/test.sh`.
- **After Phase 3** — the watch UI test asserts a seeded excluded project's card does not render; full
  CI (`./scripts/test.sh`) is green.

## Resume Note / Constraints

- This change is **receive-only**. Never route the receive path through `setExcludedProjectTitles`,
  or an echo loop forms (`setExcludedProjectTitles` → `onExcludedProjectsChanged` → push back to sender).
- The service remains store-agnostic — it exposes a hook and relies on the app layer to refresh the
  store. No `ReminderStore` reference is held in `SkippedReminderSyncService`.
- Do not call full `reload()` on receive; the targeted `refresh` covers the in-memory set only.
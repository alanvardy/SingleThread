# Implementation Plan

**Ticket**: VAR-978 — reschedule not working on watch
**Branch**: `alanvardy-var-978-reschedule-not-working-on-watch`
**Artifact dir**: `/Users/vardy/dev/alanvardy-var-978-reschedule-not-working-on-watch/.pi/orksorksorks/alanvardy-var-978-reschedule-not-working-on-watch/`

## Overview

Work bottom-up through the reschedule chain's four layers: make the transport seam
reachability-aware (send **or** queue, applied uniformly to complete / delete /
reschedule), make the watchOS store relay return a truthful outcome, extract the
watch confirm logic into a testable view-model method that refreshes on success and
exposes failure, then render that outcome in the sheet. The iOS EventKit write and
the date-only wire semantics are never touched.

### Deviations from `structure.md` (called out deliberately)

1. **No `AppViewModel.init(arguments:session:)` seam (Stage 1).** The hop-6 test drives
   the *existing* `AppViewModel.syncService` instance directly
   (`service.session(WCSession.default, didReceiveMessage:)`), exactly like the existing
   `RescheduleSyncTests` do. Injecting `(any SkipSyncSession)?` into `AppViewModel.init`
   would force a `#if os(iOS)`-conditional initializer (the protocol does not exist on
   macOS) or an `Any?` production parameter, and gives no extra evidence — the closure
   assignment under test lives on the service the app already built. Fewer production
   changes, same hop-6 coverage.
2. **`FakeSession.errorToThrow` is used, not vestigial.** It backs one guard test
   (`rescheduleDoesNotQueueAfterSendError`) that proves the "exactly one delivery per
   attempt" invariant in the error path. If that test is dropped during implementation,
   drop the property too.
3. **`confirmReschedule()` closes the sheet *before* `await refresh(...)`.** The refresh
   enforces a 1 s minimum display duration; closing first means the user sees the sheet
   dismiss immediately and the list update behind it. Structure only required "refresh on
   success"; the order is a UX call, not a contract change.

### Sanctioned red-first handoff

- The **symptom-level** evidence is the paired-simulator repro (Stage 1, manual).
- The **unit-level red** is `rescheduleRelaysWhenPhoneUnreachable` (Stage 1, hop 3,
  expected RED against current code). Stage 2 must not start until that red is captured.
- The Stage 3/4 tests are green-first at the hop they add (`onRescheduleReminder` has no
  `Bool` today, so `confirmReschedule` cannot compile against current code — the red is a
  compile failure, captured in the PR body).

---

## Phase 1 (Stage 1): Test seams + hop-level diagnostic matrix

Make every unit-testable hop observable, add the reachability/queue surface all later
stages assert against, add the missing hop-1/hop-6 coverage, and capture the one red.

### Changes

#### 1. `SingleThreadTests/TestFixtures.swift` — extend `FakeSession`
**Action**: modify (`#if os(iOS) || os(watchOS)` block, ~line 66)

```swift
final class FakeSession: SkipSyncSession {
    var activated = false
    var lastContext: [String: Any]?
    var lastMessage: [String: Any]?
    var pushShouldThrow = false

    /// Reachability the production request path branches on. Defaults to the
    /// happy path so every pre-existing test keeps taking `sendMessage`.
    var isReachable = true
    /// Recorded `transferUserInfo` deliveries (the unreachable fallback).
    var queuedUserInfo: [[String: Any]] = []
    /// When set, `sendMessage` reports it through `errorHandler` synchronously.
    var errorToThrow: (any Error)?

    func activate() { activated = true }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        if pushShouldThrow { throw NSError(domain: "test", code: 1) }
        lastContext = applicationContext
    }

    func sendMessage(
        _ message: [String: Any],
        replyHandler _: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?) {
        lastMessage = message
        if let errorToThrow { errorHandler?(errorToThrow) }
    }

    /// Present at Stage 1 so the red test compiles; promoted to a
    /// `SkipSyncSession` requirement in Stage 2.
    func queueUserInfo(_ userInfo: [String: Any]) {
        queuedUserInfo.append(userInfo)
    }
}
```

#### 2. `SingleThreadWatchTests/TestFixtures.swift` — extend `WatchFakeSession`
**Action**: modify (same shape as `FakeSession`)

Add `var isReachable = true`, `var queuedUserInfo: [[String: Any]] = []`,
`var lastMessage: [String: Any]?`, `var errorToThrow: (any Error)?`, and a
`queueUserInfo(_:)` that appends. Change `sendMessage` to record
`lastMessage = message` and call `errorHandler?(errorToThrow)` when set.

#### 3. `SingleThreadTests/RescheduleSyncTests.swift` — hop-3 red test
**Action**: modify

```swift
@Test
func rescheduleRelaysWhenPhoneUnreachable() {
    let fake = FakeSession()
    fake.isReachable = false
    let suffix = UUID().uuidString
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-unreachable-\(suffix)"))

    service.requestRescheduleReminder(
        identifier: "ABC",
        dueDateComponents: DateComponents(year: 2027, month: 1, day: 2))

    // RED against current code: the request is dropped on the floor instead of
    // being queued for delivery on reconnect/relaunch.
    #expect(fake.queuedUserInfo.count == 1)
    #expect(fake.lastMessage == nil)
}
```

`requestRescheduleReminderSendsMessage` / `requestRescheduleOmitsNilComponents` /
`receiveRescheduleReminderFiresHook` / `receiveMessageWithoutRescheduleKeyIsNoOp` are
re-run untouched (they exercise the reachable path, which must stay `sendMessage`).

#### 4. **New** `SingleThreadTests/AppViewModelSyncWiringTests.swift` — hop 6
**Action**: create

```swift
#if os(iOS)
    import SingleThreadCore
    @testable import SingleThread
    import Testing
    import WatchConnectivity

    /// Hop 6: the phone's `onRescheduleReminderReceived` → `ReminderStore` wiring
    /// that `AppViewModel.setupSyncService` installs, driven through the service's
    /// real delegate entry point. `--ui-testing` builds an `InMemoryEventStore`-backed
    /// store (one "Buy groceries" reminder, `loadsReminders: false`) while leaving
    /// `usesInMemoryStore == false`, so the live sync service is wired.
    ///
    /// Serialized: `--ui-testing` writes `AppGroup.defaults["enableActionButtons"]`
    /// and a `.standard` swipe-prompt key.
    @MainActor
    @Suite(.serialized)
    struct AppViewModelSyncWiringTests {
        @Test
        func rescheduleMessageReachesStoreThroughWiring() async throws {
            let appViewModel = AppViewModel(arguments: ["--ui-testing", "--ui-testing-noop-settle"])
            let service = try #require(appViewModel.syncService)
            let store = appViewModel.store
            let reminder = try #require(store.reminders.first)
            let identifier = reminder.calendarItemIdentifier

            service.session(
                WCSession.default,
                didReceiveMessage: [
                    "rescheduleReminderIdentifier": identifier,
                    "dueDateComponents": ["year": 2027, "month": 1, "day": 2]
                ])

            // The receive hook funnels onto MainActor through a spawned Task; pump
            // until the write lands (noop-settle removes the 200 ms production pad).
            for _ in 0 ..< 20 where store.reminders.first?.dueDateComponents?.year != 2027 {
                try await Task.sleep(for: .milliseconds(20))
            }

            #expect(store.reminders.first?.dueDateComponents?.year == 2027)
            #expect(store.reminders.first?.dueDateComponents?.month == 1)
            #expect(store.reminders.first?.dueDateComponents?.day == 2)
        }

        @Test
        func rescheduleMessageIsIgnoredWhenStoreHasNoMatchingIdentifier() async throws {
            let appViewModel = AppViewModel(arguments: ["--ui-testing", "--ui-testing-noop-settle"])
            let service = try #require(appViewModel.syncService)
            let store = appViewModel.store

            service.session(
                WCSession.default,
                didReceiveMessage: [
                    "rescheduleReminderIdentifier": "does-not-exist",
                    "dueDateComponents": ["year": 2027, "month": 1, "day": 2]
                ])

            try await Task.sleep(for: .milliseconds(50))
            #expect(store.reminders.first?.dueDateComponents == nil)
        }
    }
#endif
```

**Hop matrix** (record in the PR body):

| Hop | Coverage |
|---|---|
| 1 watch sheet → store | paired-sim repro (Stage 1 manual) |
| 2 watch store relay | `ReminderStoreWatchTests` (Stage 3 extends) |
| 3 service request | `RescheduleSyncTests` (+ the red above) |
| 4 real `WCSession` | paired-sim repro only — `UNVALIDATED` if not reproduced |
| 5 phone decode → hook | `RescheduleSyncTests` |
| 6 phone hook → store | `AppViewModelSyncWiringTests` (new) |
| 7 iOS EventKit write | `EventKitStoringTests` |

### Verification

#### Automated
- [x] `bash -c 'cd /Users/vardy/dev/alanvardy-var-978-reschedule-not-working-on-watch && ./scripts/test-one.sh SingleThreadTests/SkippedReminderSyncServiceTests'` — all existing cases green
- [x] `bash -c 'cd /Users/vardy/dev/alanvardy-var-978-reschedule-not-working-on-watch && ./scripts/test-one.sh SingleThreadTests/RescheduleSyncTests'` — the 4 existing cases green; `rescheduleRelaysWhenPhoneUnreachable` **FAILS** (red captured, non-zero exit, `ok: N case(s) ran`)
- [x] `bash -c 'cd /Users/vardy/dev/alanvardy-var-978-reschedule-not-working-on-watch && ./scripts/test-one.sh SingleThreadTests/AppViewModelSyncWiringTests'` — `ok: 2 case(s) ran`, both green
- [x] Paste the red output (the `#expect` failure line) into the PR body as the diagnosis artifact
- [x] `make lint` green

#### Manual (paired-sim repro — hop 4)
- [ ] Boot the phone sim from `.simulator_id`; `xcrun simctl list pairs` to confirm a phone↔watch pair exists (else follow the `simulator-pairing` skill; watch UI tests need an unpaired watch sim)
- [ ] Install + launch the phone and watch apps on the pair; stream logs from both:
      `xcrun simctl spawn <phone-udid> log stream --predicate 'subsystem == "app.alanvardy.SingleThread"'`
- [ ] On the watch, open Skip → Reschedule → pick a date → Confirm
- [ ] Observe: does the phone log a `Failed to send reschedule request` (hop 3/4 drop) or process the write (hop 1/4 fine)? Does the watch card change?
- [ ] Record the finding. If real `WCSession` transport is implicated, mark hop 4 `UNVALIDATED` and rely on the queued fallback + phone behaviour

---

## Phase 2 (Stage 2): Sync transport — send-or-queue with reachability fallback

One delivery per attempt: `sendMessage` when reachable, otherwise `queueUserInfo`
(auto-delivers on reconnect / relaunch). Applied to all three mutating requests.

### Changes

#### 1. `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift` — protocol + shim
**Action**: modify (~lines 8-17)

```swift
public protocol SkipSyncSession: AnyObject {
    /// Whether the counterpart app is currently reachable for `sendMessage`.
    var isReachable: Bool { get }
    func activate()
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?)
    /// Queue a message for delivery when the counterpart is unreachable.
    /// Named `queueUserInfo` (not `transferUserInfo`) because the SDK call
    /// returns a `WCSessionUserInfoTransfer` and cannot witness a `Void`
    /// requirement.
    func queueUserInfo(_ userInfo: [String: Any])
}

extension WCSession: SkipSyncSession {
    public func queueUserInfo(_ userInfo: [String: Any]) {
        _ = transferUserInfo(userInfo)
    }
}
```
`isReachable` is witnessed by the SDK's own `WCSession.isReachable` property.

#### 2. Same file — the delivery chokepoint and the three request methods
**Action**: modify (replace the three `sendMessage` call sites)

```swift
/// Single delivery chokepoint: exactly one of `sendMessage` (reachable) or
/// `queueUserInfo` (unreachable) fires per call, so a queued mutation can never
/// be applied twice. Returns `true` once a delivery was handed to the transport.
@discardableResult
private func deliver(_ payload: [String: Any]) -> Bool {
    if session.isReachable {
        session.sendMessage(payload, replyHandler: nil) { error in
            Self.logger.error("Failed to deliver sync request: \(error.localizedDescription, privacy: .public)")
        }
    } else {
        session.queueUserInfo(payload)
    }
    return true
}

/// Ask the iPhone to complete a reminder (watch-side action).
@discardableResult
public func requestCompleteReminder(_ identifier: String) -> Bool {
    deliver([PayloadKey.completeReminderIdentifier: identifier])
}

/// Ask the iPhone to delete a reminder (watch-side action).
@discardableResult
public func requestDeleteReminder(_ identifier: String) -> Bool {
    deliver([PayloadKey.deleteReminderIdentifier: identifier])
}

/// Ask the iPhone to reschedule a reminder (watch-side action). ...
@discardableResult
public func requestRescheduleReminder(identifier: String, dueDateComponents: DateComponents) -> Bool {
    var payload: [String: Any] = [PayloadKey.rescheduleReminderIdentifier: identifier]
    var dueComponents: [String: Int] = [:]
    if let year = dueDateComponents.year { dueComponents["year"] = year }
    if let month = dueDateComponents.month { dueComponents["month"] = month }
    if let day = dueDateComponents.day { dueComponents["day"] = day }
    if let hour = dueDateComponents.hour { dueComponents["hour"] = hour }
    if let minute = dueDateComponents.minute { dueComponents["minute"] = minute }
    payload["dueDateComponents"] = dueComponents
    return deliver(payload)
}
```
Payload keys and the bare `"dueDateComponents"` literal are unchanged.

> Note: `store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }`
> discards the `Bool` via Swift's single-expression-closure `Void` conversion. If the
> compiler rejects it under `SWIFT_TREAT_WARNINGS_AS_ERRORS`, write
> `{ identifier in _ = service.requestCompleteReminder(identifier) }`.

#### 3. `SingleThreadTests/TestFixtures.swift` + `SingleThreadWatchTests/TestFixtures.swift`
**Action**: modify

No change needed beyond Stage 1 — both fakes already satisfy the new requirements.
If Stage 1 was skipped, add the properties/methods from Phase 1 §1–§2 now.

#### 4. `SingleThreadTests/RescheduleSyncTests.swift` — queue/XOR cases
**Action**: modify

```swift
@Test
func rescheduleQueuesExactlyOnceWhenUnreachable() {
    let fake = FakeSession()
    fake.isReachable = false
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-xor-\(UUID().uuidString)"))

    service.requestRescheduleReminder(identifier: "ABC", dueDateComponents: DateComponents(year: 2027, month: 1, day: 2))

    #expect(fake.queuedUserInfo.count == 1)
    #expect(fake.lastMessage == nil) // send XOR queue, never both
    let queued = fake.queuedUserInfo[0]
    #expect(queued["rescheduleReminderIdentifier"] as? String == "ABC")
    #expect(queued["dueDateComponents"] as? [String: Int] == ["year": 2027, "month": 1, "day": 2])
}

@Test
func rescheduleStillSendsWhenPhoneReachable() {
    let fake = FakeSession() // isReachable defaults true
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-send-\(UUID().uuidString)"))

    service.requestRescheduleReminder(identifier: "ABC", dueDateComponents: DateComponents(year: 2027, month: 1, day: 2))

    #expect(fake.lastMessage != nil)
    #expect(fake.queuedUserInfo.isEmpty)
}

@Test
func rescheduleDoesNotQueueAfterSendError() {
    let fake = FakeSession()
    fake.errorToThrow = NSError(domain: "test", code: 1)
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-err-\(UUID().uuidString)"))

    service.requestRescheduleReminder(identifier: "ABC", dueDateComponents: DateComponents(year: 2027, month: 1, day: 2))

    #expect(fake.lastMessage != nil)
    #expect(fake.queuedUserInfo.isEmpty) // a rejected send is not retried on the queue
}
```
`rescheduleRelaysWhenPhoneUnreachable` from Stage 1 stays in place and is now green.

#### 5. `SingleThreadTests/SkippedReminderSyncServiceTests.swift` — complete/delete parity
**Action**: modify

```swift
@Test
func completeQueuesWhenPhoneUnreachable() {
    let fake = FakeSession()
    fake.isReachable = false
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "test-complete-queue-\(UUID().uuidString)"),
        sortStore: makeTestSortStore())

    service.requestCompleteReminder("ABC")

    #expect(fake.queuedUserInfo.count == 1)
    #expect(fake.lastMessage == nil)
    #expect(fake.queuedUserInfo[0]["completeReminderIdentifier"] as? String == "ABC")
}

@Test
func deleteQueuesWhenPhoneUnreachable() {
    let fake = FakeSession()
    fake.isReachable = false
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "test-delete-queue-\(UUID().uuidString)"),
        sortStore: makeTestSortStore())

    service.requestDeleteReminder("ABC")

    #expect(fake.queuedUserInfo.count == 1)
    #expect(fake.lastMessage == nil)
    #expect(fake.queuedUserInfo[0]["deleteReminderIdentifier"] as? String == "ABC")
}
```

### Verification

#### Automated
- [x] `bash -c 'cd /Users/vardy/dev/alanvardy-var-978-reschedule-not-working-on-watch && ./scripts/test-one.sh SingleThreadTests/SkippedReminderSyncServiceTests'` — existing + 2 new green (35 cases)
- [x] `bash -c 'cd /Users/vardy/dev/alanvardy-var-978-reschedule-not-working-on-watch && ./scripts/test-one.sh SingleThreadTests/RescheduleSyncTests'` — the Stage-1 red is now green; 8 cases ran
- [x] `make build` — `SkipSyncSession` conformance compiles on iOS
- [x] `make watch-build` — conformance compiles on watchOS
- [x] `make lint` green

#### Manual
- [ ] Confirm by inspection that no `session.sendMessage` call remains outside `deliver(_:)` (grep the file)

---

## Phase 3 (Stage 3): Core store relay — truthful outcome

The watchOS relay branch stops returning unconditional `true`; it reports what the
relay actually did. iOS/macOS `#else` branch, `canMutate` gate, and the EventKit write
are byte-for-byte unchanged.

### Changes

#### 1. `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` — hook + branch
**Action**: modify (~lines 108-113 and 366-372)

```swift
/// Hook invoked when the user reschedules a reminder on watchOS, where EventKit
/// writes are unavailable. Passes the reminder's identifier and the new due-date
/// components, and returns whether the relay accepted the request (dispatched to
/// the transport, including queued delivery). Wired by the watch app layer to
/// relay the reschedule to the iPhone via WatchConnectivity.
public var onRescheduleReminder: ((String, DateComponents) -> Bool)?
```

```swift
@discardableResult
public func rescheduleReminder(identifier: String, to due: DateComponents) async -> Bool {
    guard canMutate else { return false }
    #if os(watchOS)
        // Truthful outcome: report what the relay actually did, so a missing
        // hook surfaces as a failure instead of a silent success.
        let handler = onRescheduleReminder
        return handler?(identifier, due) ?? false
    #else
        // ... unchanged ...
    #endif
}
```

> `Bool` because the relay is synchronous and cannot observe an async
> `sendMessage` failure — "accepted" means *dispatched to the transport*, and a
> queued delivery counts as accepted. A stricter signal would be a design change.

#### 2. `SingleThreadWatch/WatchAppViewModel.swift` — closure returns the relay result
**Action**: modify (~line 220)

```swift
store.onRescheduleReminder = { identifier, components in
    service.requestRescheduleReminder(identifier: identifier, dueDateComponents: components)
}
```

#### 3. `SingleThreadWatchTests/ReminderStoreWatchTests.swift` — replace/extend relay tests
**Action**: modify (`rescheduleFiresRelayHookAndReturnsTrue` + gated test)

```swift
@Test
func rescheduleRelayPropagatesHookResult() async {
    let rem = watchReminder("A")
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [rem],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    var receivedIdentifier: String?
    var receivedComponents: DateComponents?
    store.onRescheduleReminder = { identifier, components in
        receivedIdentifier = identifier
        receivedComponents = components
        return true
    }
    let due = DateComponents(year: 2027, month: 1, day: 2)

    let rescheduled = await store.rescheduleReminder(identifier: rem.calendarItemIdentifier, to: due)

    #expect(rescheduled)
    #expect(receivedIdentifier == rem.calendarItemIdentifier)
    #expect(receivedComponents?.year == 2027)
    #expect(receivedComponents?.month == 1)
    #expect(receivedComponents?.day == 2)
}

@Test
func rescheduleRelayReturnsFalseWhenHookRejects() async {
    let rem = watchReminder("A")
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [rem],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    store.onRescheduleReminder = { _, _ in false }

    let rescheduled = await store.rescheduleReminder(
        identifier: rem.calendarItemIdentifier,
        to: DateComponents(year: 2027, month: 1, day: 2))

    #expect(!rescheduled)
}

@Test
func rescheduleRelayReportsMissingHookAsFailure() async {
    let rem = watchReminder("A")
    let store = ReminderStore(
        eventStore: InMemoryEventStore(),
        loadsReminders: false,
        reminders: [rem],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    // No onRescheduleReminder hook wired.

    let rescheduled = await store.rescheduleReminder(
        identifier: rem.calendarItemIdentifier,
        to: DateComponents(year: 2027, month: 1, day: 2))

    #expect(!rescheduled)
}
```
`rescheduleNoOpWhenGated` stays; update its closure to
`store.onRescheduleReminder = { _, _ in fired = true; return true }`.

#### 4. `SingleThreadTests/ReminderStoreTests.swift`
**Action**: no change required

`rescheduleResetsSkipCount` / `reschedulePreservesRecurrenceOnRepeatingReminder` are
`#if !os(watchOS)` iOS write-path tests and stay untouched. Re-run to prove it.

### Verification

#### Automated
- [x] `bash -c 'cd /Users/vardy/dev/alanvardy-var-978-reschedule-not-working-on-watch && xcodebuild test -scheme SingleThreadWatch -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" -configuration Debug -derivedDataPath DerivedData -only-testing:SingleThreadWatchTests/ReminderStoreWatchTests'` — relay cases green (16 cases, pinned by id due to dual watchOS runtimes)
- [x] `bash -c 'cd /Users/vardy/dev/alanvardy-var-978-reschedule-not-working-on-watch && ./scripts/test-one.sh SingleThreadTests/ReminderStoreTests'` — `rescheduleResetsSkipCount` + `reschedulePreservesRecurrenceOnRepeatingReminder` green, no regressions (34 cases)
- [x] `make watch-build` green
- [x] `make lint` green

#### Manual
- [ ] Inspect the `#else` branch diff: the iOS `rescheduleReminder` body (find/save/skip-reset/settle/reload/catch) is unchanged — checked and unchanged on commit ed68e787

---

## Phase 4 (Stage 4): Watch view-model — extracted confirm + outcome state

Move the confirm logic out of the SwiftUI closure into a testable view-model method.

### Changes

#### 1. `SingleThreadWatch/WatchReminderViewModel.swift` — state + method
**Action**: modify

Add near `rescheduleDate` (~line 74):

```swift
/// `true` when the last reschedule attempt was rejected by the relay. Drives the
/// sheet's inline failure message and alert; cleared at the start of each attempt.
var rescheduleFailure = false

/// Confirms the pending reschedule: builds date-only components, relays through
/// the store, and refreshes the visible list on acceptance. A rejected relay
/// keeps the sheet open and surfaces `rescheduleFailure`.
func confirmReschedule() async {
    guard let identifier = store.visibleReminders.first?.calendarItemIdentifier else {
        isShowingRescheduleSheet = false
        return
    }
    let components = Calendar.current.dateComponents([.year, .month, .day], from: rescheduleDate)
    rescheduleFailure = false
    let accepted = await store.rescheduleReminder(identifier: identifier, to: components)
    if accepted {
        isShowingRescheduleSheet = false
        await refresh(clearSkipped: store.allSkipped)
    } else {
        rescheduleFailure = true
    }
}
```

> `refresh` takes `clearSkipped:` (there is no zero-arg `refresh()`), so the method
> mirrors `refreshFromCardTap()`.

#### 2. `SingleThreadWatchTests/WatchReminderViewModelTests.swift` — new coverage
**Action**: modify

Add a fixture backed by `AppGroup.defaults` (the new shared-value rule; the existing
`makeWatchReminderViewModel` uses `.standard` and is left alone):

```swift
@MainActor
private func makeRescheduleFixture() -> (viewModel: WatchReminderViewModel, store: ReminderStore, key: String) {
    let visible = watchReminder("Visible")
    let key = "watch-resched-vm-\(UUID().uuidString)"
    let skipStore = SkippedReminderStore(defaults: AppGroup.defaults, key: key)
    let store = ReminderStore(
        eventStore: InMemoryEventStore(reminders: [visible]),
        skipStore: skipStore,
        loadsReminders: true,
        reminders: [visible],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
    let viewModel = WatchReminderViewModel(
        store: store,
        showDateState: ShowDateState(),
        showRecurrenceState: ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState(),
        showListState: ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState(),
        entitlementState: EntitlementState(),
        showEnableActionButtonsState: ShowEnableActionButtonsState())
    return (viewModel, store, key)
}
```

Tests:

```swift
@Test
func confirmRescheduleRefreshesVisibleRemindersOnSuccess() async {
    let fixture = makeRescheduleFixture()
    defer { AppGroup.defaults.removeObject(forKey: fixture.key) }
    let viewModel = fixture.viewModel
    let store = fixture.store
    store.onRescheduleReminder = { _, _ in true }
    var reloads = 0
    store.onRemindersChanged = { reloads += 1 }
    viewModel.isShowingRescheduleSheet = true
    viewModel.rescheduleDate = Date(timeIntervalSince1970: 1_800_000_000) // arbitrary

    await viewModel.confirmReschedule()

    #expect(reloads >= 1)                      // refresh ran
    #expect(!viewModel.rescheduleFailure)
    #expect(!viewModel.isShowingRescheduleSheet) // success closes the sheet
}

@Test
func confirmRescheduleSetsFailureWhenRelayRejected() async {
    let fixture = makeRescheduleFixture()
    defer { AppGroup.defaults.removeObject(forKey: fixture.key) }
    let viewModel = fixture.viewModel
    fixture.store.onRescheduleReminder = { _, _ in false }
    viewModel.isShowingRescheduleSheet = true

    await viewModel.confirmReschedule()

    #expect(viewModel.rescheduleFailure)
    #expect(viewModel.isShowingRescheduleSheet) // sheet stays open on failure
}

@Test
func confirmRescheduleNoopWithoutVisibleReminder() async {
    let skipped = watchReminder("Only")
    let key = "watch-resched-vm-none-\(UUID().uuidString)"
    defer { AppGroup.defaults.removeObject(forKey: key) }
    let skipStore = SkippedReminderStore(defaults: AppGroup.defaults, key: key)
    skipStore.save([skipped.calendarItemIdentifier])
    let store = ReminderStore(
        eventStore: InMemoryEventStore(reminders: [skipped]),
        skipStore: skipStore,
        loadsReminders: true,
        reminders: [skipped],
        skippedIDs: [skipped.calendarItemIdentifier],
        authorizationStatus: .fullAccess)
    let viewModel = WatchReminderViewModel(
        store: store,
        showDateState: ShowDateState(),
        showRecurrenceState: ShowRecurrenceState(),
        showAlarmsState: ShowAlarmsState(),
        showListState: ShowListState(),
        showCompletionGlowState: ShowCompletionGlowState(),
        entitlementState: EntitlementState(),
        showEnableActionButtonsState: ShowEnableActionButtonsState())
    var fired = false
    store.onRescheduleReminder = { _, _ in fired = true; return true }
    viewModel.isShowingRescheduleSheet = true

    await viewModel.confirmReschedule()

    #expect(!fired)
    #expect(!viewModel.rescheduleFailure)
    #expect(!viewModel.isShowingRescheduleSheet) // pre-existing no-op closes the sheet
}

@Test
func confirmRescheduleSendsDateOnlyComponents() async throws {
    let fixture = makeRescheduleFixture()
    defer { AppGroup.defaults.removeObject(forKey: fixture.key) }
    let viewModel = fixture.viewModel
    var sent: DateComponents?
    fixture.store.onRescheduleReminder = { _, components in
        sent = components
        return true
    }
    // A date with a non-midnight time; the picker is date-only.
    viewModel.rescheduleDate = Date(timeIntervalSince1970: 1_800_000_000)

    await viewModel.confirmReschedule()

    let components = try #require(sent)
    #expect(components.year != nil)
    #expect(components.month != nil)
    #expect(components.day != nil)
    #expect(components.hour == nil)   // date-only wire semantics preserved
    #expect(components.minute == nil)
}
```

### Verification

#### Automated
- [x] `bash -c 'cd /Users/vardy/dev/alanvardy-var-978-reschedule-not-working-on-watch && xcodebuild test -scheme SingleThreadWatch -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" -configuration Debug -derivedDataPath DerivedData -only-testing:SingleThreadWatchTests/WatchReminderViewModelTests'` — 4 new + existing cases green (12 cases, pinned by id)
- [x] `make lint` green — SwiftFormat does not strip any new test name (none start with `test`/`testing`)
- [x] Confirm new persisted keys use `AppGroup.defaults` (grep the new tests for `.standard`)

#### Manual
- [ ] `make watch-build` green

---

## Phase 5 (Stage 5): Watch view — thin rendering of the outcome

Wire the sheet's Confirm button to `viewModel.confirmReschedule()` and render failure;
the view holds no business logic.

### Changes

#### 1. `SingleThreadWatch/WatchReminderView.swift` — sheet body
**Action**: modify (`actionMenuRescheduleSheet()`, ~lines 290-318)

```swift
private func actionMenuRescheduleSheet() -> some View {
    @Bindable var viewModel = viewModel
    return NavigationStack {
        VStack(spacing: 12) {
            DatePicker(
                "Reschedule to",
                selection: $viewModel.rescheduleDate,
                displayedComponents: [.date])
            Button("Reschedule") {
                Task { await viewModel.confirmReschedule() }
            }
            .accessibilityIdentifier("rescheduleConfirmButton")
            if viewModel.rescheduleFailure {
                Text("Couldn't reschedule. Try again with your iPhone nearby.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("rescheduleFailureMessage")
            }
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { viewModel.isShowingRescheduleSheet = false }
            }
        }
        .alert("Reschedule failed", isPresented: $viewModel.rescheduleFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your reminder wasn't updated.")
        }
    }
}
```
The store call, component extraction, and discarded `Bool` are all removed from the view.

### Verification

#### Automated
- [x] `make watch-build` green
- [x] `make lint` green
- [x] No watch UI test is added (decision, not a step): the state transition is fully captured by the Stage-4 unit tests and repo policy keeps UI tests exceptional; the existing watch smoke + a11y audit run in the gate

#### Manual
- [ ] Grep `WatchReminderView.swift` for `rescheduleReminder` — no hits (view is presentation-only) — verified on commit for Phase 5
- [ ] On the paired sim: tap Reschedule → Confirm with a reachable phone → sheet dismisses and the card reflects the new date

---

## Phase 6 (Stage 6): Regression + gate

Prove the phone path is untouched and the whole surface is green.

### Changes

None (verification only). Update the PR body with:
- the Stage-1 red output + paired-sim finding (hop matrix),
- the deviation notes from the Overview,
- the reason no watch UI test was added.

### Verification

#### Automated
- [x] `bash -c 'cd /Users/vardy/dev/alanvardy-var-978-reschedule-not-working-on-watch && ./scripts/test-one.sh SingleThreadTests/EventKitStoringTests'` — `reschedulePersistsDueDateAndReloads`, `rescheduleUnknownIdentifierIsNoop`, `rescheduleFailureReturnsFalse`, `reschedulePreservesRecurrenceRules` green, unchanged (actual Swift Testing suite is `ReminderStoreWriteTests` in that file — 12 cases, matched-zero trap avoided)
- [x] `bash -c 'cd /Users/vardy/dev/alanvardy-var-978-reschedule-not-working-on-watch && ./scripts/test-one.sh SingleThreadTests/RescheduleSyncTests'` green (8 cases)
- [ ] Full CI-identical gate runs **once**, via the `run-gate` skill (one async gate subagent in a managed worktree, multi-hour timeout): `./scripts/test.sh`
      — do **not** `nohup` it ad-hoc, and do not re-run it locally after UI-stage contention (CI is authoritative)
      — PENDING: parent-side `run-gate` launch after phases commit (branch tip to gate: 2c27f18d)
- [x] Confirm the PR includes `git rm DELETEME` if the branch bootstrap marker is still present — removed on commit d6102755

#### Manual
- [ ] The three local-only macOS `EntitlementStoreTests` failures (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`) are pre-existing — annotate, do not debug — annotated in PR body

---

## Testing Checkpoints

- **After Phase 1**: pre-existing suites green; hop matrix complete; `rescheduleRelaysWhenPhoneUnreachable` RED captured and pasted into the PR.
- **After Phase 2**: `SkippedReminderSyncServiceTests` + `RescheduleSyncTests` green; the Stage-1 red is green; send XOR queue proven.
- **After Phase 3**: `ReminderStoreWatchTests` + `ReminderStoreTests` green; watch relay returns `false` with no hook; iOS `#else` untouched.
- **After Phase 4**: `WatchReminderViewModelTests` green incl. sad paths; success refreshes, failure sets state.
- **After Phase 5**: watch build + lint green; view holds no business logic.
- **After Phase 6**: full gate green once.

**If context resets**: replay the checkpoint for the last committed phase; a phase whose tests are not green is not done.

## Open Risks Carried From `structure.md`

- **Hop 4 is not unit-testable** — the paired-sim repro must run; if real `WCSession` transport is implicated, mark hop 4 `UNVALIDATED` and rely on the queued fallback.
- **`transferUserInfo` double-apply** — enforced by the single `deliver` chokepoint (send XOR queue); `rescheduleDoesNotQueueAfterSendError` + the grep check in Phase 2 guard it.
- **Hook signature change** touches macOS compilation (`#else` branch) — verified by the CI `mac-tests` job, outside the local gate's watch focus.

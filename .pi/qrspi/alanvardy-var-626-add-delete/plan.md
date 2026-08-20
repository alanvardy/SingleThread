# Implementation Plan — VAR-626: Add Delete

## Overview
Give the user a way to **permanently delete the current reminder** from EventKit so it disappears on every surface. A new seam primitive (`remove`) removes the whole `EKReminder` (entire recurring series) and funnels through `ReminderStore.deleteCurrentReminder`; watch deletes are relayed to the iPhone over WatchConnectivity (no on-watch permanent store). iOS/macOS/watch get unconfirmed, red-tinted, accessibility-labeled Delete controls. The widget stays untouched.

Phase order follows `structure.md`. All test/lint/build commands come from `AGENTS.md` and `Makefile`. Simulators default to `iPhone 17`; the Makefile's `WATCH_SIM` is `generic/platform=watchOS Simulator`.

---

## Phase 1: Disposal seam + store delete + unit tests *(foundation)*

### Changes

#### 1. `EventKitStoring.swift` — add removal protocol op + EKS bridge
**File**: `SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift`
**Action**: modify

Add a `remove` op inside the existing `#if !os(watchOS)` block, beside `save` (currently `:29`), so the watch target still compiles:

```swift
#if !os(watchOS)
    func refreshSourcesIfNecessary()

    func save(_ reminder: EKReminder, commit: Bool) throws

    /// Deletes `reminder` from EventKit. Removes the whole repository object,
    /// so a recurring reminder's entire series is deleted (no per-occurrence span).
    func remove(_ reminder: EKReminder, commit: Bool) throws

    func makeReminder(...) -> EKReminder
#endif
```

Add the thin bridge in the `extension EKEventStore: EventKitStoring` block, beside the existing `#if !os(watchOS)` override (currently `:41`–`:64`), calling the framework's `removeReminder:commit:` (`EKEventStore.h:370`):

```swift
#if !os(watchOS)
    public func remove(_ reminder: EKReminder, commit: Bool) throws {
        Self.removeReminder(reminder, commit: commit)
    }
#endif
```

> **Binding note**: `EKEventStore.removeReminder(_:commit:error:)` is `__WATCHOS_PROHIBITED` and returns `BOOL` with an `NSError **` out-param, so Swift binds it as `throws` (matching how `save`/`saveReminder` behave). If the exact Swift name differs from `removeReminder`, adjust the call to the interop-visible name and re-verify with a build (Phase 3). No generated-file conflict is expected; if the overlay already exposes a differently-named `remove`, rename this extension method to avoid a conflict.

#### 2. `ReminderStore.swift` — `deleteReminder` + `deleteCurrentReminder` + hook
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add a new public hook beside `onCompleteReminder` (currently `:54`):

```swift
/// Hook invoked when the user deletes a reminder on watchOS, where EventKit
/// writes are unavailable. Passes the deleted reminder's identifier. Wired by
/// the watch app layer to relay the deletion to the iPhone via WatchConnectivity.
public var onDeleteReminder: ((String) -> Void)?
```

Add two public methods. Place `deleteCurrentReminder` beside `completeCurrentReminder` (currently `:138`) and `deleteReminder` beside `completeReminder` (currently `:121`):

```swift
/// Deletes a specific reminder by identifier.
///
/// On iOS: removes the whole `EKReminder` object from EventKit and reloads.
/// On watchOS (where EventKit is read-only): removes it locally and relays the
/// deletion to the iPhone via `onDeleteReminder`.
public func deleteReminder(identifier: String) async {
    #if os(watchOS)
        reminders.removeAll { $0.calendarItemIdentifier == identifier }
        onDeleteReminder?(identifier)
    #else
        guard let reminder = reminders.first(where: { $0.calendarItemIdentifier == identifier }) else { return }
        do {
            try eventStore.remove(reminder, commit: true)
            try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
            await reload()
        } catch {
            Self.logger.error("Failed to delete reminder: \(error.localizedDescription, privacy: .public)")
        }
    #endif
}

public func deleteCurrentReminder() async {
    guard let reminder = visibleReminders.first else { return }
    await deleteReminder(identifier: reminder.calendarItemIdentifier)
}
```

> **Design notes**: mirrors `completeReminder`'s mutate → settle → `reload()` shape, including the `do/catch` where `reload()` is skipped on a failed remove (so the item stays visible and the error is logged). The skip list needs no delete-specific handling — `ReminderSkipLogic.resolve` (`ReminderStore.swift:109`/`ReminderSkip.swift:12`) prunes the deleted ID on the next `reload()`.

#### 3. `FakeEventStore` + write tests — `EventKitStoringTests.swift`
**File**: `SingleThreadTests/EventKitStoringTests.swift`
**Action**: modify

Extend the recording fake (add near `saveShouldThrow`/`saved`/`lastSaveCommit`, currently `:67`–`:97`):

```swift
// MARK: Configuration
var removeShouldThrow = false

// MARK: Recording
private(set) var removed: [EKReminder] = []
private(set) var lastRemoveCommit = false
```

Add a `remove(_:)` implementation inside the same `#if !os(watchOS)` block that currently holds `save` (currently `:93`–`:97`), mirroring `save`:

```swift
func remove(_ reminder: EKReminder, commit: Bool) throws {
    lastRemoveCommit = commit
    if removeShouldThrow {
        throw NSError(domain: "FakeEventStore", code: 1)
    }
    removed.append(reminder)
}
```

Add three tests inside the existing `ReminderStoreWriteTests` struct (already `#if !os(watchOS)`):

```swift
@Test
func deleteReminderRemovesAndReloads() async {
    let reminder = makeReminder(title: "Task")
    let fake = FakeEventStore(fetchResult: [reminder])
    let store = testStore(eventStore: fake)
    await store.reload()
    let before = fake.fetchCallCount

    await store.deleteReminder(identifier: reminder.calendarItemIdentifier)

    #expect(fake.removed.count == 1)
    #expect(fake.removed.first === reminder)
    #expect(fake.lastRemoveCommit == true)
    #expect(fake.lastPredicate != nil)
    #expect(fake.fetchCallCount == before + 1) // reload-after-remove
    #expect(store.visibleReminders.isEmpty)
}

@Test
func deleteReminderRemoveErrorStaysSilentAndSkipsReload() async {
    let reminder = makeReminder(title: "Task")
    let fake = FakeEventStore(fetchResult: [reminder])
    fake.removeShouldThrow = true
    let store = testStore(eventStore: fake)
    await store.reload()
    let before = fake.fetchCallCount

    await store.deleteReminder(identifier: reminder.calendarItemIdentifier)

    #expect(fake.removed.isEmpty)
    #expect(fake.fetchCallCount == before) // no reload on remove error
}

@Test
func deleteReminderWhileSkippedPrunesSkipIDOnReload() async {
    let reminder = makeReminder(title: "Task")
    let fake = FakeEventStore(fetchResult: [reminder])
    let skipStore = SkippedReminderStore(
        defaults: .standard,
        key: "test-delete-skip-\(UUID().uuidString)")
    let store = ReminderStore(eventStore: fake, skipStore: skipStore, loadsReminders: true)
    await store.reload()
    // Skip it so the ID is in the persisted skip set; then the reminder is gone.
    store.skipCurrentReminderImmediately()
    #expect(Set(skipStore.load()).contains(reminder.calendarItemIdentifier))

    fake.fetchResult = []
    await store.deleteReminder(identifier: reminder.calendarItemIdentifier)

    #expect(fake.removed.first === reminder)
    #expect(!Set(skipStore.load()).contains(reminder.calendarItemIdentifier))
}
```

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes
- [x] The four new `ReminderStoreWriteTests` cases pass: happy path (removed count 1 / `lastRemoveCommit` true / fetch +1 / gone from `visibleReminders`), error path (`removed.isEmpty` + no reload), and skip-prune (deleted-while-skipped ID drops from `skipStore` on `reload()`).
- [x] `make lint` (or `swiftlint lint --strict`) is clean — no new warnings (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`).

#### Manual
- [ ] Surfacing list still empty; no delete control exists yet after Phase 1 (UI untouched until Phase 3).

---

## Phase 2: Watch↔iPhone sync relay

### Changes

#### 1. `SkippedReminderSyncService.swift` — new payload key + relays + receive
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

Add the payload key to `private enum PayloadKey` (beside `completeReminderIdentifier`, currently `:232`):

```swift
static let deleteReminderIdentifier = "deleteReminderIdentifier"
```

Add a public hook beside `onCompleteReminderReceived` (currently `:52`):

```swift
/// Hook invoked on the iPhone when the watch asks to delete a reminder.
/// Passes the deleted reminder's identifier. Same write-once-before-activate /
/// `nonisolated(unsafe)` rationale as `onCompleteReminderReceived`.
public nonisolated(unsafe) var onDeleteReminderReceived: ((String) -> Void)?
```

Add a request method beside `requestCompleteReminder` (currently `:125`–`:135`):

```swift
public func requestDeleteReminder(_ identifier: String) {
    session.sendMessage(
        [PayloadKey.deleteReminderIdentifier: identifier],
        replyHandler: nil) { error in
            let description = error.localizedDescription
            Self.logger.error("Failed to send delete request: \(description, privacy: .public)")
        }
}
```

Update `session(_: WCSession, didReceiveMessage:)` (currently `:128`–`:130`) to handle both message keys instead of returning after completion:

```swift
public func session(_: WCSession, didReceiveMessage message: [String: Any]) {
    if let identifier = message[PayloadKey.completeReminderIdentifier] as? String {
        onCompleteReminderReceived?(identifier)
    }
    if let identifier = message[PayloadKey.deleteReminderIdentifier] as? String {
        onDeleteReminderReceived?(identifier)
    }
}
```

> Absent key → no-op for whichever message type isn't present, matching the existing missing-key convention in the tests.

#### 2. `SkippedReminderSyncServiceTests.swift` — relay test coverage
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify

Add three cases in the "Completion relay" section (beside `requestCompleteReminderSendsMessage`/`receiveMessageTriggersCompletionHook`):

```swift
@Test
func requestDeleteReminderSendsMessage() throws {
    let fake = FakeSession()
    let store = SkippedReminderStore(defaults: .standard, key: "test-delete-request")
    let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
    service.requestDeleteReminder("ABC")
    let message = try #require(fake.lastMessage)
    let identifier = try #require(message["deleteReminderIdentifier"] as? String)
    #expect(identifier == "ABC")
}

@Test
func receiveMessageTriggersDeleteHook() {
    let fake = FakeSession()
    let store = SkippedReminderStore(defaults: .standard, key: "test-delete-receive")
    let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
    var received: String?
    service.onDeleteReminderReceived = { received = $0 }
    service.session(WCSession.default, didReceiveMessage: ["deleteReminderIdentifier": "XYZ"])
    #expect(received == "XYZ")
}

@Test
func receiveMessageIgnoringDeleteKeyIsNoOp() {
    let fake = FakeSession()
    let store = SkippedReminderStore(defaults: .standard, key: "test-delete-bad")
    let service = SkippedReminderSyncService(session: fake, skipStore: store, sortStore: makeTestSortStore())
    var received = false
    service.onDeleteReminderReceived = { _ in received = true }
    service.session(WCSession.default, didReceiveMessage: ["wrongKey": 42])
    #expect(!received)
}
```

#### 3. `SingleThreadApp.swift` — wire iOS hooks
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

Inside the `#if os(iOS)` block (beside the `onCompleteReminderReceived` handler at `:35`, and the `store.onCompleteReminder` line at `:46`):

```swift
// Receive-side: a watch Delete arrives and is executed on the phone.
service.onDeleteReminderReceived = { [weak store] identifier in
    Task { await store?.deleteReminder(identifier: identifier) }
}
// Send-side (defensive/consistent): a phone-side delete relays to the watch.
store.onDeleteReminder = { identifier in service.requestDeleteReminder(identifier) }
```

> The iPhone's `deleteReminder` does **not** fire `onDeleteReminder` (only the watchOS branch does), so the `store.onDeleteReminder → requestDeleteReminder` wiring is inert on iOS but kept for symmetry with the completion path.

#### 4. `SingleThreadWatchApp.swift` — watch relay send-side
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

Beside the existing `store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }` (currently `:29`):

```swift
store.onDeleteReminder = { identifier in service.requestDeleteReminder(identifier) }
```

> Receive-side stays unwired (local removal + relay only, matching completion). Call out if receive-side delivery is later wanted.

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes — `SkippedReminderSyncServiceTests` new cases green (requestDelete sends correct key; receive handler fires; missing key no-ops).
- [x] `make lint` clean.

#### Manual
- [ ] Relay a watch-app Delete to a target "iPhone" session wakes the receive handler (`onDeleteReminderReceived`).

---

## Phase 3: iOS + macOS destinations

### Changes

#### 1. `ContentView.swift` — iOS context-menu Delete + macOS action-button Delete
**File**: `SingleThread/ContentView.swift`
**Action**: modify

**iOS** — add a Delete row beside "View in Reminders" in the `.contextMenu` (currently `:277`–`:286`):

```swift
.contextMenu {
    Button {
        let deep = ReminderDeepLink.url(forReminderIdentifier: ...)
        if let url = deep { openURL(url) }
    } label: {
        Label("View in Reminders", systemImage: "eye")
    }

    Button {
        Task { await store.deleteCurrentReminder() }
    } label: {
        Label("Delete", systemImage: "trash")
    }
    .tint(.red)
}
```

**macOS** — add a Delete button into `actionButtons` HStack (currently `:191`–`:215`), after the Skip button. No `.keyboardShortcut` (avoid a destructive key):

```swift
Button {
    Task { await store.deleteCurrentReminder() }
} label: {
    Label("Delete", systemImage: "trash")
        .labelStyle(.iconOnly)
        .font(.title)
}
.tint(.red)
.accessibilityLabel("Delete reminder")
.accessibilityAddTraits(.isButton)
```

> No new `#Preview` needed — the existing injected-fixture previews reuse `deleteCurrentReminder`'s injected store. The widget is **unchanged** (no `DeleteReminderIntent`), per design decision 4.

Preview `#Preview` macros stay as-is. No new `self.store` wiring required here — the store is already shared from the app entry point.

### Verification

#### Automated
- [ ] Build succeeds (catches any `removeReminder` Swift6 binding issue from Phase 1 early): `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`
- [ ] iOS accessibility audit passes: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests` — includes `testAccessibilityAudit()` covering hit regions, element descriptions, and traits.
- [ ] `make lint` clean.

#### Manual
- [ ] iOS: the context menu shows a red "Delete" row; tapping it removes the card (the reminder disappears after `reload()`).
- [ ] macOS: a red Delete button appears in the action row (no keyboard key binding), is accessibility-labeled "Delete reminder", and carries `.isButton`. Selecting it removes the current reminder.

---

## Phase 4: Watch destination

### Changes

#### 1. `WatchReminderView.swift` — watch Delete button
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

Add a Delete button into `actionButtons` (currently `:83`–`:96`), making the HStack three buttons:

```swift
Button {
    Task { await store.deleteCurrentReminder() }
} label: {
    Label("Delete", systemImage: "trash")
        .labelStyle(.iconOnly)
}
.tint(.red)
.accessibilityLabel("Delete reminder")
```

> Wired back in Phase 2 (`SingleThreadWatchApp.swift`), so this phase is UI-only — no app-layer changes.

### Verification

#### Automated
- [ ] Watch target builds: `xcodebuild -scheme SingleThreadWatch -destination 'generic/platform=watchOS Simulator' -configuration Debug build`
- [ ] Full CI-equivalent pipeline green: `./scripts/test.sh` (format, lint, build singleThread + watch, Periphery dead-code, unit tests, UI/accessibility audit).
- [ ] `make format` + `make lint` (or the formatting inside `./scripts/test.sh`) is clean.

#### Manual
- [ ] On-simulator: tapping Delete clears the card and relays to the paired iPhone (the phone's reminder disappears).
- [ ] Skip-list self-prunes on the next `reload()` with no stale push (a deleted-while-skipped reminder drops cleanly).

---

## Testing Checkpoints (from structure.md)

- [ ] **After Phase 1**: seam + store delete + fake exist; UnitTests green (removal recorded, reload-after-remove, no reload on error, skip-prune). Surfacing list still empty.
- [ ] **After Phase 2**: payload/service/relay green headless; a watch delete still reaches an iPhone even before any button exists.
- [ ] **After Phase 3**: iOS + macOS delete controls, audio accessibility audit passes, build clean.
- [ ] **After Phase 4**: watch delete wired + full `./scripts/test.sh` pipeline green.

## Notes / Resolved Questions

- **Watch receive-side**: `onDeleteReminderReceived` on the watch stays unwired (local + relay only), matching the completion path. Receive-side delivery to the watch is intentionally out of scope — call out if later wanted. *(Resolves the design's "Open Question".)*
- **Recurrence**: deletion removes the entire recurring series because `removeReminder:` operates on the whole object (no per-occurrence `span`, unlike `removeEvent:`).
- **No schema migration or codegen**: this feature touches no SwiftData schema and performs no codegen, so there are no schema-version test assertions or codegen-fallback steps to update.
- **Widget untouched**: no `DeleteReminderIntent`; delete is intentionally omitted from the widget extension.
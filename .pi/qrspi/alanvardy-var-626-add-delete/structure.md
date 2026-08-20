# Structure Outline — VAR-626: Add Delete

## Approach
Add a permanent-delete path that removes the whole `EKReminder` (entire recurring series) from EventKit through a new seam primitive, funnel every surface through `ReminderStore.deleteCurrentReminder`, relay watch deletes to the iPhone over WatchConnectivity (no on-watch permanent store), and expose unconfirmed, red-tinted, accessibility-labeled Delete controls on iOS (context menu), macOS (button row), and watch. The widget stays untouched.

---

## Phase 1: Disposal seam + store delete + unit tests *(foundation)*

Delivers delete end-to-end at the store layer: EventKit removal primitive, the iOS (removes series) and watch (removes locally) branches, the relay hook, and the recording fake.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift`, `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`, `SingleThreadTests/EventKitStoringTests.swift`

**Key changes**:
- New protocol op inside existing `#if !os(watchOS)` gate (beside `save`, :29): `func remove(_ reminder: EKReminder, commit: Bool) throws` — watch target still compiles.
- `extension EKEventStore: EventKitStoring` adds a thin override calling the framework's `EKEventStore.removeReminder(_: EKReminder, commit: Bool)` (iOS/macOS only). Whole-series removal; no per-occurrence span.
- `ReminderStore`:
  - `public func deleteCurrentReminder() async` → `guard let reminder = visibleReminders.first else { return }` → `deleteReminder(reminder.calendarItemIdentifier)` (mirrors `completeCurrentReminder`, :138).
  - `public func deleteReminder(identifier: String) async` — watch branch `reminders.removeAll { $0.calendarItemIdentifier == identifier }` + `onDeleteReminder?(identifier)`; else `guard let reminder = reminders.first(where: …)` → `eventStore.remove(reminder, commit: true)` → settle 200 ms → `reload()`. Log `Self.logger.error` + skip reload on throw.
  - New hook `public var onDeleteReminder: ((String) -> Void)?`.
- `FakeEventStore` (EventKitStoringTests.swift): `private(set) var removed: [EKReminder]`, `var lastRemoveCommit: Bool`, `var removeShouldThrow = false`; `remove(_:)` mirrors `save` (:94).

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` — new write tests: happy path removes 1, `lastRemoveCommit == true`, fetch count +1 after reload, reminder gone from `visibleReminders`; error path `removed.isEmpty` + no reload (mirrors :145–157); skip-prune test (delete-while-skipped drops the ID on next `reload()`).

---

## Phase 2 — Watch↔iPhone sync relay

Delete crossing the device boundary: a new WatchConnectivity payload, the relay service call + receive handler, and both apps' hook wiring. Independent of any specific UI (headless-testable).

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`, `SingleThread/SingleThreadApp.swift`, `SingleThreadWatch/SingleThreadWatchApp.swift`, `SingleThreadTests/SkippedReminderSyncServiceTests.swift`

**Key changes**:
- `private enum PayloadKey`: add `deleteReminderIdentifier` (beside `completeReminderIdentifier`).
- `public func requestDeleteReminder(_ identifier: String)` — `session.sendMessage([PayloadKey.deleteReminderIdentifier: identifier])` (beside :136).
- `public nonisolated(unsafe) var onDeleteReminderReceived: ((String) -> Void)?` (beside :56).
- In `session(... didReceiveMessage:)` (:180): guard `PayloadKey.deleteReminderIdentifier` → `onDeleteReminderReceived`.
- `SingleThreadApp.swift` (~:37, :46): `service.onDeleteReminderReceived = { [weak store] id in Task { await store?.deleteReminder(id) } }` (for phone→...deliveries) and `store.onDeleteReminder = { id in service.requestDeleteReminder(id) }`.
- `SingleThreadWatchApp.swift`: `store.onDeleteReminder = { id in service.requestDeleteReminder(id) }` — local removal + relay, receive-side left unwired (same as complete).

**Verify**: `-only-testing:SingleThreadTests` — `SkippedReminderSyncServiceTests` new cases: `requestDeleteReminder` sends correct payload key; receive handler fires `onDeleteReminderReceived`; missing key no-ops. Manual: relay a watch-app delete to a target "iPhone" session wakes the receive handler.

---

## Phase 3 — iOS + macOS destinations

Expose delete on both native surfaces (one file, one screen). iOS gets a context-menu row; macOS a red action-button (no shortcut).

**Files**: `SingleThread/ContentView.swift`

**Key changes**:
- iOS `.contextMenu` (:277), beside "View in Reminders": `Button { Task { await store.deleteCurrentReminder() } }`, `Label("Delete", systemImage: "trash")`, `.tint(.red)`.
- macOS `actionButtons` (:191): `Button { Task { await store.deleteCurrentReminder() } }`, `Label("Delete", systemImage: "trash")`, `.tint(.red)`, `.accessibilityLabel("Delete reminder")`, `.accessibilityAddTraits(.isButton)` — no `.keyboardShortcut` (avoid a destructive key).
- `#Preview` macro: no new preview needed (reuses injected fixtures).
- Widget: **unchanged** — note only, no `DeleteReminderIntent`.

**Verify**: `xcodebuild build` succeeds (catch any `removeReminder` Swift6 binding issue early). iOS: context menu shows a red "Delete" row; tapping it removes the card. macOS: Delete button (No `…)` in the action row, labeled + `.isButton`. Run `-only-testing:SingleThreadUITests` accessibility audit — new hit region + labels/traits present.

---

## Phase 4 — Watch destination

Delivery to the watch surface: a red Delete button that removes locally and relays to the iPhone.

**Files**: `SingleThreadWatch/WatchReminderView.swift`

**Key changes**:
- `actionButtons` (:83–96): `Button { Task { await store.deleteCurrentReminder() } }`, `Label("Delete", systemImage: "trash")`, `.tint(.red)`, `.accessibilityLabel("Delete reminder")`. HStack grows to 3 buttons.
- Wired in Phase 2 (`SingleThreadWatchApp.swift`), so this phase is UI-only.

**Verify**: Build the watch target; manual on-simulator: Delete clears the card and relays to the paired iPhone (phone's reminder disappears). Skip-list self-prunes on next `reload()` with no stale push.

---

## Testing Checkpoints

- **After Phase 1**: seam + store delete + fake exist; UnitTests green (removal recorded, reload, no-skip on error, skip-prune). Surfacing list still empty.
- **After Phase 2**: payload/service/relay green headless; a watch delete still reaches an iPhone even before any button exists.
- **After Phase 3**: iOS + macOS delete controls, audio audit passes, build clean.
- **After Phase 4**: watch delete wired + full `./scripts/test.sh` pipeline green (format, lint, Periphery, unit, UI/accessibility).

## Notes

- **Inherently serial foundation**: the EventKit removal seam + `deleteReminder` are shared by every surface and cannot be split per-surface — they are the Phase 1 underpin; every later phase is independently valuable.
- **Can't be sliced per-recurrence/undo**: no confirmation/undo/toast by design; recurring series deletion is one EventKit call, so no per-occurrence slice exists.
- Watch `onDeleteReminderReceived` remains unwired (local + relay only, matching completion) — call out if receive-side delivery is later wanted.
# Structure Outline

## Approach

Add one hybrid re-check so each surfaced platform, while a reminder is on screen, notices an out-of-band completion/deletion and advances without a gesture. Reuse the existing fresh `ReminderStore.reload()` funnel (already proven to drop completed-elsewhere reminders) as the sole re-check action; a new Core coordinator — started/stopped by the view models — combines a `.EKEventStoreChanged` observer with a slow poll, gated to on-screen reminders; the widget only shortens its timeline policy 15 → 5 min.

Layers build bottom-up; every stage ships its tests green before the next starts.

---

## Stage 1: Re-check coordinator (`StaleReminderRechecker`, Core — bottom)

Pure coordination logic, fully injectable, no EventKit/NotificationCenter of its own. Owns the tick funnel: *change/poll tick → on-screen gate → debounce/coalesce → `reload()`*, plus a cancellable poll loop and `start()`/`stop()`. Depends only on `ReminderStore.reload()` and `listContent`, both already verified by `ReminderStoreTests`.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/StaleReminderRechecker.swift` (new)

**Key changes** (types/signatures — what the next layer consumes):
```swift
@MainActor
final class StaleReminderRechecker: Sendable {
    static let defaultPollInterval: Duration = .seconds(60)   // named, tunable constant
    typealias Reload = @MainActor () async -> Void
    init(
        isShowingReminder: @escaping @MainActor () -> Bool,   // == store.listContent == .reminder
        reload: @escaping Reload,                              // == { await store.reload() }
        sleep: @escaping @Sendable (Duration) async -> Void,   // ReminderStoreSettle-style seam
        pollInterval: Duration = Self.defaultPollInterval
    )                                                   // change-tick source injected at Stage 2
    func start()                                        // begin poll loop; arm first reload
    func stop()                                         // cancel loop; idempotent
}
```
Debounce/coalesce is internal state, not a separate type: overlapping poll/observer/own-write ticks collapse to one `reload()` (mirrors `ContentViewModel.refreshManual` re-entrancy guard). Loop is tracked and cancellable — explicitly **not** an unstructured fire-and-forget `Task` (design "Do NOT follow").

**Tests**: new `SingleThreadTests/StaleReminderRecheckerTests.swift` — using `noopSettle`-style/continuation-gated `sleep` + recording `reload` + `withCheckedContinuation` rendezvous (house determinism stack, `research.md` Q7).
- Happy: `start()` with a reminder showing → poll tick fires `reload`; a change tick fires `reload`; `stop()` is idempotent and cancels the loop.
- Sad: gate idles — `isShowingReminder == false` (`.empty`/`.allDone`) → no `reload` on tick; overlapping ticks coalesce to a single `reload`; `stop()` before a pending `sleep` resolves cancels without a second `reload`.

**Verify**: `xcodebuild -only-testing:SingleThreadTests/StaleReminderRecheckerTests` (pinned destination) green.

---

## Stage 2: EventKit change-observer source (Core)

The production `.EKEventStoreChanged` observer feeding Stage 1's tick input — the EventKit/NotificationCenter integration, kept out of the loop logic so Stage 1 stays deterministic. Closes Open Risk "observer store filter": observe globally (`object: nil`) and let the Stage 1 gate + full `reload()` do the filtering (design decision 3: no cheap second fetch path).

**Files**: `SingleThreadCore/Sources/SingleThreadCore/EventStoreChangedObserver.swift` (new)

**Key changes**:
```swift
@MainActor
protocol EventStoreChangedObserving {
    // Registers a tick handler; returns an unregister closure.
    func onChange(_ handler: @escaping @MainActor () -> Void) -> (() -> Void)
}

@MainActor
final class EventStoreChangedObserver: EventStoreChangedObserving {
    init(center: NotificationCenter = .default)      // injectable for tests
    func onChange(_ handler: @escaping @MainActor () -> Void) -> (() -> Void)
    // registers .EKEventStoreChanged (object: nil); unregister removes the observer
}
```
`StaleReminderRechecker` gains `init(..., changeSource: EventStoreChangedObserving?)` and calls `start()` on its unregister closure in `stop()`; Stage 1 tests keep `changeSource: nil` (poll-only). This protocol is what Stage 3 wires.

**Tests**: new `SingleThreadTests/EventStoreChangedObserverTests.swift`.
- Happy: posting `.EKEventStoreChanged` fires the registered handler.
- Sad: unregister removes the observer — a later post does **not** fire (no leak/rebroadcast).

**Verify**: `xcodebuild -only-testing:SingleThreadTests` (Stage 1 + 2 suites) green; no live EventKit store required.

---

## Stage 3: View-model lifecycle attachment (iOS/macOS + watch)

The handler/transport wiring: start the rechecker where `store.start()` already runs, stop on `.task` cancellation. No SwiftUI changes — attach points already exist (`.task` at `ContentView.swift:249-257`, `WatchReminderView.swift:59-61`).

**Files**: `SingleThread/ContentViewModel.swift`, `SingleThreadWatch/WatchReminderViewModel.swift`

**Key changes**:
```swift
// ContentViewModel (iOS/macOS) — @MainActor
var rechecker: StaleReminderRechecker?   // created after store.start()
func task() { store.start(); rechecker = StaleReminderRechecker(
    isShowingReminder: { store.listContent == .reminder },
    reload: { await store.reload() }, sleep: …, changeSource: EventStoreChangedObserver()) }
func stop()/deinit/defer { rechecker?.stop() }   // `.task` auto-cancel path

// WatchReminderViewModel (watchOS) — same shape, against its local store
```
Rechecker factory is injectable for tests (house pattern for `store` injection). Production `sleep` = real `Task.sleep`; poll interval stage-1 default 60 s. Watch reuses the same Core type (its store is EventKit read-only locally but `reload()` is identical).

**Tests**: extend `SingleThreadTests/ContentViewModelTests.swift` and `SingleThreadWatchTests/WatchAppViewModelTests.swift` (or `WatchReminderViewModelTests.swift`) with a fake rechecker/factory.
- Happy: `task()` starts the rechecker after `store.start()`; cancellation/deinit stops it exactly once.
- Sad: `stop()` is not double-called; a nil/injected failure path does not crash the view model.

**Verify**: `xcodebuild -only-testing:SingleThreadTests -only-testing:SingleThreadWatchTests` green on their destinations; then a manual/`--seed` check that a foregrounded on-screen reminder advances when its `isCompleted` flips.

---

## Stage 4: Widget timeline policy constant (widget — independent leaf)

No rechecker on widget (design decision 5; intents rely on WidgetKit auto-reload). Change only the refresh constant.

**Files**: `SingleThreadWidget/NextThingWidget.swift` (`:44-50`)

**Key changes**:
```swift
static let refreshInterval: TimeInterval = 5 * 60   // was 15 * 60; named constant
let refresh = Date().addingTimeInterval(Self.refreshInterval)
Timeline(entries: [entry], policy: .after(refresh))
```

**Tests**: no widget unit-test target exists (inventory in `conventions.md`); this stage's gate is compile + Periphery/lint cleanliness of the named constant — the widget's rem-render behavior is already covered by the entry-building path.

**Verify**: `make build` (widget target compiles) + `make periphery` clean; no `-only-testing` widget suite.

---

## Testing Checkpoints

Resume markers — before advancing, each must be green:

1. **After Stage 1**: `StaleReminderRecheckerTests` green (loop starts/stops, gate idles, coalesce).
2. **After Stage 2**: +`EventStoreChangedObserverTests` green (observer fires, unregister silent).
3. **After Stage 3**: +`ContentViewModelTests` / watch view-model tests green (start-after-`store.start()`, stop-once).
4. **After Stage 4**: `make build` + `make periphery` + `make lint` clean.
5. **Full gate — run ONCE, by the parent after all stages commit**: `./scripts/test.sh` (per AGENTS gate staging; workers verify with targeted `-only-testing:` suites only).

## Cross-cutting note

The only cross-cutting seam is the EventKit notification itself: pure loop logic (Stage 1) must not import NotificationCenter. Handled horizontally by injecting `EventStoreChangedObserving` at Stage 1 and supplying the concrete observer at Stage 2 — the design's observer-store-filter open risk is resolved by design decision 3 (global observation + gate + full reload, no cheap second fetch).
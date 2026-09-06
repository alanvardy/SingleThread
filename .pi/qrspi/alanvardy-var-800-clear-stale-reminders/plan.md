# Implementation Plan

## Overview

When the currently-displayed reminder is completed or deleted outside the app, each surfaced platform re-checks on its own and advances without a manual refresh: iOS/macOS and watchOS get a hybrid `StaleReminderRechecker` (`.EKEventStoreChanged` observer + 60 s poll fallback, gated to on-screen reminders, funnelled through the existing `ReminderStore.reload()`), and the widget only shortens its timeline policy from 15 → 5 minutes.

Stages build bottom-up; verify each checkpoint before advancing. Core/test targets keep explicit `@MainActor` (no default isolation); app/watch targets already default `@MainActor`.

---

## Stage 1: Re-check coordinator (`StaleReminderRechecker`, Core)

### Changes

#### 1. New coordinator + its conformance protocol
**File**: `SingleThreadCore/Sources/SingleThreadCore/StaleReminderRechecker.swift`
**Action**: create

```swift
import Foundation

/// Conformance seam so app/watch view models can be tested with a recording
/// fake instead of the real loop (house pattern: the store itself is injected;
/// here the rechecker is injected).
@MainActor
public protocol StaleReminderRechecking {
    func start()
    func stop()
}

/// Hybrid re-check coordinator for out-of-band reminder completion/deletion.
/// Combines a change-observer tick source (injected in Stage 2) with a slow
/// poll; both funnel into the on-screen gate → debounce/coalesce → `reload()`
/// so a currently-displayed reminder advances without a user gesture.
///
/// Pure coordination: owns no EventKit/NotificationCenter reference of its own;
/// `reload`, `sleep`, `isShowingReminder`, and (Stage 2) the change source are
/// all injected. The `sleep` seam mirrors `ReminderStoreSettle`.
@MainActor
public final class StaleReminderRechecker: StaleReminderRechecking, Sendable {
    // MARK: Types

    /// Poll-fallback interval. Named/tunable (design decision 5).
    public static let defaultPollInterval: Duration = .seconds(60)

    public typealias Reload = @MainActor () async -> Void
    public typealias IsShowingReminder = @MainActor () -> Bool
    public typealias Sleep = @Sendable (Duration) async -> Void

    // MARK: Lifecycle

    public init(
        isShowingReminder: @escaping IsShowingReminder,
        reload: @escaping Reload,
        sleep: @escaping Sleep,
        pollInterval: Duration = Self.defaultPollInterval
    ) {
        self.isShowingReminder = isShowingReminder
        self.reload = reload
        self.sleep = sleep
        self.pollInterval = pollInterval
    }

    // MARK: Control

    /// Begins the poll loop and arms an immediate first tick. Idempotent: a
    /// second `start()` while running is a no-op.
    public func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// Cancels the poll loop. Idempotent — safe to call more than once.
    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: Private

    private let isShowingReminder: IsShowingReminder
    private let reload: Reload
    private let sleep: Sleep
    private let pollInterval: Duration

    private var loopTask: Task<Void, Never>?
    /// True while a coalesced `reload()` is in flight.
    private var isReloading = false
    /// Set when a tick arrives during an in-flight reload; collapses N
    /// overlapping ticks into exactly one trailing reload.
    private var reloadPending = false

    private func runLoop() async {
        while !Task.isCancelled {
            receiveTick()
            if Task.isCancelled { return }
            await sleep(pollInterval)
        }
    }

    /// Single tick funnel: on-screen gate → debounce/coalesce → `reload()`.
    private func receiveTick() {
        guard isShowingReminder() else { return }
        if isReloading {
            reloadPending = true
            return
        }
        isReloading = true
        Task { [weak self] in
            await self?.drain()
        }
    }

    /// Runs one `reload()`, plus one trailing reload if a tick arrived while
    /// the previous reload was in flight (coalescing; mirrors
    /// `ContentViewModel.refreshManual`'s re-entrancy guard). No `await` sits
    /// between the final `reload()` return and `isReloading = false`, so a tick
    /// can't race the guard on the MainActor.
    private func drain() async {
        repeat {
            reloadPending = false
            await reload()
        } while reloadPending
        isReloading = false
    }
}
```

#### 2. Production factory (small `extension` in the same file)
**File**: `SingleThreadCore/Sources/SingleThreadCore/StaleReminderRechecker.swift`
**Action**: modify (append)

```swift
extension StaleReminderRechecker {
    /// Production wiring used by the view models: gate on
    /// `store.listContent == .reminder`, reload via `store.reload()`, real
    /// `Task.sleep` poll, and a global `.EKEventStoreChanged` observer
    /// (availability of the observer type lands in Stage 2 — the parameter
    /// below is added by that stage and defaults to nil until then).
    @MainActor
    public static func live(store: ReminderStore) -> StaleReminderRechecker {
        StaleReminderRechecker(
            isShowingReminder: { store.listContent == .reminder },
            reload: { await store.reload() },
            sleep: { try? await Task.sleep(for: $0) })
    }
}
```

> Deviation note: the structure lists this Stage 1 type without the `changeSource`
> parameter, and points `live(store:)` at Stage 3. The `changeSource`/observer
> wiring is added in **Stage 2** (per the structure's own "change-tick source
> injected at Stage 2" note); `live(store:)` is stubbed here with poll-only
> wiring and finished in Stage 2. The `StaleReminderRechecking` protocol is
> declared here (rather than Stage 3) so the view models in Stage 3 need no
> further Core edits.

#### 3. Tests
**File**: `SingleThreadTests/StaleReminderRecheckerTests.swift`
**Action**: create

Deterministic timing uses two `@MainActor` helpers (house `withCheckedContinuation`
rendezvous — no real sleeps; the rechecker's `sleep` seam is a gated one-shot):

```swift
import Testing
import SingleThreadCore

/// One-shot MainActor rendezvous: `wait()` suspends, `resume()` releases.
@MainActor
private final class AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
struct StaleReminderRecheckerTests {
    @Test
    func startFiresImmediateReloadWhenReminderShowing() async {
        let firstReload = AsyncGate()
        var reloadCount = 0
        let rechecker = StaleReminderRechecker(
            isShowingReminder: { true },
            reload: {
                reloadCount += 1
                if reloadCount == 1 { firstReload.resume() }
            },
            sleep: { _ in } // no-op: loop stays parked only until stop()
        )
        rechecker.start()
        await firstReload.wait()
        #expect(reloadCount == 1)
        rechecker.stop()
    }
}
```

> The no-op `sleep` is safe here **because** the test calls `stop()` immediately
> after the assertion; the tight poll loop between `start()` and `stop()` cannot
> fire a second reload in that window reliably, so for the poll-tick and
> stop-cancellation cases use the gated-sleep form below rather than a no-op.

Remaining cases, each following the same shape:

- `pollTickRefiresReloadWhenSleepResolves` — **happy**: `sleep: { _ in await sleepGate.wait() }`; a second `AsyncGate` resolves on `reloadCount == 2`. `start()`, then `sleepGate.resume()` (first poll sleep returns → second tick). Assert `reloadCount == 2`, then `stop()`.
- `startIdlesWhileNothingShowing` — **sad** (empty/all-done gate): `isShowingReminder: { false }`, gated sleep. `start()`; yield; assert `reloadCount == 0`. `stop()`.
- `stopIsIdempotentAndCancelsLoop` — **happy/sad**: after `start()` + first reload, call `stop()` twice (no crash); release a gated sleep afterwards and assert no further reload.
- `stopBeforePendingSleepResolvesCancelsWithoutSecondReload` — **sad**: gated sleep, `stop()` while the loop is parked on `sleepGate.wait()` (do not resume it); assert `reloadCount == 1` and the loop never fires again.

### Verification — Stage 1

#### Automated
- [x] `make format` (then `git diff` — confirm no phantom renames of the new test names)
- [x] `make lint` (SwiftFormat `--lint` + SwiftLint `--strict`) passes
- [x] `xcodebuild -only-testing:SingleThreadTests/StaleReminderRecheckerTests` green (pin the destination: resolve a UDID via `xcrun simctl list devices available` and pass `-destination 'platform=iOS Simulator,id=<udid>'` — a bare `name=iPhone 17` hangs with multiple runtimes)

#### Manual
- [ ] Sanity-read the coalescing branch: a second tick while `reload()` is in flight sets `reloadPending` and produces exactly one trailing reload, no more.

---

## Stage 2: EventKit change-observer source (Core)

### Changes

#### 1. Add `changeSource` to the rechecker
**File**: `SingleThreadCore/Sources/SingleThreadCore/StaleReminderRechecker.swift`
**Action**: modify

- Add stored property `private let changeSource: (any EventStoreChangedObserving)?` and `private var unregisterChange: (() -> Void)?`.
- Extend `init` with `changeSource: (any EventStoreChangedObserving)? = nil` (order: after `sleep`, before `pollInterval`) and assign it.
- In `start()`, before spawning the loop:
```swift
unregisterChange = changeSource?.onChange { [weak self] in
    self?.receiveTick()
}
```
- In `stop()`, before cancelling the loop:
```swift
unregisterChange?()
unregisterChange = nil
```
- Finish `live(store:)` by passing `changeSource: EventStoreChangedObserver()`.

#### 2. New observer type
**File**: `SingleThreadCore/Sources/SingleThreadCore/EventStoreChangedObserver.swift`
**Action**: create

```swift
import EventKit
import Foundation

/// Registers a `.EKEventStoreChanged` handler and returns an unregister
/// closure. Protocol seam so the rechecker's loop stays free of
/// NotificationCenter/EventKit coupling.
@MainActor
public protocol EventStoreChangedObserving {
    func onChange(_ handler: @escaping @MainActor () -> Void) -> (() -> Void)
}

/// Production implementation: observes globally (`object: nil`) and lets the
/// rechecker's on-screen gate + full `reload()` do the filtering (design
/// decision 3 — no cheap second-fetch path).
@MainActor
public final class EventStoreChangedObserver: EventStoreChangedObserving {
    private let center: NotificationCenter

    public init(center: NotificationCenter = .default) {
        self.center = center
    }

    public func onChange(_ handler: @escaping @MainActor () -> Void) -> (() -> Void) {
        let token = center.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return { [center] in
            center.removeObserver(token)
        }
    }
}
```

#### 3. Tests
**File**: `SingleThreadTests/EventStoreChangedObserverTests.swift`
**Action**: create

```swift
import EventKit
import Testing
import SingleThreadCore

@MainActor
struct EventStoreChangedObserverTests {
    @Test
    func onChangeFiresWhenEventStoreChangedPosted() async {
        let fired = AsyncGate()
        let observer = EventStoreChangedObserver()
        var count = 0
        let unregister = observer.onChange {
            count += 1
            fired.resume()
        }
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
        await fired.wait()
        #expect(count == 1)
        unregister()
    }

    @Test
    func unregisterRemovesObserver() async {
        let observer = EventStoreChangedObserver()
        var count = 0
        let unregister = observer.onChange { count += 1 }
        unregister()
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
        await Task.yield() // allow the .main queue block a chance to run
        #expect(count == 0)
    }
}
```

(`AsyncGate` is reused — either duplicate the tiny `@MainActor` helper in this file or move it to a shared test helper file.)

Also add an `@MainActor` rechecker test using a fake change source to prove coalescing across observer ticks:

```swift
@MainActor
private final class FakeChangeSource: EventStoreChangedObserving {
    var handler: (@MainActor () -> Void)?
    func onChange(_ handler: @escaping @MainActor () -> Void) -> (() -> Void) {
        self.handler = handler
        return {}
    }
    func fire() { handler?() }
}
```

- `overlappingChangeTicksCoalesceToSingleTrailingReload` — **sad**: gate a `reload` on a continuation (so the first reload is "in-flight"), call `fake.fire()` twice while in flight, release the reload, assert exactly **one** trailing reload (total 2, not 3).

### Verification — Stage 2

#### Automated
- [ ] `make lint` passes
- [ ] `xcodebuild -only-testing:SingleThreadTests` (Stage 1 + Stage 2 suites) green, pinned destination; no live EventKit store needed (`EventStoreChangedObserver` posts to `NotificationCenter.default` only)

#### Manual
- [ ] None beyond automated — the observer is exercised headlessly.

---

## Stage 3: View-model lifecycle attachment (iOS/macOS + watch)

No SwiftUI edits — both attach points already exist (`.task { await viewModel.task() }` at `ContentView.swift:249-257` and `WatchReminderView.swift:59-61`). The rechecker lifetime is made the `.task` lifetime: `task()` starts it and then suspends until SwiftUI cancels the task, a `defer` stops it.

### Changes

#### 1. ContentViewModel (iOS/macOS)
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify

- Add an `@MainActor` factory type (file-scoped) and init parameter with a default so every existing call site compiles unchanged:
```swift
/// Builds the re-check coordinator from the started store. Injectable so tests
/// can supply a recording fake; production is `StaleReminderRechecker.live`.
typealias RecheckerFactory = @MainActor (ReminderStore) -> (any StaleReminderRechecking)?

init(
    store: ReminderStore,
    backgroundImage: BackgroundImageStore,
    speechTranscriber: any SpeechTranscribing,
    showCompletionGlow: BoolPreferenceStore = ...,
    urlOpener: (any URLOpening)? = nil,
    makeRechecker: @escaping RecheckerFactory = { StaleReminderRechecker.live(store: $0) }) {
    ...
    self.makeRechecker = makeRechecker
    ...
}
```
- Add stored properties:
```swift
private var rechecker: (any StaleReminderRechecking)?
private let makeRechecker: RecheckerFactory
```
- Rewrite `task(_:)`:
```swift
func task(showUndatedReminders: Bool) async {
    store.showsUndatedReminders = showUndatedReminders
    await store.start()
    rechecker = makeRechecker(store)
    rechecker?.start()
    defer { rechecker?.stop(); rechecker = nil }
    await backgroundImage.refreshIfNeeded()
    // Suspend until SwiftUI cancels the `.task` on view disappear; the
    // cancellation makes `Task.sleep` throw (swallowed by `try?`), which runs
    // the `defer` above and stops the rechecker.
    try? await Task.sleep(for: .seconds(1_000_000_000))
}
```

#### 2. WatchReminderViewModel (watchOS)
**File**: `SingleThreadWatch/WatchReminderViewModel.swift`
**Action**: modify

Same shape — add the `makeRechecker: @escaping RecheckerFactory = { StaleReminderRechecker.live(store: $0) }` init parameter (new `typealias` or inline closure type), the two stored properties, and rewrite `task()`:
```swift
func task() async {
    await store.start()
    rechecker = makeRechecker(store)
    rechecker?.start()
    defer { rechecker?.stop(); rechecker = nil }
    try? await Task.sleep(for: .seconds(1_000_000_000))
}
```

#### 3. iOS/macOS view-model tests
**File**: `SingleThreadTests/ContentViewModelTests.swift`
**Action**: modify (append tests + a recording fake)

```swift
@MainActor
final class RecordingRechecker: StaleReminderRechecking {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}
```

- `taskStartsRecheckerAfterStoreStart` — **happy**: build a `ContentViewModel` with `loadsReminders: false` store and `makeRechecker: { _ in recording }`; `let t = Task { await viewModel.task(showUndatedReminders: true) }`; rendezvous/yield until the recording fake's `startCount == 1`; assert started once.
- `taskCancellationStopsRecheckerOnce` — **happy/stop-once**: cancel `t` and `await t.value`; assert `stopCount == 1` (not 0, not 2).
- `nilRecheckerFactoryDoesNotCrash` — **sad**: `makeRechecker: { _ in nil }`; run `task()` in a Task, cancel, `await t.value`; the `rechecker?.start()/stop()` optional chaining must not crash.

#### 4. watchOS view-model tests
**File**: `SingleThreadWatchTests/WatchReminderViewModelTests.swift`
**Action**: create

Same three cases as §3, against `WatchReminderViewModel` (its long init already has defaults for every non-store param per the existing test conventions; `makeRechecker` is added as anther defaulted param). Reuse a local `RecordingRechecker` (watch tests import `SingleThreadCore` + `@testable import SingleThreadWatch`; the fake lives in the watch test target since test targets aren't importable across bundles).

### Verification — Stage 3

#### Automated
- [ ] `make lint` passes
- [ ] `xcodebuild -only-testing:SingleThreadTests -only-testing:SingleThreadWatchTests` green on their respective pinned destinations (watch needs a paired/standalone watch simulator — see `make watch-test` / `WATCH_TEST_SIM`)

#### Manual
- [ ] Launch the iOS app (`make build` then run, or seed via `--seed '<json>' --ui-testing-noop-settle`), foreground a reminder, then complete that reminder in the macOS Reminders app (or flip `isCompleted` on another device): the on-screen card advances to the next reminder without pull-to-refresh.
- [ ] Confirm the wire-down on watch: with a reminder showing, complete it on the phone; the watch card advances on the next phone→watch push (existing sync reload) and within ~60 s via the poll fallback.

---

## Stage 4: Widget timeline policy constant (widget — independent leaf)

### Changes

#### 1. Shorten the timeline refresh interval
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

- Add a named constant to `NextThingProvider` (next to `placeholder`/`getSnapshot` in the struct):
```swift
struct NextThingProvider: TimelineProvider {
    /// How soon to re-ask EventKit for a possibly-changed current reminder.
    /// Was 15 min; shortened so an out-of-band completion/deletion clears the
    /// widget sooner. This is the widget's entire staleness mechanism — no
    /// rechecker (design decision 5).
    private static let refreshInterval: TimeInterval = 5 * 60
    ...
```
- Replace the literal in `getTimeline` (currently `:44-50`):
```swift
let refresh = Date().addingTimeInterval(Self.refreshInterval)
Timeline(entries: [entry], policy: .after(refresh))
```

### Verification — Stage 4

#### Automated
- [ ] `make build` (widget target compiles; the constant resolves within the module)
- [ ] `make periphery` clean (the new constant is used — no unused-declaration hit)
- [ ] `make lint` clean

#### Manual
- [ ] No widget unit-test target exists (per conventions inventory) — verify via a simulator widget after an app-side completion that the widget's card advances within ~5 minutes of the timeline refresh.

---

## Testing Checkpoints (resume markers)

1. **After Stage 1**: `StaleReminderRecheckerTests` green.
2. **After Stage 2**: + `EventStoreChangedObserverTests` green.
3. **After Stage 3**: + `ContentViewModelTests` / `WatchReminderViewModelTests` green.
4. **After Stage 4**: `make build` + `make periphery` + `make lint` clean.
5. **Full gate — run ONCE, by the parent after all stages commit**: `./scripts/test.sh` (formats, lints, builds, Periphery, iOS unit+UI, watch build/UI/unit, macOS unit — identical to CI).

## Cross-cutting notes

- The only cross-cutting seam is the EventKit notification: pure loop logic (Stage 1) never imports `NotificationCenter`/`EventKit`; it takes `EventStoreChangedObserving` (Stage 2) + injected `reload`/`sleep`.
- Core is imported **non-`@testable`** in unit tests, so every rechecker/observer surface the tests touch (`init`, `start`, `stop`, `onChange`, `defaultPollInterval`, typealiases) must stay `public`.
- No widget reload wiring beyond the constant; intents keep nil hooks and rely on WidgetKit's automatic timeline reload.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` covers the app/watch targets only — the two new Core types annotate `@MainActor` explicitly, and the two view-model `task()` bodies must NOT wrap work in `Task { @MainActor in }` (redundant there).
- Unit-test names must not start with `test`/`testing` (SwiftFormat strips the prefix); the names above follow that rule.
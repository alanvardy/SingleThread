# Structure Outline

## Approach

Build a daily completion counter ("cleared N today") from the persistence
layer up — a new `DailyCompletionStore` type, wired into `ReminderStore`'s
existing complete/undo paths, surfaced through a transient auto-dismissing
overlay on the single card. Every layer is independently tested before the
next layer touches it.

---

## Stage 1: `DailyCompletionStore` — persistence layer

New struct in `SingleThreadCore` that stores a **start-of-day
marker** + **today's count** in `AppGroup.defaults`. Day-rollover is lazy:
on `increment()`, if the stored marker ≠ `Calendar.current.startOfDay(for: Date())`,
reset count to 1 and write the new marker; otherwise increment normally.
`decrement()` clamps at 0. `resetForTesting()` clears both keys.

### Files
- **New**: `SingleThreadCore/Sources/SingleThreadCore/DailyCompletionStore.swift`

### Key changes
- `struct DailyCompletionStore`
- `init(defaults: UserDefaults = AppGroup.defaults, markerKey: String = Self.defaultsMarkerKey, countKey: String = Self.defaultsCountKey)`
- `static let defaultsMarkerKey = "completionDayMarker"` — `TimeInterval` (start-of-day)
- `static let defaultsCountKey = "completionTodayCount"` — `Int`
- `var todayCount: Int { get }` — reads `defaults.integer(forKey: countKey)` (0-defaulted)
- `var dayMarker: TimeInterval { get }` — reads `defaults.double(forKey: markerKey)` (0-defaulted)
- `func increment()` — lazy rollover + increment
- `func decrement()` — `max(0, todayCount - 1)`
- `func resetForTesting()` — sets both keys to 0

### Tests
- **New**: `SingleThreadTests/DailyCompletionStoreTests.swift` — `@Suite(.serialized)`
- `defaultsAreZero` — fresh store, both keys absent → 0
- `incrementSetsCountToOne` — first increment → count = 1, marker = today
- `incrementSameDay` — second increment → count = 2, marker unchanged
- `dayRolloverResetsCount` — inject yesterday's marker, increment → count = 1, marker = today
- `decrementClamps` — count 0, decrement → stays 0
- `decrementAfterIncrement` — count 2 → decrement → 1
- `survivesRecreation` — new instance reads same keys → count preserved
- `perKeyIsolation` — two stores with UUID-keyed isolation don't interfere
- `resetForTesting` — after increment, reset → both keys 0

### Verify
```bash
make build && xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:SingleThreadTests/DailyCompletionStoreTests
```

---

## Stage 2: `ReminderStore` integration — business logic

Inject `DailyCompletionStore` into `ReminderStore` (parallel to
`completionCounter: CompletionCounterStore`). Call `dailyCompletion.increment()`
in `completeReminder` (iOS branch, after `completionCounter.increment()` at
:246) and `dailyCompletion.decrement()` in `undoLastCompletion` (after
`completionCounter.decrement()` at :278). Expose `dailyCompletion` as a
`public private(set) var` so the view model can read `todayCount`.

### Files
- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` — init param + complete/undo branches

### Key changes
- `ReminderStore.init(…, dailyCompletion: DailyCompletionStore = DailyCompletionStore(), …)`
- `public private(set) var dailyCompletion: DailyCompletionStore`
- `completeReminder(identifier:)` iOS branch: add `dailyCompletion.increment()` after :246
- `undoLastCompletion()`: add `dailyCompletion.decrement()` after :278

### Tests
- **Existing**: `SingleThreadTests/ReminderStoreTests.swift` — new tests in the integration sections
- `completeReminderIncrementsDailyCount` — complete → `dailyCompletion.todayCount` = 1
- `completeReminderSameDayIncrements` — two completions → count = 2
- `undoDecrementsDailyCount` — complete + undo → count = 0
- `undoClampsDailyCountAtZero` — undo from 0 → count stays 0
- `dailyCountSurvivesReload` — complete → reload → count still 1
- Test pattern: use `InMemoryEventStore` + `noopSettle` + `makeReminder`; assert `store.dailyCompletion.todayCount` directly

### Verify
```bash
make build && xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:SingleThreadTests/ReminderStoreTests
```

---

## Stage 3: `CompletionMomentumOverlay` — presentation model

New `@MainActor @Observable` class in `SingleThreadCore` that mirrors
`CompletionGlow`'s trigger/auto-dismiss pattern. Stores the `todayCount` to
display while active. `trigger(count:)` sets `isActive = true`, records the
count, and schedules auto-dismiss after `duration` (default 2.0 s — longer
than the glow's 0.5 s so the text is readable). Re-triggering resets the timer.

### Files
- **New**: `SingleThreadCore/Sources/SingleThreadCore/CompletionMomentumOverlay.swift`

### Key changes
- `@MainActor @Observable public final class CompletionMomentumOverlay`
- `public private(set) var isActive = false`
- `public private(set) var todayCount = 0`
- `public var duration: TimeInterval = 2.0`
- `public func trigger(count: Int)` — sets `todayCount`, `isActive = true`, schedules dismiss
- `private var dismissTask: Task<Void, Never>?`

### Tests
- **New**: `SingleThreadTests/CompletionMomentumOverlayTests.swift`
- `triggerSetsActiveAndCount` — `trigger(count: 5)` → `isActive = true`, `todayCount = 5`
- `autoDismissAfterDuration` — inject `duration = 0.05`, trigger, `Task.sleep(0.1)`, assert `isActive = false`
- `retriggerResetsTimer` — trigger, sleep 0.03, trigger again, sleep 0.06 → still active (first timer cancelled)
- `defaultDuration` — `duration == 2.0`

### Verify
```bash
make build && xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:SingleThreadTests/CompletionMomentumOverlayTests
```

---

## Stage 4: Preference gating + `ContentViewModel` trigger + `ContentView` render

Wire the full UI surface. This stage ties together all three previous layers:
reads the count from `DailyCompletionStore` (Stage 1+2), gates with a
`BoolPreferenceStore` (new key), triggers the overlay (Stage 3), and renders
it in `ContentView`.

### 4a: Preference key + SettingsBindings + ReminderSettingsView toggle

- `BoolPreferenceKey.swift`: add `case showCompletionMomentum` (fallback `true`)
- `SettingsBindings.swift`: add `showCompletionMomentum` computed property
  (mirrors `showCompletionGlow` — `access`/`withMutation` + `BoolPreferenceStore`)
- `ReminderSettingsView.swift`: add `@Binding var showCompletionMomentum: Bool` +
  `Toggle` below the glow toggle (same section, "Completion Momentum" label)

### 4b: ContentViewModel trigger

- `ContentViewModel.init`: add `showCompletionMomentum: BoolPreferenceStore` param
  (default: `BoolPreferenceStore(key: BoolPreferenceKey.showCompletionMomentum.rawValue, fallback: true)`)
- Add `completionMomentum: CompletionMomentumOverlay` property (default `CompletionMomentumOverlay()`)
- `completeCurrentReminder()`: add second guarded trigger after the glow trigger:
  ```swift
  if await store.completeCurrentReminder() {
      if showCompletionGlow.isEnabled { completionGlow.trigger() }
      if showCompletionMomentum.isEnabled {
          completionMomentum.trigger(count: store.dailyCompletion.todayCount)
      }
  }
  ```

### 4c: ContentView render

- `ContentView.swift`: add `completionMomentum` overlay near the glow overlay
  (~line 553-562). Mirror the glow pattern: `.overlay` with
  `.allowsHitTesting(false)`, fade animation `.animation(.easeInOut(duration: 0.4), value: completionMomentum.isActive)`.
  Text: `"You've cleared \(completionMomentum.todayCount) today"` in a subtle
  style (e.g. `.foregroundStyle(.secondary)`, positioned center or bottom of card).
- Coexists with the glow: glow is a background tint; overlay is foreground
  text — they layer without collision per the design risk note.

### Files
- `SingleThreadCore/Sources/SingleThreadCore/BoolPreferenceKey.swift`
- `SingleThread/SettingsBindings.swift`
- `SingleThread/ReminderSettingsView.swift`
- `SingleThread/ContentViewModel.swift`
- `SingleThread/ContentView.swift`

### Verify
- **Build**: `make build` (iOS) — confirms all wiring compiles
- **Sim check**: launch in simulator, complete a reminder → overlay appears with "You've cleared 1 today", auto-dismisses; complete again → "You've cleared 2 today"; toggle off in settings → no overlay
- No new unit tests at this stage (the touched layers are already tested; the
  toggle follows the identical `showCompletionGlow` pattern and the trigger
  forwarding is a one-line call to a tested model)

---

## Stage 5: Seed/reset seams — testing infrastructure

Add the new persisted keys to the `--seed` and `resetPersistedState` seams so
UI tests and seeded launches start clean and can inject known daily counts.

### Files
- `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift` — seed fields + reset keys
- `SingleThread/AppViewModel.swift` — `seededStore` wiring

### Key changes
- `UITestingSeed`: add `var completionDayMarker: TimeInterval?` + `var completionTodayCount: Int?` to the payload struct
- `CodingKeys`: add `"completionDayMarker"`, `"completionTodayCount"`
- `resetPersistedState()`: add `DailyCompletionStore.defaultsMarkerKey` and `DailyCompletionStore.defaultsCountKey` to the removal list
- `AppViewModel.seededStore`: write `dailyCompletion` values from seed (mirror
  `completionCount` write at `AppViewModel.swift:296`)

### Tests
- **Existing**: `SingleThreadTests/UITestingSeedTests.swift` — add:
- `seedParsesDailyCompletion` — seed with both fields → store reads them back
- `resetClearsDailyCompletion` — write then reset → both keys absent (0)
- `seedDailyCountUnclamped` — seed with `completionTodayCount: 250` → reads back 250

### Verify
```bash
make build && xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:SingleThreadTests/UITestingSeedTests
```

---

## Testing Checkpoints

| Stage | Checkpoint — must be green before advancing |
|-------|---------------------------------------------|
| 1 | `DailyCompletionStoreTests` — all 9 tests pass |
| 2 | `ReminderStoreTests` — new daily-completion tests + existing suite pass |
| 3 | `CompletionMomentumOverlayTests` — all 4 tests pass |
| 4 | `make build` succeeds + sim-check overlay visible/correct |
| 5 | `UITestingSeedTests` — new seed tests + existing suite pass |

### Full-gate verification

After Stage 5 commits, launch the full `./scripts/test.sh` gate via the
`run-gate` skill (one async gate subagent in a worktree). This covers
`make format`, `make lint`, `make build`, `make periphery`, and the full unit
+ UI test suite. No new watch keys or UI tests are added, so the watch and UI
test suites are expected to pass unchanged.

---

## Not in scope (explicit)

- No watch sync keys, `PayloadKey` additions, `pushAll`/`apply` hooks, or
  `Show*State` holders
- No `completionCount` (lifetime) changes
- No haptics, sounds, or toasts
- No streak logic, day-history, or "longest streak" records
- No persistent badge on the card
- No UTC/timezone-independent day tracking
- No UI tests (overlay is transient; unit tests cover the model + integration;
  sim-check covers the visual)
# Structure Outline

## Approach

Add a single-level undo for the most-recent completion: an in-memory
`UndoStore` holds the `EKReminder` reference at complete-time, a new
`ReminderStore.undoLastCompletion()` reverts it, and a `.topLeading`
control-plate button in `ContentView` surfaces it — gated on both the
retained reference and a new `showUndoButton` settings toggle. Each layer
is fully tested before the next begins.

---

## Stage 1: UndoStore type

Delivers the transient holder type — an `@Observable` class that stores one
optional `EKReminder` reference, exposes a `hasUndoableReminder` computed
property, and supports retain/clear. Zero dependencies; tested in isolation.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/UndoStore.swift` (new)

**Key changes**:
- `@MainActor @Observable public final class UndoStore` — new type
  - `public private(set) var lastCompletedReminder: EKReminder?`
  - `public var hasUndoableReminder: Bool { lastCompletedReminder != nil }`
  - `public func retain(_ reminder: EKReminder)` — stashes the reference; overwrites any prior
  - `public func clear()` — nils out the reference

**Tests**: `SingleThreadTests/UndoStoreTests.swift` (new)
- `testRetainStoresReminder` — retain sets `lastCompletedReminder`
- `testClearNilsReminder` — after retain, clear sets to nil
- `testRetainOverwritesPrevious` — second retain replaces first
- `testHasUndoableReminderReflectsState` — computed flag is true after retain, false after clear, false initially

**Verify**:
```fish
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests/UndoStoreTests
```

---

## Stage 2: ReminderStore undo logic

Wires the `UndoStore` into `ReminderStore`: retain on complete, revert on undo,
decrement the counter. Adds `decrement()` to `CompletionCounterStore`.
Builds on Stage 1; tested with `InMemoryEventStore` fixtures.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` (modify)
- `SingleThreadCore/Sources/SingleThreadCore/CompletionCounterStore.swift` (modify)
- `SingleThreadTests/ReminderStoreTests.swift` (modify)
- `SingleThreadTests/CompletionCounterStoreTests.swift` (modify)

**Key changes**:
- `ReminderStore`:
  - `public let undoStore = UndoStore()` — new property, per-instance, no ctor injection needed
  - In `completeReminder(identifier:)` iOS branch, **before** `try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)` and `await reload()`: add `undoStore.retain(reminder)` on the found `EKReminder`
  - `@discardableResult public func undoLastCompletion() async -> Bool` — new method:
    - `guard canMutate, let reminder = undoStore.lastCompletedReminder else { return false }`
    - `reminder.isCompleted = false`
    - `try eventStore.save(reminder, commit: true)`
    - `completionCounter.decrement()`
    - `undoStore.clear()`
    - `try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)`
    - `await reload()`
    - Return `true`; on throw, log and return `false`
- `CompletionCounterStore`:
  - `public func decrement()` — sets `max(0, count - 1)` to prevent negative counts
  - Doc comment update: "never decremented" → "only decremented by undo"

**Tests**:
- `CompletionCounterStoreTests`:
  - `testDecrementReducesCount` — 5 → 4
  - `testDecrementDoesNotGoBelowZero` — 0 → 0
- `ReminderStoreTests` (new suite or additions):
  - `testCompleteRetainsInUndoStore` — after complete, `store.undoStore.hasUndoableReminder` is true
  - `testUndoLastCompletionRevertsReminder` — complete → undo → reminder is back in `visibleReminders`, `isCompleted` is false
  - `testUndoLastCompletionClearsUndoStore` — after undo, `hasUndoableReminder` is false
  - `testSecondCompleteOverwritesUndoStore` — complete A → complete B → undo B (A is gone), verify B reverted
  - `testUndoReturnsFalseWhenNoRetainedReminder` — undo on fresh store returns false
  - `testUndoReturnsFalseWhenGated` — undo at gate boundary returns false when `canMutate` is false
  - `testUndoDecrementsCompletionCounter` — complete → counter up → undo → counter down

**Verify**:
```fish
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests/ReminderStoreTests \
  -only-testing:SingleThreadTests/CompletionCounterStoreTests
```

---

## Stage 3: Settings toggle plumbing

Adds the `showUndoButton` preference toggle following the `enableActionButtons`
pattern exactly: `@AppStorage` (`.standard`, iOS-only, default `true`),
`SettingsBindings` bag entry, `InterfaceSettingsView` Toggle row, sheet
`.onChange` write-back. Independent of undo logic; can run in parallel with
Stage 2 but must be green before Stage 4.

**Files**:
- `SingleThread/ContentView.swift` (modify — `@AppStorage` decl + `.onChange` + `makeSettingsBag`)
- `SingleThread/SettingsBindings.swift` (modify — property + init param)
- `SingleThread/InterfaceSettingsView.swift` (modify — `@Binding` + Toggle row)

**Key changes**:
- `ContentView.swift`:
  - `#if os(iOS) @AppStorage("showUndoButton") private var showUndoButton = true` — new `.standard`-backed property (alongside `enableActionButtons`)
  - `.onChange(of: bag.showUndoButton) { _, new in showUndoButton = new }` — in the sheet write-back block
  - `makeSettingsBag()` — add `showUndoButton: showUndoButton` parameter in `#if os(iOS)` branch
- `SettingsBindings.swift`:
  - `var showUndoButton: Bool` — new stored property
  - Init parameter: `showUndoButton: Bool = true` — defaults to true per design
- `InterfaceSettingsView.swift`:
  - `#if os(iOS) @Binding var showUndoButton: Bool` — new binding
  - Toggle row inside `#if os(iOS)` block (alongside `enableActionButtons`):
    ```swift
    Toggle(isOn: $showUndoButton) {
        Label("Show undo button", systemImage: "arrow.uturn.backward")
    }
    ```
  - Preview: add `showUndoButton: .constant(true)` in `#if os(iOS)` branch

**Tests**:
- `SingleThreadTests/SettingsViewTests.swift` — add or extend to verify the toggle bound value propagates; if the existing suite covers `enableActionButtons` Toggle presence via accessibility label, extend the same pattern for `showUndoButton`

**Verify**:
```fish
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests/SettingsViewTests
```

> **Note on `persistedKeys`**: The design decides against adding `showUndoButton`
> to `UITestingSeed.persistedKeys`. The `enableActionButtons` toggle (identical
> pattern — `.standard`, iOS-only) **is** in `persistedKeys`, while
> `backgroundFadePercent` (also `.standard`) is not — the codebase is already
> inconsistent. If a relaunch-persistence UI test is added in Stage 5,
> `showUndoButton` must be added to `persistedKeys` or that test will fail
> because `resetPersistedState()` won't clear it between seed runs. The
> implementing stage should reconcile this.

---

## Stage 4: UI button in ContentView

Adds the undo control-plate button to the `.topLeading` overlay of
`ContentView` and wires it through `ContentViewModel`. Builds on Stages 2
and 3; the button is visible only when `undoStore.hasUndoableReminder &&
showUndoButton && store.canMutate`.

**Files**:
- `SingleThread/ContentView.swift` (modify — `.overlay(alignment: .topLeading)` + imports if needed)
- `SingleThread/ContentViewModel.swift` (modify — new forwarding method)

**Key changes**:
- `ContentViewModel.swift`:
  - `func undoLastCompletion() async { await store.undoLastCompletion() }` — new forwarding method (no glow trigger; undo is its own feedback)
- `ContentView.swift`:
  - New `.overlay(alignment: .topLeading)` on the root ZStack (after the existing `.topTrailing` gear overlay):
    ```swift
    #if os(iOS)
    .overlay(alignment: .topLeading) {
        if viewModel.store.undoStore.hasUndoableReminder, showUndoButton, viewModel.store.canMutate {
            Button {
                Task { await viewModel.undoLastCompletion() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .controlPlate()
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Undo completion")
            .accessibilityAddTraits(.isButton)
            .padding(.top, 8)
            .padding(.leading, 12)
        }
    }
    #endif
    ```
  - Style follows the gear overlay precedent: same font, plate, accessibility traits, padding pattern — opposite corner.

**Tests**: No separate unit-test stage; UI tests in Stage 5 exercise the button.
A manual smoke test on iPhone 17 simulator is the immediate checkpoint.

**Verify**:
```fish
# Build check (no dedicated unit tests at this layer)
xcodebuild build -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug
```
Then manual: launch, complete a reminder, confirm undo button appears top-left,
tap it, confirm reminder returns and button disappears. Confirm button hidden
when `showUndoButton` toggle is off.

---

## Stage 5: UI tests

End-to-end XCTest coverage for the undo button appearance/disappearance and
the `showUndoButton` toggle. Uses the `--seed '<json>'` seam for deterministic
state; builds on all prior stages.

**Files**:
- `SingleThreadUITests/SingleThreadUITestsFlows.swift` (modify — add test methods)
- `SingleThreadUITests/` (possibly new `UndoUITests.swift` if test count warrants)

**Key changes**:
- `testUndoButtonAppearsAfterCompleteAndUndoRemovesReminder`:
  - Seed: one incomplete reminder
  - Tap complete (via action button or swipe)
  - Assert undo button exists (`app.buttons["Undo completion"]`)
  - Tap undo button
  - Assert reminder reappears in list
  - Assert undo button no longer exists
- `testUndoButtonHiddenWhenToggleOff`:
  - Seed: one incomplete reminder, `enableActionButtons: true`
  - Complete the reminder → undo button appears
  - Open settings, flip `showUndoButton` toggle to off via `flipToggle`
  - Dismiss settings
  - Assert undo button no longer exists
- `testUndoButtonDoesNotAppearWithoutCompletion`:
  - Seed: one incomplete reminder
  - Assert undo button does not exist on fresh launch

**Tests**:
- Above three UI test functions, plus the existing `testAccessibilityAudit()` will pick up the new button's accessibility label/traits automatically.

**Verify**:
```fish
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadUITests
```

---

## Testing Checkpoints

After each stage, the following must be green before advancing:

1. **Stage 1**: `UndoStoreTests` pass
2. **Stage 2**: `ReminderStoreTests` + `CompletionCounterStoreTests` pass (undo suites)
3. **Stage 3**: `SettingsViewTests` pass
4. **Stage 4**: Debug build succeeds; manual smoke test passes
5. **Stage 5**: `SingleThreadUITests` pass (undo-specific + existing accessibility audit)

Full gate after all stages:
```fish
./scripts/test.sh
```

---

## Open Decisions for Implementation

- **Counter decrement**: Stage 2 adds `CompletionCounterStore.decrement()`. If
  the decision is reversed (don't decrement), skip that method and adjust undo
  tests. The design flags this: non-decrementing undo at exactly count=100
  would leave the user unable to re-complete that reminder.
- **`persistedKeys` entry**: The design says no, but `enableActionButtons` has
  one. If Stage 5 adds a relaunch-persistence UI test (toggle survives
  relaunch), `showUndoButton` must be added to `persistedKeys`. The
  implementing stage should either omit the persistence-relaunch test or add
  the key.
- **Undo button gating on `canMutate`**: The button is hidden when the gate is
  closed (`!canMutate`), matching the design's direction. The store method
  also guards on `canMutate` (defense in depth). If the gate design review
  reaches a different conclusion (e.g. undo should always be allowed regardless
  of gate), update both layers.
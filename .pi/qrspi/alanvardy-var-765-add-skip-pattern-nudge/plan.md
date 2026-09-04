# Implementation Plan

## Overview

Persist a per-reminder skip count (`[String: Int]`) in the App Group suite, increment it only on local interactive skips, and when a reminder's count first crosses 6, interrupt the skip and surface an in-card nudge banner that opens Delete / Reschedule / View-in-Reminders (iOS) or Delete-only (watch). Counts sync bidirectionally, latest-wins, and reset/prune on action, complete, and window exit.

### Resolved decisions (not left open)

- **Nudge timing (chosen by user — Option A)**: the crossing skip *interrupts* the cycle. On the 6th skip, the count increments and `onSkipNudgeRequested` fires, but the skip set is **not** applied — the reminder stays visible with the banner. Acting (delete/reschedule) or dismissing, then skipping again, resumes the normal advance (count 7+).
- **Re-fire policy**: the nudge fires only on the *first* crossing (`old < 6 && new >= 6`). A later skip of the same reminder (count 7, 8, …) advances silently; the reminder must be reset (delete/reschedule/complete) or pruned (window exit) before it can cross 6 again.
- **macOS**: there is no nudge UI on macOS. The 6th-skip interrupt is gated to `#if os(iOS) || os(watchOS)`; on macOS skips always advance (the count still increments, so a paired phone/watch nudges via sync).
- **Widget**: `skipCurrentReminderImmediately` always advances (the widget has no nudge surface and the intent must complete); it still increments the count so the phone/watch surface the nudge.

---

## Phase 1: Persistence — `SkipCountStore` + `"skipCounts"` key

Delivers a standalone store (shaped exactly after `SkippedReminderStore`) plus the pure nudge-threshold logic, decoupled from the skip-set lifecycle so a `reconcileSkipState` prune can't wipe counts. Registers the key in the `--seed` reset seam.

### Changes

#### 1. `SkipCountStore` + `SkipCountLogic` (new)
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkipCountStore.swift`
**Action**: create

```swift
import Foundation

/// Pure logic for the skip-count nudge threshold. No EventKit/UI dependencies.
public nonisolated enum SkipCountLogic {
    /// Default threshold: nudged once skipped more than five times (count ≥ 6).
    public static let defaultThreshold = 6

    /// True when `count` has reached the nudge threshold (count ≥ 6 by default,
    /// i.e. "skipped more than five times").
    public static func shouldNudge(_ count: Int, threshold: Int = defaultThreshold) -> Bool {
        count >= threshold
    }

    /// True when incrementing from `old` to `new` first crosses the threshold.
    /// Fires once on the first crossing so the nudge never re-fires on every
    /// subsequent skip — the count must reset (or be pruned) to re-cross.
    public static func crossedThreshold(from old: Int, to new: Int, threshold: Int = defaultThreshold) -> Bool {
        old < threshold && new >= threshold
    }
}

/// Persists the per-reminder skip counts (`identifier → count`) in UserDefaults.
public struct SkipCountStore {
    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "skipCounts") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [String: Int] {
        defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    public func save(_ counts: [String: Int]) {
        defaults.set(counts, forKey: key)
    }

    private let defaults: UserDefaults
    private let key: String
}
```

> `UserDefaults.dictionary(forKey:)` round-trips `[String: Int]` (values are `NSNumber`). Same dict precedent as `PendingCompletionStore` (`[String: TimeInterval]`).

#### 2. Register the key in the `--seed` reset seam
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

In `UITestingSeed.resetPersistedState()`'s `persistedKeys` array, add `"skipCounts"` (so it is cleared from **both** `AppGroup.defaults` and `UserDefaults.standard`):

```swift
    private static let persistedKeys = [
        "skippedReminderIdentifiers",
        "skipCounts",
        "excludedListTitles",
        ...
    ]
```

### Verification

#### Automated
- [x] `make build` passes
- [x] New `SingleThreadTests/SkipCountStoreTests.swift` passes (`make test`, or targeted `xcodebuild -only-testing:SingleThreadTests/SkipCountStoreTests` with a `,id=`-pinned destination)
- [x] `make test` green for `UITestingSeedTests` after adding a reset-clears assertion

New `SingleThreadTests/SkipCountStoreTests.swift` (Swift Testing):
- `roundTripsSaveAndLoad` — save `["a": 3, "b": 1]`, load returns the same dict.
- `loadsEmptyByDefault` — a fresh store over an isolated UUID-keyed `UserDefaults(suiteName:)` returns `[:]`.
- `isolatesByUUIDKey` — two stores over different UUID suites don't see each other's data.
- `shouldNudgeFiresOnlyAtOrPastThreshold` — `@Test(arguments:)` table: `0…5 → false`, `6, 7, 20 → true`.
- `crossedThresholdFiresOnlyOnce` — `@Test(arguments:)` table over `(old, new)` pairs: `(5,6)→true`, `(6,7)→false`, `(4,5)→false`, `(0,6)→true`, `(5,7)→true`.

Extend `SingleThreadTests/UITestingSeedTests.swift`:
- `resetPersistedStateClearsSkipCounts` — write `AppGroup.defaults.set(["x": 1], forKey: "skipCounts")`, call `UITestingSeed.resetPersistedState()`, assert `AppGroup.defaults.dictionary(forKey: "skipCounts") == nil` (and same for `.standard`).

#### Manual
- [ ] On the iPhone simulator, confirm `"skipCounts"` round-trips through `AppGroup.defaults` (set in a scratch `xcrun simctl spawn booted defaults write group.app.alanvardy.SingleThread skipCounts -dict "a" 3`, then a quick debugger/`defaults read`), never `.standard`.

---

## Phase 2: Store — skip-count lifecycle + threshold trigger in `ReminderStore`

The sole writer of counts, the interrupt-on-6th-skip behavior, an accessor, and the nudge hook.

### Changes

#### 1. `ReminderStore` — injected store, hook, accessor, helpers
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

**(a)** Add an init parameter (beside `skipStore`) and a stored property:

```swift
        skipStore: SkippedReminderStore = SkippedReminderStore(),
        skipCountStore: SkipCountStore = SkipCountStore(),
```

```swift
    private let skipStore: SkippedReminderStore
    private let skipCountStore: SkipCountStore
```

**(b)** Add the hook near `onSkipSetChanged`:

```swift
    /// Hook fired when a reminder's skip count first crosses the nudge threshold
    /// (6). Passes the reminder's identifier. Wired by the iOS/watch view models
    /// to surface the nudge banner.
    public var onSkipNudgeRequested: ((String) -> Void)?
```

**(c)** Add the accessor and private helpers (near the other private helpers):

```swift
    /// The persisted skip count for a reminder, `0` when unknown.
    public func skipCount(for identifier: String) -> Int {
        skipCountStore.load()[identifier] ?? 0
    }

    /// Increments the count and persists it, returning `true` when the increment
    /// first crossed the nudge threshold.
    private func incrementSkipCount(for identifier: String) -> Bool {
        var counts = skipCountStore.load()
        let old = counts[identifier] ?? 0
        let new = old + 1
        counts[identifier] = new
        skipCountStore.save(counts)
        return SkipCountLogic.crossedThreshold(from: old, to: new)
    }

    /// Removes a reminder's count (delete/reschedule/complete). No-op when absent.
    private func resetSkipCount(for identifier: String) {
        var counts = skipCountStore.load()
        guard counts.removeValue(forKey: identifier) != nil else { return }
        skipCountStore.save(counts)
    }

    /// Prunes counts for identifiers no longer in the in-window fetched set, so a
    /// reminder that leaves the window re-zeros (mirrors the skip-set prune).
    private func reconcileSkipCounts(visibleShown: [EKReminder]) {
        let windowIDs = Set(visibleShown.map(\.calendarItemIdentifier))
        let counts = skipCountStore.load()
        let pruned = counts.filter { windowIDs.contains($0.key) }
        if pruned.count != counts.count {
            skipCountStore.save(pruned)
        }
    }
```

**(d)** Make `skipCurrentReminder()` interrupt on crossing (iOS/watch):

```swift
    public func skipCurrentReminder() {
        guard canMutate else { return }
        guard let reminder = visibleReminders.first else { return }
        let identifier = reminder.calendarItemIdentifier
        #if os(iOS) || os(watchOS)
            if incrementSkipCount(for: identifier) {
                // 6th skip: interrupt the cycle and prompt instead of advancing.
                onSkipNudgeRequested?(identifier)
                return
            }
        #else
            _ = incrementSkipCount(for: identifier)
        #endif
        let updated = updatedSkipSet(afterSkipping: identifier)
        let capturedGeneration = skipGeneration
        Task {
            await settle()
            if applySkipSet(updated, generation: capturedGeneration) {
                await reload()
            }
        }
    }
```

**(e)** Make `skipCurrentReminderImmediately()` always advance (widget) but still record the count:

```swift
    @discardableResult
    public func skipCurrentReminderImmediately() -> Bool {
        guard canMutate else { return false }
        guard let reminder = visibleReminders.first else { return false }
        let identifier = reminder.calendarItemIdentifier
        if incrementSkipCount(for: identifier) {
            // Widget has no nudge UI; the count still persists so the paired
            // phone/watch surfaces the prompt. The skip still applies.
            onSkipNudgeRequested?(identifier)
        }
        let updated = updatedSkipSet(afterSkipping: identifier)
        applySkipSet(updated)
        return true
    }
```

**(f)** Reset the count in `completeReminder(identifier:)` — both branches:
- watchOS branch, inside `if removed` after `onCompleteReminder?(identifier)`: `resetSkipCount(for: identifier)`
- iOS branch, after `undoStore.retain(reminder)` (before `await settle()`): `resetSkipCount(for: identifier)`

**(g)** Reset the count in `deleteReminder(identifier:)` — both branches:
- watchOS branch after `reminders.removeAll { … }`: `resetSkipCount(for: identifier)`
- iOS branch after `try eventStore.remove(reminder, commit: true)`: `resetSkipCount(for: identifier)`

**(h)** Prune in `reconcileSkipState` — restructure so the prune runs on *both* `clearSkipped` and non-clear paths:

```swift
    private func reconcileSkipState(clearSkipped: Bool, visibleShown: [EKReminder]) {
        if clearSkipped {
            clearSkippedState()
        } else {
            let resolved = ReminderSkipLogic.resolve(
                fetched: visibleShown.map(\.calendarItemIdentifier),
                skipped: skipStore.load())
            skippedIDs = Set(resolved)
            excludedListTitles = Set(excludeStore.load())
            skipStore.save(resolved)
        }
        reconcileSkipCounts(visibleShown: visibleShown)
    }
```

> Counts are history, not part of the skip set — `clearSkipped: true` clears the skip set but keeps counts (the prune still runs, so only out-of-window ids drop).

#### 2. Deterministic UI-test seam (consumed by Stages 5/6)
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift` + `SingleThread/AppViewModel.swift`
**Action**: modify

**(a)** `UITestingSeed.swift` — extend the wire schema with a **title-keyed** `skipCounts` map (identifiers aren't known stable identifiers until materialization), resolved to identifier-keyed on the struct:

```swift
    public let skipCountsByIdentifier: [String: Int]
```

In `SeedPayload`:
```swift
    var skipCounts: [String: Int] = [:]
    // decode in init(from:): skipCounts = try container.decodeIfPresent([String: Int].self, forKey: .skipCounts) ?? [:]
```
Add `case skipCounts` to `CodingKeys`, and in `materialize()`:
```swift
        let countsByIdentifier = Dictionary(
            uniqueKeysWithValues: createdReminders.compactMap { reminder in
                guard let title = reminder.title, let count = skipCounts[title] else { return nil }
                return (reminder.calendarItemIdentifier, count)
            })
```
Pass `skipCountsByIdentifier: countsByIdentifier` into the `UITestingSeed(...)` call, and add the field to the initializer + doc comment in `UITestingSeed.swift` (JSON example gains `"skipCounts": {"Buy groceries": 5}`).

**(b)** `AppViewModel.seededStore(_:)` — after `UITestingSeed.resetPersistedState()` and the `completionCount` write, preload the counts (the store's `SkipCountStore` reads `AppGroup.defaults`):

```swift
        AppGroup.defaults.set(seed.skipCountsByIdentifier, forKey: "skipCounts")
```

> Seeded tests reach count 6 with **one** skip tap: seed `skipCounts` at `5`, tap skip → 6 → interrupt → banner.

### Verification

#### Automated
- [x] `make build` passes
- [x] `make test` green for `ReminderStoreTests` plus the `SkipCountStoreTests` logic tables

New `ReminderStoreTests` cases (reuse file-scoped `makeReminder` fixtures, `noopSettle`, `InMemoryEventStore`, and `withCheckedContinuation` on `onSkipSetChanged`/`onRemindersChanged`):
- `incrementsSkipCountOnInteractiveSkip` — skip once → `skipCount(for:) == 1`.
- `receivePathDoesNotIncrementSkipCount` — build store, `await reload()`, assert count still 0 (reconcile never increments).
- `skipCountReturnsZeroForUnknownIdentifier`.
- `nudgeInterruptsSixthSkipAndKeepsReminderVisible` — seed count 5 (via `SkipCountStore(defaults: uuidSuite)` preloaded), skip → `onSkipNudgeRequested` fired once with the id, `skipCount == 6`, `visibleReminders.first` still the same reminder (not advanced), `skippedIDs` empty.
- `nudgeDoesNotFireAtFive` — seed count 4, skip → hook nil, `skipCount == 5`, reminder advanced (skipped).
- `seventhSkipAdvancesWithoutRenudging` — seed count 6 (skip already crossed), skip → hook nil, reminder skipped.
- `completeResetsSkipCount` and `deleteResetsSkipCount` (delete via the iOS `eventStore.remove` branch against `InMemoryEventStore`).
- `reconcilePrunesSkipCountForAbsentIdentifier` — preload count for a stale id, `reload()` against a store whose reminders don't include it, assert the id is gone from the store.

#### Manual
- [ ] On the iPhone simulator: skip a reminder 5 times (it advances 5 times), on the 6th tap it stays put with the banner; Delete/Reschedule resets so the next 6 skips nudge again.

---

## Phase 3: Store — `rescheduleReminder(identifier:to:)`

The app's first due-date write, as a small tested `ReminderStore` mutation consumed by the iOS nudge sheet.

### Changes

#### 1. `ReminderStore.rescheduleReminder(identifier:to:)`
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

```swift
    /// Reschedules `identifier` to a new due date (iOS only — EventKit is
    /// read-only on watchOS). Sets `dueDateComponents`, saves, and reloads; also
    /// resets the reminder's skip count so its nudge history starts over.
    #if !os(watchOS)
        @discardableResult
        public func rescheduleReminder(identifier: String, to due: DateComponents) async -> Bool {
            guard canMutate else { return false }
            guard let reminder = reminders.first(where: { $0.calendarItemIdentifier == identifier }) else { return false }
            do {
                reminder.dueDateComponents = due
                try eventStore.save(reminder, commit: true)
                resetSkipCount(for: identifier)
                await settle()
                await reload()
                return true
            } catch {
                Self.logger.error("Failed to reschedule reminder: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    #else
        @discardableResult
        public func rescheduleReminder(identifier _: String, to _: DateComponents) async -> Bool {
            false
        }
    #endif
```

> Follows the `completeReminder`/`deleteReminder` shape (guard → mutate → save → settle → reload). Recurrence-aware reschedule is out of scope; this sets the simple due date only.

### Verification

#### Automated
- [x] `make build` passes
- [x] `make test` green for `EventKitStoringTests` + `ReminderStoreTests`

New `EventKitStoringTests` cases (reuse `fakeEventStore`/`testStore` helpers; `FakeEventStore` already records `saved: [EKReminder]` and `saveShouldThrow`):
- `reschedulePersistsDueDateAndReloads` — reschedule a seeded reminder to `DateComponents(year: 2027, month: 1, day: 2)`, assert `fake.saved.last?.dueDateComponents` matches and `fetchCallCount` advanced (reload fired).
- `rescheduleUnknownIdentifierIsNoop` — unknown id → `false`, nothing saved.
- `rescheduleFailureReturnsFalse` — `saveShouldThrow = true` → `false`.

New `ReminderStoreTests` case:
- `rescheduleResetsSkipCount` — count 6 → `await rescheduleReminder(...)` → `skipCount(for:) == 0`.

#### Manual
- [ ] On the iPhone simulator, rescheduling from the nudge sheet relocates the card's due date (further verified end-to-end in Phase 5's UI test).

---

## Phase 4: Transport — `"skipCounts"` in `SkippedReminderSyncService`

Count snapshots ride the existing combined context. Receive is authoritative (save then hook), never deferred to a later reload.

### Changes

#### 1. `SkippedReminderSyncService` — key, store, hook, push, receive
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

**(a)** Add init param + stored property:
```swift
        skipStore: SkippedReminderStore,
        countStore: SkipCountStore = SkipCountStore(),
```
```swift
    private let countStore: SkipCountStore
```
Assign in the `init` alongside `self.skipStore = skipStore`.

**(b)** Add `PayloadKey` member:
```swift
        static let skipCounts = "skipCounts"
```

**(c)** Add the receive hook (near `onSkippedIdentifiersReceived`), same `nonisolated(unsafe)` + write-once-before-activate rationale:
```swift
    public nonisolated(unsafe) var onSkipCountsReceived: (([String: Int]) -> Void)?
```

**(d)** In `pushAll()`, add to the always-present base context:
```swift
                    PayloadKey.skipCounts: countStore.load(),
```

**(e)** In `apply(context:)`, right after the skipped-identifiers block:
```swift
            if let received = context[PayloadKey.skipCounts] as? [String: Int] {
                countStore.save(received)
                let handler = onSkipCountsReceived
                handler?(received)
            }
```
> If this pushes `apply(context:)` over SwiftLint's 50-line function-body limit, move the block into the existing `applyFreemium(context:)` helper (rename it `applyRemaining(context:)`) — same behavior.

#### 2. Wire receive on both platforms
**File**: `SingleThread/AppViewModel.swift` and `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify

Both, inside their `setupSyncService`/sync-wiring block, before `service.activate()` (iPhone mirrors the watch's `onSkippedIdentifiersReceived` shape instead of relying on next reload — authoritative receive):

```swift
                service.onSkipCountsReceived = { [weak store] _ in
                    Task { @MainActor in await store?.reload() }
                }
```

- iPhone: add after `service.onExcludedListTitlesReceived = …` (store `[weak store]` capture already exists).
- Watch: add next to `service.onSkippedIdentifiersReceived = { [weak store] _ in Task { await store?.reload() } }`.

#### 3. Widget — no code change
Widget writes counts via App Group only (its default `SkipCountStore` = `AppGroup.defaults`), and `skipCurrentReminderImmediately` already persists the increment. No live WCSession push (matches skip IDs today).

### Verification

#### Automated
- [x] `make build` passes
- [x] `make test` green for `SkippedReminderSyncServiceTests` + `WatchSyncPipelineTests` (extend the `FakeSession`/`WatchFakeSession` fixtures to carry `skipCounts` where they carry `skippedReminderIdentifiers`)

New/extended sync cases:
- `pushAllIncludesSkipCounts` — `FakeSession.lastContext["skipCounts"]` equals `countStore.load()`.
- `receiveSkipCountsSavesAndFiresHook` — deliver `["skipCounts": ["a": 6]]`, assert store saved and `onSkipCountsReceived` fired with the dict.
- `receiveAbsentSkipCountsIsNoop` — a context without the key neither saves nor fires.
- `WatchSyncPipelineTests`: watch push includes `skipCounts`, and the receive-every-key list adds `skipCounts`; phone-only keys (`isEntitled` etc.) remain omitted.

#### Manual
- [ ] On a simulator phone+watch pair, skip a reminder to 6 on the phone → the watch's store reloads with the count (banner surfaces there in Phase 6); reverse direction as well.

---

## Phase 5: Presentation — iOS nudge (banner + sheet + 3 actions) + localization

First consumer of Stages 1–4.

### Changes

#### 1. Shared copy
**File**: `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift` and `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`
**Action**: modify

```swift
    public static var skipNudgeTitle: String {
        String(localized: "Skipped 6 times", table: "Localizable", bundle: .module)
    }
```
Add the same English source key to the Core `.xcstrings` catalog in all 6 locales (`en`, `zh-Hans`, `es`, `ja`, `de`, `fr`) — reuse English for the 5 non-English locales initially so `LocalizationTests` passes; flag for a human translator.

#### 2. `ContentViewModel` — nudge state + actions
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify

```swift
    /// Identifier of the reminder that just crossed the 6-skip threshold. Drives
    /// the in-card banner. Cleared on act or dismiss.
    var nudgeIdentifier: String?
```
In `init(...)`, wire the hook (single owner — ContentViewModel, not AppViewModel):
```swift
        store.onSkipNudgeRequested = { [weak self] identifier in
            self?.nudgeIdentifier = identifier
        }
```
Add actions:
```swift
    func isNudged(_ identifier: String) -> Bool { nudgeIdentifier == identifier }

    func dismissNudge() { nudgeIdentifier = nil }

    func deleteNudgedReminder() async {
        guard let identifier = nudgeIdentifier else { return }
        await store.deleteReminder(identifier: identifier)
        nudgeIdentifier = nil
    }

    @discardableResult
    func rescheduleNudgedReminder(to due: DateComponents) async -> Bool {
        guard let identifier = nudgeIdentifier else { return false }
        let succeeded = await store.rescheduleReminder(identifier: identifier, to: due)
        if succeeded { nudgeIdentifier = nil }
        return succeeded
    }
```

#### 3. `ReminderCardView` — in-card banner
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify

Add params `showNudge: Bool = false` and `onNudgeTap: @escaping () -> Void = {}` to the primary `init`; render between `content` and `prompt`:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if showNudge {
                nudgeBanner
            }
            if showSwipePrompt {
                prompt
            }
        }
        .cardPlate(...)
    }
```
```swift
    /// Tappable nudge banner. Unlike the swipe hint, NOT `.accessibilityHidden` —
    /// the nudge is actionable and must be screen-reader reachable.
    private var nudgeBanner: some View {
        Button(action: onNudgeTap) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble")
                Text(SharedStrings.skipNudgeTitle)
                    .font(.caption.bold())
            }
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityLabel("Skipped 6 times — tap to manage")
        .accessibilityIdentifier("skipNudgeBanner")
    }
```

#### 4. `ContentView` — sheet + 3 actions + deep link reuse
**File**: `SingleThread/ContentView.swift`
**Action**: modify

- Pass `showNudge: viewModel.isNudged(reminder.calendarItemIdentifier)` and `onNudgeTap: { isShowingNudgeSheet = true }` to `ReminderCardView(...)` (iOS only; other platforms get defaults).
- Add `@State private var isShowingNudgeSheet = false` and `@State private var rescheduleDate = Date().addingTimeInterval(86_400)`.
- Add the sheet near the other `.sheet` modifiers (`.sheet(isPresented: $isShowingNudgeSheet, onDismiss: { viewModel.dismissNudge() }) { nudgeSheetContent }`).

```swift
    #if os(iOS)
    private var nudgeSheetContent: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("This reminder keeps coming back.")
                    .font(.headline)
                    .accessibilityIdentifier("nudgeSheetTitle")

                DatePicker(
                    "Reschedule to",
                    selection: $rescheduleDate,
                    displayedComponents: [.date, .hourAndMinute])

                Button {
                    let components = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: rescheduleDate)
                    Task {
                        if await viewModel.rescheduleNudgedReminder(to: components) {
                            isShowingNudgeSheet = false
                        }
                    }
                } label: {
                    Label("Reschedule", systemImage: "calendar")
                }
                .accessibilityIdentifier("nudgeRescheduleButton")

                Button {
                    let identifier = viewModel.nudgeIdentifier
                    if let identifier,
                       let url = ReminderDeepLink.url(forReminderIdentifier: identifier) {
                        openURL(url)
                    }
                    isShowingNudgeSheet = false
                } label: {
                    Label("View in Reminders", systemImage: "eye")
                }
                .accessibilityIdentifier("nudgeViewInRemindersButton")

                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteNudgedReminder()
                        isShowingNudgeSheet = false
                    }
                } label: {
                    Label(SharedStrings.deleteAction, systemImage: "trash")
                }
                .accessibilityIdentifier("nudgeDeleteButton")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isShowingNudgeSheet = false }
                }
            }
        }
    }
    #endif
```

- Reuses the existing `ReminderDeepLink.url(forReminderIdentifier:)` (same call as the context menu) and `SharedStrings.deleteAction`; "View in Reminders" literal already exists in the catalog so it reuses the entry.

#### 5. iOS catalog
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify

Add the iOS-only English literals ("This reminder keeps coming back.", "Reschedule", "Reschedule to", "Cancel" if not already present) in all 6 locales (reuse English for non-English initially; flag for translation). Build once (or run `make build`) so Xcode auto-extracts any missed literal.

### Verification

#### Automated
- [x] `make build` passes
- [x] `make lint` clean (SwiftLint `--strict`: watch SwiftLint's 50-line function-body limit on the sheet builder — split into smaller `@ViewBuilder` vars if it trips)
- [x] `make ui-test` green for the new iOS test (targeted `xcodebuild -only-testing:SingleThreadUITests/…` with `,id=`-pinned destination)

New `SingleThreadUITests/…` XCTest flows (seed via `launchSeeded(_:extra:)` with `--seed '{"reminders":[{"title":"Buy groceries"}],"skipCounts":{"Buy groceries":5}}'`):
- `testSkipNudgeBannerAppearsAfterSixthSkipAndDeletes` — tap `skipButton` → assert `skipNudgeBanner` exists → tap it → assert `nudgeSheetTitle` exists → tap `nudgeDeleteButton` → assert empty/all-done state.
- `testSkipNudgeRescheduleActs` — banner → `nudgeRescheduleButton` → assert the card's `dueDateText` appears/changed.
- `testSkipNudgeViewInRemindersOffersDeepLink` — banner → assert `nudgeViewInRemindersButton` exists (tap covered by the existing deep-link path; a real `openURL` hop can't be asserted).
- Run `testAccessibilityAudit` unchanged (banner is not `.accessibilityHidden`).

#### Manual
- [ ] iPhone simulator: skip a reminder 5×, on the 6th the card stays and shows the banner; tap → sheet with Delete / Reschedule / View in Reminders; each acts and clears the banner.

---

## Phase 6: Presentation — watch nudge (banner + `confirmationDialog`, Delete only) + localization

### Changes

#### 1. `WatchReminderViewModel` — nudge state
**File**: `SingleThreadWatch/WatchReminderViewModel.swift`
**Action**: modify

```swift
    var nudgeIdentifier: String?
    var isShowingNudgeDialog = false
```
Wire in `init(...)`:
```swift
        store.onSkipNudgeRequested = { [weak self] identifier in
            self?.nudgeIdentifier = identifier
        }
```
Helper:
```swift
    func isNudged(_ identifier: String) -> Bool { nudgeIdentifier == identifier }
```

#### 2. `WatchReminderView` — banner + dialog
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

In `reminderCard(_:)`, add the tappable banner under the `ScrollView` (before `actionButtons`), and a dedicated `confirmationDialog`:

```swift
            if viewModel.isNudged(reminder.calendarItemIdentifier) {
                Button {
                    viewModel.isShowingNudgeDialog = true
                } label: {
                    Label(SharedStrings.skipNudgeTitle, systemImage: "exclamationmark.bubble")
                        .font(.caption)
                }
                .accessibilityIdentifier("skipNudgeBanner")
                .confirmationDialog(SharedStrings.skipNudgeTitle, isPresented: $viewModel.isShowingNudgeDialog) {
                    Button(SharedStrings.deleteAction, role: .destructive) {
                        Task { await viewModel.store.deleteCurrentReminder() }
                    }
                    .accessibilityIdentifier("nudgeDeleteButton")
                }
            }
```

> Delete already resets the count (Phase 1/2). No date picker or deep link on watch; the dialog reuses `SharedStrings.deleteAction`.

#### 3. Watch `--ui-testing-skip-count` seam
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify

In `uiTestingStore(arguments:)`, after the reminder is built (and before the excluded-list early returns), seed the count into `.standard` (App Group falls back there on watch):

```swift
        if let index = arguments.firstIndex(of: "--ui-testing-skip-count"),
           index + 1 < arguments.count,
           let count = Int(arguments[index + 1]) {
            AppGroup.defaults.set([reminder.calendarItemIdentifier: count], forKey: "skipCounts")
        }
```

#### 4. Watch catalog
**File**: `SingleThreadWatch/Resources/Localizable.xcstrings`
**Action**: modify (only if a watch-only literal is introduced — otherwise none)

The nudge banner/dialog reuse `SharedStrings.skipNudgeTitle` + `SharedStrings.deleteAction`, so no new watch-only key is required. If Xcode auto-extracts any literal, add its 6-locale entry.

### Verification

#### Automated
- [x] `make build` passes (watch scheme)
- [x] `make watch-ui-test` green (targeted `-only-testing:SingleThreadWatchUITests/…`)

New `SingleThreadWatchUITests` XCTest flow:
- `testSkipNudgeShowsDeleteDialog` — launch `["--ui-testing", "--ui-testing-skip-count", "5"]` → tap `skipButton` → assert `skipNudgeBanner` exists → tap it → assert `nudgeDeleteButton` (destructive) → tap → assert all-done state.
- Run the watch `performAccessibilityAudit` unchanged.

#### Manual
- [ ] watch simulator: skip 5×, on the 6th the card stays with the banner; tap → Delete dialog → Delete removes the reminder.

---

## Final gate (parent runs once, after phases commit)

- [ ] `make format` (SwiftFormat) clean
- [ ] `make lint` (SwiftLint `--strict`) clean
- [ ] `./scripts/test.sh` (full: unit + iOS UI + watch UI + watch unit + macOS unit) green, `SIM=`/`WATCH_TEST_SIM=` pinned as needed
- [ ] `make periphery` (`periphery scan --strict`) clean — new public APIs (`SkipCountStore`, `SkipCountLogic`, `skipCount(for:)`, `rescheduleReminder`, `onSkipNudgeRequested`, `onSkipCountsReceived`) are exercised by production or test call sites
- [ ] Confirm coverage ships: unit tests for count increment/reset/prune/threshold + reschedule; sync tests for the new key; iOS + watch UI tests for the nudge end-to-end

---

## Deviations from `structure.md` (and why)

1. **6th-skip interrupt (Option A)** — per user choice. `skipCurrentReminder()` gains a crossing-interrupt branch (gated `#if os(iOS) || os(watchOS)`); `skipCurrentReminderImmediately()` always advances but records the count. `structure.md` listed only "increment + hook" for these methods; the interrupt is the consequence of the chosen presentation timing.
2. **macOS advance-always** — no nudge UI exists on macOS; the interrupt is platform-gated so macOS skips keep advancing (count still increments). Not mentioned in `structure.md`.
3. **`SkipCountLogic` split into `shouldNudge(_:)` + `crossedThreshold(from:to:)`** — `structure.md` named only `shouldNudge(_:threshold:)`. The second pure function is what makes "fire once at first crossing" (the resolved re-fire policy) a testable rule rather than ad-hoc call-site math.
4. **Seed `skipCounts` is title-keyed on the wire, identifier-keyed on the struct** — `EKReminder.calendarItemIdentifier` is read-only and generated at materialize time, so the JSON can't key by identifier. This is a clarification, not a behavior change.
5. **Watch adds no new catalog copy** — the watch banner/dialog reuse `SharedStrings.skipNudgeTitle` + `deleteAction`, so `structure.md`'s watch `.xcstrings` change is only needed if Xcode auto-extracts a stray literal.
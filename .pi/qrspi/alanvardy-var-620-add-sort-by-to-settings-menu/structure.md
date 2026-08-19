# Structure Outline

## Approach

Make `visibleReminders` option-aware: add a `SortOption` enum + store in Core
(same split as `ReminderPriority`/`SkippedReminderStore`), inject it into
`ReminderStore`, persist it in the App Group with `@AppStorage`, and surface it
as a "Sort By" `Picker` in `SettingsView`. Widget/intents read the App Group
directly; the watch receives it over the existing WatchConnectivity channel.
Default `.priority` = today's order, so existing installs see no change.

---

## Phase 1: `SortOption` + option-aware comparator + `SortOptionStore`

Delivers the three orderings as pure, unit-tested Core logic plus the
persistence seam. No UI or store wiring yet — the comparator's default is
today's behavior, so this lands with zero observable change.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SortOption.swift` (new),
`SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift`

**Key changes**:
```swift
// SortOption.swift (new)
public enum SortOption: String, CaseIterable, Sendable {
    case priority   // "priority" — today's compound order
    case dueDate    // "dueDate" — date soonest-first → title
    case title      // "title"    — A→Z (case-insensitive) → date
    public static let defaultsKey = "sortOption"   // single shared key constant
}

public struct SortOptionStore {                       // mirrors SkippedReminderStore
    public init(defaults: UserDefaults = AppGroup.defaults,
                 key: String = SortOption.defaultsKey)
    public func load() -> SortOption                    // rawValue ?? .priority
    public func save(_ option: SortOption)              // set(option.rawValue, forKey:)
}

// ReminderSort.swift (modified)
public static func areInIncreasingOrder(_ lhs: EKReminder, _ rhs: EKReminder,
                                        using option: SortOption) -> Bool
public static func areInIncreasingOrder(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool
    // delegates to `using: .priority`; keeps test helper `titles(of:)` compiling
```

**Verify**: `make test` — new `ReminderSortTests` cases for each of the three
options (priority rank→date→title; dueDate date→title; title case-insensitive→date),
new `SortOptionTests` (raw values, `allCases == [.priority, .dueDate, .title]`),
new `SortOptionStoreTests` (default `.priority` on missing/invalid key, round-trip
save→load). Existing 2-arg comparator tests still pass unchanged.

---

## Phase 2: Store wiring + persistence + Settings picker (iPhone/macOS end-to-end)

User can choose a sort in Settings; the choice persists to the App Group and
`visibleReminders.first` re-sorts instantly on device. This is the first
fully user-observable slice.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThread/SortOption+Presentation.swift` (new),
`SingleThread/ContentView.swift`, `SingleThread/SettingsView.swift`,
`SingleThread/SingleThreadApp.swift`

**Key changes**:
```swift
// ReminderStore.swift (modified)
public var sortOption: SortOption = .priority              // @Observable: change re-renders
public var onSortOptionChanged: ((SortOption) -> Void)?    // fired on change (watch push, Phase 4)
public func setSortOption(_ option: SortOption)            // no-op if equal; else assign +
                                                           // onSortOptionChanged?(option) + onRemindersChanged?()
// visibleReminders: .sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }

// SortOption+Presentation.swift (new, app target)
extension SortOption {
    var title: String        // "Priority" / "Due Date" / "Title"
    var systemImage: String  // e.g. "exclamationmark.3" / "calendar" / "textformat.abc"
}

// ContentView.swift (modified)
@AppStorage(SortOption.defaultsKey, store: AppGroup.defaults)
private var sortOption = SortOption.priority     // + .onChange { _, new in store.setSortOption(new) }
// pass sortOption: Binding<SortOption> to SettingsView (both platform inits)

// SettingsView.swift (modified)
//   both inits gain `sortOption: Binding<SortOption>`; add @Binding property;
//   add Picker("Sort By", selection: $sortOption) { ForEach(SortOption.allCases, id:\.self) { ... } }

// SingleThreadApp.swift (modified)
//   init: store.sortOption = SortOptionStore().load()   // direct assign, before hooks → no startup push
```

**Verify**: `make test` — new `SortOptionTests` presentation cases (`title`,
`systemImage`); updated `SettingsViewTests` passes the new binding and asserts
`String(describing: view.body)` contains "Sort By"; new `ReminderStoreTests`
(`setSortOption` re-sorts `visibleReminders`, fires both hooks, is idempotent).
Manual: open Settings → "Sort By" → pick "Due Date"/"Title"; the current-reminder
card reorders immediately and the pick persists across relaunch. `make mac-build`
confirms the non-iOS 3-binding init stays in sync.

---

## Phase 3: Widget + App Intents read the shared sort

The extension processes (`NextThingWidget`, both intents) apply the persisted
option before deriving `.first`, so the widget and Complete/Skip actions stay
consistent with the phone.

**Files**: `SingleThreadWidget/NextThingWidget.swift`,
`SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift`

**Key changes**:
```swift
// In NextThingProvider.makeEntry and both intent perform()s, after creating the store:
store.setSortOption(SortOptionStore().load())
await store.reload()              // then read visibleReminders.first / act
// safe: setSortOption's hooks are nil in these processes (no closure wired)
```

**Verify**: `make test` (builds widget + intents) plus `make build`. Manual:
change sort on iPhone, then confirm the widget shows the same first reminder;
trigger widget Skip/Complete and confirm it targets the correctly-sorted first.

---

## Phase 4: Watch sync over the existing WatchConnectivity channel

The iPhone pushes the option alongside the skip list; the watch saves it via
its local `SortOptionStore()` (falls back to `.standard` — no App Group
entitlement) and applies it through a new receive hook.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`,
`SingleThread/SingleThreadApp.swift`, `SingleThreadWatch/SingleThreadWatchApp.swift`

**Key changes**:
```swift
// SkippedReminderSyncService.swift (modified)
public init(session: any SkipSyncSession, skipStore: SkippedReminderStore,
            sortStore: SortOptionStore = SortOptionStore())
public nonisolated(unsafe) var onSortOptionReceived: ((SortOption) -> Void)?
public func pushSortOption(_ option: SortOption)
// Combined atomic context (fixes latest-wins drop risk): every updateApplicationContext
// carries BOTH keys — pushSkipIDs also includes sortStore.load().rawValue; pushSortOption
// also includes skipStore.load().
// didReceiveApplicationContext reads both keys: skipStore.save(...) + sortStore.save(...)
//   + onSortOptionReceived?(...)
// PayloadKey: add `sortOption = "sortOption"`

// SingleThreadApp.swift (iPhone):    store.onSortOptionChanged = { service.pushSortOption($0) }
// SingleThreadWatchApp.swift (watch): service.onSortOptionReceived = { [weak store] in store?.setSortOption($0) }
```

**Verify**: `make watch-build` + `make test` — update `SkippedReminderSyncServiceTests`
for the new init param, plus new cases: `pushSortOption`/`pushSkipIDs` emit both
keys; received context saves sort + fires `onSortOptionReceived`; malformed/missing
sort key leaves the local value unchanged. Manual: change sort on iPhone → the Apple
Watch companion shows the same first reminder.

---

## Testing Checkpoints

- **After Phase 1**: all three comparators pass unit tests; existing 2-arg sort
  tests unchanged; `SortOptionStore` round-trips with `.priority` default.
- **After Phase 2**: Settings shows "Sort By"; picking an option re-sorts the
  card and persists across relaunch; `setSortOption` is idempotent and fires
  `onSortOptionChanged` + `onRemindersChanged`.
- **After Phase 3**: widget + intents compile and honor the persisted option;
  widget Skip/Complete target the correctly-sorted first reminder.
- **After Phase 4**: watch builds; sync service tests cover combined-context
  push and receive; iPhone→watch sort change propagates.

## Notes & Carried Risks

- **Idempotent `setSortOption`** avoids a redundant `onRemindersChanged`
  (widget-timeline reload + watch push) on every launch. Launch injection uses
  a direct property assignment, not `setSortOption`, so no hook fires at startup.
- **Combined atomic context (Phase 4)**: `updateApplicationContext` is
  latest-wins; push both keys in one context or a skip-only push would clobber
  the sort value on the watch.
- **macOS guard**: the sync service is already `#if os(iOS) || os(watchOS)`;
  macOS compiles via the same `@AppStorage`+store read and has no `onSortOptionChanged`
  subscriber.
- **Watch read-only EventKit**: watch applies the sort only to its own fetch; if
  fetch sets diverge, "first" can still differ even with a shared sort.
- Out of scope (per design): sort direction, Created/Modified key, per-list
  ordering, and any EventKit eligibility-window change.
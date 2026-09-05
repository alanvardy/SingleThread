# Implementation Plan — Collapse 6 `Show*Preference` → `BoolPreferenceStore`

## Overview

Replace six near-identical `Show*Preference` structs with a single generic `BoolPreferenceStore` parameterized by key and fallback, plus a `BoolPreferenceKey` enum of named constants. No behavior change; full CI gate green.

---

## Stage 1: `BoolPreferenceKey` — Key Constants

### Changes

#### 1. New: `BoolPreferenceKey.swift`
**File**: `SingleThreadCore/Sources/SingleThreadCore/BoolPreferenceKey.swift`
**Action**: create

```swift
import Foundation

/// Named constants for the six Bool preference keys persisted in UserDefaults.
/// Production callers use these cases; tests may inject custom key strings.
enum BoolPreferenceKey: String, CaseIterable, Sendable {
    /// "showDate" — fallback: true
    case showDate
    /// "showRecurrence" — fallback: true
    case showRecurrence
    /// "showAlarms" — fallback: true
    case showAlarms
    /// "showCompletionGlow" — fallback: true
    case showCompletionGlow
    /// "showList" — fallback: false
    case showList
    /// "showUndatedReminders" — fallback: false
    case showUndatedReminders
}
```

Note: fallback values are NOT stored on the enum — they are properties of each `BoolPreferenceStore` instance. Comments are documentation only.

#### 2. New: `BoolPreferenceKeyTests.swift`
**File**: `SingleThreadTests/BoolPreferenceKeyTests.swift`
**Action**: create

```swift
import SingleThreadCore
import Testing

@Suite struct BoolPreferenceKeyTests {
    /// Every case's rawValue matches the exact string the old structs' `key` defaults used.
    @Test(arguments: [
        (BoolPreferenceKey.showDate, "showDate"),
        (BoolPreferenceKey.showRecurrence, "showRecurrence"),
        (BoolPreferenceKey.showAlarms, "showAlarms"),
        (BoolPreferenceKey.showCompletionGlow, "showCompletionGlow"),
        (BoolPreferenceKey.showList, "showList"),
        (BoolPreferenceKey.showUndatedReminders, "showUndatedReminders"),
    ]) func keyStringsMatchExistingHardcodedKeys(_ key: BoolPreferenceKey, _ expected: String) {
        #expect(key.rawValue == expected)
    }

    @Test func allCasesIsExhaustive() {
        #expect(BoolPreferenceKey.allCases.count == 6)
    }

    /// Compile-time Sendable conformance check.
    @Test func isSendable() {
        let key: any Sendable = BoolPreferenceKey.showDate
        _ = key
    }}
```

### Verification
#### Automated
- [x] `make test SIM=iPhne 17,OS=26.1 -only-testing:SingleThreadTests/BoolPreferenceKeyTests` passes

#### Manual
- [ ] Confirm the six rawValue strings match the old structs' key defaults: "showDate", "showRecurrence", "showAlarms", "showCompletionGlow", "showList", "showUndatedReminders"

---

## Stage2: `BoolPreferenceStore` — Generic Store

### Changes

#### 1. New: `BoolPreferenceStore.swift`
**File**: `SingleThreadCore/Sources/SingleThreadCore/BoolPreferenceStore.swift`
**Action**: create

```swift
import Foundation

/// Generic Bool preference store parameterized by key string and absent-value fallback.
/// Replaces six near-identical `Show*Preference` structs.
///
/// - Read via `isEnabled` (uses `object(forKey:) as? Bool ?? fallback)` — never `bool(forKey:)`,
///   so nil ≠ explicitly-off).
/// - Write via `set(_:)`.
/// - `defaults:` defaults to `AppGroup.defaults` (like every old struct).
public struct BoolPreferenceStore: Sendable {
    // MARK: Lifecycle

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String,
        fallback: Bool
    ) {
        self.defaults = defaults
        self.key = key
        self.fallback = fallback
    }

    // MARK: Public

    /// Whether the preference is enabled. Absent key → `fallback`.
    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    public func set(_ value: Bool) {
        defaults.set(value, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
    private let fallback: Bool
}
```

Pattern follows `SortOptionStore` shape (init with `defaults:` + `key:`, read/write in same method, `Sendable`) but uses `isEnabled`/`set` — the API five of six existing structs already use.

#### 2. New: `BoolPreferenceStoreTests.swift`
**File**: `SingleThreadTests/BoolPreferenceStoreTests.swift`
**Action**: create

```swift
import SingleThreadCore
import Testing

@Suite struct BoolPreferenceStoreTests {
    /// Every (key, fallback) pair from the six old structs.
    private static let allPairs: [(key: String, fallback: Bool)] = [
        ("showDate", true),
        ("showRecurrence", true),
        ("showAlarms", true),
        ("showCompletionGlow", true),
        ("showList", false),
        ("showUndatedReminders", false),
    ]

    // MARK: — Absent-key fallback

    @Test(arguments: allPairs)
    func absentValueFallsBackToConfiguredDefault(_ pair: (String, Bool)) {
        let key = "test-absent-\(UUID().uuidString)-\(pair.0)"
        let store = BoolPreferenceStore(defaults: .standard, key: key, fallback: pair.1)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        #expect(store.isEnabled == pair.1)
    }

    // MARK: — Round-trip

    @Test(arguments: allPairs)
    func roundTripTrue(_ pair: (String, Bool)) {
        let key = "test-rtt-\(UUID().uuidString)-\(pair.0)"
        let store = BoolPreferenceStore(defaults: .standard, key: key, fallback: pair.1)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.set(true)
        #expect(store.isEnabled == true)
    }

    @Test(arguments: allPairs)
    func roundTripFalse(_ pair: (String, Bool)) {
        let key = "test-rf-\(UUID().uuidString)-\(pair.0)"
        let store = BoolPreferenceStore(defaults: .standard, key: key, fallback: pair.1)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.set(false)
        #expect(store.isEnabled == false)
    }

    // MARK: — Overwrite

    @Test func setOverwritesPreviousValue() {
        let key = "test-overwrite-\(UUID().uuidString)"
        let store = BoolPreferenceStore(defaults: .standard, key: key, fallback: true)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.set(true)
        store.set(false)
        #expect(store.isEnabled == false)
    }

    // MARK: — Injection

    @Test func customDefaultsInjection() {
        let suite = UserDefaults(suiteName: "test-custom-\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.volatileDomainNames.first ?? "") }
        let store1 = BoolPreferenceStore(defaults: suite, key: "k", fallback: false)
        let store2 = BoolPreferenceStore(defaults: .standard, key: "k", fallback: true)
 store1.set(true)
        #expect(store2.isEnabled == true) // .standard never got written
    }

    // MARK: — Sendable

    @Test func isSendable() {
        let store: any Sendable = BoolPreferenceStore(defaults: .standard, key: "k", fallback: false)
        _ = store
    }
}
```

Follows existing test pattern: UUID-key on `.standard` + `defer removeObject`, absent-fallback first, then set/read both polarities (e.g. `ShowAlarmsPreferenceTests.swift:8-15`).

### Verification
#### Automated
- [x] `make test SIM=iPhone 17,OS=26.1 -only-testing:SingleThreadTests/BoolPreferenceStoreTests` passes

#### Manual
- [ ] Confirm all six key+fallback pairs are covered by the parameterized tests

---

## Stage 3: Call-Site Replacement + Old-Code Removal + Full Gate

### 3a. SingleThreadCore call sites

#### 1. `AppViewMode.swift`
**File**: `SingleThread/SingleThread/AppViewModel.swift`
**Action**: modify

The sync-service construction (`AppViewModel.swift:30-39`) changes six concrete store defaults:
```swift
// Before
showDateStore: ShowDatePreference(),
showRecurrenceStore: ShowRecurrencePreference(),
showAlarmsStore: ShowAlarmsPreference(),
showListStore: ShowListPreference(),
showCompletionGlowStore: ShowCompletionGlowPreference(),

// After
showDateStore: BoolPreferenceStore(key: BoolPreferenceKey.showDate.rawValue, fallback: true),
showRecurrenceStore: BoolPreferenceStore(key: BoolPreferenceKey.showRecurrence.rawValue, fallback: true),
showAlarmsStore: BoolPreferenceStore(key: BoolPreferenceKey.showAlarms.rawValue, fallback: true),
showListStore: BoolPreferenceStore(key: BoolPreferenceKey.showList.rawValue, fallback: true),
showCompletionGlowStore: BoolPreferenceStore(key: BoolPreferenceKey.showCompletionGlow.rawValue, fallback: true),
```

`showUndatedStore` (also in this init call) — was already `ShowUndatedRemindersPreference()`, becomes `BoolPreferenceStore(key: BoolPreferenceKey.showUndatedReminders.rawValue, fallback: false)`.

`handlePreferencesChanged` (`:432-449`): the five explicit `Show*Preference().isEnabled` reads become `store.isEnabled` on the already-cached stores (or simple BoolPreferenceStore reads). The `lastShowDate` etc. caches (`:453-457`) are already `Bool` — no type change needed; they were initialized via `ShowDatePreference().isEnabled` etc., which become `BoolPreferenceStore(key:…, fallback:…)`.isEnabled`.

`showCompletionGlowStore` field type: from `ShowCompletionGlowPreference` to `BoolPreferenceStore`.

`--reset-glow-preference` seam at `:285-287`:
```swift
// Before
UserDefaults.standard.removeObject(forKey: "showCompletionGlow")

// After — keep the literal; it's intentionally .standard, not AppGroup
UserDefaults.standard.removeObject(forKey: "showCompletionGlow")
```
No change needed — this already uses a raw literal and isn't coupled to the struct. But optionally use `BoolPreferenceKey.showCompletionGlow.rawValue`.

####2. `ContentViewModel.swift`
**File**: `SingleThread/SingleThread/ContentViewMode.swift`
**Action**: modify

Init param (`:14-26`):
```swift
// Before
showCompletionGlow: ShowCompletionGlowPreference = ShowCompletionGlowPreference(),

// After
showCompletionGlow: BoolPreferenceStore = BoolPreferenceStore(
    key: BoolPreferenceKey.showCompletionGlow.rawValue,
    fallback: true
),
```

Private field (`218`):
```swift
// Before
private var showCompletionGlow: ShowCompletionGlowPreference

// After
private var showCompletionGlow: BoolPreferenceStore
```

`isEnabled` read at `:137` (`if showCompletionGlow.isEnabled { … }`) — unchanged (same API).

#### 3. `SkippedReminderSyncService.swift`
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

**Import**: add no new import — `BoolPreferenceStore` and `BoolPreferenceKey` are in the same module (SingleThreadCore).

**Init signature** (`:26-68`): six store params change type:
```swift
// Before
showUndatedStore: ShowUndatedRemindersPreference = ShowUndatedRemindersPreference(),
showDateStore: ShowDatePreference = ShowDatePreference(),
showRecurrenceStore: ShowRecurrencePreference = ShowRecurrencePreference(),
showAlarmsStore: ShowAlarmsPreference = ShowAlarmsPreference(),
showListStore: ShowListPreference = ShowListPreference(),
showCompletionGlowStore: ShowCompletionGlowPreference = ShowCompletionGlowPreference(),

// After
showUndatedStore: BoolPreferenceStore = BoolPreferenceStore(
    key: BoolPreferenceKey.showUndatedReminders.rawValue, fallback: false),
showDateStore: BoolPreferenceStore = BoolPreferenceStore(
    key: BoolPreferenceKey.showDate.rawValue, fallback: true),
showRecurrenceStore: BoolPreferenceStore = BoolPreferenceStore(
    key: BoolPreferenceKey.showRecurrence.rawValue, fallback: true),
showAlarmsStore: BoolPreferenceStore = BoolPreferenceStore(
    key: BoolPreferenceKey.showAlarms.rawValue, fallback: true),
showListStore: BoolPreferenceStore = BoolPreferenceStore(
    key: BoolPreferenceKey.showList.rawValue, fallback: false),
showCompletionGlowStore: BoolPreferenceStore = BoolPreferenceStore(
    key: BoolPreferenceKey.showCompletionGlow.rawValue, fallback: true),
```

**Stored property types** (`:50-55`): same mechanical change — `ShowDatePreference` → `BoolPreferenceStore`, etc.

**`pushAll()`** (`:176-214`): `showUndatedStore.load()` → `showUndatedStore.isEnabled` (the other five already use `.isEnabled`). One-line change.

**`apply(context:)`** (`:339-372`): `showUndatedStore.save(received)` → `showUndatedStore.set(received)` (the other five already use `.set`). One-line change.

Note: `function_body_length` suppression at `:298-300` for `init` → the six defaulted params are replaced, not added; line count should not increase materially.

#### 4. `ReminderStore.swift`
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

`showsUndatedReminders` property — currently reads via `ShowUndatedRemindersPreference().load()`. Replace with a `BoolPreferenceStore` instance:
```swift
// Before (approximate — the store is implicitly created each read)
var showsUndatedReminders = ShowUndatedRemindersPreference().load()

// After
private let showUndatedStore = BoolPreferenceStore(
    key: BoolPreferenceKey.showUndatedReminders.rawValue, fallback: false)

var showsUndatedReminders: Bool {
    showUndatedStore.isEnabled
}
```

Check the exact current code: the property likely has a `didSet` that triggers `onShowUndatedRemindersChanged` and widens the fetch predicate (`:134-139,421-433`). The `didSet` and its side effects are unchanged — only the read source changes.

#### 5. `NextThingWidget.swift`
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

Four reads at `:64-67`:
```swift
// Before
ShowDatePreference().isEnabled
ShowRecurrencePreference().isEnabled
ShowAlarmsPreference().isEnabled
ShowListPreference().isEnabled

// After
BoolPreferenceStore(key: BoolPreferenceKey.showDate.rawValue, fallback: true).isEnabled
BoolPreferenceStore(key: BoolPreferenceKey.showRecurrence.rawValue, fallback: true).isEnabled
BoolPreferenceStore(key: BoolPreferenceKey.showAlarms.rawValue, fallback: true).isEnabled
BoolPreferenceStore(key: BoolPreferenceKey.showList.rawValue, fallback: false).isEnabled
```

Raw read at `:71`:
```swift
// Before
AppGroup.defaults.bool(forKey: "showUndatedReminders")

// After — optionally use the store for consistency
BoolPreferenceStore(key: BoolPreferenceKey.showUndatedReminders.rawValue, fallback: false).isEnabled
```
Note: the old code used `bool(forKey:)` which collapses nil→false — matching the `fallback: false` behavior. Using `BoolPreferenceStore.isEnabled` with `object(forKey:) as? Bool ?? false` is equivalent for this key.

### 3b. Watch target call sites

#### 1. `ShowDateState.swift`
**File**: `SingleThreadWatch/ShowDateState.swift`
**Action**: modify

```swift
// Before (line 28)
private let preference = ShowDatePreference(defaults: .standard)

// After
private let preference = BoolPreferenceStore(
    defaults: .standard,
    key: BoolPreferenceKey.showDate.rawValue,
    fallback: true
)
```

`preference.isEnabled` and `preference.set(value)` calls — unchanged (same API).

#### 2. `ShowListState.swift`
**File**: `SingleThreadWatch/ShowListState.swift`
**Action**: modify

```swift
private let preference = BoolPreferenceStore(
    defaults: .standard,
    key: BoolPreferenceKey.showList.rawValue,
    fallback: false
)
```

#### 3. `ShowRecurrenceState.swift`
**File**: `SingleThreadWatch/ShowRecurrenceState.swift`
**Action**: modify

```swift
private let preference = BoolPreferenceStore(
    defaults: .standard,
    key: BoolPreferenceKey.showRecurrence.rawValue,
    fallback: true
)
```

#### 4. `ShowAlarmsState.swift`
**File**: `SingleThreadWatch/ShowAlarmsState.swift`
**Action**: modify

```swift
private let preference = BoolPreferenceStore(
    defaults: .standard,
    key: BoolPreferenceKey.showAlarms.rawValue,
    fallback: true
)
```

#### 5. `ShowCompletionGlowState.swift`
**File**: `SingleThreadWatch/ShowCompletionGlowState.swift`
**Action**: modify

```swift
private let preference = BoolPreferenceStore(
    defaults: .standard,
    key: BoolPreferenceKey.showCompletionGlow.rawValue,
    fallback: true
)
```

#### 6. `WatchAppViewModel.swift`
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify

Same mechanical change as 3a.3 (`SkippedReminderSyncService.init` call at `:160-175`): six concrete store params → six `BoolPreferenceStore` params with the watch's `.standard` defaults:
```swift
showUndatedStore: BoolPreferenceStore(
    defaults: .standard, key: BoolPreferenceKey.showUndatedReminders.rawValue, fallback: false),
showDateStore: BoolPreferenceStore(
    defaults: .standard, key: BoolPreferenceKey.showDate.rawValue, fallback: true),
// … same pattern for recurrence, alarms, list, glow
```

Also: `sendsShowDate: false` etc. — unchanged (these are independent `Bool` flags).

#### 7. `WatchReminderViewModel.swift`
**File**: `SingleThreadWatch/WatchReminderViewModel.swift`
**Action**: modify

State-holder types (`ShowDateState` etc.) are unchanged — only the internal `preference` field in each holder changed (3b.1–5 above). The ViewModel's init params remain the same `ShowDateState` types.

### 3c. Test adaptation

#### 1. `SkippedReminderSyncServiceTests.swift`
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify

All init calls that pass concrete store types (e.g. `:80-87` and throughout) — mechanical replacement:
```swift
// Before
showDateStore: ShowDatePreference(defaults: .standard, key: "test-date-\(suffix)"),

// After
showDateStore: BoolPreferenceStore(defaults: .standard, key: "test-date-\(suffix)", fallback: true),
```

Same for showRecurrence (fallback: true), showAlarms (fallback: true), showList (fallback: false), showCompletionGlow (fallback: true), showUndated (fallback: false).

#### 2. `WatchSyncPipelineTests.swift`
**File**: `SingleThreadWatchTests/WatchSyncPipelineTests.swift`
**Action**: modify

`makeService(forContextKey:session:storageKey:)` switch (`:411-455`): every arm creates a concrete `Show*Preference` store — replace with `BoolPreferenceStore`:
```swift
case "showUndatedReminders":
    return SkippedReminderSyncService(
        session: session,
        skipStore: skipStore,
        showUndatedStore: BoolPreferenceStore(defaults: .standard, key: storageKey, fallback: false))
case "showRecurrence":
    return SkippedReminderSyncService(
        session: session,
        skipStore: skipStore,
        showRecurrenceStore: BoolPreferenceStore(defaults: .standard, key: storageKey, fallback: true))
// … same for "showAlarms", "showList", "showCompletionGlow"
```

Note: the `default` arm's `Issue.record("unexpected legacy context key \(contextKey)")` — unchanged (the switch still handles all five context keys, just with different store types).

`makePreference(forContextKey:defaults:storageKey:)` (`:411` area): this reads `defaults.object(forKey: storageKey) as? Bool ?? false` — no change needed (it's already generic, doesn't reference the old structs). But the fallback of `false` is wrong for four of the five context keys — this is a **pre-existing** issue and out of scope. Do not fix.

`recceivedPreferenceSurvivesRelaunch` (`157-164`): the `@Test(arguments:)` array passes context-key strings — unchanged (the switch inside `makeService` handles the mapping).

#### 3. `ShowCompletionGlowStateTests.swift`
**File**: `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift`
**Action**: modify

The tests write to/read from `.standard` with the hardcoded key `"showCompletionGlow"` (`:34-35`). This is test code that interacts with the real key — change:
```swift
// Before
let key = "showCompletionGlow"

// After
let key = BoolPreferenceKey.showCompletionGlow.rawValue
```
Or keep the literal — test isolation is the priority. The store construction inside `ShowCompletionGlowState` (3b.5) is what matters.

#### 4. `ContentViewModelTests.swift`
**File**: `SingleThreadTests/ContentViewModelTests.swift`
**Action**: modify

Init injection of `ShowCompletionGlowPreference` → `BoolPreferenceStore`:
```swift
// Before
let viewModel = ContentViewModel(showCompletionGlow: ShowCompletionGlowPreference(defaults: .standard, key: "test-glow-\(suffix)"))

// After
let viewModel = ContentViewModel(showCompletionGlow: BoolPreferenceStore(defaults: .standard, key: "test-glow-\(suffix)", fallback: true))
```

#### 5. `CompletionGlowViewModelTests.swift`
**File**: `SingleThreadTests/CompletionGlowViewModelTests.swift`
**Action**: modify

`glowStaysInactiveWhenPreferenceDisabled` (`:83-93`) — adapt store construction:
```swift
// Before
let pref = ShowCompletionGlowPreference(defaults: .standard, key: "test-glow-disabled-\(UUID())")
pref.set(false)

// After
let pref = BoolPreferenceStore(defaults: .standard, key: "test-glow-disabled-\(UUID())", fallback: true)
pref.set(false)
```

### 3d. Old-code removal

**Delete** these six production files:
- `SingleThreadCore/Sources/SingleThreadCore/ShowDatePreference.swift`
- `SingleThreadCore/Sources/SingleThreadCore/ShowListPreference.swift`
- `SingleThreadCore/Sources/SingleThreadCore/ShowRecurrencePreference.swift`
- `SingleThreadCore/Sources/SingleThreadCore/ShowAlarmsPreference.swift`
- `SingleThreadCore/Sources/SingleThreadCore/ShowCompletionGlowPreference.swift`
- `SingleThreadCore/Sources/SingleThreadCore/ShowUndatedRemindersPreference.swift`

**Delete** these five test files:
- `SingleThreadTests/ShowDatePreferenceTests.swift`
- `SingleThreadTests/ShowListPreferenceTests.swift`
- `SingleThreadTests/ShowRecurrencePreferenceTests.swift`
- `SingleThreadTests/ShowAlarmsPreferenceTests.swift`
- `SingleThreadTests/ShowCompletionGlowPreferenceTests.swift`

(`ShowUndatedRemindersPreferenceTests.swift` never existed — covered only via sync tests.)

### 3e. Format + lint

Run:
- [ ] `make format` (SwiftFormat + SwiftLint --fix)
- [ ] `make lint` (SwiftFormat --lint + SwiftLint lint --strict)

Watch for:
- `function_body_length` on `SkippedReminderSyncService.init` — replacing six concrete params with six generic params shouldn't change line count significantly, but the init is near the limit (suppressed `:298-300`).
- `identifier_name` on `key` and `fallback` — both are ≥ 3 characters, should pass.
- Line length on long `BoolPreferenceStore(key: BoolPreferenceKey.… .rawValue, fallback: …)` lines — may need wrapping.

### Verification
#### Automated
- [ ] `./scripts/test.sh` — full CI gate: format, lint, build, Periphery, unit tests (iOS + watchOS), UI tests (iOS + watchOS). All green.
- [ ] Periphery specifically confirms no dead code from removed files (no lingering `ShowDatePreference` references).

#### Manual
- [ ] Run app once with `--seed` launch arg to confirm seeded prefs round-trip
- [ ] Run app once with `--reset-glow-preference` to confirm the `.standard` vs App-Group glow-seam mismatch still works
- [ ] Toggle each of the six preferences in Settings → confirm they persist across app restart
- [ ] Confirm watch app receives preference changes from phone

---

## What's NOT in This Plan

- `@AppStorage` declarations in `ContentView.swift` — out of scope (design.md).
- Watch double-persistence fix (T2.3) — separate concern.
- `UserDefaults` container split (T2.1/T2.4) — deferred in var-759 audit.
- Widget or watch-UI test bundles — widget has none; adding one is a pbxproj operation.
- `SortOptionStore` extraction — it stores a non-Bool type.
- `SettingsViewModel.swift` — already confirmed to have no references to the old structs (research Q1).
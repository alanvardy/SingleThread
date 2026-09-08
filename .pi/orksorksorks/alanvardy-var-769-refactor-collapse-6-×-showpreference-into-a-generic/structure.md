# Structure Outline

## Approach

Replace six near-identical `Show*Preference` structs with a single generic
`BoolPreferenceStore` parameterized by key string and absent-value fallback,
exposing `isEnabled`/`set`. Add a `BoolPreferenceKey` enum of named
constants so production callers never hand-type key strings. Build bottom-up:
constants → store → mechanical call-site rename + cleanup. Every layer ships
with its tests green before the next layer begins. `@AppStorage` declarations
in `ContentView.swift` are out of scope — they are SwiftUI bindings, not
duplicated logic.

---

## Stage 1: `BoolPreferenceKey` — Key Constants

The ground-floor layer: a single `String`-backed enum providing named
constants for the six preference keys. Zero dependencies — no store, no
UserDefaults, no logic. This layer exists so Stage 2's tests and Stage 3's
call sites never hand-type key strings, eliminating silent typo divergence
across the 15+ call sites (widget, sync service, AppViewModel, watch states).

**Files**:
- New: `SingleThreadCore/Sources/SingleThreadCore/BoolPreferenceKey.swift`
- New: `SingleThreadTests/BoolPreferenceKeyTests.swift`

**Key changes**:
```swift
// BoolPreferenceKey.swift
enum BoolPreferenceKey: String, CaseIterable, Sendable {
    case showDate = "showDate"
    // fallback: true
    case showRecurrence = "showRecurrence"
    // fallback: true
    case showAlarms = "showAlarms"
    // fallback: true
    case showCompletionGlow = "showCompletionGlow"
    // fallback: true
    case showList = "showList"
    // fallback: false
    case showUndatedReminders = "showUndatedReminders"
    // fallback: false
}
```
Note: the fallback boolean is NOT stored on the enum — it's a property of the
`BoolPreferenceStore` instance. The comments are documentation only.

**Tests** (`BoolPreferenceKeyTests.swift`):
- `keyStringsMatchExistingHardcodedKeys` — parameterized over all six cases,
  asserts `rawValue` equals the exact string each old struct's `key` default
  uses (verified against research.md Q1 table)
- `allCasesIsExhaustive` — count == 6
- `isSendable` — compile-time conformance check

**Verify**: `make test SIM=iPhone 17,OS=26.1 -only-testing:SingleThreadTests/BoolPreferenceKeyTests`
passes. (No UI or Periphery gate yet — this is a leaf type with no consumers.)

---

## Stage 2: `BoolPreferenceStore` — Generic Store

The core data-access layer: a single generic-shaped struct that replaces all
six `Show*Preference` structs. Parameterized by `key: String` (for test
injection) and `fallback: Bool`; exposes `var isEnabled: Bool` (read via
`object(forKey:) as? Bool ?? fallback`) and `func set(_: Bool)` (write via
`set(_:forKey:)`). `defaults:` defaults to `AppGroup.defaults`.

**Files**:
- New: `SingleThreadCore/Sources/SingleThreadCore/BoolPreferenceStore.swift`
- New: `SingleThreadTests/BoolPreferenceStoreTests.swift`

**Key changes**:
```swift
// BoolPreferenceStore.swift
public struct BoolPreferenceStore: Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let fallback: Bool

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String,
        fallback: Bool
    ) { ... }

    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    public func set(_ value: Bool) {
        defaults.set(value, forKey: key)
    }
}
```

Pattern follows `SortOptionStore` shape (`research.md` Q2 — init with
`defaults:` + `key:`, read/write in same method, Sendable) but uses
`isEnabled`/`set` (five of six existing structs' API) instead of
`load()`/`save()` (only `ShowUndatedRemindersPreference`'s API). Fallback
boolean is explicit in `init` — no magic defaults.

**Tests** (`BoolPreferenceStoreTests.swift`):
Parameterized over all six `(key: String, fallback: Bool)` pairs, using
`UserDefaults.standard` + UUID-scoped key per test to avoid cross-test
contamination:
- `absentValueFallsBackToConfiguredDefault` — nil→fallback (both true and false cases)
- `roundTripTrue` / `roundTripFalse` — set then read, both polarities
- `setOverwritesPreviousValue` — set true, set false, read false
- `customDefaultsInjection` — init with a non-default UserDefaults suite, verify isolation
- `isSendable` — compile-time conformance check

`defer { defaults.removeObject(forKey: uuidKey) }` per test (existing
pattern from `ShowAlarmsPreferenceTests.swift:8-15`,
`research.md` Q4).

**Verify**: `make test SIM=iPhone 17,OS=26.1 -only-testing:SingleThreadTests/BoolPreferenceStoreTests`
passes. The old `Show*Preference` structs still exist — this layer adds the
replacement without removing anything.

---

## Stage 3: Call-Site Replacement + Old-Code Removal + Full Gate

The integration layer: mechanically replace every reference to the six old
`Show*Preference` types with `BoolPreferenceStore` across all targets, then
delete the old struct files. This is one stage because the replacements are
coupled to the removals — leaving both in the tree creates dead code and two
parallel conventions.

### 3a. SingleThreadCore call sites

| File | Change |
|---|---|
| `AppViewModel.swift` | `ShowDatePreference()` → `BoolPreferenceStore(key: BoolPreferenceKey.showDate.rawValue, fallback: true)` (×5, one per key); `lastShowDate` etc. caches become `Bool`; `handlePreferencesChanged` reads `.isEnabled` (already does for 5 of 6, now uniform). `showCompletionGlowStore` field type changes. |
| `ContentViewModel.swift` | `showCompletionGlow: ShowCompletionGlowPreference` → `showCompletionGlow: BoolPreferenceStore`; init default `BoolPreferenceStore(key: BoolPreferenceKey.showCompletionGlow.rawValue, fallback: true)`. Private field type changes; `isEnabled` read unchanged (same API). |
| `SkippedReminderSyncService.swift` | Six concrete store params (`showDateStore: ShowDatePreference`, …) → six `BoolPreferenceStore` params. `showUndatedStore.save(value)` → `.set(value)`. Push `showUndatedStore.load()` → `.isEnabled`. Receive hooks unchanged (already call `.set`/`.isEnabled`/`.save`). |
| `ReminderStore.swift` | `showsUndatedReminders` property: `ShowUndatedRemindersPreference().load()` → `boolStore.isEnabled` (store injected or default-constructed). |
| `SettingsViewModel.swift` | No type references to old structs (only `@AppStorage`-facing; confirmed in research Q1). May need no change. |
| `Widget/NextThingWidget.swift` | `ShowDatePreference().isEnabled` → `BoolPreferenceStore(key: ..., fallback: true).isEnabled` (×4); raw `bool(forKey:)` for undated → `BoolPreferenceStore(key: ..., fallback: false).isEnabled`. |

### 3b. Watch target call sites

| File | Change |
|---|---|
| `ShowDateState.swift` | `private let preference = ShowDatePreference(defaults: .standard)` → `BoolPreferenceStore(defaults: .standard, key: BoolPreferenceKey.showDate.rawValue, fallback: true)` |
| `ShowListState.swift` | Same pattern, `key: .showList, fallback: false` |
| `ShowRecurrenceState.swift` | `key: .showRecurrence, fallback: true` |
| `ShowAlarmsState.swift` | `key: .showAlarms, fallback: true` |
| `ShowCompletionGlowState.swift` | `key: .showCompletionGlow, fallback: true` |
| `WatchAppViewModel.swift` | Sync service init: six concrete store params → six `BoolPreferenceStore` params (same mechanical change as 3a sync service). |
| `WatchReminderViewModel.swift` | `showDateState: ShowDateState` etc. — state-holder types unchanged (they wrap the store, not the old struct directly); only the internal `preference` field in each state holder changes. |

### 3c. Test adaptation

| File | Change |
|---|---|
| `ShowDatePreferenceTests.swift` (×5) | **Delete.** Replaced by `BoolPreferenceStoreTests` (Stage 2) which already parameterizes all six key+fallback pairs. |
| `SkippedReminderSyncServiceTests.swift` | `ShowDatePreference(defaults:key:)` → `BoolPreferenceStore(defaults:key:fallback:)` (×6 in test setup). |
| `WatchSyncPiipelineTests.swift` | `makePreference(forContextKey:defaults:storageKey:)` switch → `BoolPreferenceStore(defaults:key:fallback:)`; `makeService` similarly. |
| `ShowCompletionGlowStateTests.swift` | Hardcoded key `"showCompletionGlow"` → `BoolPreferenceKey.showCompletionGlow.rawValue` (or keep literal — test isolation is the priority). |
| `ContentViewModelTests.swift` | Init injection of `ShowCompletionGlowPreference` → `BoolPreferenceStore`. |
| `CompletionGlowViewModelTests.swift` | `glowStaysInactiveWhenPreferenceDisabled` — adapt store construction. |

### 3d. Old-code removal

Delete these six files from `SingleThreadCore/Sources/SingleThreadCore/`:
- `ShowDatePreference.swift`
- `ShowListPreference.swift`
- `ShowRecurrencePreference.swift`
- `ShowAlarmsPreference.swift`
- `ShowCompletionGlowPreference.swift`
- `ShowUndatedRemindersPreference.swift`

Delete these five test files from `SingleThreadTests/`:
- `ShowDatePreferenceTests.swift`
- `ShowListPreferenceTests.swift`
- `ShowRecurrencePreferenceTests.swift`
- `ShowAlarmsPreferenceTests.swift`
- `ShowCompletionGlowPreferenceTests.swift`

(`ShowUndatedRemindersPreferenceTests.swift` never existed — research Q4.)

### 3e. Format + lint

Run `make format` then `make lint` to ensure SwiftFormat/SwiftLint pass.
`function_body_length` on `SkippedReminderSyncService.init` — already
suppressed (`:298-300`); replacing six concrete params with six generic
params shouldn't change line count but vigilance is warranted.

**Verify**: Full CI gate:
```fish
./scripts/test.sh
```
This runs format, lint, build, Periphery, unit tests, and UI tests across
both iOS and watchOS. Periphery confirms no dead code from the removed files
(e.g. no lingering `ShowDatePreference` references).

**Manual spot-check**: after gate passes, run once with `--seed` to confirm
the seeded prefs round-trip, and once with `--reset-glow-preference` to
confirm the `.standard` vs App-Group glow-seam mismatch still works
(behavior-preserving — design.md open risks).

---

## Testing Checkpoints

After each stage, before advancing:

1. **Stage 1 gate**: `make test -only-testing:SingleThreadTests/BoolPreferenceKeyTests` — all key strings match existing hardcoded literals; enum has exactly 6 cases.
2. **Stage 2 gate**: `make test -only-testing:SingleThreadTests/BoolPreferenceStoreTests` — parameterized absent-fallback + round-trip passes for all six key+fllback pairs.
3. **Stage 3 gate**: `./scripts/test.sh` — full CI pipeline (format, lint, build, Periphery, iOS unit+UI, watch unit+UI) all green. No dead code. No user-visible behavior change.

---

## What This Outline Does NOT Cover

- **`@AppStorage` declarations** in `ContentView.swift` — out of scope (design.md).
- **Watch double-persistence fix** (T2.3) — separate concern; this refactor
  doesn't change how `SkippedReminderSyncService` + `Show*State` each write.
- **UserDefaults container split** (T2.1/T2.4) — deferred in var-759 audit;
  `BoolPreferenceStore` inherits the same `defaults:` parameter pattern as
  the oldstructs, preserving current behavior (App Group on iOS/widget,
  `.standard` on watch).
- **Widget or watch-UI test bundles** — widget has no test bundle and adding
  one is apbxproj/scheme operation (AGENTS.md). Watch-UI tests are
  unchanged — they are launch-arg-driven.
- **`SortOptionStore` extraction** — it stores a non-Bool type and is out
  of scope.
- **Raw `bool(forKey:)` read in `NextThingWidget.swift:71`** — the generic
  store doesn't prevent this; migrating it to use the store is a one-line
  improvement (optional, noted in design.md open risks).
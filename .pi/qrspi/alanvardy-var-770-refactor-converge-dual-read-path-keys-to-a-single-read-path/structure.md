# Structure Outline

## Approach

Converge 12 keys (7 AG-suite, 5 STD-suite) that are read through two coexisting
mechanisms — `@AppStorage` + raw/typed `UserDefaults` — to a single authoritative
read path each. Built bottom-up: centralize key constants → normalize the
odd-one-out store type → add store wrappers for launch-time STD keys → remove
`@AppStorage` for AG keys → migrate the settings sheet → fix remaining raw reads.

---

## Stage 1: Key constant centralization on existing store types

Add `static let defaultsKey` to every Core store type that lacks one, then update
every site that repeats the literal to reference the constant. Purely additive —
no behavior change.

**Files**:
- `SingleThreadCore/…/ShowDatePreference.swift`, `ShowListPreference.swift`,
  `ShowRecurrencePreference.swift`, `ShowAlarmsPreference.swift`,
  `ShowCompletionGlowPreference.swift`, `ShowUndatedRemindersPreference.swift`
- `SingleThreadCore/…/CompletionCounterStore.swift`, `SkipCountStore.swift`,
  `SkippedReminderStore.swift` (`ReminderSkip.swift`), `ExcludedListStore.swift`,
  `PendingCompletionStore.swift`
- `SingleThreadCore/…/SkippedReminderSyncService.swift` (PayloadKey enum)
- `SingleThreadCore/…/UITestingSeed.swift` (persistedKeys array)
- `SingleThread/ContentView.swift` (@AppStorage declarations for AG keys)
- `SingleThread/AppViewModel.swift` (registerDefaults, didChange observer keys,
  sync hook writes)
- `SingleThreadWidget/NextThingWidget.swift` (raw bool(forKey:) line)
- `SingleThreadWatch/WatchAppViewModel.swift` (seam writes)
- Test fixtures that repeat literals directly

**Key changes**:

```swift
// Added to each of 11 store types (SortOption already has it):
static let defaultsKey = "<literal>"

// PayloadKey raw values become:
enum PayloadKey: String {
    case skippedReminderIdentifiers = SkippedReminderStore.defaultsKey  // was "skippedReminderIdentifiers"
    case skipCounts = SkipCountStore.defaultsKey
    case excludedListTitles = ExcludedListStore.defaultsKey
    // … 8 more, same pattern; 2 payload-only keys (completeReminderIdentifier,
    // deleteReminderIdentifier) keep their literals
}

// UITestingSeed.persistedKeys becomes:
static let persistedKeys: [String] = [
    ShowDatePreference.defaultsKey, ShowListPreference.defaultsKey,
    // … all 12 dual-read-path keys + existing constants
]
```

**Tests**: Existing tests pass unchanged — they use per-test UUID keys, not the
centralized literal. `UITestingSeedTests` (`persistedKeys` wipe list still
correct). `SkippedReminderSyncServiceTests` (wire format byte-identical).
New: grep-based verification that each key string appears only at its `static
let` declaration (plus the PayloadKey case referencing it).

**Verify**: `make test` (unit-only) green. `make lint` green.

---

## Stage 2: ShowUndatedRemindersPreference normalization

Replace `load()/save(_:)` with `isEnabled`/`set(_:)` to match the five sibling
`Show*Preference` types. Update all callers. This is prerequisite for using this
type as the sole AG read path in Stage 4.

**Files**:
- `SingleThreadCore/…/ShowUndatedRemindersPreference.swift`
- `SingleThreadCore/…/ReminderStore.swift` (`showsUndatedReminders` didSet)
- `SingleThreadCore/…/SkippedReminderSyncService.swift` (`pushAll` read,
  `apply` write)
- `SingleThread/AppViewModel.swift` (didChange observer read, init snapshot,
  `onShowUndatedRemindersChanged` hook, seed writes)
- `SingleThreadWatch/WatchAppViewModel.swift` (launch restore, sync receive
  hooks)
- `SingleThreadWidget/NextThingWidget.swift` (raw read — still raw in this
  stage, converted to `.isEnabled` in Stage 6)

**Key changes**:

```swift
// ShowUndatedRemindersPreference gains:
var isEnabled: Bool { defaults.object(forKey: key) as? Bool ?? false }
func set(_ enabled: Bool) { defaults.set(enabled, forKey: key) }

// load()/save(_:) become internal or removed; callers migrate:
//   preference.load()     → preference.isEnabled
//   preference.save(true) → preference.set(true)
```

**Tests**: New `ShowUndatedRemindersPreferenceTests.swift` (round-trip true/false
+ absent-key → false, matching sibling test patterns from conventions.md).
Existing callers' tests still green: `ReminderStoreTests` (showsUndatedReminders
didSet still fires reload hook), `SkippedReminderSyncServiceTests` (pushAll
round-trip + apply persist), `WatchSyncPipelineTests` (watch receive).

**Verify**: `make test` green. New preference tests pass. `make lint` green.

---

## Stage 3: STD launch-time store types + programmatic read switch

Create three new store types in `SingleThreadCore` for the four STD-suite keys
read before/outside SwiftUI views. Switch AppDelegate and background-handler
reads to use them. `@AppStorage` **remains** for these keys in ContentView —
the store types serve the programmatic reads only.

**Files**:
- `SingleThreadCore/…/OrientationPreference.swift` (new)
- `SingleThreadCore/…/NotificationPreference.swift` (new, absorbing
  `AppViewModel.NotificationKeys` constants)
- `SingleThreadCore/…/AppearanceModePreference.swift` (new)
- `SingleThread/AppDelegate.swift` (orientation + appearanceMode reads)
- `SingleThread/AppViewModel.swift` (background notification reads; remove
  `NotificationKeys` enum, replaced by `NotificationPreference` constants)
- `SingleThread/ContentView.swift` (@AppStorage declarations update to
  reference new constants)
- `SingleThreadCore/…/UITestingSeed.swift` (persistedKeys gains new keys)

**Key changes**:

```swift
// OrientationPreference — follows Show*Preference pattern
struct OrientationPreference {
    static let defaultsKey = "allowsLandscape"
    init(defaults: UserDefaults = .standard, key: String = defaultsKey)
    var isLandscapeEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true  // absent → true
    }
    func setLandscapeEnabled(_ enabled: Bool)
}

// NotificationPreference — two keys, one type (replaces AppViewModel.NotificationKeys)
struct NotificationPreference {
    static let enabledDefaultsKey = "notificationsEnabled"
    static let intervalDefaultsKey = "notificationIntervalHours"
    init(defaults: UserDefaults = .standard,
         enabledKey: String = enabledDefaultsKey,
         intervalKey: String = intervalDefaultsKey)
    var isEnabled: Bool { … ?? false }
    var intervalHours: Int { … ?? 48 }
    func setEnabled(_ enabled: Bool)
    func setIntervalHours(_ hours: Int)
}

// AppearanceModePreference — wraps the existing AppearanceMode enum
struct AppearanceModePreference {
    static let defaultsKey = "appearanceMode"
    init(defaults: UserDefaults = .standard, key: String = defaultsKey)
    var mode: AppearanceMode {
        // delegates to AppearanceMode.load(from:) or inlines the rawValue logic
    }
    func setMode(_ mode: AppearanceMode) {
        defaults.set(mode.rawValue, forKey: key)
    }
}

// AppDelegate reads switch:
//   UserDefaults.standard.object(forKey: "allowsLandscape")   → OrientationPreference().isLandscapeEnabled
//   AppearanceMode.load()                                      → AppearanceModePreference().mode

// AppViewModel background handler:
//   UserDefaults.standard.bool(forKey: NotificationKeys.enabled)  → NotificationPreference().isEnabled
//   UserDefaults.standard.integer(forKey: NotificationKeys.intervalHours) → NotificationPreference().intervalHours
```

**Tests**: New `OrientationPreferenceTests.swift`, `NotificationPreferenceTests.swift`,
`AppearanceModePreferenceTests.swift` (round-trip + absent-key defaults, matching
Show*PreferenceTests patterns; AppearanceModePreferenceTests may extend existing
`AppearanceModeTests.swift`). `AppDelegateTests.swift` updated for new read path.
`NotificationSchedulingUITests` (background notification scheduling still
correct).

**Verify**: `make test` green. New store-type tests pass. `make lint` green.

---

## Stage 4: AG-suite @AppStorage removal + view observation

Remove the 7 `@AppStorage(…, store: AppGroup.defaults)` declarations for AG keys
from `ContentView`. Establish a view-observation mechanism so the settings sheet,
sort picker, and reminder cards still refresh when AG keys change. The exact
mechanism — `@Observable` holder fed by stores, or direct store reads at view
appearance — is deferred to `/5_plan`; this stage describes the boundary.

After this stage, **no `@AppStorage` for AG keys exists in any target**, and
every AG-key read goes through its store type.

**Files**:
- `SingleThread/ContentView.swift` (remove 7 @AppStorage; add observation source)
- `SingleThreadCore/…/` (possible new `@Observable` holder type)
- `SingleThread/ContentView+Settings.swift` (`makeSettingsBag()` AG reads —
  currently from `@AppStorage`; must switch to store reads; full migration in
  Stage 5)
- `SingleThread/ContentViewModel.swift` (if AG-key values are consumed here)

**Key changes** (signatures approximate — exact mechanism TBD in plan):

```swift
// Removed from ContentView:
//   @AppStorage("showDate") var showDate: Bool = true
//   @AppStorage("showList") var showList: Bool = false
//   … (all 7 AG keys)

// Added to ContentView (one possible mechanism):
@State private var preferences = PreferenceHolder()  // @Observable class

// PreferenceHolder (new, in Core or app target):
@MainActor @Observable
final class PreferenceHolder {
    var showDate = ShowDatePreference().isEnabled
    var showList = ShowListPreference().isEnabled
    // … 5 more; each reads store on init, refreshed via didChangeNotification
}

// ContentView body reads preferences.showDate instead of showDate @AppStorage
```

**Tests**: UI tests (`SingleThreadUITestsFlows` settings toggles, sort picker)
still pass — toggling a setting in the sheet persists and is visible on next
view appearance. Unit tests for the observation mechanism (new). Existing
`SettingsViewModelTests` may need update for new read path.

**Verify**: `make ui-test` green for settings-related flows. `make test` green.
`make lint` green. Manual: toggle each AG-key setting in the sheet, confirm the
change persists and is visible in the reminder list.

---

## Stage 5: Settings sheet store write-through

`SettingsBindings` AG-key property setters write directly to store types
(`showDatePreference.set(value)`) instead of assigning to `@AppStorage`-backed
properties. `makeSettingsBag()` AG-key reads come from stores. The `.onChange`
bridges for AG keys in `settingsSheetWritebacks` are removed. This eliminates
the `@AppStorage` → `.onChange` middleman for AG keys and is the natural
consequence of Stage 4.

**Files**:
- `SingleThread/ContentView+Settings.swift` (`settingsSheetWritebacks` AG-key
  `.onChange` handlers removed; `makeSettingsBag()` AG reads from stores)
- `SingleThread/SettingsBindings.swift` (AG property setters call
  `store.set(_:)`)
- `SingleThread/ContentView.swift` (side-effect `.onChange`s attached to the
  now-removed `@AppStorage` AG-setters — `showUndatedReminders → store + reload`,
  `sortOption → store.setSortOption` — must be re-anchored to the new
  observation mechanism)

**Key changes**:

```swift
// SettingsBindings — AG-key setters switch from @AppStorage write to store write:
var showDate: Bool {
    get { showDatePreference.isEnabled }
    set { showDatePreference.set(newValue) }
}
// … 6 more AG keys, same pattern

// makeSettingsBag() AG reads switch from @AppStorage properties to stores:
//   settings.showDate = showDate              → settings.showDate = showDatePreference.isEnabled

// settingsSheetWritebacks — AG-key .onChange blocks removed (7 blocks deleted)
```

**Tests**: UI tests for settings persistence (`SingleThreadUITestsFlows`).
`SettingsViewModelTests` updated. Manual: open settings, toggle each AG key,
dismiss sheet, reopen — values are preserved.

**Verify**: `make ui-test` green. `make test` green. `make lint` green.

---

## Stage 6: Remaining raw read fixes

Three small, independent stragglers — the last raw reads that bypass store types:

1. **`ContentViewModel.showsActionButtons`** — eliminate the raw
   `UserDefaults.standard.bool(forKey: "enableActionButtons")` read. Pass the
   value from the view hierarchy (where the `@AppStorage` binding still lives)
   or read from a shared property.
2. **Widget `showUndatedReminders` raw read** — `NextThingWidget.swift:71`:
   `AppGroup.defaults.bool(forKey:)` → `ShowUndatedRemindersPreference().isEnabled`.
3. **`ReminderStore.showsUndatedReminders` didSet** — the direct
   `AppGroup.defaults.set(newValue, forKey:)` write → `ShowUndatedRemindersPreference().set(newValue)`.

**Files**:
- `SingleThread/ContentViewModel.swift` (remove raw `bool(forKey:)`; add
  injected or passed `enableActionButtons: Bool`)
- `SingleThread/ContentView.swift` (pass `enableActionButtons` binding to
  `ContentViewModel`)
- `SingleThreadWidget/NextThingWidget.swift` (`:71` raw read → store)
- `SingleThreadCore/…/ReminderStore.swift` (`showsUndatedReminders` didSet
  write → store)

**Key changes**:

```swift
// ContentViewModel — enableActionButtons becomes a parameter, not a raw read:
// BEFORE: UserDefaults.standard.bool(forKey: "enableActionButtons")
// AFTER:  let enableActionButtons: Bool  // passed from ContentView's @AppStorage

// NextThingWidget — raw read becomes store:
// BEFORE: AppGroup.defaults.bool(forKey: "showUndatedReminders")
// AFTER:  ShowUndatedRemindersPreference().isEnabled

// ReminderStore.showsUndatedReminders didSet:
// BEFORE: AppGroup.defaults.set(newValue, forKey: "showUndatedReminders")
// AFTER:  ShowUndatedRemindersPreference().set(newValue)
```

**Tests**: `ActionButtonTests.swift` updated for new injection path.
`ReminderStoreTests` — `showsUndatedReminders` didSet still fires reload hook
without double-fire. Widget read path — widget timeline entry still reflects
correct `showUndatedReminders` value.

**Verify**: `make test` green. `make ui-test` green. `make lint` green.
Full gate: `./scripts/test.sh` — all targets, all suites, Periphery.

---

## Testing Checkpoints

After each stage, the incremental gate is `make test` (unit-only) green + `make
lint` green. The full `./scripts/test.sh` (unit + UI + watch + macOS + Periphery)
runs once, after Stage 6, as the final verification.

- **Stage 1**: `make test && make lint` — no behavior change, all existing
  tests green
- **Stage 2**: `make test && make lint` — new `ShowUndatedRemindersPreferenceTests`
  green; caller tests unaffected
- **Stage 3**: `make test && make lint` — new `OrientationPreferenceTests`,
  `NotificationPreferenceTests`, `AppearanceModePreferenceTests` green;
  `AppDelegateTests` updated
- **Stage 4**: `make test && make lint` + `make ui-test` (settings flows) —
  AG keys observable through new mechanism; no @AppStorage for AG keys remains
- **Stage 5**: `make test && make lint` + `make ui-test` — settings sheet
  persists through stores
- **Stage 6**: `make test && make lint` — final stragglers; then full
  `./scripts/test.sh` gate

---

## Cross-Cutting Notes

- **View observation mechanism (Stage 4) is deferred to `/5_plan`**. The
  design explicitly leaves this open; the plan will evaluate `@Observable`
  holder vs. direct store reads and pick one. Stage 4's signature is
  approximate until the plan locks it.
- **AppearanceModePreference (Stage 3) boundary**: `AppearanceMode` is an
  enum, not a bool — the `Show*Preference` pattern needs adaptation. The inline
  logic can live in the preference struct (removing `AppearanceMode.load(from:)`)
  or the preference can delegate to it. The plan resolves this.
- **SettingsBindings migration order** (Stage 5): all AG keys must switch
  atomically to store write-through — a half-migrated state where some write
  through stores and others through `@AppStorage` could break settings
  persistence. Stage 5 runs after Stage 4 has removed `@AppStorage` for AG keys
  entirely, so there is no `@AppStorage` to write to — the risk is eliminated by
  ordering.
- **`ReminderStore.showsUndatedReminders` didSet reload hook**: after Stage 6,
  the didSet writes through `ShowUndatedRemindersPreference().set(_:)`, which
  posts `didChangeNotification` on `AppGroup.defaults`. The existing observer in
  `AppViewModel` fires `handlePreferencesChanged` → diffs the value → may
  trigger `pushAll`. Verify no double-reload — the didSet's own reload hook
  (`ReminderStore.forceReload()`) should fire once, and the observer's diff
  should see no change (the value was already written).
- **Watch read paths are untouched throughout** — they already read exclusively
  through store types (`.standard`-constructed). The sync payload format is
  unchanged. PayloadKey constants (Stage 1) keep the same wire bytes.

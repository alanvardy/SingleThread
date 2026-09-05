# Design Discussion

## Current State

Twelve `UserDefaults`-backed preference keys are read through two coexisting
mechanisms, creating a transient-divergence window where a write between
`@AppStorage` (SwiftUI-observed, refreshed on `didChangeNotification`) and a
raw `UserDefaults.*` read (value at call time) can produce different values.

**AG-suite keys (7)** — persisted to `AppGroup.defaults`, shared with widget/watch:

| Key | @AppStorage site | Raw/typed read sites |
|---|---|---|
| `showDate` | `ContentView.swift:121` | `ShowDatePreference.isEnabled` (`ShowDatePreference.swift:20`), sync push/pull (`AppViewModel.swift:432`, `SkippedReminderSyncService.swift:187,354`), widget (`NextThingWidget.swift:64`), watch state (`ShowDateState.swift:13`) |
| `showList` | `ContentView.swift:124` | same pattern as showDate (`ShowListPreference.swift:20`, sync `:196,369`, widget `:65`, watch) |
| `showRecurrence` | `ContentView.swift:127` | same (`ShowRecurrencePreference.swift:20`, sync `:190,359`, widget `:66`, watch) |
| `showAlarms` | `ContentView.swift:129` | same (`ShowAlarmsPreference.swift:20`, sync `:193,364`, widget `:67`, watch) |
| `showCompletionGlow` | `ContentView.swift:132` | same (`ShowCompletionGlowPreference.swift:20`, sync `:199,374`, widget `:67` implicit, watch) |
| `sortOption` | `ContentView.swift:118` | `SortOptionStore.load()` at init (`AppViewModel.swift:25`, `WatchAppViewModel.swift:31`, `NextThingWidget.swift:72`, intents `ReminderIntents.swift:20,43`), sync (`:184,349`) |
| `showUndatedReminders` | `ContentView.swift:115` | **Three** read patterns: `ShowUndatedRemindersPreference.load()` (`:19`), `ReminderStore.showsUndatedReminders` didSet (`ReminderStore.swift:103-106`), **raw literal** `AppGroup.defaults.bool(forKey:)` in widget (`NextThingWidget.swift:71`) |

**STD-suite keys (5)** — `UserDefaults.standard`, not shared with widget/watch:

| Key | @AppStorage site | Raw read sites |
|---|---|---|
| `appearanceMode` | `ContentView.swift:72` | `AppearanceMode.load()` (`AppearanceMode.swift:80`) — called from `applicationDidBecomeActive` (`AppDelegate.swift:47`) **before** SwiftUI is alive |
| `allowsLandscape` | `ContentView.swift:79` | `UserDefaults.standard.object(forKey:)` in `application(_:supportedInterfaceOrientationsFor:)` (`AppDelegate.swift:50-57`) — **pre-SwiftUI** |
| `enableActionButtons` | `ContentView.swift:96` | `ContentViewModel.showsActionButtons` (`ContentViewModel.swift:58`) — during body evaluation; UI-test seams (`AppViewModel.swift:291,350`) |
| `notificationsEnabled` | `ContentView.swift:109` | background handler `scheduleNotificationIfNeeded` (`AppViewModel.swift:129`) |
| `notificationIntervalHours` | `ContentView.swift:112` | same handler (`AppViewModel.swift:133`) |

**Cross-cutting issues**:
- Key strings duplicated 4-6× each across store init defaults, `@AppStorage`
  literals, `PayloadKey` enum (`SkippedReminderSyncService.swift:278-294`),
  `UITestingSeed.persistedKeys` (`UITestingSeed.swift:73-98`), and test seams
  (research Q4). Only `SortOption.defaultsKey` (`SortOption.swift:18`) and
  `NotificationKeys` (`AppViewModel.swift:95-101`) are shared constants.
- Settings sheet writes through an intermediate `@Observable` `SettingsBindings`
  bag (`SettingsBindings.swift:14-16`); `.onChange` handlers write each bag
  value back to the `@AppStorage` property (`ContentView+Settings.swift:16-52`).
- `ShowUndatedRemindersPreference` uses `load()/save(_:)` while its five
  siblings use `isEnabled`/`set(_:)` — inconsistent API shape (research Q3).
- Widget reads `showUndatedReminders` via raw `bool(forKey:)` bypassing the
  wrapper entirely (`NextThingWidget.swift:71`).

## Desired End State

Every key has exactly one authoritative read path. A write through the
authoritative path is immediately visible to all consumers on the same target.

### AG-suite keys → store types (sole read path)

The seven AG keys converge to their existing typed store wrappers.
`@AppStorage` bindings for these keys are **removed** from `ContentView`.
View observation flows through the store types (or an `@Observable` holder
fed by them). The widget's raw `bool(forKey:)` read converts to the wrapper.

Verify: all 7 AG keys round-trip through their store type's `isEnabled`/`load()`
→ `set(_:)`/`save(_:)`. No `@AppStorage` for these keys remains in any target.

### STD-suite launch-time keys → new store types

`appearanceMode`, `allowsLandscape`, `notificationsEnabled`,
`notificationIntervalHours` get typed store wrappers in `SingleThreadCore`
following the `Show*Preference` pattern (`ShowDatePreference.swift:10-23`).
Their pre-SwiftUI reads (AppDelegate, background handler) use the store.
Their `@AppStorage` bindings in `ContentView` **remain** — these keys are
not shared across targets, SwiftUI observation is the natural view path,
and the store type serves the programmatic reads only.

Verify: `application(_:supportedInterfaceOrientationsFor:)` reads
`OrientationPreference().isLandscapeEnabled` (or equivalent), not
`UserDefaults.standard.object(forKey:)`. `scheduleNotificationIfNeeded`
reads `NotificationPreference().isEnabled`/`.intervalHours`.

### `enableActionButtons` → refactored without new type

The raw read in `ContentViewModel.showsActionButtons`
(`ContentViewModel.swift:58`) is eliminated. The value is passed in from the
view hierarchy (where the `@AppStorage` binding already lives) or read from a
shared view-model property that `@AppStorage` feeds. No new Core type.

Verify: `ContentViewModel` no longer calls `UserDefaults.standard.bool(forKey:)`.

### Key strings centralized

Each store type exposes its key as a `static let` constant. `@AppStorage`
declarations, `PayloadKey` members, `UITestingSeed.persistedKeys`, and test
fixtures reference the constant instead of repeating the literal. The two
existing constants (`SortOption.defaultsKey`, `NotificationKeys`) are kept;
all others follow the same pattern.

Verify: grep for each key string (e.g. `"showDate"`) returns only the store
type's `static let` declaration, plus the `PayloadKey` case literal (which
references the constant). No independent literals remain.

### Settings sheet writes through stores

`SettingsBindings` writes AG-key changes directly to store types
(`showDatePreference.set(value)`) instead of through `@AppStorage` →
`.onChange`. STD-key changes that keep `@AppStorage` continue through the
existing `.onChange` bridge. The `makeSettingsBag()` snapshot
(`ContentView+Settings.swift:55-83`) reads from stores for AG keys.

Verify: toggling any AG-key setting in the sheet persists through the store
type's `set(_:)` method, not through `@AppStorage`.

### `ShowUndatedRemindersPreference` normalized

`ShowUndatedRemindersPreference` gains `isEnabled`/`set(_:)` matching its
siblings. Existing `load()/save(_:)` become internal or are removed. The
widget's raw `bool(forKey:)` becomes `ShowUndatedRemindersPreference().isEnabled`.

## Patterns to Follow

- **Store type shape**: `init(defaults: UserDefaults = AppGroup.defaults, key: String = "<static constant>")`, `private let defaults/key`, computed `var isEnabled: Bool` reading `defaults.object(forKey:) as? Bool ?? <default>`, `func set(_ enabled: Bool)` writing `defaults.set(enabled, forKey: key)`. Template: `ShowDatePreference.swift:10-23`.
- **Default-when-missing**: `object(forKey:) as? Bool ?? <true/false>` — **not** `bool(forKey:)`, which returns `false` for missing keys and would silently flip the default for `true`-by-default keys (showAlarms, showCompletionGlow, showDate, showRecurrence). Documented rationale at `ShowDatePreference.swift:3-7`.
- **AppGroup.defaults for shared keys**: every store type defaulting to `AppGroup.defaults`. Widget and iOS app share the suite via the App Group entitlement (`AppGroup.entitlements:10`). Watch falls back to `.standard` (`AppGroup.swift:15-17`), which is correct — the watch has no App Group and sync writes to `.standard`.
- **Testing**: per-test UUID-keyed `.standard` with `defer removeObject` for unit tests (`ShowDatePreferenceTests.swift:8-9`); or per-test `UserDefaults(suiteName: "…Tests-\(UUID)")` for parallel-safe suites (`SkipCountStoreTests.swift:69-71`). New store types follow the same pattern.
- **Key constant pattern**: `static let defaultsKey = "<literal>"` on the store type (cf. `SortOption.swift:18`). `@AppStorage` uses the constant; `PayloadKey` members reference it; `UITestingSeed.persistedKeys` becomes `[ShowDatePreference.defaultsKey, …]`.
- **SettingsBindings pattern**: `@Observable` class with `var` properties mirroring preference values (`SettingsBindings.swift:14-16`). AG-key writes call store `.set(_:)`; STD-key writes keep the `@AppStorage` → `.onChange` bridge.
- **Do NOT follow**: `ShowUndatedRemindersPreference`'s `load()/save(_:)` asymmetry — normalize to `isEnabled`/`set(_:)` before adding it as the sole read path.
- **Do NOT follow**: the widget's raw `AppGroup.defaults.bool(forKey:)` (`NextThingWidget.swift:71`) — replace with the wrapper.
- **Do NOT follow**: independent key literals in `PayloadKey` and `UITestingSeed` — reference the store constants.

## Design Decisions

1. **AG keys converge to store types (eliminate @AppStorage)**: the store types
   are already the de facto read path across widget, watch, sync service, and
   AppViewModel. Removing `@AppStorage` for these 7 keys eliminates the last
   dual-read surface. View observation will use the store or an `@Observable`
   holder fed by it — exact mechanism decided in `/5_plan`.

2. **STD launch-time keys get store types; @AppStorage retained for views**:
   `appearanceMode`, `allowsLandscape`, `notificationsEnabled`,
   `notificationIntervalHours` are read before or outside SwiftUI view
   evaluation (AppDelegate, background handler) where `@AppStorage` genuinely
   cannot serve. Store types solve that constraint. `@AppStorage` stays for
   the view path — these keys aren't shared across targets, so dual-path risk
   is low once programmatic reads use the same store.

3. **`enableActionButtons` refactored without a new Core type**: the sole
   raw read (`ContentViewModel.swift:58`) runs during body evaluation where
   the `@AppStorage` binding is already in scope. Pass the value in or read
   from a shared property. No new type needed.

4. **Key strings centralized**: each store type gains a `static let defaultsKey`.
   `@AppStorage`, `PayloadKey`, `UITestingSeed.persistedKeys`, and test fixtures
   reference it. The two existing constants (`SortOption.defaultsKey`,
   `NotificationKeys`) are the pattern; all others follow suit. PayloadKey
   drift from store keys is eliminated.

5. **Settings sheet writes AG keys through stores**: `SettingsBindings`
   properties for AG keys call `store.set(_:)` directly instead of relying on
   `@AppStorage` → `.onChange` propagation. Removes the write-back middleman
   for those keys and is a natural consequence of decision 1.

6. **`ShowUndatedRemindersPreference` normalized to `isEnabled`/`set(_:)`**:
   the `load()/save(_:)` asymmetry is fixed before this type becomes the sole
   read path. Internal implementation can delegate to the new methods; callers
   (`ReminderStore.showsUndatedReminders`, sync service, watch) migrate to the
   uniform API.

## What We're NOT Doing

- **Not touching watch read paths** — they already read exclusively through
  store types (`.standard`-constructed, `WatchAppViewModel.swift:164-172`) or
  `@Observable` state holders fed by sync. No `@AppStorage` exists on watch.
- **Not changing the sync payload format or transport** — `PayloadKey` members
  remain string-identical to store keys; `applicationContext` shape stays the
  same. The change is only that `PayloadKey` members reference the store
  constant instead of a duplicate literal.
- **Not touching cosmetic-only STD keys**: `textSize`, `backgroundEnabled`,
  `backgroundFadePercent`, `backgroundPinned`, `showMicrophoneButton`,
  `showSwipePrompt`, `showUndoButton`. These are `@AppStorage`-only with no
  raw read sites — they have no dual-path problem to solve.
- **Not removing `@AppStorage` entirely** — it remains the view path for
  STD-suite keys and cosmetic keys.
- **Not changing widget timeline policy or refresh triggers** — the widget
  already reads through store types (AG-defaulted); only the
  `showUndatedReminders` raw read is converted.
- **Not touching `isEntitled`** — it has no UserDefaults backing (in-memory
  `EntitlementStore`), so it's not a dual-read-path key.
- **Not changing the `didChangeNotification` observer** in `AppViewModel` —
  it already watches AG and triggers sync; once all AG reads go through stores,
  the observer's own raw reads are through the stores too.

## Open Risks

- **AppDelegate orientation read before SwiftUI boot**: `allowsLandscape` must
  be readable before any SwiftUI view exists. A store type constructed over
  `.standard` with the correct key satisfies this — the store is a thin wrapper
  over `UserDefaults`. Risk: if the new store type is placed in `SingleThreadCore`
  and imported, the import must not trigger SwiftUI. Mitigation: the store types
  are plain structs with no SwiftUI dependency; they already exist in Core today.
- **View observation after @AppStorage removal**: the 7 AG keys currently use
  `@AppStorage` which auto-refreshes views on `didChangeNotification`. After
  removal, views need another observation mechanism. Options: read through an
  `@Observable` holder that watches the store (the watch `Show*State` pattern),
  or read the store at view appearance. Exact mechanism deferred to `/5_plan`.
- **SettingsBindings migration order**: the settings sheet write-back chain is
  sensitive — a half-migrated state where some keys write through stores and
  others through `@AppStorage` could break settings persistence. The plan must
  migrate all AG keys atomically or ensure the intermediate state is safe.
- **`ReminderStore.showsUndatedReminders` didSet path**: this property
  (`ReminderStore.swift:103-106`) writes `AppGroup.defaults.set` directly
  (bypassing the wrapper) and fires a reload hook. After normalization, it
  should write through `ShowUndatedRemindersPreference.set(_:)`. Risk: the
  didSet and the preference store write must not race or double-fire the
  reload hook.
- **Watch sync receive timing**: watch launch reads `.standard` before sync
  delivers values (`WatchAppViewModel.swift:31,34`). After sync, `apply(context:)`
  overwrites via store `.set()`. This is unchanged — we're not touching watch
  read paths — but the plan must verify no accidental regression in the init
  order.

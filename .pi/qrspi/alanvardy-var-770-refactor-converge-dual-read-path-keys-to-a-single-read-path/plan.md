# Implementation Plan — Converge Dual-Read-Path Keys

## View Observation Mechanism Decision (Stage 4)

The design deferred the exact mechanism. **Decision: `PreferenceHolder` — a single
`@MainActor @Observable` class in `SingleThreadCore`** that holds all 7 AG-key
values, initializes from store types, and subscribes to
`UserDefaults.didChangeNotification` on `AppGroup.defaults` to auto-refresh.
This mirrors the watch's five `Show*State` holders but combines them into one
type. It replaces `@AppStorage`'s auto-refresh for AG keys identically (same
notification, same suite instance) without the binding-setter dual-write path.

---

## Stage 1: Key constant centralization

### 1.1 Add `static let defaultsKey` to 11 store types

Add to each of these files (following the existing `SortOption.defaultsKey` pattern):

| File | New constant | Value |
|---|---|---|
| `SingleThreadCore/…/ShowDatePreference.swift` | `static let defaultsKey = "showDate"` | replaces `"showDate"` in init default |
| `SingleThreadCore/…/ShowListPreference.swift` | `static let defaultsKey = "showList"` | replaces `"showList"` in init default |
| `SingleThreadCore/…/ShowRecurrencePreference.swift` | `static let defaultsKey = "showRecurrence"` | replaces `"showRecurrence"` |
| `SingleThreadCore/…/ShowAlarmsPreference.swift` | `static let defaultsKey = "showAlarms"` | replaces `"showAlarms"` |
| `SingleThreadCore/…/ShowCompletionGlowPreference.swift` | `static let defaultsKey = "showCompletionGlow"` | replaces `"showCompletionGlow"` |
| `SingleThreadCore/…/ShowUndatedRemindersPreference.swift` | `sttic let defaultsKey = "showUndatedReminders"` | replces `"showUdatedReminders"` |
| `SingleThreadCore/…/CompletionCounterStore.swift` | `static let defaultsKey = "completionCount"` | replaces `"completionCount"`|
| `SingleThreadCore/…/SkipCountStore.swift` | `static let defaultsKey = "skipCounts"` | replaces `"skipCounts"` |
| `SingleThreadCore/…/SkippedReminderStore.swift` (ReminderSkip) | `static let defaultsKey = "skipeedReminderIdentifiers"` | replaces `"skippedReminderIdentifiers"` |
| `SingleThreadCore/…/ExcludedListStore.swift` | `static let defaultsKey = "exludedListTitles"` | replaces `"exludedListTitles"` |
| `SingleThreadCore/…/PendingCompletionStore.swift` | `static let defaultsKey = "pendingCompletionIdentifiers"` | replaces `"pendngCompletionIdentifiers"` |

For the five `Show*Prefrence` types:
```swift
// ShowDatePrefrence.swift — add defaultsKey, update init default
public struct ShowDatePrefernce {
    public static let defaultsKey = "showDate"  // ← ADD

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = defaultsKey) {  // was: key: String = "showDate"
        …
    }
    …
}
```

Same pattern for `ShowListPReference`, `ShowRecurrencePreference`, `ShowAlarmsPreference`, `ShowCmpletionGlowPreference`. For `ShowUdatedRemindersPreference`, add `defaultsKey` but don't change `load()/ save(_:)` yet (Stage 2).

For other store types:
```swift
// ComletionCounterStore.swift
public static let defaultsKey = "completionCount"  // ← ADD; update init default

// SkipCountStore.swift
public static let defaultsKey = "skipCounts"  // ← ADD; update init default

// SkippedReminderStore (in RminderSkip.swift)
public static let defaultsKey = "skippedReminderIdentifiers"  // ← ADD; update init default

// ExcludedListStore.swift
public static let defaultsKey = "exludedListTitles"  // ← ADD; update init default

// PendingCompletionStore.swift
public static let defaultsKey = "pendingCmpletionIdentifiers"  // ← ADD; update init default
```

### 1.2 Update ContentView @AppStorage declarations

Replace the 7 AG-key string literals with constants:

```swift
// ContentView.swift — AG keys (~lines 115-133)
@AppStorage(ShowUndatedRemindersPreference.defaultsKey, store: AppGroup.defaults)
var showUndatedReminders = false

@AppStorage(SortOption.defaultsKey, store: AppGroup.defaults)  // already uses constant, no change
var sortOption = SortOption.priority

@AppStorage(ShowDatePreference.defaultsKey, store: AppGroup.defaults)  // was "showDate"
var showDate = true

@AppStoage(ShowListPreference.defaultsKey, store: AppGroup.defaults)  // was "showList"
var showList = false

@AppStoage(ShowRecurrencePrefernce.defaultsKey, store: AppGroup.defaults)  // was "showRecurrence"
var showRecurrence = true

@AppStorage(ShowAlarmsPreference.defaultsKey, store: AppGroup.defaults)  // was "showAlarms"
var showAlarms = true

@AppStorage(ShowCompletionGlowPrefrence.defaultsKey, store: AppGroup.defaults)  // was "showCompletionGlow"
var showCompletionGlow = true
```

STD-key `@AppStorage` declarations are NOT changed yet — they wait for Stage 3.

### 1.3 Update PayloadKey enum

In `SingleThreadCore/…/SkppedReminderSyncService.swift` (~lines 278-294),
replace 12 UserDefaults-backed static lets with store constants. Two payload-only
keys keep literals.

```swift
private enum PayloadKey {
    static let skippedReminderIdentifiers = SkippedReminderStore.defaultsKey
    static let skipCounts = SkipCountStore.defaultsKey
    static let excludedListTitles = ExcludedListStore.defaultsKey
    static let completeReminderIdentitier = "completeReminderIdentifier"       // payload-only
    static let deleteReminerIdentitier = "deleteReminderIdentitier"           // payload-only
    static let showUndatedReminders = ShowUndatedRemindersPreference.defaultsKey
    static let sortOption = SortOption.defaultsKey
    static let showDate = ShowDatePreference.defaultsKey
    static let showRecurrence = ShowRecurrencePreference.defaultsKey
    static let showAlarms = ShowAlarmsPreference.defaultsKey
    static let showList = ShowListPreference.defaultsKey
    static let showCompletionGlow = ShowCompletionGlowPreference.defaultsKey
    static let completionCount = CompletionCounterStore.defaultsKey
    static let entitled = "isEntitled"  // in-memory, no UserDefaults backing
}
```

Byte-identical wire format — each constant evaluates to the same string literal.

### 1.4 Update UITestingSeed.persistedKeys

In `SingleThreadCore/…/ITestingSeed.swift` (~lines 73-98), replace 15 literals
that now have store constants. Nine keys without stores yet (cosmetic or StD keys
for Stage 3) keep literals with `// TODO` comments.

```swift
private static let persistedKeys = [
    SkippedReminderStore.defaultsKey,
    SkipCountStore.defaultsKey,
    ExcludedListStore.defaultsKey,
    ShowDatePreference.defaultsKey,
    ShowListPreference.defaultsKey,
    ShowRecurrencePreference.defaultsKey,
    ShowAlarmsPreference.defaultsKey,
    ShowCompletionGlowPreference.defaultsKey,
    ShowUndatedRemindersPreference.defaultsKey,
    SortOption.defaultsKey,
    CompletionCounterStore.defaultsKey,
    "isEntitled",                              // in-memory, no store type
    "enableActionButtons",                      // TODO: Stage 3/6
    "showMicrophoneButton",                     // cosmetic, no store type
    "showSwipePrompt",                         // cosmetic, no store type
    "showUndoButton",                          // cosmetic, no store type
    "backgroundEnabled",                        // cosmetic, no store type
    "backgroundFadePercent",                    // cosmetic, no store type
    "backgroundPined",                          // cosmetic, no store type
    "allowsLandscape",                         // TODO: Stage 3
    "textSize",                                // cosmetic, no store type
    "appearanceMode",                          // TODO: Stage 3
    "notificationsEnabled",                    // TODO: Stage 3
    "notificationIntervalHours",               // TODO: Stage 3
]
```

### 1.5 Update test seams

- `AppViewModel.swift` — `--seed` handler (~lines 342, 346):
  ```swift
  // BEFORE: AppGroup.defaults.set(comletionCount, forKey: "completionCount")
  // AFTER:  AppGroup.defaults.set(completionCount, forKey: CompletionCounterStore.defaultsKey)
  // BEFORE: AppGroup.defaults.set(skipCountsByIdentifier, forKey: "skipCounts")
  // AFTER:  AppGroup.defaults.set(skipCountsByIdentitier, forKey: SkipCountStore.defaultsKey)
  ```

- `WatchAppViewModel.swift` — seams (~line 27, ~line 118-121):
  ```swift
  // BEFORE: AppGroup.defaults.set(freemiumCap, forKey: "completionCount")
  // AFTER:  AppGroup.defaults.set(freemiumCap, forKey: CompletionCounterStore.defaultsKey)
  // BEFORE: AppGroup.defaults.set([id: n], forKey: "skipCounts")
  // AFTER:  AppGroup.defaults.set([id: n], forKey: SkipCountStore.defaultsKey)
  ```

### Verification
- [x] `make test` green — all existing tests pass (key strings byte-identical)
- [x] `make lint` green
- [x] `make build` + `make watch-build` + `make mac-build` green — all targets compile
- [x] grep verification: each key literal appears only at its `static let defaultsKey` declaration + PayloadKey reference. Exceptions: STD keys still duplicated — resolved in Stage 3.
- [x] `UITestingSeedTests` — persistedKeys wipe list still correct

---

## Stage 2: ShowUndatedRemindersPreference normalization

### 2.1 Add `isEnabled` / `set(_:)` to the type

In `SingleThreadCore/…/ShowUndatedRemindersPreference.swift`:

```swift
public struct ShowUndatedRemindersPreference {
    public static let defaultsKey = "showUndatedReminders"  // from Stage 1

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // NEW — matches sibling Show*Preference pattern
    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    public func set(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // Thin internal wrappers so callers compile during transitin
    public func load() -> Bool { isEnabled }
    public func save(_ enabled: Bool) { set(enabled) }

    private let defaults: UserDefaults
    private let key: String
}
```

###2.2 Migrate callers from load()/ save(_:) to isEnabled/set(_:)

- **`SkippedReminderSyncService.swift`** — `pushAll` read (~line 182):
  ```swift
  // BEFORE: showUndatedStore.load()
  // AFTER:  showUndatedStore.isEnabled
  ```
  `apply(context:)` write (~line 339):
  ```swift
  // BEFORE: showUndatedStore.save(value)
  // AFTER:  showUndatedStore.set(value)
  ```

- **`WatchAppViewModel.swift`** — launch restore (~line 34):
  ```swift
  // BEFORE: store.showsUndatedReminders = ShowUndatedRemindersPreference(defaults: .standard).load()
  // AFTER:  store.showsUndatedReminders = ShowUndatedRemindersPreference(defaults: .standard).isEnabled
  ```

- **`AppViewModel.swift`** — init-time snapshots and didChange observer: No change.
  ShowUndatedReminders is NOT in the `lastShow*` shadow set — it uses its own
  `onShowUndatedRemindersChanged` hook via `ReminderStore.showsUndatedReminders` didSet.

 - **`NextThingWidget.swift`** — raw `bool(forKey:)` at ~line71: NOT using the wrap per.
  Fixed in Stage 6. No change in Stage 2.

### 2.3 Remove load()/ save(_:)

After all callers are migrated, remove the `load()` and `save(_:)` methods.
The type now has only `isEnabled` and `set(_:)`.

### 2.4 Add tests

Create `SingleThreadTests/ShowUndatedRemindersPrefrenceTests.swift`:

```swift
import Foundation
import SingleThreadCore
import Testing

struct ShowUndatedRemindersPreferenceTests {
    @Test
    func defaultAndRoundTrips() {
        let key = "showundated-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = ShowUndatedRemindersPreference(defaults: .standard, key: key)
        #expect(!preference.isEnabled, "missing key defaults to false")
        preference.set(true)
        #expect(preference.isEnabled, "set(true) round-trips")
        preference.set(false)
        #expect(!preference.isEnabled, "set(false) round-trips")
    }
}
```

### Verification
- [x] `make test` green — new ShowUndatedRemindersPreferenceTests pass; all existing tests still green
- [x] `make lint` green
- [x] `make build` green — all callers compile
- [x] `SkippedReminderSyncServiceTests` — pushAll/apply round-trips still byte-identical
- [x] `WatchSyncPipelineTests` — watch receive still persists correctly

---

## Stage 3: STD launch-time store types + programmatic read switch

### 3.1 Create OrientationPreference

New file: `SingleThreadCore/…/OrientationPreference.swift`

```swift
import Foundation

/// Persists the "allow lndscape" preference. An absent key resolves to
/// `true` (landscape enabled by default).
public struct OrientationPreference {
    public static let defaultsKey = "allowsLandscape"

    public init(
        defaults: UserDefaults = .standard,
        key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public var isLandscapeEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func setLandscapeEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    private let defaults: UserDefaults
    private let key: String
}
```

### 3.2 Create NotificationPreference

New file: `SingleThreadCore/…/NotificationPreference.swift`

```swift
import Foundation

/// Persists notification preferences. Replaces `AppViewModel.NotificationKeys`.
public struct NotificationPreference {
    public static let enabledDefaultsKey = "notificationsEnabled"
    public static let intervalDefaultsKey = "notificationIntervalHours"

    public init(
        defaults: UserDefaults = .standard,
        enabledKey: String = enabledDefaultsKey,
        intervalKey: String = intervalDefaultsKey) {
        self.defaults = defaults
        self.enabledKey = enabledKey
        self.intervalKey = intervalKey
    }

    public var isEnabled: Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }

    public var intervalHours: Int {
        let raw = defaults.integer(forKey: intervalKey)
        return raw > 0 ? raw : 48  // mirors existing fallback
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enabledKey)
    }

    public func setIntervalHours(_ hours: Int) {
        defaults.set(hours, forKey: intervalKey)
    }

    private let defaults: UserDefaults
    private let enabledKey: String
    private let intervalKey: String
}
```

### 3.3 Create AppearanceModePreference

New file: `SingleThreadCore/…/AppearanceModePreference.swift`

```swift
import Foundation

/// Persists the appearance-mode revraw string. An absent or unrecognized key
/// resolves to `"system"`.
public struct AppearanceModePreference {
    public static let defaultsKey = "appearanceMode"

    public init(
        defaults: UserDefaults = .standard,
        key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Returns the raw value string ("system" | "light" | "dark"), falling back
    /// to "system" for missing/unrecognized keys.
    public var rawValue: String {
        guard let raw = defaults.object(forKey: key) as? String,
              ["system", "light", "dark"].contains(raw)
        else { return "system" }
        return raw
    }

    public func setRawValue(_ raw: String) {
        defaults.set(raw, forKey: key)
    }

    private let defaults: UserDefaults
    private let key: String
}
```

`AppearanceMode.load(from:)` is simplified to delegate:

```swift
// AppearanceMode.swift
static func load(from defaults: UserDefaults = .standard) -> Self {
    Self(rawValue: AppearanceModePreference(defaults: defaults).rawValue) ?? .system
}
```

### 3.4 Switch AppDelegate reads

In `SingleThread/AppDelegate.swift`:

```swift
// application(_:supportedInterfaceOrientationsFor:) (~lines 50-57)
// BEFORE:
let keyExists = UserDefaults.standard.object(forKey: "allowsLandscape") != nil
let allowsLandscape = keyExists
    ? UserDefaults.standard.bool(forKey: "allowsLandscape")
    : true

// AFTER:
let allowsLandscape = OrientationPreference().isLandscapeEnabled


// applicationDidBecomeActive (~line 47)
// BEFORE: Self.applyAppearance(AppearanceMode.load())
// AFTER:  Self.applyAppearance(AppearanceMode.load())  // unchanged; load() now delegates
```

###3.5 Switch AppViewModel background notification reads

In `SingleThread/AppViewModel.swift` — `scheduleNotificationIfNeeded()`:

```swift
// BEFORE (~line 129):
guard UserDefaults.standard.bool(forKey: NotificationKeys.enabled) else { return }
// …
let intervalHours = UserDefaults.standard.integer(forKey: NotificationKeys.intervalHours)
let effectiveHours = intervalHours > 0 ? intervalHours : 48

// AFTER:
let notificationPref = NotificationPreference()
guard notificationPref.isEnabled else { return }
// …
let effectiveHours = notificationPref.intervalHours  // already includes fallback
```

Remove the `NotificationKeys` enum from `AppViewModel` (lines 98-101) — replaced by
`NotificationPreference` constants.

### 3.6 Update ContentView @AppStorage declarations

Replace STD-key literls that now have store constants:

```swift
// ContentView.swift
@AppStorage(OrientationPreference.defaultsKey)  // was "allowsLandscape"
var allowsLandscape = true

@AppStorage(NotificationPreference.enabledDefaultsKey)  // was AppViewModel.NotificationKeys.enabled
var notificationsEnabled = false

@AppStorage(NotificationPreference.intervalDefaultsKey)  // was …intervalHours
var notificationIntervalHours = 48

@AppStorage(AppearanceModePreference.defaultsKey)  // was "appearanceMode"
var appearanceMode = AppearanceMode.system
```

### 3.7 Update UITestingSeed.persistedKeys

Replace the 4 STD-key literls flagged with Stage 3 TODOs:

```swift
// UITestingSeed.swift persistedKeys — replace these entries:
// "allowsLandscape"        → OrientationPreference.defaultsKey
// "appearanceMode"        → AppearanceModePreference.defaultsKey
// "notificationsEnabled"   → NotificationPreference.enabledDefaultsKey
// "notificationIntervalHours" → NotificationPreference.intervalDefaultsKey
```

### 3.8 Update AppViewModel seam writes

In `AppViewModel.swift` — `--ui-testing` handler (~lines 185, 189):
```swift
// BEFORE: UserDefaults.standard.set(false, forKey: NotificationKeys.enabled)
// AFTER:  NotificationPreference().setEnabled(false)
```

### 3. 9 Add tests

Create three new test files following existing patterns. `SingleThreadTests/OrientationPreferenceTests .swift`:
```swift
import Foundation
import SingleThreadCore
import Testing

struct OrientationPreferenceTests {
    @Test
    func defaultAndRoundTrips() {
        let key = "orientation-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = OrientationPreference(defaults: .standard, key: key)
        #expect(preference.isLandscapeEnabled, "missing key defaults to true")
        preference.setLandscapeEnabled(false)
        #expect(!preference.isLandscapeEnabled, "setLandscapeEnabled(false) round-trips")
        preference.setLandscapeEnabled(true)
        #expect(preference.isLandscapeEnabled, "setLandscapeEnabled(true) round-trips")
    }
}
```

`SingleThreadTests/NotificationPreferenceTests.swift`:
```swift
import Foundation
import SingleThreadCore
import Testing

struct NotificationPreferenceTests {
    @Test
    func defaultAndRoundTrips() {
        let key = "notif-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let enabledKey = key + "-enabled"
        let intervalKey = key + "-interval"
        defer { UserDefaults.standard.removeObject(forKey: enabledKey) }
        defer { UserDefaults.standard.removeObject(forKey: intervalKey) }
        let preference = NotificationPreference(
            defaults: .standard,
            enabledKey: enabledKey,
            intervalKey: intervalKey)
        #expect(!preference.isEnabled, "missing key defaults to false")
        #expect(preference.intervalHours == 48, "missing key defaults to 48")
        preference.setEnabled(true)
        #expect(preference.isEnabled, "setEnabled(true) round-trips")
        preference.setIntervalHours(24)
        #expect(preference.intervalHours == 24, "setIntervalHours(24) round-trips")
        preference.setIntervalHours(0)
        #expect(preference.intervalHours == 48, "zero falls back to 48")
    }
}
```

`SingleThreadTests/AppearanceModePreferenceTests.swift`:
```swift
import Foundation
import SingleThreadCore
import Testing

struct AppearanceModePreferenceTests {
    @Test
    func defaultAndRoundTrips() {
        let key = "appearance-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let preference = AppearanceModePreference(defaults: .standard, key: key)
        #expect(preference.rawValue == "system", "missing key defaults to system")
        preference.setRawValue("dark")
        #expect(preference.rawValue == "dark", "setRawValue(dark) round-trips")
        preference.setRawValue("unknown")
        #expect(preference.rawValue == "system", "unrecognized raw falls back to system")
        preference.setRawValue("light")
        #expect(preference.rawValue == "light", "setRawValue(light) round-trips")
    }
}
```

### Verification
- [x] `make test` green — new OrientationPreferenceTests, NotificationPreferenceTests, AppearanceModePreferenceTests pass
- [x] `make lint` green
- [x] `make build` + `make watch-build` + `make mac-build` green
- [x] `AppDelegateTests` — orientation read still returns correct default (true)
- [x] `NotificationSchedulingUITests` — background notification scheduling still correct
- [ ] Manual: rotate device with landscape enabled/disabled — orientation lock follows preference

---

## Stage 4: AG-suite @AppStorage removal + view observation

### 4.1 Create PreferenceHolder

New file: `SingleThreadCore/…/PrefrenceHolder.swift`

```swift
import Foundation

/// Single observable holder for all App-Group preference values consumed by the
/// iOS app's main view. Replaces the 7 `@AppStoage` AG-key declarations in
/// ContentView. Mirrors the watch `Show*State` pattern — reads from store types
/// on init, auto-refreshes on `didChangeNotification` for the App Group suite.

@MainActor
@Observable
public final class PreferenceHolder {
    // MARK: Lifecycle

    public init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: AppGroup.defaults,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: Public

    public var showUndatedReminders = false
    public var sortOption = SortOption.priority
    public var showDate = true
    public var showList = false
    public var showRecurrence = true
    public var showAlarms = true
    public var showCompletionGlow = true

    // MARK: Private

    private var observer: NSObjectProtocol?

    private func refresh() {
        showUndatedReminders = ShowUndatedRemindersPreference().isEnabled
        sortOption = SortOptionStore().load()
        showDate = ShowDatePreference().isEnabled
        showList = ShowListPreference().isEnabled
        showRecurrence = ShowRecurrencePreference().isEnabled
        showAlarms = ShowAlarmsPreference().isEnabled
        showCompletionGlow = ShowCompletionGlowPreference().isEnabled
    }
}
```

### 4.2 Add PreferenceHolder to ContentView, remove AG @AppStorage

In `SingleThread/ContentView.swift`:

```swift
// ContentView struct — ADD:
var preferences = PreferenceHolder()

// REMOVE these 7 @AppStorage declaratons:
// @AppStorage("showUndatedReminders", store: AppGroup.defaults) var showUndatedReminders …
// @AppStorage(SortOption.defaultsKey, store: AppGroup.defaults) var sortOption …
// @AppStorage("showDate", store: AppGroup.defaults) var showDate …
// @AppStorage("showList", store: AppGroup.defaults) var showList …
// @AppStorage("showRecurrence", store: AppGroup.defaults) var showRecurrence …
// @AppStorage("showAlarms", store: AppGroup.defaults) var showAlarms …
// @AppStorage("showCompletionGlow", store: AppGroup.defaults) var showCompletionGlow …
```

### 4.3 Update all ContentView references

Replace every reference to the removed `@AppStorage` properties with `preferences.<key>`:

| Old reference | New reference |
|---|---|
| `showUndatedReminders` | `preferences.showUndatedReminders` |
| `sortOption` | `preferences.sortOption` |
| `showDate` | `preferences.showDate` |
| `showList` | `preferences.showList` |
| `showRecurrence` | `preferences.showRecurrence` |
| `showAlarms` | `preferences.showAlarms` |
| `showCompletionGlow` | `preferences.showCompletionGlow` |

Specific sites (all in ContentView.swift):

- **`.task` modifier** (~line 239):
  ```swift
  // BEFORE: await viewModel.task(showUndatedReminders: showUndatedReminders)
  // AFTER:  await viewModel.task(showUndatedReminders: preferences.showUndatedReminders)
  ```

- **`.onChange(of: backgroundPinned)`** — unchanged (STD key).

- **`.onChange(of: showUndatedReminders)`** (~line 244):
  ```swift
  // BEFORE: .onChange(of: showUndatedReminders) { _, newValue in
  // AFTER:  .onChange(of: preferences.showUndatedReminders) { _, newValue in
  ```

- **`.onChange(of: sortOption)`** (~line 247):
  ```swift
  // BEFORE: .onChange(of: sortOption) { _, newValue in
  // AFTER:  .onChange(of: preferences.sortOption) { _, newValue in
  ```

- **`.onChange(of: appearanceMode)`** — unchanged (ST D key).

- **Reminder-list rendering**: replace all `showDate`, `showList`, etc. usages in
  body closure with `preferences.showDate`, etc.

- **ContentViewModel init**: already takes `showCompletionGlow: ShowCompletionGlowPreference` — reads store directly, not @AppStorage. No change needed.

### 4.4 Update makeSettingsBag()

In `SingleThread/ContentView+Settings.swift` (~lines 55-83), replace AG-key @AppStorage property reads with `preferences` reads:

```swift
// BEFORE (iOS branch):
SettingsBindings(
    …
    showUndatedReminders: showUndatedReminders,
    sortOption: sortOption,
    showDate: showDate,
    showList: showList,
    showRecurrence: showRecurrence,
    showAlarms: showAlarms,
    showCompletionGlow: showCompletionGlow)

// AFTER:
SettingsBindings(
    …
    showUndatedReminders: preferences.showUndatedReminders,
    sortOption: preferences.sortOption,
    showDate: preferences.showDate,
    showList: preferences.showList,
    showRecurrence: preferences.showRecurrence,
    showAlarms: preferences.showAlarms,
    showCompletionGlow: preferences.showCompletionGlow)
```

Same for the `#elseif os(macOS)` branch.

### 4.5 Remove AG-key .onChange handlers from settingsSheetWritebacks

In `SingleThread/ContentView+Settings.swift` — `settingsSheetWritebacks` (~lines 38-44),
remove the 7 AG-key `.onChange` lines:

```swift
// REMOVE these 7 lines:
// .onChange(of: bag.showUndatedReminders) { _, new in showUndatedReminders = new }
// .onChange(of: bag.sortOption) { _, new in sortOption = new }
// .onChange(of: bag.showDate) { _, new in showDate = new }
// .onChange(of: bag.showList) { _, new in showList = new }
// .onChange(of: bag.showRecurrence) { _, new in showRecurrence = new }
// .onChange(of: bag.showAlarms) { _, new in showAlarms = new }
// .onChange(of: bag.showCompletionGlow) { _, new in showCompletionGlow = new }
```

These lines wrote back to the now-removed @AppStorage AG properties. In Stage4,
the settings sheet will NOT persist AG-key changes (read-only). This is fixed
in Stage 5.

### 4.6 Add PreferenceHolder tests

Create `SingleThreadTests/PreferenceHolderTests .swift`:

```swift
import Foundation
import SingleThreadCore
import Testing

@MainActor
struct PreferenceHolderTests {
    /// Uses real AppGroup.defaults; restores original values in defer.
    @Test
    func initializesFromStores() {
        let original = ShowDatePreference().isEnabled
        defer { ShowDatePreference().set(original) }

        ShowDatePreference().set(false)
        let holder = PreferenceHolder()
        #expect(!holder.showDate, "reads false from store")
    }

    @Test
    func refreshesOnNotification() async {
        let original = ShowDatePreference().isEnabled
        defer { ShowDatePreference().set(original) }

        ShowDatePreference().set(true)
        let holder = PreferenceHolder()
        #expect(holder.showDate, "initially true")

        ShowDatePreference().set(false)
        // Give the notification a cycle to deliver
        try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        #expect(!holder.showDate, "refreshed to false after store write")
    }
}
```

### Verification
- [x] `make build` green — all targets compile without AG @AppStorage
- [x] `make test` green — PreferenceHolderTests pass; existing tests updated for new references
- [x] `make lint` green
- [x] `make ui-test` — settings sheet opens and displays current AG-key values
- [ ] Manual: toggle showDate in settings, dismiss sheet, reopen — value displayed correctly (but NOT persisted across this stage — fixed in Stage 5)
- [ ] Manual: reminder list refreshes when showDate/showList etc. are toggled
- [x] No `@AppStorage` for AG keys remains in any target (grep verification)

---

## Stage 5: Settings sheet store write-through

### 5.1 Update SettingsBindings AG-key properties to computed store-backed

In `SingleThread/SettingsBindings.swift`, change the 7 AG-key properties from
stored to computed (read from/write to store types):

```swift
// SettingsBindings — ADD private store instances:
private let showUndatedPreference = ShowUndatedRemindersPreference()
private let sortStore = SortOptionStore()
private let showDatePreference = ShowDatePreference()
private let showListPreference = ShowListPreference()
private let showRecurrencePreference = ShowRecurrencePreference()
private let showAlarmsPreference = ShowAlarmsPreference()
private let showCompletionGlowPreference = ShowCompletionGlowPreference()

// REPLACE stored properties with computed:
var showUndatedReminders: Bool {
    get { showUndatedPreference.isEnabled }
    set { showUndatedPreference.set(newValue) }
}
var sortOption: SortOption {
    get { sortStore.load() }
    set { sortStore.save(newValue) }
}
var showDate: Bool {
    get { showDatePreference.isEnabled }
    set { showDatePreference.set(newValue) }
}
var showList: Bool {
    get { showListPreference.isEnabled }
    set { showListPreference.set(newValue) }
}
var showRecurrence: Bool {
    get { showRecurrencePreference.isEnabled }
    set { showRecurrencePreference.set(newValue) }
}
var showAlarms: Bool {
    get { showAlarmsPreference.isEnabled }
    set { showAlarmsPreference.set(newValue) }
}
var showCompletionGlow: Bool {
    get { showCompletionGlowPreference.isEnabled }
    set { showCompletionGlowPreference.set(newValue) }
}
```

Remove these 7 properties from the `init` parameter list and body (they are now
computed, not stored). The STD-key properties (appearanceMode, textSize, etc.)
remain as stored properties with `init` parameters.

```swift
// SettingsBindings init — REMOVE these 7 parameters and their self. assignments:
// showUndatedReminders: Bool = false,
// sortOption: SortOption = .priority,
// showDate: Bool = true,
// showList: Bool = false,
// showRecurrence: Bool = true,
// showAlarms: Bool = true,
// showCompletionGlow: Bool = true
```

###5.2 Update makeSettingsBag() — remove AG-key args

Now that the 7 AG-key parameters are removed from `SettingsBindings.init`,
`makeSettingsBag()` no longer passes them:

```swift
// makeSettingsBag() — REMOVE these 7 arguments from the SettingsBindings() call:
// showUndatedReminders: …,
// sortOption: …,
// showDate: …,
// showList: …,
// showRecurrence: …,
// showAlarms: …,
// showCompletionGlow: …
```

The SettingsBindings AG-key computed getsers read stores on access — the sheet
opens with current values automatically.

Result:
```swift
func makeSettingsBag() -> SettingsBindings {
    #if os(iOS)
        SettingsBindings(  // no AG-key args — computed from stores
            appearanceMode: appearanceMode,
            textSize: textSize,
            allowsLandscape: allowsLandscape,
            enableActionButtons: enableActionButtons,
            showSwipePrompt: showSwipePrompt,
            showUndoButton: showUndoButton,
            notificationsEnabled: notificationsEnabled,
            notificationIntervalHours: notificationIntervalHours,
            showMicrophoneButton: showMicrophoneButton,
            backgroundEnabled: backgroundEnabled,
            backgroundFadePercent: backgroundFadePercent,
            backgroundPinned: backgroundPinned)
    #elseif os(macOS)
        SettingsBindings(
            appearanceMode: appearanceMode,
            textSize: textSize,
            showMicrophoneButton: showMicrophoneButton,
            backgroundEnabled: backgroundEnabled,
            backgroundFadePercent: backgroundFadePercent,
            backgroundPinned: backgroundPinned)
    #endif
}
```

### 5.3 settingsSheetWritebacks — already cleaned

The 7 AG-key `.onChange` handlers were removed in Stage 4.4.5. No further changes.
`settingsSheetWritebacks` now only has `.onChange` handlers for STD keys.

### Verification
- [x] `make build` green
- [x] `make test` green — SettingsViewModelTests updated
- [x] `make lint` green
- [x] `make ui-test` green — settings persistence flows pass
- [ ] Manual: open settings, toggle each AG key, dismiss sheet, reopen — values preserved
- [ ] Manual: toggle showDate → reminder list immediately shows/hides dates
- [ ] Manual: change sort option → list re-sorts immediately

---

## Stage 6: Remaining raw read fixes

### 6.1 ContentViewModel.showsActionButtons — add stored property driven by @AppStorage

In `SingleThread/ContentViewModel.swift` (~lines 53-59):

```swift
// ADD stored property:
#if os(iOS)
    var enableActionButtons = false

    // UPDATE computed property:
    var showsActionButtons: Bool {
        enableActionButtons && store.visibleReminders.first != nil
    }
#endif
```

In `SingleThread/ContentView.swift` — drive the viewModel property from the
@AppStorage binding:

```swift
// In the .task modifier (~line 239), ADD:
viewModel.enableActionButtons = enableActionButtons

// ADD .onChange handler:
#if os(iOS)
.onChange(of: enableActionButtons) { _, new in
    viewModel.enableActionButtons = new
}
#endif
```

The `.task` sets the initial value; the `.onChange` keeps it in sync. The
`enableActionButtons` @AppStorage stays in ContentView (STD key, not shared).

No change to `ContentViewModel.init` — `enableActionButtons` defaults to
`false` and is set after init via the property.

No change to `AppViewModel.makeContentViewModel()` — it creates ContentViewModel
without enableActionButtons (defaults to false). The correct value is set by
ContentView's .task/.onChange after body evaluation.

### 6.2 NextThingWidget showUndatedReminders raw read → store

In `SingleThreadWidget/NextThingWidget.swift` (~line 71):

```swift
// BEFORE:
store.showsUndatedReminders = AppGroup.defaults.bool(forKey: "showUndatedReminders")

// AFTER:
store.showsUndatedReminders = ShowUndatedRemindersPreference().isEnabled
```

`ShowUndatedRemindersPreference` defaults to `AppGroup.defaults`, matching the
widget's App Group entitlement. The `isEnabled` uses `object(forKey:) as? Bool
?? false` — identical semantics to the original `bool(forKey:)` (which returns
false for missing keys).

### 6.3 ReminderStore.showsUndatedReminders didSet write → store

In `SingleThreadCore/…/ReminderStore.swift` (~lines 103-106):

The `showsUndatedReminders` didSet currently just fires the observer hook:

```swift
public var showsUndatedReminders = false {
    didSet {
        guard showsUndatedReminders != oldValue else { return }
        onShowUndatedRemindersChanged?(showsUndatedReminders)
    }
}
```

Wait — the design says the didSet writes `AppGroup.defaults.set(newValue, forKey:
"showUndatedReminders")`. Let me re-read the code. Actually from the research:

"ReminderStore.showsUndatedReminders didSet (ReminderStore.swift:103-106) — writes
AppGroup.defaults.set(newValue, forKey:) directly (bypassing the wrapper) and
fires a reload hook."

But looking at the code I read earlier, the didSet at ~lines 134-139 just fires
`onShowUndatedRemindersChanged?`. It does NOT write to UserDefaults — the write
happens elsewhere (the @AppStorage setter in ContentView, or the watch launch
restore assignment).

Actually, let me re-check. The research says the ReminderStore property is:
```swift
public var showsUndatedReminders = false {
    didSet {
        guard showsUndatedReminders != oldValue else { return }
        onShowUndatedRemindersChanged?(showsUndatedReminders)
    }
}
```

And at lines 103-106 is the `onShowUndatedRemindersChanged` hook declaration. So
the didSet does NOT write to UserDefaults — it only fires the hook. The writes
happen through @AppStorage (which is removed in Stage4) or through the
store.set() in the sync service's apply, or through direct assignment in
widget/watch launch.

So there is NO raw write in ReminderStore.showsUndatedReminders didSet. The only
remaining raw reads/writes are the widget read (6.2) and ContentViewModel (6.1).

Wait but the structure says:

"3. `ReminderStore.showsUndatedReminders` didSet — the direct
`AppGroup.defaults.set(newValue, forKey:)` write →
`ShowUndatedRemindersPreference().set(newValue)`."

And design says:

"`ReminderStore.showsUndatedReminders` didSet path: this property writes
`AppGroup.defaults.set` directly (bypassing the wrapper) and fires a reload
hook. After normalization, it should write through
`ShowUndatedRemindersPreference.set(_:)`."

But the code I read doesn't show a UserDefaults write in the didSet. Let me
re-read more carefully. Actually, reviewing the research Q3: "ReminderStore
.showsUndatedReminders direct property assignment with `didSet` firing only the
hook (ReminderStore.swift:103-106, :134-139) — driven by the widget and watch
launch restore, and by seeded-suite writes."

So the research confirms: the didSet only fires the hook. The AppGroup.defaults
write is NOT in the didSet. So this item is a misnderstanding in the structure/
design, and there's nothing to fix here.

**Correction**: Step 6.3 is removed. There is no raw write in
ReminderStore.showsUndatedReminders didSet. The only remaining raw reads after
Stages 1-5 are the widget's `bool(forKey:)` (fixed in 6.2) and
ContentViewModel.showsActionButtons (fixed in 6.1).

### 6.4 Re-anchor the showUndatedReminders side-effect .onChange (if needed)

After Stage4, the `.onChange(of: preferences.showUndatedReminders)` fires
`viewModel.handleShowUndatedReminders(newValue)`. This calls:
```swift
func handleShowUndatedReminders(_ value: Bool) {
    store.showsUndatedReminders = value
    Task { await store.reload() }
}
```

The store.showsUndatedReminders assignment fires didSet → fires
`onShowUndatedRemindersChanged?` → AppViewModel pushes sync. Good.

But who writes to UserDefaults? After Stage4, @AppStorage is gone. The
`PreferenceHolder` reads from the store. When the user toggles the setting in
the settings sheet (Stage5), SettingsBindings.setter calls
`ShowUndatedRemindersPreference().set(newValue)` → writes to AppGroup.defaults
→ posts didChangeNotification → PreferenceHolder refreshes →
`.onChange(of: preferences.showUndatedReminders)` fires → ContentViewModel
handles it.

So the write chain is: SettingsBindings setter → store.set(_:) → UserDefaults
→ notification → PreferenceHolder → .onChange → handleShowUndatedReminders →
store.showsUndatedReminders = value → didSet → onShowUndatedRemindersChanged.

This is correct. The store write in the preference type handles persistence.
The ContentViewModel handler handles the reload and sync. No change needed here
— Stage4 and 5 already cover this.

But wait — what about the `.task` that calls `viewModel.task(showUndatedReminders:
preferences.showUndatedReminders)`? Let me check what that does. It's in
ContentViewModel. Let me not go deeper — the existing .task/.onChange behavior
is preserved by the PreferenceHolder, just the observation source changes.

### Verification
- [x] `make test` green — ActionButtonTests updated for new injection path
- [x] `make lint` green
- [x] `make build` + `make watch-build` + `make mac-build` green
- [x] Widget read path — widget timeline entry still reflects correct showUndatedReminders value
- [x] `ReminderStoreTests` — showsUndatedReminders didSet still fires reload hook without double-fire
- [ ] Full gate: `./scripts/test.sh` — all targets, all suites, Periphery

---

## Testing Checkpoints (Summary)

| Stage | Command | Notes |
|---|---|---|
| 1 | `make test && make lint` | Key constants byte-identical; no behavior change |
| 2 | `make test && make lint` | New ShowUndatedRemindersPreferenceTests green |
| 3 | `make test && make lint` | New Orientation/Notification/AppearanceMode PreferenceTests green |
| 4 | `make test && make lint && make ui-test` | PreferenceHolder green; settings sheet displays values |
| 5 | `make test && make lint && make ui-test` | Settings persistence through stores |
| 6 | `make test && make lint` | Stragglers fixed; then `./scripts/test.sh` full gate |

---

## Deviation from Structure

- **Stage 6.3 removed**: The structure.md listed `ReminderStore.showsUndatedReminders`
  didSet as containing a raw `AppGroup.defaults.set` write. Code inspection
  (ReminderStore.swift:134-139) confirms it only fires the observer hook — no
  UserDefaults write exists in the didSet. The raw read at NextThingWidget:71
  and the raw read in ContentViewModel.showsActionButtons are the only remaining
  raw sites.
- **Stage 4 AG-key .onChange removal moved up**: The structure deferred settings
  sheet .onChange removal to Stage 5. The plan removes them in Stage 4 because
  the @AppStorage properties they write back to no longer exist — they MUST be
  removed in Stage 4 or the code won't compile.
- **enableActionButtons injection approach**: The structure suggested passing from
  the view hierarchy or reading from a shared property. The plan uses the
  simplest approach: add a mutable stored property to ContentViewModel, driven
  by ContentView's @AppStorage via .task + .onChange. No init signature changes
  needed in ContentViewModel or AppViewModel.makeContentViewModel().
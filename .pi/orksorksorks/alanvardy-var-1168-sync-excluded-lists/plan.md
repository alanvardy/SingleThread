# Implementation Plan — iCloud sync for excluded lists (VAR-1168)

## Overview
Add an additive iCloud channel beside App Group + WatchConnectivity: a
`UbiquitousKeyValueStoring` seam over `NSUbiquitousKeyValueStore` wrapped by an
`ExcludedListCloudStore` injected into `ReminderStore`. Local edits write KVS;
external KVS changes apply into the App Group store (local truth) and re-push over
WC. Last-writer-wins whole-set replace; best-effort and silent when unavailable.

## Conventions that apply to every phase
- Shell is **fish**: compound commands go through `bash -c '…'` or `/tmp/x.sh`.
- Unit-test **names must not start with `test`**; UI-test (XCTest) names keep `test…`.
- New `.swift` files need **no pbxproj edit** (synchronized file groups). No new test
  target, no `Makefile`/`scripts/test.sh` change: the gate already runs
  `-only-testing:SingleThreadTests`, so new suites are picked up automatically.
- Never touch `AppGroup.defaults` fallbacks; the cloud store uses the KVS singleton
  (`NSUbiquitousKeyValueStore.default`), so no caching invariant applies.
- SwiftLint `--strict` (warnings are errors), SwiftFormat `organizeDeclarations`
  (MARK order: Lifecycle → Public → Private), identifiers ≥ 3 chars.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` — no new warnings, no `@unchecked Sendable`.

### Deviation from `structure.md` (agreed with the user)
`structure.md` said "add the KVS key to `AppGroup.entitlements` (iphoneos/iphonesimulator),
widget gets no entitlement". The widget target uses `AppGroup.entitlements`
unconditionally (`pbxproj:1019,1050`), so those two statements conflict. Per the
chosen **Option A**, the iOS *app* gets its own `SingleThread/App.entitlements`
and `AppGroup.entitlements` is **not modified** — the widget's App ID provisioning
is untouched. macOS keeps using `SingleThread.entitlements`, which gains the key.

### Deviation from `structure.md` #2 (implementation detail)
`structure.md` implied the startup seed could use `store.excludedListTitles`. It
cannot: `ReminderStore` does not load the store in `init` (only `reload()` →
`reconcileSkipState()` does, `ReminderStore.swift:751-766`), so at
`AppViewModel.init` time the mirror is `[]` even when the App Group has values.
The seed/adopt source is therefore `ExcludedListStore().load()`.

### Deviation from `structure.md` #3 (testability)
The echo-suppression guard lives in `AppViewModel` (a `let`-constructed
dependency). To keep it unit-testable it is a pure static helper,
`ExcludedListCloudStore.titlesToAdopt(cloud:local:)`, and `AppViewModel` gains an
optional injected `cloudStore:` init parameter (mirroring the existing `session:`
seam, `AppViewModel.swift:23-25`).

---

## Phase 1: Walking skeleton — exclude locally, persist to iCloud, rehydrate at launch
A user excludes a list; the value is written through the real KVS seam and a fresh
launch rehydrates local state from iCloud into the App Group store (seeding
App Group → KVS once when the key was never written).

### Changes

#### 1. Ubiquity transport seam
**File**: `SingleThreadCore/Sources/SingleThreadCore/UbiquitousKeyValueStoring.swift`
**Action**: create

```swift
import Foundation

/// Minimal seam over `NSUbiquitousKeyValueStore` so tests never touch the real
/// iCloud key-value store. Modelled on `SkipSyncSession`
/// (`SkippedReminderSyncService.swift:18-34`).
public protocol UbiquitousKeyValueStoring: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func synchronize() -> Bool
}

/// Free conformance: the three selectors match the framework's own signatures.
extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStoring {}
```

#### 2. Cloud store
**File**: `SingleThreadCore/Sources/SingleThreadCore/ExcludedListCloudStore.swift`
**Action**: create

```swift
import Foundation
import os

/// Persists the excluded-list titles in the iCloud key-value store.
///
/// Mirrors `ExcludedListStore` (whole-array replace) but is a *transport*: the
/// App Group store remains the local truth. `nil` from ``load()`` means the key
/// was never written (seed it once from the App Group); `[]` means an
/// intentional clear and must be adopted, never reseeded.
public struct ExcludedListCloudStore {
    // MARK: Lifecycle

    public init(
        store: any UbiquitousKeyValueStoring = NSUbiquitousKeyValueStore.default,
        key: String = defaultsKey) {
        self.store = store
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by the cloud store and the App Group store — the
    /// same text as `ExcludedListStore.defaultsKey` on purpose.
    public static let defaultsKey = "excludedListTitles"

    /// The stored titles, or `nil` when the key has never been written.
    public func load() -> [String]? {
        guard let value = store.object(forKey: key) else { return nil }
        guard let titles = value as? [String] else {
            Self.logger.debug("Unexpected iCloud payload type; treating as absent")
            return nil
        }
        return titles
    }

    /// Whole-set replace. Best effort: a signed-out/restricted device keeps the
    /// value locally in KVS memory and never propagates it — the App Group and
    /// WatchConnectivity paths are unaffected.
    public func save(_ titles: [String]) {
        store.set(titles, forKey: key)
        if !store.synchronize() {
            Self.logger.debug("iCloud key-value store unavailable; excluded lists stay local")
        }
    }

    /// Writes `titles` only when the key was never written. Returns whether a
    /// write happened (`false` for both "already present" and "clear present").
    @discardableResult
    public func seedIfAbsent(from titles: [String]) -> Bool {
        guard load() == nil else { return false }
        save(titles)
        return true
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: "app.alanvardy.SingleThread",
        category: "ExcludedListCloudStore")

    private let store: any UbiquitousKeyValueStoring
    private let key: String
}
```

#### 3. `ReminderStore` injection + local write-through
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

- Init: add `cloudStore: ExcludedListCloudStore? = nil` immediately after
  `excludeStore:` (`:28`) and assign it (`:44` area).
- Add `private let cloudStore: ExcludedListCloudStore?` next to `excludeStore`
  (`:631`).

```swift
    public init(
        eventStore: any EventKitStoring = EKEventStore(),
        skipStore: SkippedReminderStore = SkippedReminderStore(),
        skipCountStore: SkipCountStore = SkipCountStore(),
        pendingCompletionStore: PendingCompletionStore = PendingCompletionStore(),
        excludeStore: ExcludedListStore = ExcludedListStore(),
        cloudStore: ExcludedListCloudStore? = nil,
        loadsReminders: Bool = true,
        …) {
        …
        self.excludeStore = excludeStore
        self.cloudStore = cloudStore
        …
    }
```

`setExcludedListTitles` (`:577-585`) gains one line after `excludeStore.save`:

```swift
    public func setExcludedListTitles(_ titles: Set<String>) {
        excludedListTitles = titles
        let array = Array(titles)
        excludeStore.save(array)
        cloudStore?.save(array)
        onExcludedListsChanged?(array)
        onRemindersChanged?()
    }
```

All other `ReminderStore(...)` call sites (widget `NextThingWidget.swift:57`,
previews, watch, tests) keep compiling via the `nil` default — the widget and
watch deliberately get no cloud store.

#### 4. Startup reconcile + production wiring
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

a) Init signature (`:22-27`) gains `cloudStore:` after `session:`:

```swift
    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        session: (any SkipSyncSession)? = nil,
        cloudStore: ExcludedListCloudStore? = nil,
        ranker: any AIReminderRanking = FoundationModelsReminderRanker(),
        aiRankingDebounce: Duration = .milliseconds(500)) {
        let (store, usesInMemory) = Self.makeStore(arguments: arguments)
        self.store = store
        usesInMemoryStore = usesInMemory
        self.cloudStore = cloudStore
            ?? Self.makeCloudStore(arguments: arguments, usesInMemory: usesInMemory)
        …
```

b) New stored property beside `let backgroundImage` (`:66`):

```swift
    private let cloudStore: ExcludedListCloudStore?
```

c) Gate the real KVS out of the UI-test seams (`--ui-testing` builds an
in-memory EventKit store but leaves `usesInMemoryStore == false`, see
`AppViewModelSyncWiringTests`), and add the helper next to `showPreferenceStore`:

```swift
    /// Production iCloud wiring is skipped for every UI-test seam so a test run
    /// can never write to the developer's real iCloud key-value store.
    private static func makeCloudStore(
        arguments: [String],
        usesInMemory: Bool) -> ExcludedListCloudStore? {
        guard !usesInMemory,
              !arguments.contains("--ui-testing"),
              !arguments.contains("--seed") else { return nil }
        return ExcludedListCloudStore()
    }
```

d) Production `ReminderStore` gets the store — the production branch at `:323` is
only reached when neither `--ui-testing` nor `--seed` matched, so the same gate
holds:

```swift
        return (ReminderStore(loadsReminders: loads, cloudStore: ExcludedListCloudStore()), false)
```

e) Call the reconcile from the `#if os(iOS) || os(macOS)` block, **after**
`store.onRemindersChanged` is assigned so an adopted value also refreshes the
widget/AI path:

```swift
        #if os(iOS) || os(macOS)
            store.onRemindersChanged = { … }
            …
            setupExcludedListCloudSync()
        #endif
```

f) New private method + stored observer token (Phase 2 adds the observer; Phase 1
ships seed + one-shot adopt):

```swift
    private func setupExcludedListCloudSync() {
        guard let cloudStore else { return }
        // The mirror is empty until `reload()` runs, so the App Group store — not
        // `store.excludedListTitles` — is the seed/adopt source.
        let localTitles = ExcludedListStore().load()
        cloudStore.seedIfAbsent(from: localTitles)
        adoptCloudExcludedListTitlesIfNeeded(localTitles: localTitles)
    }

    /// Applies the iCloud value into the local truth when it is present and
    /// differs from what is already local.
    private func adoptCloudExcludedListTitlesIfNeeded(localTitles: [String]? = nil) {
        guard let cloudStore else { return }
        let local = Set(localTitles ?? ExcludedListStore().load())
        guard let adopted = ExcludedListCloudStore.titlesToAdopt(
            cloud: cloudStore.load(), local: local) else { return }
        store.applyCloudExcludedListTitles(adopted)
    }
```

`titlesToAdopt` is added to `ExcludedListCloudStore` (Phase 1, used by Phase 2):

```swift
    /// The set to adopt, or `nil` when the cloud value is absent or already
    /// equals the local set (echo suppression — a local write never loops back).
    public static func titlesToAdopt(cloud: [String]?, local: Set<String>) -> Set<String>? {
        guard let cloud else { return nil }
        let cloudSet = Set(cloud)
        return cloudSet == local ? nil : cloudSet
    }
```

`applyCloudExcludedListTitles` is added in Phase 2; for Phase 1 the plan is
sequenced so the skeleton and that method land together — **Phase 1 adds
`applyCloudExcludedListTitles` as the minimal apply (assign + `excludeStore.save`
+ fire both hooks, no KVS write)**, and Phase 2 adds the observer plus its tests.
This keeps each commit compiling.

#### 5. Entitlements (smallest enabling change)
**Files**: `SingleThread/App.entitlements` (create), `SingleThread/SingleThread.entitlements`
(modify), `SingleThread.xcodeproj/project.pbxproj` (modify — 4 build settings)

Create `SingleThread/App.entitlements` (a copy of `AppGroup.entitlements` plus the
KVS key, used by the iOS app only):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.ubiquity-kvstore-identifier</key>
	<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.app.alanvardy.SingleThread</string>
	</array>
</dict>
</plist>
```

`SingleThread/SingleThread.entitlements` (macOS) — insert after
`com.apple.developer.in-app-purchases`, keeping the file alphabetically ordered:

```xml
	<key>com.apple.developer.ubiquity-kvstore-identifier</key>
	<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
```

`project.pbxproj` — point the app target's two iOS entries at the new file
(Debug `:757-758`, Release `:808-809`). Leave `[sdk=macosx*]` and both widget
entries (`:1019`, `:1050`) untouched:

```
"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]" = SingleThread/App.entitlements;
"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]" = SingleThread/App.entitlements;
```

No `PBXFileReference` is needed (the file is referenced by build-setting path
only), and `verify_deployment_target()` counts deployment-target literals, which
do not change.

#### 6. Test fixture
**File**: `SingleThreadTests/TestFixtures.swift`
**Action**: modify (append a new section, outside any `#if` — Foundation only)

```swift
// MARK: - Fake ubiquitous key-value store

/// In-memory `UbiquitousKeyValueStoring` so no test touches the real iCloud
/// key-value store. `isAvailable == false` models a signed-out / restricted
/// device: writes are ignored and reads report the key as absent.
final class InMemoryUbiquitousStore: UbiquitousKeyValueStoring {
    private(set) var values: [String: Any] = [:]
    private(set) var synchronizeCount = 0
    var isAvailable = true

    func object(forKey key: String) -> Any? {
        isAvailable ? values[key] : nil
    }

    func set(_ value: Any?, forKey key: String) {
        guard isAvailable else { return }
        values[key] = value
    }

    func synchronize() -> Bool {
        synchronizeCount += 1
        return isAvailable
    }
}
```

#### 7. Cloud store tests
**File**: `SingleThreadTests/ExcludedListCloudStoreTests.swift`
**Action**: create

```swift
import Foundation
import SingleThreadCore
import Testing

@Suite
struct ExcludedListCloudStoreTests {
    private static let key = "test-excluded-cloud"

    private func makeStore(
        _ backing: InMemoryUbiquitousStore = InMemoryUbiquitousStore()
    ) -> ExcludedListCloudStore {
        ExcludedListCloudStore(store: backing, key: Self.key)
    }

    @Test
    func loadReturnsNilWhenUnwritten() {
        #expect(makeStore().load() == nil)
    }

    @Test
    func saveThenLoadRoundTrips() {
        let store = makeStore()
        store.save(["Work", "Personal"])
        #expect(store.load() == ["Work", "Personal"])
    }

    @Test
    func seedWritesOnlyWhenAbsent() {
        let backing = InMemoryUbiquitousStore()
        let store = makeStore(backing)

        #expect(store.seedIfAbsent(from: ["Work"]))
        #expect(store.load() == ["Work"])
        #expect(!store.seedIfAbsent(from: ["Personal"]))
        #expect(store.load() == ["Work"])
        #expect(backing.values.count == 1)
    }
}
```

#### 8. `ReminderStore` write-through test
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify — add after `setExcludedListTitlesPersistsAndFiresHooks`
(`:146-161`)

```swift
    @Test
    func setExcludedListTitlesWritesCloudStore() {
        let excludeStore = ExcludedListStore(defaults: .standard, key: "test-excluded-\(UUID().uuidString)")
        let backing = InMemoryUbiquitousStore()
        let cloudKey = "test-cloud-\(UUID().uuidString)"
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            excludeStore: excludeStore,
            cloudStore: ExcludedListCloudStore(store: backing, key: cloudKey),
            loadsReminders: false)

        store.setExcludedListTitles(["Work"])

        #expect(backing.values[cloudKey] as? [String] == ["Work"])
    }
```

### Verification

#### Automated
- [x] `make format`
- [x] `make lint`
- [x] `scripts/test-one.sh SingleThreadTests/ExcludedListCloudStoreTests`
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreTests`
- [x] `make build`
- [x] `plutil -lint SingleThread/App.entitlements SingleThread/SingleThread.entitlements`

#### Manual
- [ ] Archive the iOS app for a real device (`xcodebuild -scheme SingleThread -destination 'generic/platform=iOS' archive`) — signing must accept `com.apple.developer.ubiquity-kvstore-identifier`. If it fails with a provisioning error, enable iCloud → iCloud Documents/Key-value storage on the App ID `app.alanvardy.SingleThread` in the developer portal (design's provisioning open risk) before continuing.
- [ ] `make mac-build` succeeds with the macOS entitlement.
- [ ] Simulator launch with `--seed '{"reminders":[]}'` does **not** prompt or write iCloud (cloud store is nil under the seed seam).

---

## Phase 2: Live propagation — a change on another device lands without a relaunch
A KVS change pushed by another device updates the in-memory mirror, persists to the
App Group (so the widget sees it) and re-pushes over WatchConnectivity; a local
write never loops back into KVS.

### Changes

#### 1. Remote apply entry point
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify — add beside `refreshExcludedListTitles` (`:586-594`)

```swift
    /// Applies excluded-list titles that arrived from iCloud. Persists to the
    /// App Group (so the widget and a paired watch see it) and fires
    /// `onExcludedListsChanged` so the WatchConnectivity push re-sends — but
    /// NEVER writes back to the key-value store, which would loop the value
    /// around the iCloud channel. Distinct from `refreshExcludedListTitles`,
    /// the WatchConnectivity receive path, which must not re-push.
    public func applyCloudExcludedListTitles(_ titles: Set<String>) {
        excludedListTitles = titles
        let array = Array(titles)
        excludeStore.save(array)
        onExcludedListsChanged?(array)
        onRemindersChanged?()
    }
```

#### 2. External-change observer
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify — extend `setupExcludedListCloudSync()` (Phase 1f)

Add a stored token beside `aiRulesObserver` (`:234`):

```swift
    private var cloudExcludedListObserver: NSObjectProtocol?
```

and register after the seed/adopt in `setupExcludedListCloudSync`:

```swift
        // `object: nil`: the fake seam has no notification of its own, and
        // `didChangeExternallyNotification` is only ever posted by the KVS.
        // Loop protection is the value comparison in `titlesToAdopt`.
        cloudExcludedListObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                Task { @MainActor in self?.adoptCloudExcludedListTitlesIfNeeded() }
            }
```

(No `removeObserver` needed — same lifetime convention as `syncDefaultsObserver`
and `aiRulesObserver`, which rely on the token being deallocated with the VM.)

### Tests

**File**: `SingleThreadTests/ExcludedListCloudSyncTests.swift` — create

```swift
import Foundation
import SingleThreadCore
import Testing

/// The iCloud apply path: persist to the App Group, fire the WatchConnectivity
/// push hook, and never echo back into the key-value store.
@Suite
struct ExcludedListCloudSyncTests {
    @Test
    func applyCloudExcludedListTitlesPersistsAppGroupAndFiresHook() {
        let excludeStore = ExcludedListStore(defaults: .standard, key: "test-excluded-\(UUID().uuidString)")
        let backing = InMemoryUbiquitousStore()
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            excludeStore: excludeStore,
            cloudStore: ExcludedListCloudStore(store: backing, key: "test-cloud-\(UUID().uuidString)"),
            loadsReminders: false)
        var changedTitles: [String]?
        var pushCount = 0
        var remindersChanged = false
        store.onExcludedListsChanged = { changedTitles = $0; pushCount += 1 }
        store.onRemindersChanged = { remindersChanged = true }

        store.applyCloudExcludedListTitles(["Work", "Personal"])

        #expect(store.excludedListTitles == ["Work", "Personal"])
        #expect(Set(excludeStore.load()) == ["Work", "Personal"])
        #expect(Set(changedTitles ?? []) == ["Work", "Personal"])
        #expect(pushCount == 1)
        #expect(remindersChanged)
        #expect(backing.values.isEmpty)
    }

    @Test
    func applyCloudExcludedListTitlesNeverWritesCloudStore() {
        let backing = InMemoryUbiquitousStore()
        let cloudKey = "test-cloud-\(UUID().uuidString)"
        let cloudStore = ExcludedListCloudStore(store: backing, key: cloudKey)
        cloudStore.save(["Work"])
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            excludeStore: ExcludedListStore(defaults: .standard, key: "test-excluded-\(UUID().uuidString)"),
            cloudStore: cloudStore,
            loadsReminders: false)

        store.applyCloudExcludedListTitles(["Personal"])

        #expect(store.excludedListTitles == ["Personal"])
        #expect(cloudStore.load() == ["Work"])
    }

    @Test
    func identicalCloudValueIsIgnored() {
        #expect(ExcludedListCloudStore.titlesToAdopt(cloud: ["Work"], local: ["Work"]) == nil)
        #expect(ExcludedListCloudStore.titlesToAdopt(cloud: nil, local: ["Work"]) == nil)
        #expect(ExcludedListCloudStore.titlesToAdopt(cloud: ["Work", "Home"], local: ["Work"]) == ["Work", "Home"])
        #expect(ExcludedListCloudStore.titlesToAdopt(cloud: [], local: ["Work"]) == [])
    }
}
```

#### AppViewModel wiring test
**File**: `SingleThreadTests/ExcludedListCloudSyncTests.swift`
**Action**: modify — append, gated `#if os(iOS) || os(macOS)` (needs `@testable import SingleThread`)

```swift
#if os(iOS) || os(macOS)
    import SingleThread

    /// Serialized: `--ui-testing` builds an App-Group-backed store, so the
    /// excluded-list key is written on the real suite and must be cleaned up.
    @MainActor
    @Suite(.serialized)
    struct ExcludedListCloudObserverWiringTests {
        @Test
        func externalCloudChangeAdoptsIntoStoreAndAppGroup() {
            let appGroupKey = ExcludedListStore.defaultsKey
            AppGroup.defaults.removeObject(forKey: appGroupKey)
            defer { AppGroup.defaults.removeObject(forKey: appGroupKey) }
            let backing = InMemoryUbiquitousStore()
            let cloudStore = ExcludedListCloudStore(
                store: backing,
                key: ExcludedListCloudStore.defaultsKey)
            let appViewModel = AppViewModel(
                arguments: ["--ui-testing", "--ui-testing-noop-settle"],
                cloudStore: cloudStore)
            let store = appViewModel.store

            // Another device pushes a new set, then iCloud posts the change.
            cloudStore.save(["Work"])
            NotificationCenter.default.post(
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: nil)

            #expect(store.excludedListTitles == ["Work"])
            #expect(Set(ExcludedListStore().load()) == ["Work"])
        }
    }
#endif
```

Note: the observer hops through `Task { @MainActor in … }`; if the assertion races,
`await` a short bounded pump like `AppViewModelSyncWiringTests`
(`for _ in 0 ..< 20 where store.excludedListTitles.isEmpty { try await Task.sleep(for: .milliseconds(20)) }`)
rather than an unbounded sleep.

### Verification

#### Automated
- [x] `make format`
- [x] `make lint`
- [x] `scripts/test-one.sh SingleThreadTests/ExcludedListCloudSyncTests`
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreTests`
- [x] `scripts/test-one.sh SingleThreadTests/AppViewModelSyncWiringTests` (still green)
- [x] `make build`

#### Manual
- [ ] Two simulators signed into the same (or no) iCloud account: an exclusion toggle in Settings → Excluded Lists reaches the App Group key (`xcrun simctl spawn booted defaults read group.app.alanvardy.SingleThread excludedListTitles` inside the app container path) and the widget timeline reloads.
- [ ] Watch simulator paired to the phone still receives the exclusion (WC path unchanged).

---

## Phase 3: Clear & precedence — removing the last exclusion propagates; absent ≠ empty

### Changes

#### 1. Guarantee the `nil` vs `[]` contract
**File**: `SingleThreadCore/Sources/SingleThreadCore/ExcludedListCloudStore.swift`
**Action**: modify — documentation + explicit contract only, no behaviour change
(the Phase 1 implementation already writes `[]` via `set(_:forKey:)` and never
uses `removeObject(forKey:)`)

```swift
    /// Whole-set replace — last writer wins. An empty array is written verbatim
    /// (never `removeObject`, which would resurrect the "never written" seed
    /// path); clearing is a real value that propagates.
    public func save(_ titles: [String]) { … }

    /// Writes `titles` only when the key was never written (`nil`). A stored
    /// empty array (`[]`, an intentional clear) is NOT reseeded.
    @discardableResult
    public func seedIfAbsent(from titles: [String]) -> Bool { … }
```

#### 2. Clear path through both mutation entry points
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: verify only — `setExcludedListTitles([])` already writes `[]` to both
stores (Phase 1) and `applyCloudExcludedListTitles([])` already clears the App
Group and re-pushes (Phase 2). Add a doc line to `setExcludedListTitles` noting
the empty set is a propagating clear:

```swift
    /// Replaces the excluded-list title set, persisting immediately and firing
    /// both `onExcludedListsChanged` and `onRemindersChanged`. An empty set is an
    /// intentional clear: it is written as `[]` to the App Group and iCloud.
```

**File**: `SingleThread/AppViewModel.swift` — no change; `titlesToAdopt` already
adopts `[]` over a non-empty local set (Phase 2 test `identicalCloudValueIsIgnored`
covers it).

### Tests
**File**: `SingleThreadTests/ExcludedListCloudStoreTests.swift` / `ExcludedListCloudSyncTests.swift`
**Action**: modify — append

```swift
    @Test
    func emptyClearIsAdoptedNotReseeded() {
        let store = makeStore()
        store.save([])
        #expect(store.load() == [])
        #expect(!store.seedIfAbsent(from: ["Work"]))
        #expect(store.load() == [])
    }

    @Test
    func absentKeyDoesNotClearLocalSet() {
        let excludeStore = ExcludedListStore(defaults: .standard, key: "test-excluded-\(UUID().uuidString)")
        excludeStore.save(["Work"])
        let cloudStore = ExcludedListCloudStore(
            store: InMemoryUbiquitousStore(),
            key: "test-cloud-\(UUID().uuidString)")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            excludeStore: excludeStore,
            cloudStore: cloudStore,
            loadsReminders: false,
            excludedListTitles: ["Work"])

        let adopted = ExcludedListCloudStore.titlesToAdopt(
            cloud: cloudStore.load(), local: Set(excludeStore.load()))

        #expect(adopted == nil)
        #expect(store.excludedListTitles == ["Work"])
        #expect(Set(excludeStore.load()) == ["Work"])
        #expect(cloudStore.seedIfAbsent(from: ["Work"]) == true)
        #expect(cloudStore.load() == ["Work"])
    }

    @Test
    func clearPropagatesToCloudAndWC() {
        let backing = InMemoryUbiquitousStore()
        let cloudStore = ExcludedListCloudStore(store: backing, key: "test-cloud-\(UUID().uuidString)")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            excludeStore: ExcludedListStore(defaults: .standard, key: "test-excluded-\(UUID().uuidString)"),
            cloudStore: cloudStore,
            loadsReminders: false)
        var pushed: [String]?
        store.onExcludedListsChanged = { pushed = $0 }

        store.setExcludedListTitles(["Work"])
        store.setExcludedListTitles([])

        #expect(store.excludedListTitles.isEmpty)
        #expect(cloudStore.load() == [])
        #expect(pushed == [])
    }

    @Test
    func lastWriterWinsReplaceNotUnion() {
        let store = makeStore()
        store.save(["Work"])
        store.save(["Personal"])
        #expect(store.load() == ["Personal"])
    }
```

### Verification

#### Automated
- [x] `make format`
- [x] `make lint`
- [x] `scripts/test-one.sh SingleThreadTests/ExcludedListCloudStoreTests`
- [x] `scripts/test-one.sh SingleThreadTests/ExcludedListCloudSyncTests`
- [x] `make build`

#### Manual
- [ ] Manual two-device check (same iCloud account): exclude a list on device A → it disappears on device B (foreground both after the change; KVS propagation is near-real-time but not instantaneous). Then clear all exclusions on device A → the list reappears on device B. If the clear does not propagate, treat the absent-vs-empty assumption as failed (design open risk) and stop.

---

## Phase 4: Hardening — degraded mode, macOS parity, clean gate

### Changes

#### 1. Degraded mode logging (confirmation only)
**File**: `SingleThreadCore/Sources/SingleThreadCore/ExcludedListCloudStore.swift`
**Action**: verify — `save` already logs on `synchronize() == false` and `load`
returns `nil` when the store reports nothing. No retry, no status UI (explicit
non-goals). Add one doc comment to the type:

```swift
/// Best effort and silent: when iCloud is unavailable (signed out, restricted,
/// quota) `save` only touches local KVS memory and `load` reports the key as
/// absent, so the app behaves exactly as before — App Group and
/// WatchConnectivity are never affected.
```

#### 2. macOS parity
**File**: `SingleThread/AppViewModel.swift`
**Action**: verify only — `setupExcludedListCloudSync()` sits inside
`#if os(iOS) || os(macOS)` and macOS's `SkippedReminderSyncService` stub
(`SkippedReminderSyncService.swift:11`) simply has no push to make; the Mac still
updates its `@Observable` mirrors through the external-change observer. No
Mac-specific code.

### Tests
**File**: `SingleThreadTests/ExcludedListCloudStoreTests.swift`
**Action**: modify — append

```swift
    @Test
    func unavailableStoreSaveIsNoOp() {
        let backing = InMemoryUbiquitousStore()
        backing.isAvailable = false
        let store = makeStore(backing)

        store.save(["Work"])

        #expect(backing.values.isEmpty)
        #expect(store.load() == nil)
        #expect(backing.synchronizeCount == 1)
    }

    @Test
    func unavailableStoreLoadReturnsNil() {
        let backing = InMemoryUbiquitousStore()
        let store = makeStore(backing)
        store.save(["Work"])
        backing.isAvailable = false

        #expect(store.load() == nil)
        #expect(!store.seedIfAbsent(from: ["Personal"]))
        #expect(backing.values[Self.key] as? [String] == ["Work"])
    }
```

### Verification

#### Automated
- [x] `make format`
- [x] `make lint`
- [x] `rm -rf DerivedData && make periphery` (clean the index first — stale-index trap)
- [x] `make mac-build`
- [x] `make mac-test` (expect exactly the three pre-existing local-only `EntitlementStoreTests` failures: `isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` — do not debug them)
- [x] `scripts/test-one.sh SingleThreadTests/ExcludedListCloudStoreTests`
- [ ] Full CI-identical gate **once**, after all phases have committed, via the `run-gate` skill: `./scripts/test.sh` green on both iPhone and iPad legs.

#### Manual
- [ ] Sign out of iCloud (or run a build whose App ID lacks the capability) and confirm the app behaves exactly as today: no crash, no new UI, exclusions still persist locally and still reach the watch.
- [ ] `git rm DELETEME` is done before this branch merges (repo rule; the marker is not gitignored and its commit subject is the ticket title).
- [ ] PR description states why no UI test was added: the flow is data-layer; the value is fully captured by the unit suites, and a cross-device assertion is not reachable from XCUITest.

---

## Testing checkpoints
- After Phase 1: `ExcludedListCloudStoreTests` + `ReminderStoreTests` green, `make build` passes, entitlement archive signs.
- After Phase 2: `ExcludedListCloudSyncTests` + `ReminderStoreTests` green; `AppViewModelSyncWiringTests` still green.
- After Phase 3: precedence/clear suites green — do not advance with an absent-vs-empty failure.
- After Phase 4: format/lint/periphery/`make mac-build` clean; full gate green via `run-gate`.

## Files touched (complete list)
| File | Action | Phase |
|---|---|---|
| `SingleThreadCore/Sources/SingleThreadCore/UbiquitousKeyValueStoring.swift` | create | 1 |
| `SingleThreadCore/Sources/SingleThreadCore/ExcludedListCloudStore.swift` | create | 1 (3, 4 doc/tests) |
| `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` | modify | 1, 2, 3 (doc) |
| `SingleThread/AppViewModel.swift` | modify | 1, 2 |
| `SingleThread/App.entitlements` | create | 1 |
| `SingleThread/SingleThread.entitlements` | modify | 1 |
| `SingleThread.xcodeproj/project.pbxproj` | modify (4 literals) | 1 |
| `SingleThreadTests/TestFixtures.swift` | modify | 1 |
| `SingleThreadTests/ExcludedListCloudStoreTests.swift` | create | 1 (3, 4) |
| `SingleThreadTests/ExcludedListCloudSyncTests.swift` | create | 2 (3) |
| `SingleThreadTests/ReminderStoreTests.swift` | modify | 1 |
| `SingleThread/AppGroup.entitlements` | **unchanged** | — |

## Out of scope (from design)
No CloudKit, no skipped-ID sync, no union/tombstones, no watch iCloud, no widget
entitlement, no `.xcconfig`/`SystemCapabilities`, no new test target, no iCloud
status UI or retry queue, no change to `refreshExcludedListTitles` or to the WC
payload keys.

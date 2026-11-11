# Structure Outline

## Approach
Add an **additive iCloud channel** beside the App Group + WatchConnectivity path: a
`UbiquitousKeyValueStoring` seam over `NSUbiquitousKeyValueStore` and an
`ExcludedListCloudStore` injected into `ReminderStore`. Local edits write KVS; external
KVS changes apply into the App Group store and re-push over WC. App Group stays the
local truth and WC payload source. (KVS = last-writer-wins whole-set replace, scoped to
excluded list titles, best-effort/silent when unavailable.)

---

## Phase 1: Walking skeleton — exclude locally, persist to iCloud, rehydrate at launch
A user excludes a list; the value is written through the real KVS seam and a fresh launch
rehydrates local state from iCloud into the App Group store (seeding App Group → KVS once
when the key was never written). Green tests prove the store round-trips and the local
mutation reaches the cloud path.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/UbiquitousKeyValueStoring.swift` (new),
`SingleThreadCore/Sources/SingleThreadCore/ExcludedListCloudStore.swift` (new),
`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThread/AppViewModel.swift`,
`SingleThread/AppGroup.entitlements`, `SingleThread/SingleThread.entitlements`,
`SingleThreadTests/TestFixtures.swift`, `SingleThreadTests/ExcludedListCloudStoreTests.swift` (new)

**Key changes**:
- `protocol UbiquitousKeyValueStoring: AnyObject { func object(forKey:) -> Any?; func set(_:forKey:); func synchronize() -> Bool }` + `extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStoring` — new seam
- `struct ExcludedListCloudStore { init(store:key:); func load() -> [String]?; func save(_:); func seedIfAbsent(from:) }` — new; `nil` = never written, `[]` = intentional clear
- `ReminderStore.init(…, cloudStore: ExcludedListCloudStore? = nil)`; `setExcludedListTitles(_:)` also calls `cloudStore?.save(array)` after `excludeStore.save` — modified
- `AppViewModel.setupExcludedListCloudSync()` — startup reconcile: seed-if-absent, then adopt-present into App Group — new
- `com.apple.developer.ubiquity-kvstore-identifier = $(TeamIdentifierPrefix)$(CFBundleIdentifier)` added to both entitlements files — **horizontal (see note)**

**Contract**: `UbiquitousKeyValueStoring` + `ExcludedListCloudStore.load()/save(_:)/seedIfAbsent(from:)`; `setExcludedListTitles` keeps firing `onExcludedListsChanged`. Phase 2 consumes `load()` and the injected `cloudStore`.

**Tests**: `ExcludedListCloudStoreTests` — `loadReturnsNilWhenUnwritten`, `saveThenLoadRoundTrips`, `seedWritesOnlyWhenAbsent`; `ReminderStoreTests` — `setExcludedListTitlesWritesCloudStore`. `InMemoryUbiquitousStore` added to `TestFixtures.swift`.
**Verify**: `scripts/test-one.sh SingleThreadTests/ExcludedListCloudStoreTests` and `…/ReminderStoreTests` pass; `make build`; archive on a real device to confirm the KVS entitlement signs (Open Risk: provisioning).

**Horizontal note**: the two entitlements files are the only genuinely non-vertical piece — no slice can land them green on their own, so they are the smallest enabling change shipped with this slice. Watch/widget get no entitlement (watch stays WC-only; widget reads the App Group).

---

## Phase 2: Live propagation — a change on another device lands without a relaunch
A KVS change pushed by another device updates the in-memory mirror, persists to the App
Group (so the widget and watch see it) and re-pushes over WatchConnectivity; a local write
never loops back into KVS.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThread/AppViewModel.swift`,
`SingleThreadTests/ReminderStoreTests.swift`,
`SingleThreadTests/ExcludedListCloudSyncTests.swift` (new)

**Key changes**:
- `ReminderStore.applyCloudExcludedListTitles(_ titles: Set<String>)` — assign, `excludeStore.save`, fire `onExcludedListsChanged` (WC push) + `onRemindersChanged`; **never** `cloudStore.save` (deliberate no-echo, NOT the existing `refreshExcludedListTitles`)
- `AppViewModel` registers an observer for `NSUbiquitousKeyValueStore.didChangeExternallyNotification` (object-filtered to the KVS instance) → `guard titles != store.excludedListTitles else { return }` → `applyCloudExcludedListTitles`
- reuse the existing `AppGroup.defaults` single-instance invariant; no new defaults access

**Contract**: `applyCloudExcludedListTitles(_:)` is the sole remote-apply entry point; Phases 3–4 build on it and must not call `cloudStore.save` from within it.

**Tests**: `ReminderStoreTests`/`ExcludedListCloudSyncTests` — `applyCloudExcludedListTitlesPersistsAppGroupAndFiresHook`, `applyCloudExcludedListTitlesNeverWritesCloudStore` (no-echo sad path), `identicalCloudValueIsIgnored`.
**Verify**: `scripts/test-one.sh SingleThreadTests/ExcludedListCloudSyncTests` and `…/ReminderStoreTests`; `AppViewModelSyncWiringTests` stays green.

---

## Phase 3: Clear & precedence — removing the last exclusion propagates; absent ≠ empty
Clearing the excluded set on device A removes it on device B and the paired watch, while a
key that was never written never clobbers a local set with an empty one (the nil-vs-`[]`
assumption the design depends on).

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ExcludedListCloudStore.swift`,
`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThread/AppViewModel.swift`, `SingleThreadTests/ExcludedListCloudStoreTests.swift`

**Key changes**:
- `load()`/`seedIfAbsent(from:)` enforce: `nil` ⇒ one-time App Group → KVS seed; `[]` ⇒ adopt (do not reseed)
- `setExcludedListTitles([])` writes `[]` through `cloudStore.save`; `applyCloudExcludedListTitles([])` clears the App Group and re-pushes, still no cloud write-back
- replace-not-union on every path (last-writer-wins)

**Contract**: `nil` vs `[]` semantics of `ExcludedListCloudStore.load()` are now guaranteed, not assumed.

**Tests**: `emptyClearIsAdoptedNotReseeded`, `absentKeyDoesNotClearLocalSet`, `clearPropagatesToCloudAndWC`, `lastWriterWinsReplaceNotUnion`.
**Verify**: `scripts/test-one.sh SingleThreadTests/ExcludedListCloudStoreTests` and `…/ExcludedListCloudSyncTests`.

---

## Phase 4: Hardening — degraded mode, macOS parity, clean gate
A signed-out/restricted/no-entitlement device behaves exactly as today (no crash, no UI
change, App Group + WC unaffected) and the Mac updates its mirrors from the external-change
observer; the full CI gate is green.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ExcludedListCloudStore.swift`,
`SingleThread/AppViewModel.swift`, `SingleThreadTests/ExcludedListCloudStoreTests.swift`

**Key changes**:
- `save` is a no-op beyond App Group when the store is unavailable / `synchronize()` returns false, logging only; `load` returns `nil`
- confirm macOS (`SingleThread/AppViewModel.swift` is `#if os(iOS) || os(macOS)`) runs the same observer path with the WC stub — no Mac-specific code expected
- no retry queue, no iCloud status UI (explicit non-goals)

**Tests**: `unavailableStoreSaveIsNoOp`, `unavailableStoreLoadReturnsNil`; macOS suites via `make mac-test`.
**Verify**: `make format` → `make lint` → `make periphery` (clean `DerivedData/` first) → `make mac-build`; then the full `./scripts/test.sh` gate ONCE via the `run-gate` skill.

---

## Testing Checkpoints
- After Phase 1: `ExcludedListCloudStoreTests` + `ReminderStoreTests` green, `make build` passes, entitlement archive signs.
- After Phase 2: `ExcludedListCloudSyncTests` + `ReminderStoreTests` green; `AppViewModelSyncWiringTests` still green.
- After Phase 3: precedence/clear suites green — do not advance with an absent-vs-empty failure.
- After Phase 4: format/lint/periphery/`make mac-build` clean; full gate green via `run-gate`.

## Cross-Slice Non-Goals
No skipped-ID sync, no CloudKit, no union/tombstones, no watch iCloud, no widget entitlement,
no `.xcconfig`/`SystemCapabilities`, no new test target.

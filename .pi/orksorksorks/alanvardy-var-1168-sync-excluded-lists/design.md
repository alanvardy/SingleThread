# Design Discussion — iCloud sync for excluded lists (VAR-1168)

## Current State
- Excluded list titles are a tiny `public struct ExcludedListStore` in
  `SingleThreadCore` over the shared App Group `UserDefaults`:
  `init(defaults: UserDefaults = AppGroup.defaults, key:)`, `defaultsKey =
  "excludedListTitles"`, `load() = defaults.stringArray(forKey:) ?? []`,
  `save() = defaults.set` — whole-array **replace**
  (`SingleThreadCore/Sources/SingleThreadCore/ExcludedListStore.swift:4-30`).
  `SkippedReminderStore` is the same shape (`ReminderSkip.swift:121-150`).
- The App Group suite name is `"group.app.alanvardy.SingleThread"` and
  `AppGroup.defaults` is a **single cached** `nonisolated(unsafe) static let`
  (`AppGroup.swift:10,26-27`); object-filtered `didChangeNotification`
  observers depend on that identity (`AppGroupTests.swift:26-72`).
- `ReminderStore` (`@MainActor @Observable`) holds `skippedIDs` /
  `excludedListTitles` mirrors (`ReminderStore.swift:65-66`) and injects both
  stores with defaults (`:25,:28`). `setExcludedListTitles(_:)` (`:577-585`)
  assigns, persists, then fires `onExcludedListsChanged` and
  `onRemindersChanged`. `refreshExcludedListTitles(_:)` (`:589-594`) is the
  deliberate **no-echo** remote apply: assigns and fires only
  `onRemindersChanged`, so a received WC push does not bounce back.
  `reconcileSkipState` (`:751-766`) reloads both stores from disk on every
  non-clearing reload; `reload` wraps it and fires `onRemindersChanged`.
- Cross-device state travels through one choke point:
  `SkippedReminderSyncService: WCSessionDelegate`
  (`SkippedReminderSyncService.swift:48`, gated `#if os(iOS)||os(watchOS)`,
  macOS stub at `:11`). `pushAll()` (`:238-292`) writes ONE latest-wins
  `updateApplicationContext` snapshot; `apply(context:)` (`:462-524`) decodes
  per key, persists to the store, then fires hooks; absent key = no-op.
  Both list keys live in `PayloadKey` (`:370-388`).
- Phone wiring: `AppViewModel.swift:486-539` builds the service, assigns
  receive hooks before `activate()`, and wires `onExcludedListsChanged` →
  `pushAll()` (`:525-527`). Watch wiring `WatchAppViewModel.swift:190-244`
  pushes `sends*: false`; exclusions are **phone→watch only** (`:229-244`).
- **No iCloud, CloudKit, or `NSUbiquitousKeyValueStore` code or entitlement
  exists anywhere.** Capabilities are declared only by entitlement files +
  `INFOPLIST_KEY_*` (no `SystemCapabilities` pbxproj records, no `.xcconfig`):
  app target picks `AppGroup.entitlements` for iphoneos/iphonesimulator and
  `SingleThread.entitlements` for macosx (`pbxproj:757-759,808-810`); widget is
  unconditional `AppGroup.entitlements` (`:1019,1050`); the watch target has
  **no entitlements file at all** (`:926-1006`).
- macOS is a first-class shipping target: `SUPPORTED_PLATFORMS` includes
  `macosx` (`pbxproj:793`), `mac-distribute` exports app-store-connect, and the
  exclusion UI is cross-platform and ungated (`ExcludedListsView.swift:8-46`,
  reached from `SettingsView.swift:105-116`). iOS and macOS share
  `PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.SingleThread` (`:788,839`).
- The widget has no direct iCloud/key hits, but builds a `ReminderStore` and
  reloads (`NextThingWidget.swift:57-64`), so it reads exclusions transitively
  from the App Group via `reconcileSkipState` (`ReminderStore.swift:762`).

## Desired End State
Excluded list titles sync across a user's iCloud-signed-in devices (multiple
iPhones/iPads, plus the Mac) while the existing App Group + WatchConnectivity
path keeps working unchanged. A title excluded on any device disappears from
every device (last-writer-wins whole-set replace), and clearing the set
propagates. Verified correct when: unit tests prove absent-vs-empty precedence,
whole-set replace, and the no-echo remote apply; the existing WC suites stay
green; and a manual two-device check (same iCloud account) shows an exclusion
made on device A appear on device B and on the paired watch.

## Patterns to Follow
- **Mirror the store shape**: a small struct with injected backing source and
  `load()`/`save()`, whole-array replace — `ExcludedListStore.swift:4-30`.
- **Protocol transport seam + fake**: model the new
  `UbiquitousKeyValueStoring` seam and `InMemoryUbiquitousStore` on
  `SkipSyncSession` (`SkippedReminderSyncService.swift:18-34`) and `FakeSession`
  (`SingleThreadTests/TestFixtures.swift:70-115`).
- **Persist before notifying**: receive/apply paths write the store first, then
  fire hooks (`SkippedReminderSyncService.swift:459-472`).
- **Single shared instance contract**: any App Group access goes through
  `AppGroup.defaults`; never recompute `UserDefaults(suiteName:)`
  (`AppGroup.swift:26-27`, `AppGroupTests`).
- **Constructor injection in tests** with UUID-suffixed keys / in-memory fakes
  (`ExcludedListStoreTests.swift:6-7,14-15`); serialize suites that touch real
  shared App Group keys.
- **Wire hooks before activation**, from the main actor
  (`AppViewModel.swift:486-539`).
- **Convention commands**: `make build`, `make format`, `make lint`,
  `scripts/test-one.sh <Target/Suite>` for targeted suites, full
  `./scripts/test.sh` once post-commit via the `run-gate` skill.

Patterns NOT to follow here:
- Do **not** reuse `refreshExcludedListTitles(_:)` for the iCloud remote apply —
  its no-echo design (`ReminderStore.swift:589-594`) would swallow the WC push
  to the watch. The iCloud path needs its own notify-but-don't-echo-to-KVS apply.
- Do **not** fold iCloud into `ExcludedListStore.save`; that couples plain local
  persistence to a transport and forces every existing test to carry a fake KVS.
- Do **not** add a `SystemCapabilities` pbxproj block or `.xcconfig`; this repo
  expresses capabilities via entitlements files + `INFOPLIST_KEY_*` only.

## Design Decisions
1. **Mechanism — `NSUbiquitousKeyValueStore`**: the payload is a handful of
   short strings, well inside KVS's 1 MB / 1024-key quota; Apple supplies
   cross-device propagation and conflict handling with no schema, records, or
   change tokens. CloudKit is rejected as heavy for this data.
2. **Scope — excluded list titles only**: skipped IDs are device-local EventKit
   identifiers that are pruned on fetch (`ReminderSkip.swift:14-18`) and carry
   no meaning on another device. The task's title and final sentence both scope
   the work to excluded lists.
3. **Merge semantics — last-writer-wins whole-set replace**: identical to the
   WC convention (`research` Q5; `SkippedReminderSyncService.swift:235-241,
   459-472`). Replacing, not unioning, is what lets a `[]` clear propagate. A
   concurrent edit loses one side — accepted.
4. **Coexistence — additive channel**: App Group `UserDefaults` remains the
   local persisted truth and the WC payload source; iCloud fans out on every
   `setExcludedListTitles` and its external-change notification merges into the
   local store. No existing store or WC contract changes.
5. **Watch role — WatchConnectivity only**: the watch keeps receiving exclusions
   phone→watch as today (`WatchAppViewModel.swift:229-244`). iCloud covers
   non-paired devices. Avoids a new watch entitlements file and a second sync
   engine.
6. **Integration shape — a dedicated `ExcludedListCloudStore`** in
   SingleThreadCore, backed by a `UbiquitousKeyValueStoring` protocol over
   `NSUbiquitousKeyValueStore`. `ReminderStore` gains an injected optional cloud
   store; `setExcludedListTitles` writes App Group + KVS and fires the existing
   hook; a new remote-apply path assigns, persists to App Group (so the widget
   updates), fires `onExcludedListsChanged` (WC push) but never writes back to
   KVS. Startup reconciliation runs alongside the WC wiring in `AppViewModel`.
7. **Precedence / seeding — KVS authoritative once present**: `array(forKey:)`
   returning nil means "never written" and triggers a one-time App Group → KVS
   seed; returning `[]` means an intentional clear and is adopted. Once a KVS
   value exists it wins, is persisted to App Group, and is pushed to the watch.
8. **Degraded mode — best-effort and silent**: when KVS is unavailable (signed
   out, restricted, quota), `save` is a no-op beyond App Group and `load`
   returns nil; the app behaves exactly as today, logging only. No UI state, no
   retry queue.
9. **Platform coverage — iOS + macOS app targets**: the shared bundle ID means
   one KVS identifier (`$(TeamIdentifierPrefix)$(CFBundleIdentifier)`). Add
   `com.apple.developer.ubiquity-kvstore-identifier` to
   `SingleThread/AppGroup.entitlements` (iphoneos + iphonesimulator) and
   `SingleThread/SingleThread.entitlements` (macosx). Widget needs nothing (it
   reads the App Group); watch needs nothing (WC-only). macOS's WC stub
   (`SkippedReminderSyncService.swift:11`) means its remote apply only touches
   memory + App Group.
10. **Test seam — protocol + in-memory fake**: `UbiquitousKeyValueStoring`
    exposing object/set/synchronize and the external-change notification, with
    an `NSUbiquitousKeyValueStore` conformance and an
    `InMemoryUbiquitousStore` fixture. No test touches the real KVS.
11. **Echo suppression — value comparison**: the external-change observer
    no-ops when the delivered array equals the current in-memory set, so local
    writes can never loop back regardless of notification delivery semantics.

## What We're NOT Doing
- No CloudKit private database, records, subscriptions, or change tokens.
- No iCloud sync of skipped-reminder identifiers.
- No union or timestamped/tombstoned merge — last-writer-wins only.
- No iCloud on the watch; WatchConnectivity remains the watch's only channel.
- No iCloud entitlement in the widget target (it reads the App Group).
- No replacement of the App Group store; it stays the local truth and WC source.
- No user-facing iCloud status, error banner, or enable/disable toggle.
- No retry queue, offline outbox, or conflict-resolution UI.
- No `.xcconfig` / `SystemCapabilities` pbxproj refactor; entitlements files
  stay the single capability declaration.
- No new test target; new suites join `SingleThreadTests` and the existing
  `-only-testing:` wiring.

## Open Risks
- **Provisioning / CI signing**: adding a KVS entitlement requires the iCloud
  capability on the App IDs in the developer portal. Research did not cover CI
  signing for a new capability; `mac-distribute` and CI builds may fail until
  the capability/profiles are updated. Verify early on a real archive, not just
  simulator.
- **KVS propagation timing**: KVS is near-real-time but not guaranteed and has
  no delivery push; the manual two-device check may need a background/foreground
  cycle. No polling in scope.
- **Absent-vs-empty assumption**: design depends on `array(forKey:)` returning
  nil for an unwritten key and `[]` for a written clear; confirm on device
  during implementation.
- **Concurrent edits**: last-writer-wins can drop one side's edit; accepted per
  decision 3.
- **Watch App Group resolution** was unverified in research; unaffected because
  the watch stays on the WC path, but re-check if that ever changes.
- **macOS UI parity**: macOS gets the entitlement, but its remote-apply path has
  no WC service; confirm the Mac updates its `@Observable` mirrors via the
  external-change observer.
- **`make periphery`** reads a stale build index after branch switches — clean
  `DerivedData/` before relying on a scan.

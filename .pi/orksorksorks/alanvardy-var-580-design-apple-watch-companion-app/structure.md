# Structure Outline

## Approach

Extract the app's pure reminder logic and EventKit orchestration into a local
Swift Package `SingleThreadCore` (iOS + watchOS), refactor `ContentView` to drive
a shared UI-free `@MainActor ReminderStore`, add an embedded `SingleThreadWatch`
companion target that runs the same direct-EventKit loop, and reconcile the skip
set between devices via WatchConnectivity. Five vertical slices, each
independently buildable/testable.

---

## Phase 1: Shared logic package (`SingleThreadCore`)

Move the four Foundation-only types into a new local package and repoint the app
and tests at it. No behavior change — this establishes the shared seam both
targets will consume. Must be done atomically (move + repoint in one commit) to
avoid duplicate/missing symbols.

**Files**: `SingleThreadCore/Package.swift` (new),
`SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift` (new, moved from
`SingleThread/ReminderSkip.swift`),
`SingleThreadCore/Sources/SingleThreadCore/ReminderDateFilter.swift` (new, moved
out of `SingleThread/ContentView.swift`), `SingleThread/ReminderSkip.swift`
(delete), `SingleThread/ContentView.swift` (remove `ReminderDateFilter`, add
`import SingleThreadCore`), `SingleThreadTests/ReminderSkipTests.swift`,
`SingleThreadTests/SingleThreadTests.swift`, `SingleThread.xcodeproj/project.pbxproj`
(local package reference + `SingleThreadCore` product dependency on `SingleThread`).

**Key changes**:
- `Package.swift` — platforms `[.iOS(.v26), .watchOS(.v26)]` (min ≤ project's
  `26.5` deployment targets), one library product `SingleThreadCore`, **no**
  `SWIFT_DEFAULT_ACTOR_ISOLATION`.
- `ReminderSkipLogic` / `ReminderNotesFormatter` / `SkippedReminderStore` — moved
  unchanged (`nonisolated`, Foundation-only); signatures identical.
- `ReminderDateFilter.endOfToday(calendar: Calendar = .current, now: Date = Date()) -> Date`
  — moved verbatim out of `ContentView.swift` into the package.
- `extension EKReminder: @retroactive @unchecked Sendable {}` — moved from
  `ContentView.swift` into the package (single source of truth).
- Tests: `@testable import SingleThread` → `import SingleThreadCore` in
  `ReminderSkipTests.swift`; `SingleThreadTests.swift` keeps `@testable import
  SingleThread` (still tests `ContentView`) and adds `import SingleThreadCore`
  (for `ReminderDateFilter`).

**Verify**: `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' build-for-testing SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`
then `test-without-building -only-testing:SingleThreadTests`. All pure-logic and
`ContentView` tests green. Manual: app builds/runs with identical behavior.

**Caveat**: the package reference + target dependency are pbxproj edits (not
auto-discovered like `.swift` files inside synchronized folders) — make them via
Xcode GUI or careful hand-edit.

---

## Phase 2: Extract `ReminderStore` (UI-free orchestration)

Pull the EventKit lifecycle + state out of `ContentView` into a shared
`@MainActor` observable store; `ContentView` becomes a thin view driving it.
Behavior identical; existing injection seams preserved.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` (new),
`SingleThread/ContentView.swift` (refactor to drive the store; keep previews +
`mockReminder`), `SingleThreadTests/SingleThreadTests.swift` (keep
`ContentView(loadsReminders: false)` working; optionally add store tests).

**Key changes**:
- `@MainActor @Observable final class ReminderStore` — new:
  - `private(set) var reminders: [EKReminder]`, `skippedIDs: Set<String>`,
    `authorizationStatus: EKAuthorizationStatus`
  - `var visibleReminders: [EKReminder]` (computed, filters skipped IDs)
  - `init(eventStore: EKEventStore = EKEventStore(), skipStore: SkippedReminderStore = SkippedReminderStore(), loadsReminders: Bool = true)`
  - `init(loadsReminders: Bool, reminders: [EKReminder], skippedIDs: Set<String>, authorizationStatus: EKAuthorizationStatus)` — preview/test seam
  - `func start() async` (old `.task` logic: auth check → `reload`/`requestAccess`)
  - `func completeCurrentReminder() async`, `func skipCurrentReminder()`,
    `func reload(clearSkipped: Bool = false) async`
- `ContentView` — `init(loadsReminders:reminders:skippedIDs:authorizationStatus:)`
  now forwards to a `ReminderStore`; body reads `store.*`; `.task { await store.start() }`.

**Verify**: `./scripts/test.sh --unit-only` (warnings-as-errors build) then
`./scripts/test.sh --ui-only` (accessibility audit) — all existing tests green.
Manual: complete/skip/refresh/All-Done behavior unchanged on simulator.

---

## Phase 3: Watch target + local reminder loop

Add the embedded `SingleThreadWatch` target and a button-based watch UI running
the same direct-EventKit loop (complete + skip), skip set stored locally (no sync
yet). First watch-visible vertical slice.

**Files**: `SingleThread.xcodeproj/project.pbxproj` (new native target,
`SingleThreadWatch/` synchronized group, embed-watch-content phase, package
dependency), `SingleThreadWatch/SingleThreadWatchApp.swift` (new),
`SingleThreadWatch/WatchReminderView.swift` (new),
`SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThread.xcscheme` (add watch
target).

**Key changes**:
- New target: `com.apple.product-type.application`, bundle ID
  `app.alanvardy.SingleThread.watchkitapp`, `SUPPORTED_PLATFORMS = "watchos watchsimulator"`,
  `TARGETED_DEVICE_FAMILY = 4`, `WATCHOS_DEPLOYMENT_TARGET = 26.5`,
  `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` set.
- `@main struct SingleThreadWatchApp: App` — `WindowGroup { WatchReminderView(store: ReminderStore(loadsReminders: !ProcessInfo.processInfo.arguments.contains("--ui-testing"))) }`
- `struct WatchReminderView: View` — new; drives `ReminderStore`; `VStack` with
  title / due date / notes plus two buttons: `Button("Complete") { Task { await store.completeCurrentReminder() } }`
  (green) and `Button("Skip") { store.skipCurrentReminder() }` (orange);
  single reminder at a time (no `ForEach`).

**Verify**: `xcodebuild -scheme SingleThread -destination 'platform=watchOS Simulator,name=<watch>' build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`
(grep `xcrun simctl list devices available | grep Watch` for the device name).
Manual: launch on a paired watchOS Simulator, grant Reminders access, see the
next incomplete reminder, complete/skip works.

---

## Phase 4: WatchConnectivity skip sync

Add `SkippedReminderSyncService` (guarded `#if os(iOS) || os(watchOS)`) and wire
it into both apps so a skip/clear on either device pushes the full skip array;
the receiver resolves + re-saves via `ReminderSkipLogic.resolve`.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
(new), `SingleThread/SingleThreadApp.swift` (iOS wiring),
`SingleThreadWatch/SingleThreadWatchApp.swift` (watch wiring),
`SingleThreadTests/` (service tests).

**Key changes**:
- `protocol SkipSyncSession: AnyObject { func activate(); func updateApplicationContext(_: [String: Any]) throws }`
  + `extension WCSession: SkipSyncSession {}` — test seam (WCSession is not mockable directly).
- `@MainActor final class SkippedReminderSyncService: NSObject, WCSessionDelegate` — new:
  - `init(session: any SkipSyncSession, skipStore: SkippedReminderStore)`
  - `func activate()`
  - `func pushSkipIDs(_ ids: [String])` — `updateApplicationContext(["skippedReminderIdentifiers": ids])` (latest-wins)
  - `func receiveContext(_ ctx: [String: Any], fetchedIDs: [String])` — applies
    `ReminderSkipLogic.resolve` + `skipStore.save`
- `ReminderStore` gains a sync hook: `var onSkipSetChanged: (([String]) -> Void)?`,
  invoked after every skip/clear mutation, so both apps push on change.

**Verify**: `./scripts/test.sh --unit-only` — new service tests (fake
`SkipSyncSession`: push → correct payload; receive → resolved IDs saved).
Manual (hardware, per design risk): skip on watch → appears on phone after a
WatchConnectivity round-trip, and vice versa. Simulator round-trip is unreliable;
treat hardware as the real gate.

---

## Phase 5: CI & pipeline integration

Fold the watch build, package, and watch folder into the existing
build/test/lint tooling so `./scripts/test.sh` and CI cover the new platform.

**Files**: `Makefile`, `scripts/test.sh`, `.github/workflows/ci.yml`,
`.swiftlint.yml`, `.swiftformat`, `.periphery.yml`.

**Key changes**:
- `Makefile`: new `watch-build:` →
  `xcodebuild -scheme SingleThread -destination 'platform=watchOS Simulator,name=<watch>' build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`;
  add `SingleThreadCore/ SingleThreadWatch/` to `lint`/`format`.
- `scripts/test.sh`: insert watch build step before Periphery in full mode.
- `ci.yml`: add watch-simulator pre-boot + watch build to the lint job; extend
  lint dir list + cache-key hash.
- `.swiftlint.yml` (`included`), `.swiftformat` (scope), `.periphery.yml`
  (report scope): add `SingleThreadCore/` and `SingleThreadWatch/`. Periphery
  keeps `--skip-build --index-store-path` (watch build feeds the shared index store).

**Verify**: `./scripts/test.sh` (full) exits 0 end-to-end — format, lint (new
dirs), iOS build, watch build, Periphery, unit tests, UI tests all pass with
warnings-as-errors. Manual: `make lint` reports zero in the new folders.

---

## Testing Checkpoints

- **After Phase 1**: package builds; `import SingleThreadCore` tests pass; app
  behavior unchanged.
- **After Phase 2**: unit + UI suites green; `ContentView(loadsReminders: false)`
  seam still works.
- **After Phase 3**: watch target builds for watchOS Simulator; reminder loop
  smoke-tested manually.
- **After Phase 4**: sync-service unit tests green; hardware round-trip verified
  manually (CI cannot exercise WatchConnectivity).
- **After Phase 5**: full `./scripts/test.sh` green (format, lint, both builds,
  Periphery, unit + UI).

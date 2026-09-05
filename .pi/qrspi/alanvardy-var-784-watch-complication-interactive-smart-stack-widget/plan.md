# Implementation Plan

## Overview

Ship a watchOS WidgetKit widget — three accessory complication families plus an interactive Smart Stack — in a new `SingleThreadWatchWidget` extension embedded in the watch app, sharing today's `visibleReminders.first` derivation through a Core `ReminderWidgetState` machine, and routing Complete/Skip through the watch app (App Group mailbox + `openAppWhenRun`), never WCSession from the widget process.

Phase order is fixed (bottom-up): L1 shared derivation → L2 target plumbing → L3 mutation mailbox → L4 widget surface → L5 refresh + full gate. Branch: `alanvardy-var-784-watch-complication-interactive-smart-stack-widget`. Core sources live under `SingleThreadCore/Sources/SingleThreadCore/` (abbreviated `Core/` below).

---

## Phase 1: Shared widget-state derivation (Core)

Extract the auth-gate → reload → branch logic from `NextThingWidget.makeEntry()` into a WidgetKit-free, unit-testable Core function; refactor the iOS widget onto it.

### Changes

#### 1. `ReminderWidgetState` + `makeWidgetState` (new Core type)
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderWidgetState.swift`
**Action**: create

```swift
import EventKit
import Foundation

/// The five possible states a widget surface renders. WidgetKit-free so every
/// surface (iOS today, watch next) shares one tested derivation.
public enum ReminderWidgetState: Equatable, Sendable {
    case noAccess
    case empty(hasHidden: Bool) // true when reminders exist but are out-of-window
    case allDone
    case reminder(ReminderDisplay)

    /// Derives the state from a freshly-reloaded store. The caller builds the
    /// fresh store, sets `showsUndatedReminders`/`sortOption`, and passes the
    /// authorization gate in so `.noAccess` is testable without a real
    /// `EKEventStore` (production passes
    /// `EKEventStore.authorizationStatus(for: .reminder)`).
    @MainActor
    public static func makeWidgetState(
        store: ReminderStore,
        authorization: EKAuthorizationStatus
    ) async -> ReminderWidgetState {
        guard authorization == .fullAccess else { return .noAccess }
        await store.reload()
        if store.reminders.isEmpty { return .empty(hasHidden: store.hasHidden) }
        guard let current = store.visibleReminders.first else { return .allDone }
        return .reminder(ReminderDisplay(reminder: current))
    }
}
```

Notes:
- `makeWidgetState` holds exactly the branch order in `NextThingWidget.swift:74-102` / `ReminderStore.swift:358-413`.
- `ReminderDisplay` (`Core/ReminderDisplay.swift:8-73`) is already `public Equatable Sendable`, so the enum needs no extra conformance work.
- On iOS the function is an instance of a `build state from store` — put it as a `static` on the enum (mirrors how the widget already calls a `static makeEntry`).

#### 2. Refactor the iOS widget onto the shared state
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify — **consume only; behavior unchanged**

Delete the nested `enum State` (`:8-13`) and change the entry to carry `ReminderWidgetState`:

```swift
struct NextThingEntry: TimelineEntry {
    let date: Date
    let state: ReminderWidgetState
    let showsDate: Bool
    let showsList: Bool
    let showsRecurrence: Bool
    let showsAlarms: Bool
}
```

Replace the body of `makeEntry()` (`:62-110`) — it becomes the caller that builds the fresh store, sets the two prefs, and delegates the branch:

```swift
@MainActor
private static func makeEntry() async -> NextThingEntry {
    let date = Date()
    let showsDate = ShowDatePreference().isEnabled
    let showsList = ShowListPreference().isEnabled
    let showsRecurrence = ShowRecurrencePreference().isEnabled
    let showsAlarms = ShowAlarmsPreference().isEnabled
    let store = ReminderStore(loadsReminders: true)
    store.showsUndatedReminders = AppGroup.defaults.bool(forKey: "showUndatedReminders")
    store.setSortOption(SortOptionStore().load())
    let state = await ReminderWidgetState.makeWidgetState(
        store: store,
        authorization: EKEventStore.authorizationStatus(for: .reminder))
    return NextThingEntry(
        date: date, state: state,
        showsDate: showsDate, showsList: showsList,
        showsRecurrence: showsRecurrence, showsAlarms: showsAlarms)
}
```

View + previews: `switch entry.state` cases are already named identically (`.noAccess`, `.empty(hasHidden)`, `.allDone`, `.reminder(display)`). Only the `empty` associated-value label changes from positional `Bool` to `hasHidden` — update the one pattern (`:135`) from `case let .empty(hasHidden)` to `case .empty(let hasHidden)` (identical shape) and it compiles. Previews construct `.reminder(...)`/`.noAccess`/`.allDone` unchanged.

#### 3. Unit tests for the state machine
**File**: `SingleThreadTests/ReminderWidgetStateTests.swift`
**Action**: create

Drive all four (five) states with injected `InMemoryEventStore` + `loadsReminders: false`. Because `ReminderStore.reload()` is a no-op when `loadsReminders == false` (`ReminderStore.swift:361`), and the init seeds `reminders`/`skippedIDs`/`excludedListTitles`/`hasHidden` directly, each case is a pure seed → assert.

```swift
import EventKit
import SingleThreadCore
import Testing

@MainActor
@Suite struct ReminderWidgetStateTests {
    @Test func makeWidgetStateReturnsReminderForSeededStore() async {
        let reminder = makeReminder(title: "Next thing")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [reminder]),
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            settle: { })
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .fullAccess)
        #expect(state == .reminder(ReminderDisplay(reminder: reminder)))
    }

    @Test func makeWidgetStateReturnsEmptyWhenNoReminders() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(), loadsReminders: false,
            reminders: [], authorizationStatus: .fullAccess, settle: { })
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .fullAccess)
        #expect(state == .empty(hasHidden: false))
    }

    @Test func makeWidgetStateReturnsEmptyWithHiddenWhenSeeded() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(), loadsReminders: false,
            reminders: [], hasHidden: true, authorizationStatus: .fullAccess, settle: { })
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .fullAccess)
        #expect(state == .empty(hasHidden: true))
    }

    @Test func makeWidgetStateReturnsAllDoneWhenEverythingSkipped() async {
        let reminder = makeReminder(title: "Next thing")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [reminder]),
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [reminder.calendarItemIdentifier],
            authorizationStatus: .fullAccess,
            settle: { })
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .fullAccess)
        #expect(state == .allDone)
    }

    @Test func makeWidgetStateReturnsNoAccessWhenDenied() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(), loadsReminders: false,
            reminders: [], authorizationStatus: .denied, settle: { })
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .denied)
        #expect(state == .noAccess)
    }

    @Test func makeWidgetStateReturnsNoAccessWhenNotDetermined() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(), loadsReminders: false,
            reminders: [], authorizationStatus: .notDetermined, settle: { })
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .notDetermined)
        #expect(state == .noAccess)
    }

    // Reuse the process-wide shared EKEventStore so EKReminder creation never
    // exceeds EventKit's per-process connection cap (see ReminderStoreTests).
    private static let scratchStore = EKEventStore()
    private func makeReminder(title: String) -> EKReminder {
        let reminder = EKReminder(eventStore: Self.scratchStore)
        reminder.title = title
        return reminder
    }
}
```

Note: the `settle: { }` (noop) injection mirrors the repo's `noopSettle` convention (`ReminderStoreTests.swift:10-12`) without importing that private helper; the fixture uses a file-scoped shared `EKEventStore` (the `ReminderStoreWatchTests` pattern, needed to dodge EKReminder weak-store SIGTRAP safety).

### Verification

#### Automated
- [x] `make test` passes (full iOS+macOS unit gate; covers new `ReminderWidgetStateTests`)
- [x] Targeted, if iterating: `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath DerivedData test -only-testing:SingleThreadTests/ReminderWidgetStateTests` (pin `,OS=`/`,id=` if the name is ambiguous)
- [x] `make build` passes (iOS widget refactor still compiles; behavior unchanged)

#### Manual
- [ ] iOS widget still renders the same four states on the home screen (no-access lock, empty, all-done, reminder card) — no visual diff.

---

## Phase 2: Watch widget extension target + App Group plumbing

Stand up the build foundation: a compilable, embedded `SingleThreadWatchWidget` extension and the App Group entitlement on both watch targets. No new behavior yet — schema/build layer only.

### Changes

#### 1. New entitlement files (watch app + extension)
**File**: `SingleThreadWatch/AppGroup.entitlements` (create) and `SingleThreadWatchWidget/AppGroup.entitlements` (create)
**Action**: create (identical content — mirrors `SingleThread/AppGroup.entitlements`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.app.alanvardy.SingleThread</string>
	</array>
</dict>
</plist>
```

#### 2. Widget extension Info.plist + stub bundle
**File**: `SingleThreadWatchWidget/Info.plist` (create) and `SingleThreadWatchWidget/SingleThreadWatchWidgetBundle.swift` (create)
**Action**: create

Info.plist (identical to `SingleThreadWidget/Info.plist` — generated keys + NSExtension block):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
```

Stub bundle — a `WidgetBundle` with an empty body won't compile, so register the real widget's skeleton now and finalize it in Phase 4:

```swift
import SwiftUI
import WidgetKit

@main
struct SingleThreadWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchNextThingWidget()
    }
}
```

This requires the Phase 4 widget files' skeletons (bundle + provider + entry) to exist — create them with minimal bodies now (see the Phase 4 snippets), and flesh them out there.

#### 3. `.appex` target + embed phase in `project.pbxproj`
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify — clone the `SingleThreadWidget` target (`:339-361`, `:1015/1040` configs, `:1199-1210` list) with the watchOS settings.

Back up first: `cp SingleThread.xcodeproj/project.pbxproj SingleThread.xcodeproj/project.pbxproj.bak` (project convention — no undo for overwritten assets).

All new object IDs are illustrative; generate fresh unique 24-hex-char IDs (the `51AA3F…` scheme is used site-wide) and verify with `plutil -lint SingleThread.xcodeproj/project.pbxproj` and `xcodebuild -list -project SingleThread.xcodeproj` afterward. Insertions by section:

**PBXBuildFile** (2 new):
```
		51AA3F7300000000000001 /* SingleThreadWatchWidget.appex in Embed App Extensions */ = {isa = PBXBuildFile; fileRef = 51AA3F7000000000000001 /* SingleThreadWatchWidget.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
		51AA3F7300000000000002 /* SingleThreadCore in Frameworks */ = {isa = PBXBuildFile; productRef = 51AA3F110000000000000002 /* SingleThreadCore */; };
```

**PBXContainerItemProxy** (1 new — for the watch app → widget dependency):
```
		51AA3F7400000000000000 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 51AA3ECE302D5C4500960DFC /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 51AA3F7200000000000000;
			remoteInfo = SingleThreadWatchWidget;
		};
```

**PBXCopyFilesBuildPhase** (1 new — the embed phase, `dstSubfolderSpec = 13` PlugIns):
```
		51AA3F7300000000000000 /* Embed App Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				51AA3F7300000000000001 /* SingleThreadWatchWidget.appex in Embed App Extensions */,
			);
			name = "Embed App Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
```

**PBXFileReference** (1 new product):
```
		51AA3F7000000000000001 /* SingleThreadWatchWidget.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = SingleThreadWatchWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; };
```

**PBXFileSystemSynchronizedBuildFileExceptionSet** (1 new — exclude Info.plist from auto-membership, same as the iOS widget):
```
		51AA3F7600000000000000 /* Exceptions for "SingleThreadWatchWidget" folder in "SingleThreadWatchWidget" target */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = 51AA3F7200000000000000 /* SingleThreadWatchWidget */;
		};
```

**PBXFileSystemSynchronizedRootGroup** (1 new):
```
		51AA3F7000000000000002 /* SingleThreadWatchWidget */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				51AA3F7600000000000000 /* Exceptions for "SingleThreadWatchWidget" folder in "SingleThreadWatchWidget" target */,
			);
			path = SingleThreadWatchWidget;
			sourceTree = "<group>";
		};
```

**PBXFrameworksBuildPhase** (1 new):
```
		51AA3F7100000000000000 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				51AA3F7300000000000002 /* SingleThreadCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

**PBXGroup** — add the root group to the main group children (after `51AA3F400000000000000000 /* SingleThreadWidget */`):
```
				51AA3F7000000000000002 /* SingleThreadWatchWidget */,
```
and the product to the Products group children:
```
				51AA3F7000000000000001 /* SingleThreadWatchWidget.appex */,
```

**PBXNativeTarget** (1 new):
```
		51AA3F7200000000000000 /* SingleThreadWatchWidget */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 51AA3F7500000000000002 /* Build configuration list for PBXNativeTarget "SingleThreadWatchWidget" */;
			buildPhases = (
				51AA3F7100000000000001 /* Sources */,
				51AA3F7100000000000000 /* Frameworks */,
				51AA3F7100000000000002 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				51AA3F7000000000000002 /* SingleThreadWatchWidget */,
			);
			name = SingleThreadWatchWidget;
			packageProductDependencies = (
				51AA3F110000000000000002 /* SingleThreadCore */,
			);
			productName = SingleThreadWatchWidget;
			productReference = 51AA3F7000000000000001 /* SingleThreadWatchWidget.appex */;
			productType = "com.apple.product-type.app-extension";
		};
```

**Modify the `SingleThreadWatch` native target** (`:316-338`) — add the embed phase to `buildPhases` (after Resources) and the dependency:
```
			buildPhases = (
				51AA3F230000000000000004 /* Sources */,
				51AA3F240000000000000005 /* Frameworks */,
				51AA3F250000000000000006 /* Resources */,
				51AA3F7300000000000000 /* Embed App Extensions */,
			);
			...
			dependencies = (
				51AA3F7400000000000001 /* PBXTargetDependency */,
			);
```

**PBXProject** — add to `TargetAttributes` (inside the existing block):
```
					51AA3F7200000000000000 = {
						CreatedOnToolsVersion = 26.6;
					};
```
and to `targets` (after SingleThreadWidget):
```
				51AA3F7200000000000000 /* SingleThreadWatchWidget */,
```

**PBXResourcesBuildPhase** + **PBXSourcesBuildPhase** (1 new each):
```
		51AA3F7100000000000002 /* Resources */ = { ... buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; };
		51AA3F7100000000000001 /* Sources */ = { ... buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; };
```
(Empty `files()` — synchronized file groups auto-populate `SingleThreadWatchWidget/*.swift`.)

**PBXTargetDependency** (1 new):
```
		51AA3F7400000000000001 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 51AA3F7200000000000000 /* SingleThreadWatchWidget */;
			targetProxy = 51AA3F7400000000000000 /* PBXContainerItemProxy */;
		};
```

**XCBuildConfiguration** (2 new — Debug + Release). Clone the iOS widget config (`51AA3F4B`/`51AA3F4C`, `:1000-1046`) but swap platforms/ID/target/entitlements/Info.plist:

```
		51AA3F7500000000000000 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = SingleThreadWatchWidget/AppGroup.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 6NWX2DHB9Q;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = SingleThreadWatchWidget/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = SingleThread;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				INFOPLIST_KEY_NSRemindersFullAccessUsageDescription = "SingleThread needs access to show your reminders.";
				LD_RUNPATH_SEARCH_PATHS = (
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.SingleThread.watchwidget;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = watchos;
				SKIP_INSTALL = YES;
				STRING_CATALOG_GENERATE_SYMBOLS = NO;
				SUPPORTED_PLATFORMS = "watchos watchsimulator";
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 26.5;
			};
			name = Debug;
		};
```
Release is byte-identical except `name = Release;`. (No `SWIFT_DEFAULT_ACTOR_ISOLATION` key — the extension target must NOT default to MainActor; annotate `@MainActor` explicitly, per project convention.)

**XCConfigurationList** (1 new):
```
		51AA3F7500000000000002 /* Build configuration list for PBXNativeTarget "SingleThreadWatchWidget" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				51AA3F7500000000000000 /* Debug */,
				51AA3F7500000000000001 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

**Add CODE_SIGN_ENTITLEMENTS to the two watch-app configs** — `51AA3F2B…0C` (Debug, `:943-967`) and `51AA3F2C…0D` (Release, `:968-994`), insert alongside the other settings:
```
				CODE_SIGN_ENTITLEMENTS = SingleThreadWatch/AppGroup.entitlements;
```

#### 4. Deployment-target guard counts
**File**: `scripts/test.sh`
**Action**: modify

```diff
-#   WATCHOS_DEPLOYMENT_TARGET  (all 6: watch app + watch UI tests + watch tests) = 26.5
+#   WATCHOS_DEPLOYMENT_TARGET  (all 8: watch app + watch UI tests + watch tests + watch widget) = 26.5
 ...
-EXPECTED_TARGET_LITERALS=20    # all *_DEPLOYMENT_TARGET in project.pbxproj (8+6+6)
+EXPECTED_TARGET_LITERALS=22    # all *_DEPLOYMENT_TARGET in project.pbxproj (8+6+8)
```

Recompute with the guard's own grep before finalizing:
`grep -cE 'IPHONEOS_DEPLOYMENT_TARGET|MACOSX_DEPLOYMENT_TARGET|WATCHOS_DEPLOYMENT_TARGET' SingleThread.xcodeproj/project.pbxproj` must equal 22 (8 IPHONEOS + 6 MACOSX + 8 WATCHOS — the new target adds exactly 2 WATCHOS literals: Debug + Release).

### Verification

#### Automated
- [x] `make watch-build` green — new `SingleThreadWatchWidget` target compiles and embeds into `SingleThreadWatch.app`
- [x] `./scripts/test.sh` deployment-target guard passes with the updated 22 (`8+6+8`) counts
- [x] `plutil -lint SingleThread.xcodeproj/project.pbxproj` reports `OK`; `xcodebuild -list -project SingleThread.xcodeproj` lists `SingleThreadWatchWidget`
- [x] `make watch-test` still green (existing watch suites — plumbing only, no new assertions)

#### Manual
- [ ] `xcrun simctl get_app_container <booted-watch-UDID> app.alanvardy.SingleThread.watchkitapp app` shows `SingleThreadWatchWidget.appex` inside `PlugIns/`

---

## Phase 3: Mutation dispatch + mailbox drain (Core + watch), no WCSession from the widget

Make Complete/Skip from the Smart Stack reach the phone: the intent records a pending action and opens the app; the app drains it via the already-wired relay hooks. iOS behavior unchanged.

### Changes

#### 1. `PendingReminderAction` + `PendingReminderActionStore`
**File**: `SingleThreadCore/Sources/SingleThreadCore/PendingReminderAction.swift`
**Action**: create

```swift
import Foundation

/// A user action recorded by a watch widget extension process and later drained
/// by the watch app process (the only WatchConnectivity peer on the watch).
public struct PendingReminderAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case complete
        case skip
    }

    public let kind: Kind
    /// `EKReminder.calendarItemIdentifier` of the reminder to complete/skip.
    public let identifier: String

    public init(kind: Kind, identifier: String) {
        self.kind = kind
        self.identifier = identifier
    }
}

/// Single-slot mailbox in `AppGroup.defaults` (real suite on watch once the
/// App Group is registered). Mirrors `SkippedReminderStore`'s shape.
public struct PendingReminderActionStore {
    public static let key = "pendingReminderAction"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    public func load() -> PendingReminderAction? {
        guard
            let data = defaults.data(forKey: Self.key),
            let action = try? JSONDecoder().decode(PendingReminderAction.self, from: data)
        else { return nil }
        return action
    }

    public func save(_ action: PendingReminderAction) {
        guard let data = try? JSONEncoder().encode(action) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
```

#### 2. WatchOS branch in the two intents
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift`
**Action**: modify — keep the iOS body unchanged; gate a watchOS body in via `#if os(watchOS)`.

```swift
public struct CompleteReminderIntent: AppIntent {
    public init() {}
    public static let title: LocalizedStringResource = "Complete Reminder"
    public static let isDiscoverable = false

    #if os(watchOS)
        /// The Smart Stack button opens the watch app, whose `.task` drains the
        /// mailbox and relays through the already-wired `onCompleteReminder` hook.
        public static var openAppWhenRun: Bool { true }
    #endif

    @MainActor
    public func perform() async throws -> some IntentResult {
        #if os(watchOS)
            let store = ReminderStore(loadsReminders: true)
            store.setSortOption(SortOptionStore().load())
            await store.reload()
            guard let identifier = store.visibleReminders.first?.calendarItemIdentifier else {
                return .result()
            }
            PendingReminderActionStore().save(
                PendingReminderAction(kind: .complete, identifier: identifier))
            return .result()
        #else
            let store = ReminderStore(loadsReminders: true)
            store.setSortOption(SortOptionStore().load())
            await store.reload()
            await store.completeCurrentReminder()
            return .result()
        #endif
    }
}
```

`SkipReminderIntent` is the same shape: `openAppWhenRun` under `#if os(watchOS)`, and the watchOS `perform()` writes `PendingReminderAction(kind: .skip, identifier:)` (no store mutation, no `SkippedReminderSyncService`); the `#else` branch keeps today's `skipCurrentReminderImmediately()` path.

#### 3. Drain helper in the watch app
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify — add a static, testable drain and a thin instance method.

```swift
// Static so the watch unit tests can drive it with an injected store + isolated
// mailbox defaults (mirrors WatchSyncPipelineTests' fake-session pattern).
@MainActor
static func drainPendingReminderAction(
    store: ReminderStore,
    actionStore: PendingReminderActionStore = PendingReminderActionStore()
) async {
    guard let action = actionStore.load() else { return }
    switch action.kind {
    case .complete:
        await store.completeReminder(identifier: action.identifier)
    case .skip:
        store.skipCurrentReminder()
    }
    actionStore.clear()
    WidgetCenter.shared.reloadAllTimelines()
}

/// Drains the widget-process mailbox on launch. The store's relay hooks are
/// already wired in `setupSyncService`, so completing fires
/// `onCompleteReminder` → `requestCompleteReminder`, and skipping fires
/// `onSkipSetChanged` → `pushAll()`.
func drainPendingReminderAction() async {
    await Self.drainPendingReminderAction(store: store)
}
```

Add `import WidgetKit` at the top of the file.

#### 4. Trigger the drain on launch
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify — add a `.task` alongside the root view (the `openAppWhenRun` launch lands here).

```swift
    var body: some Scene {
        WindowGroup {
            WatchReminderView(viewModel: viewModel.reminderViewModel)
                .task { await viewModel.drainPendingReminderAction() }
        }
    }
```

#### 5. Unit tests
**File**: `SingleThreadTests/PendingReminderActionTests.swift` (create)
**Action**: create — Codable round-trip and store save/load/clear against an isolated `UserDefaults(suiteName:)` (defer `removePersistentDomain` cleanup, mirroring `ReminderStoreWatchTests`):

```swift
import SingleThreadCore
import Testing
import Foundation

@Suite struct PendingReminderActionTests {
    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suite = "PendingReminderActionTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func codableRoundTrip() throws {
        let action = PendingReminderAction(kind: .complete, identifier: "rem-42")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(PendingReminderAction.self, from: data)
        #expect(decoded == action)
    }

    @Test func storeRoundTripsSaveAndLoad() {
        let defaults = isolatedDefaults("roundtrip")
        let store = PendingReminderActionStore(defaults: defaults)
        store.save(PendingReminderAction(kind: .skip, identifier: "rem-7"))
        #expect(store.load() == PendingReminderAction(kind: .skip, identifier: "rem-7"))
    }

    @Test func storeClearsSavedAction() {
        let defaults = isolatedDefaults("clear")
        let store = PendingReminderActionStore(defaults: defaults)
        store.save(PendingReminderAction(kind: .complete, identifier: "rem-7"))
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func storeLoadsNilWhenEmpty() {
        let defaults = isolatedDefaults("empty")
        #expect(PendingReminderActionStore(defaults: defaults).load() == nil)
    }
}
```

**File**: `SingleThreadWatchTests/PendingActionDrainTests.swift` (create)
**Action**: create — mirror `WatchSyncPipelineTests`: fake `SkipSyncSession` + `InMemoryEventStore`, wire the store's relay hooks exactly as `setupSyncService` does, then drain and assert the relay fired + mailbox cleared.

```swift
import EventKit
import SingleThreadCore
import Testing

@MainActor
@Suite struct PendingActionDrainTests {
    @Test func drainAppliesCompletionAndFiresRelay() async {
        let reminder = makeReminder(title: "Next thing")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [reminder]),
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            settle: { })
        var relayed: [String] = []
        store.onCompleteReminder = { relayed.append($0) }
        let actionStore = isolatedActionStore()
        actionStore.save(PendingReminderAction(kind: .complete, identifier: reminder.calendarItemIdentifier))

        await WatchAppViewModel.drainPendingReminderAction(store: store, actionStore: actionStore)

        #expect(relayed == [reminder.calendarItemIdentifier])
        #expect(actionStore.load() == nil)
    }

    @Test func drainSkipFiresPushAll() async {
        let reminder = makeReminder(title: "Next thing")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [reminder]),
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            settle: { })
        var pushed: [String] = []
        store.onSkipSetChanged = { pushed = $0 }
        let actionStore = isolatedActionStore()
        actionStore.save(PendingReminderAction(kind: .skip, identifier: reminder.calendarItemIdentifier))

        WatchAppViewModel.drainPendingReminderAction(store: store, actionStore: actionStore)
        // `skipCurrentReminder()` applies the skip inside an internal detached
        // task after the injected noop settle — wait as WatchSyncPipelineTests
        // does (small `Task.yield()` / `pollUntil` on `pushed`).

        #expect(pushed.contains(reminder.calendarItemIdentifier))
        #expect(actionStore.load() == nil)
    }

    @Test func drainNoOpsWhenMailboxEmpty() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(), loadsReminders: false,
            reminders: [], authorizationStatus: .fullAccess, settle: { })
        store.onCompleteReminder = { _ in Issue.record("relay fired with empty mailbox") }
        await WatchAppViewModel.drainPendingReminderAction(store: store, actionStore: isolatedActionStore())
        #expect(store.reminders.isEmpty)
    }

    private static let scratchStore = EKEventStore()
    private func makeReminder(title: String) -> EKReminder {
        let reminder = EKReminder(eventStore: Self.scratchStore)
        reminder.title = title
        return reminder
    }
    private func isolatedActionStore() -> PendingReminderActionStore {
        let suite = "PendingActionDrainTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PendingReminderActionStore(defaults: defaults)
    }
}
```

Notes:
- This target compiles under `SDKROOT = watchos`, so `#if os(watchOS)` branches (the `completeReminder(identifier:)` relay path, `skipCurrentReminder()`) are active.
- `canMutate` is true by default (`completionCount 0 < freemiumCap`), so the skip path proceeds without entitlement setup.
- Follow `WatchSyncPipelineTests.swift` exactly for how it awaits the internal skip task if the naive yield is insufficient.

### Verification

#### Automated
- [x] `make test` green (iOS + macOS; covers `PendingReminderActionTests`)
- [x] `make watch-test` green (covers `PendingActionDrainTests` + existing watch suites)

#### Manual
- [ ] (deferred to Phase 4's smoke test — mutations can't be exercised until the Smart Stack buttons exist)

---

## Phase 4: Watch widget surface (bundle, provider, accessory views)

Render the three accessory families from `ReminderWidgetState`; wire the interactive buttons. Consumes Phase 1's state and Phase 3's intents.

### Changes

#### 1. Bundle
**File**: `SingleThreadWatchWidget/SingleThreadWatchWidgetBundle.swift`
**Action**: modify (finalize from the Phase 2 stub)

```swift
import SwiftUI
import WidgetKit

@main
struct SingleThreadWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchNextThingWidget()
    }
}
```

#### 2. Entry + provider
**File**: `SingleThreadWatchWidget/WatchNextThingProvider.swift`
**Action**: create

```swift
import EventKit
import SingleThreadCore
import WidgetKit

struct WatchNextThingEntry: TimelineEntry {
    let date: Date
    let state: ReminderWidgetState
}

struct WatchNextThingProvider: TimelineProvider {
    func placeholder(in _: Context) -> WatchNextThingEntry {
        WatchNextThingEntry(date: Date(), state: .reminder(ReminderDisplay(title: "Next thing")))
    }

    func getSnapshot(in _: Context, completion: @escaping @Sendable (WatchNextThingEntry) -> Void) {
        completion(WatchNextThingEntry(date: Date(), state: .reminder(ReminderDisplay(title: "Buy groceries"))))
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<WatchNextThingEntry>) -> Void) {
        Task { @MainActor in
            let store = ReminderStore(loadsReminders: true)
            store.showsUndatedReminders = AppGroup.defaults.bool(forKey: "showUndatedReminders")
            store.setSortOption(SortOptionStore().load())
            let state = await ReminderWidgetState.makeWidgetState(
                store: store,
                authorization: EKEventStore.authorizationStatus(for: .reminder))
            let refresh = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [WatchNextThingEntry(date: Date(), state: state)],
                                policy: .after(refresh)))
        }
    }
}
```

(`.after(15 min)` mirrors `NextThingProvider.getTimeline` `:54-55`.)

#### 3. Widget + accessory views
**File**: `SingleThreadWatchWidget/WatchNextThingWidget.swift`
**Action**: create

```swift
import AppIntents
import SingleThreadCore
import SwiftUI
import WidgetKit

struct WatchNextThingWidget: Widget {
    let kind = "NextThingWatch"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchNextThingProvider()) { entry in
            WatchNextThingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(
            LocalizedStringResource("Next Thing", table: "Localizable", bundle: .main))
        .description(
            LocalizedStringResource(
                "Your next reminder, with Complete and Skip.",
                table: "Localizable",
                bundle: .main))
        .supportedFamilies([.accessoryRectangular, .accessoryCorner, .accessoryCircular])
    }
}

// Views below are explicit @MainActor: the extension target does NOT enable
// SWIFT_DEFAULT_ACTOR_ISOLATION (unlike the app/watch targets).
struct WatchNextThingWidgetView: View {
    let entry: WatchNextThingEntry

    var body: some View {
        switch entry.state {
        case .noAccess: accessoryGlyph("lock.shield")
        case let .empty(hasHidden):
            if hasHidden { accessoryGlyph("clock.badge.questionmark") }
            else { accessoryGlyph("checklist") }
        case .allDone: accessoryGlyph("checkmark.circle")
        case let .reminder(display):
            accessoryReminder(display)
        }
    }
}
```

Accessory family views (in the same file; reuse `SharedStrings` for labels — decision 6, no new ad-hoc strings). Rectangular carries a compact label + glyph; corner/circular fall back to a single glyph so the complication is never blank:

```swift
private extension WatchNextThingWidgetView {
    func accessoryReminder(_ display: ReminderDisplay) -> some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(display.priorityMarker.isEmpty ? display.titleAttributed : display.priorityMarker + " " + display.titleAttributed)
                    .font(.headline).lineLimit(1)
                if let due = display.dueDate { Text(due, style: .date).font(.caption2).foregroundStyle(.secondary) }
                Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
            }
        default:
            accessoryGlyph(display.priorityMarker.isEmpty ? "checklist" : "exclamationmark")
        }
    }

    func accessoryGlyph(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
    }

    var family: WidgetFamily {
        // resolved via @Environment(\.widgetFamily) in the view body.
        environmentFamily
    }
}
```

Implementation detail: obtain the family with `@Environment(\.widgetFamily) var family: WidgetFamily` on `WatchNextThingWidgetView` (or `.widgetFamily` styled env) and branch on it; use `ViewThatFits` on tiny families if layout overflows. The interactive buttons are `Button(intent:)` (Smart Stack only — WidgetKit strips them from complications):

```swift
Button(intent: CompleteReminderIntent()) {
    Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
}
.buttonStyle(.bordered).tint(.green)
.accessibilityLabel(SharedStrings.completeReminderAccessibility)

Button(intent: SkipReminderIntent()) {
    Label(SharedStrings.skipAction, systemImage: "circle.slash")
}
.buttonStyle(.bordered).tint(.orange)
.accessibilityLabel(SharedStrings.skipReminderAccessibility)
```

(mirrors `NextThingWidget.swift:166-186`). Reference `SharedStrings` accessors exactly — `completeAction`, `skipAction`, `allDone`, `noReminders`, `nothingDueRightNow` (`Core/LocalizedString+Shared.swift:11-72`).

### Verification

#### Automated
- [x] `make watch-build` green (extension compiles + embeds)
- [x] `make test` + `make watch-test` still green (Phase 1 + Phase 3 suites — the widget consumes both, no new runnable tests)

#### Manual (simulator smoke)
- [ ] Complication renders all four states on a watch face (boot a watch sim via `xcrun simctl`; add the complication)
- [ ] Smart Stack shows the widget with Complete/Skip buttons
- [ ] Tapping a button opens the watch app (drains + relays) and the reminder leaves the list

---

## Phase 5: Refresh lifecycle + full gate (integration/hardening)

Close the freshness loop, then run the single full gate.

### Changes

#### 1. Watch-side `reloadAllTimelines` in mutation + sync-receive paths
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify — alongside the existing hook wiring (`:165-198`), append `WidgetCenter.shared.reloadAllTimelines()` to the hooks that change visible reminder state (mirrors iOS `AppViewModel.swift:76-77`).

```swift
service.onSkippedIdentifiersReceived = { [weak store] _ in
    Task { @MainActor in
        await store?.reload()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
// ... and in the other state-changing receive hooks:
service.onShowUndatedRemindersReceived = { [weak store] value in
    Task { @MainActor in
        store?.showsUndatedReminders = value
        await store?.reload()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
service.onSortOptionReceived = { [weak store] option in
    Task { @MainActor in
        store?.setSortOption(option)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
service.onExcludedListTitlesReceived = { [weak store] titles in
    Task { @MainActor in
        store?.refreshExcludedListTitles(Set(titles))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
// Local mutation paths:
store.onSkipSetChanged = { _ in
    service.pushAll()
    WidgetCenter.shared.reloadAllTimelines()
}
store.onCompleteReminder = { identifier in
    service.requestCompleteReminder(identifier)
    WidgetCenter.shared.reloadAllTimelines()
}
```

No other source changes.

### Verification

#### Automated
- [x] `./scripts/test.sh` — the ONE full gate (format, lint, build iOS/watch/mac, deployment-target guard, unit + UI tests)
- [x] `make periphery` green
- [x] `make lint` green

#### Manual
- [ ] Complete/skip a reminder in the watch app → complication refreshes promptly (no 15-min wait)

---

## Testing Checkpoints (gate the phase order)

- **After Phase 1**: `make test` (`ReminderWidgetStateTests`) green + `make build` green — else do not proceed.
- **After Phase 2**: `make watch-build` green + deployment-target guard (22) green + `make watch-test` green.
- **After Phase 3**: `make test` + `make watch-test` green (action codec + drain suites).
- **After Phase 4**: `make watch-build` green + Phase 1/3 suites still green + manual smoke (four states render, buttons wire).
- **After Phase 5**: full `./scripts/test.sh` + `make periphery` + `make lint` green.

## Cross-cutting notes

- **The only thing not provable below the top layer is actual widget rendering and the tap→`openAppWhenRun`→app→relay handoff** (the widget process is not XCUITest-drivable). Every logical link is stubbed/tested one layer down: state (Phase 1) and mailbox+relay (Phase 3) are unit-green before the views (Phase 4) that route between them. **State the UI-test gap explicitly in the PR body** (only `makeWidgetState` + drain tests guard the widget; watch UI tests exercise the app, not the system-launched extension).
- **App Group + storage shift** (Phase 2) is the one physical side effect: `AppGroup.defaults` stops collapsing to `.standard` on watchOS once the suite is registered, so watch-side skips/exclusions/sort reset once and re-sync from the phone on the next WatchConnectivity exchange. No migration code by design — flag it in the PR.
- **Destination pinning**: name-only simulator destinations hang with 4 runtimes installed — pin `,OS=`/`,id=` (CI pins `id=`). One `xcodebuild test` process at a time.
- **Commit in phases** (one commit per phase); run `make format` then `make lint` before each commit. Never push to `main` — work lands via PR.
- **Deviations from structure.md** (noted for review): (1) Phase 3 adds `SingleThreadWatch/SingleThreadWatchApp.swift` as the `.task` drain-trigger site — `WatchAppViewModel` has no `.task`; the structure's "drain on `.task`/launch" requires an App-level hook. (2) The drain is written as a `static` helper + thin instance method so `SingleThreadWatchTests` can inject store/mailbox without constructing a `WCSession`-dependent `WatchAppViewModel`. (3) Phase 2's stub bundle registers the real `WatchNextThingWidget` skeleton immediately (an empty `WidgetBundle` won't compile), so Phase 4 finalizes rather than creates the widget declaration.
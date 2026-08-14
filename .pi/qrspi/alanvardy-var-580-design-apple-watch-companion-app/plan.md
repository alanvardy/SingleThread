# Implementation Plan

## Overview

Add an embedded watchOS companion app that runs the same direct-EventKit reminder loop as the iPhone, shares pure logic through a new local Swift Package `SingleThreadCore`, and reconciles the skip set between devices via WatchConnectivity.

---

## Phase 1: Shared logic package (`SingleThreadCore`)

Extract the four Foundation-only types into a local package so both iOS and watchOS targets share one source of truth. No behavior change.

### Changes

#### 1. Create package manifest
**File**: `SingleThreadCore/Package.swift` (new)
**Action**: create

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingleThreadCore",
    platforms: [
        .iOS("26.5"),
        .watchOS("26.5"),
        .macOS("26.5"),
        .visionOS("26.5"),
    ],
    products: [
        .library(name: "SingleThreadCore", targets: ["SingleThreadCore"]),
    ],
    targets: [
        .target(name: "SingleThreadCore"),
    ]
)
```

No `SWIFT_DEFAULT_ACTOR_ISOLATION` — the package does not set it. Pure logic stays `nonisolated`; `ReminderStore` (Phase 2) and `SkippedReminderSyncService` (Phase 4) are explicitly `@MainActor` on their class declarations.

#### 2. Move ReminderSkip.swift into the package
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift` (new)
**Action**: move `SingleThread/ReminderSkip.swift` verbatim — same content, same `import Foundation`, no changes.

Contains: `ReminderSkipLogic`, `ReminderNotesFormatter`, `SkippedReminderStore`.

#### 3. Extract ReminderDateFilter + EKReminder Sendable conformance
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderDateFilter.swift` (new)
**Action**: create

```swift
import EventKit
import Foundation

extension EKReminder: @retroactive @unchecked Sendable {}

/// Computes the due-date boundary for the "today or overdue" filter.
nonisolated enum ReminderDateFilter {
    /// The last instant of today (23:59:59), so reminders due tomorrow are excluded.
    static func endOfToday(
        calendar: Calendar = .current,
        now: Date = Date()) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return startOfToday
        }
        return tomorrow.addingTimeInterval(-1)
    }
}
```

#### 4. Delete old ReminderSkip.swift
**File**: `SingleThread/ReminderSkip.swift`
**Action**: delete

#### 5. Update ContentView.swift
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Replace lines 1–18 (the `import EventKit`, `import SwiftUI`, `extension EKReminder…`, and `ReminderDateFilter` enum) with:

```swift
import EventKit
import SingleThreadCore
import SwiftUI
```

Lines 1–2 become `import EventKit` + `import SingleThreadCore` + `import SwiftUI`. The `extension EKReminder: @retroactive @unchecked Sendable {}` and `ReminderDateFilter` enum are removed (now in the package). The rest of the file stays identical — `ContentView` still uses `ReminderDateFilter.endOfToday()`, `ReminderSkipLogic`, `ReminderNotesFormatter`, and `SkippedReminderStore` via the package import.

#### 6. Update ReminderSkipTests.swift
**File**: `SingleThreadTests/ReminderSkipTests.swift`
**Action**: modify

Line 1: change `@testable import SingleThread` → `import SingleThreadCore`

All `ReminderSkipLogic` / `ReminderNotesFormatter` references still resolve through the package. No other changes to test bodies.

#### 7. Update SingleThreadTests.swift
**File**: `SingleThreadTests/SingleThreadTests.swift`
**Action**: modify

Add `import SingleThreadCore` alongside the existing `@testable import SingleThread` and `import SwiftUI`. The `ReminderDateFilterTests` struct references `ReminderDateFilter` which now lives in the package.

New imports:
```swift
@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing
```

#### 8. Wire package into Xcode project
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

Three additions to the pbxproj (use Xcode GUI: drag `SingleThreadCore` folder into project navigator, then add `SingleThreadCore` to the `SingleThread` target's "Frameworks, Libraries, and Embedded Content"; or hand-edit):

a) **PBXFileReference** — add in `PBXFileReference section`:
```
/* SingleThreadCore */ = {isa = PBXFileReference; lastKnownFileType = folder; path = SingleThreadCore; sourceTree = "<group>"; };
```
Use a unique UUID (generate e.g. `51AA3F10`-range hex).

b) **Add to main PBXGroup** — insert the package reference as a child of the root group (`51AA3ECD302D5C4500960DFC`), after the existing folder refs:
```
/* SingleThreadCore */,
```

c) **PBXFileSystemSynchronizedRootGroup** — add for `SingleThreadCore`:
```
51AA3F10... /* SingleThreadCore */ = {
    isa = PBXFileSystemSynchronizedRootGroup;
    path = SingleThreadCore;
    sourceTree = "<group>";
};
```
And reference it in the main group children.

d) **XCSwiftPackageProductDependency section** — new section:
```
/* Begin XCSwiftPackageProductDependency section */
51AA3F11... /* SingleThreadCore */ = {
    isa = XCSwiftPackageProductDependency;
    productName = SingleThreadCore;
};
/* End XCSwiftPackageProductDependency section */
```

e) **Add to app target `packageProductDependencies`** — in `SingleThread` target (`51AA3ED5`):
```
packageProductDependencies = (
    51AA3F11... /* SingleThreadCore */,
);
```

f) **Add to `SingleThreadTests` target `packageProductDependencies`** — the unit test target does `import SingleThreadCore` directly, so it must link the package too:
```
packageProductDependencies = (
    51AA3F11... /* SingleThreadCore */,
);
```

**Fallback**: If hand-editing the pbxproj proves fragile, open the project in Xcode, use File → Add Package Dependency → Local → select `SingleThreadCore` folder, then add `SingleThreadCore` to the `SingleThread` target's Frameworks phase. Delete `SingleThread/ReminderSkip.swift` in Xcode so Xcode removes the stale synchronized-group membership automatically.

### Verification
#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug -derivedDataPath DerivedData build-for-testing` succeeds (note: `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` is now in the project-level build configs because the global `xcodebuild` flag conflicts with the local package's `-suppress-warnings` — a known Apple bug)
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath DerivedData test-without-building -only-testing:SingleThreadTests` — all 30 tests pass (same count as before)

#### Manual
- [ ] App launches on simulator, reminders load, complete/skip/refresh/All-Done behavior identical to pre-package baseline
- [ ] No duplicate symbol warnings during build

---

## Phase 2: Extract `ReminderStore` (UI-free orchestration)

Pull the EventKit lifecycle + state out of `ContentView` into a shared `@MainActor` observable store. `ContentView` becomes a thin view driving it. Behavior identical; existing injection seams preserved.

### Changes

#### 1. Create ReminderStore
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` (new)
**Action**: create

```swift
import EventKit
import Foundation

@MainActor
@Observable
public final class ReminderStore {
    // MARK: - Public properties

    public private(set) var reminders: [EKReminder] = []
    public private(set) var skippedIDs: Set<String> = []
    public private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    public var visibleReminders: [EKReminder] {
        reminders.filter { !skippedIDs.contains($0.calendarItemIdentifier) }
    }

    /// Hook invoked after every skip/clear mutation — passes the full skip ID array.
    /// Wired by each app layer to push skip-set changes via WatchConnectivity (Phase 4).
    public var onSkipSetChanged: (([String]) -> Void)?

    // MARK: - Init

    /// Production init: uses real EventKit + UserDefaults.
    public init(
        eventStore: EKEventStore = EKEventStore(),
        skipStore: SkippedReminderStore = SkippedReminderStore(),
        loadsReminders: Bool = true
    ) {
        self.eventStore = eventStore
        self.skipStore = skipStore
        self.loadsReminders = loadsReminders
    }

    /// Preview/test init: pre-populate all state, never touches EventKit.
    public init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus
    ) {
        self.loadsReminders = loadsReminders
        self.reminders = reminders
        self.skippedIDs = skippedIDs
        self.authorizationStatus = authorizationStatus
    }

    // MARK: - Public methods

    /// Kicks off authorization + loading. Call from `.task` in the view layer.
    public func start() async {
        guard loadsReminders else { return }
        let current = EKEventStore.authorizationStatus(for: .reminder)
        authorizationStatus = current
        if current == .fullAccess {
            await reload()
        } else {
            await requestAccess()
        }
    }

    public func completeCurrentReminder() async {
        guard let reminder = visibleReminders.first else { return }
        do {
            reminder.isCompleted = true
            try eventStore.save(reminder, commit: true)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await reload()
        } catch {
            print("[\(Date.now.timeIntervalSince1970)] complete error \(error)")
        }
    }

    public func skipCurrentReminder() {
        guard let reminder = visibleReminders.first else { return }
        let fetchedIDs = reminders.map(\.calendarItemIdentifier)
        let updated = ReminderSkipLogic.skipping(
            reminder.calendarItemIdentifier,
            fetched: fetchedIDs,
            skipped: Array(skippedIDs))
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            skippedIDs = Set(updated)
            skipStore.save(updated)
            onSkipSetChanged?(updated)
        }
    }

    public func reload(clearSkipped: Bool = false) async {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: ReminderDateFilter.endOfToday(),
            calendars: nil)
        let fetched: [EKReminder] = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.eventStore.fetchReminders(matching: predicate) { results in
                    continuation.resume(returning: results ?? [])
                }
            }
        }
        reminders = fetched
        if clearSkipped {
            skippedIDs = []
            skipStore.save([])
            onSkipSetChanged?([])
        } else {
            let resolved = ReminderSkipLogic.resolve(
                fetched: fetched.map(\.calendarItemIdentifier),
                skipped: skipStore.load())
            skippedIDs = Set(resolved)
        }
    }

    // MARK: - Private

    private let eventStore: EKEventStore
    private let skipStore: SkippedReminderStore
    private let loadsReminders: Bool

    private func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            if granted {
                authorizationStatus = .fullAccess
                await reload()
            } else {
                authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            }
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        }
    }
}
```

Important: the `ReminderStore` type, init, and public methods need `public` access modifiers since callers are in other modules (the app and watch targets).

#### 2. Refactor ContentView to drive ReminderStore
**File**: `SingleThread/ContentView.swift`
**Action**: modify — replace the body of the file

After the imports and before the preview helpers, replace `ContentView` with a thin view that owns a `@State ReminderStore`:

```swift
struct ContentView: View {
    // MARK: Lifecycle

    init(loadsReminders: Bool = true) {
        _store = State(initialValue: ReminderStore(loadsReminders: loadsReminders))
    }

    /// Pre-populates state for canvas previews.
    init(
        loadsReminders: Bool,
        reminders: [EKReminder],
        skippedIDs: Set<String>,
        authorizationStatus: EKAuthorizationStatus) {
        _store = State(initialValue: ReminderStore(
            loadsReminders: loadsReminders,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: authorizationStatus))
    }

    // MARK: Internal

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if store.loadsReminders {                          // CHANGED: loadsReminders → store.loadsReminders
                authGatedContent
            } else {
                reminderList
            }
        }
        .onAppear {
            print("[\(Date.now.timeIntervalSince1970)] onAppear \(store.authorizationStatus.rawValue)/\(store.reminders.count)")
        }
        .task {
            await store.start()                                // CHANGED: inline logic → store.start()
        }
    }

    // MARK: Private

    @State private var store: ReminderStore                    // CHANGED: 4 @State vars → 1 @State store

    // No loadsReminders property — it's on `store`

    // No visibleReminders, allSkipped computed — replaced with `store.visibleReminders`

    private var allSkipped: Bool {                             // CHANGED: computed from store
        !store.reminders.isEmpty && store.visibleReminders.isEmpty
    }

    @ViewBuilder private var authGatedContent: some View {
        switch store.authorizationStatus {                     // CHANGED: authorizationStatus → store.authorizationStatus
        case .notDetermined:
            ProgressView("Requesting access…")
        case .fullAccess:
            reminderList
        default:
            ContentUnavailableView(
                "Reminders Access",
                systemImage: "lock.shield",
                description: Text("Enable access in Settings to see your reminders."))
        }
    }

    private var reminderList: some View {
        GeometryReader { geometry in
            let viewHeight = geometry.size.height
                - geometry.safeAreaInsets.top
                - geometry.safeAreaInsets.bottom
            if allSkipped {
                ScrollView {
                    ContentUnavailableView(
                        "All Done",
                        systemImage: "checkmark.circle",
                        description: Text("Pull to refresh to see all your reminders again."))
                        .frame(minHeight: viewHeight, alignment: .center)
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await store.reload(clearSkipped: true)     // CHANGED
                }
            } else if store.reminders.isEmpty {                // CHANGED
                ScrollView {
                    ContentUnavailableView(
                        "No Reminders",
                        systemImage: "checklist",
                        description: Text("You don't have any reminders yet."))
                        .frame(minHeight: viewHeight, alignment: .center)
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await store.reload()                       // CHANGED
                }
            } else {
                List {
                    if let reminder = store.visibleReminders.first {  // CHANGED
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.title)
                                .font(.title)
                            if let due = reminder.dueDateComponents?.date {
                                Text(due, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let noteText = ReminderNotesFormatter.format(reminder.notes) {
                                Text(noteText)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            if let url = reminder.url {
                                Link(url.absoluteString, destination: url)
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .frame(minHeight: viewHeight, alignment: .center)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await store.completeCurrentReminder() }  // CHANGED
                            } label: {
                                Label("Complete", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                store.skipCurrentReminder()                     // CHANGED
                            } label: {
                                Label("Skip", systemImage: "circle.slash")
                            }
                            .tint(.orange)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await store.reload()                       // CHANGED
                }
            }
        }
    }
}
```

All private functions (`skipReminder()`, `completeReminder()`, `requestAccess()`, `loadReminders(clearSkipped:)`) are deleted — logic lives in `ReminderStore`.

The previews and `mockReminder` fixture remain exactly as-is in the file.

#### 3. Mark SkippedReminderStore visible
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift`
**Action**: modify — add `public` to `SkippedReminderStore` struct, its `init`, `load()`, and `save()` methods (they're referenced from `ReminderStore` which is in the same module, so technically `internal` is fine — no change needed if both are in `SingleThreadCore`). **No change required**: `ReminderStore` is in the same package target, so `internal` access suffices.

### Verification
#### Automated
- [x] `./scripts/test.sh --unit-only` — unit tests build and pass (4 `ReminderDateFilterTests`, 2 `SingleThreadTests`, 10 `ReminderSkipLogicTests`, 14 `ReminderNotesFormatterTests`)
- [x] `./scripts/test.sh --ui-only` — accessibility audit passes; app renders with `loadsReminders: false` seam intact

#### Manual
- [ ] Complete a reminder — swipe action works, next reminder appears
- [ ] Skip a reminder — skip state persists across app relaunch
- [ ] Pull to refresh "All Done" clears skip list
- [ ] "Requesting access…" → grant → reminders appear flow works on clean install

---

## Phase 3: Watch target + local reminder loop

Add the embedded `SingleThreadWatch` target with a button-based watch UI driving the shared `ReminderStore`. Watch runs its own direct-EventKit loop; skip set stored locally (no sync yet).

### Changes

#### 1. Add watch target to pbxproj
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify — create via Xcode GUI (File → New → Target → watchOS → App, name `SingleThreadWatch`, bundle ID `app.alanvardy.SingleThread.watchkitapp`, embed in `SingleThread`) or hand-edit:

Add these sections/entries:

a) **PBXFileReference** for the watch product:
```
51AA3F20... /* SingleThreadWatch.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SingleThreadWatch.app; sourceTree = BUILT_PRODUCTS_DIR; };
```

b) **PBXFileSystemSynchronizedRootGroup** for watch sources:
```
51AA3F21... /* SingleThreadWatch */ = {isa = PBXFileSystemSynchronizedRootGroup; path = SingleThreadWatch; sourceTree = "<group>"; };
```
Add to main group children.

c) **PBXNativeTarget** `SingleThreadWatch`:
```
51AA3F22... /* SingleThreadWatch */ = {
    isa = PBXNativeTarget;
    buildConfigurationList = 51AA3F2A... /* Build configuration list for PBXNativeTarget "SingleThreadWatch" */;
    buildPhases = (
        51AA3F23... /* Sources */,
        51AA3F24... /* Frameworks */,
        51AA3F25... /* Resources */,
    );
    buildRules = ();
    dependencies = ();
    fileSystemSynchronizedGroups = (
        51AA3F21... /* SingleThreadWatch */,
    );
    name = SingleThreadWatch;
    packageProductDependencies = (
        51AA3F11... /* SingleThreadCore */,
    );
    productName = SingleThreadWatch;
    productReference = 51AA3F20... /* SingleThreadWatch.app */;
    productType = "com.apple.product-type.application";
};
```

d) **PBXContainerItemProxy** + **PBXTargetDependency** — iOS app depends on watch:
```
51AA3F26... /* PBXContainerItemProxy */ = {
    isa = PBXContainerItemProxy;
    containerPortal = 51AA3ECE302D5C4500960DFC /* Project object */;
    proxyType = 1;
    remoteGlobalIDString = 51AA3F22...;
    remoteInfo = SingleThreadWatch;
};
51AA3F27... /* PBXTargetDependency */ = {
    isa = PBXTargetDependency;
    target = 51AA3F22... /* SingleThreadWatch */;
    targetProxy = 51AA3F26... /* PBXContainerItemProxy */;
};
```
Add `51AA3F27...` to the iOS `SingleThread` target's `dependencies` array.

e) **Embed Watch Content** build phase on iOS app — add to `SingleThread` target's `buildPhases`:
```
51AA3F28... /* Embed Watch Content */ = {
    isa = PBXCopyFilesBuildPhase;
    buildActionMask = 2147483647;
    dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
    dstSubfolderSpec = 16;
    files = ();
    runOnlyForDeploymentPostprocessing = 0;
};
```

f) **Build configurations** — Debug + Release for the watch target, key settings:
```
Debug:
    CODE_SIGN_STYLE = Automatic;
    DEVELOPMENT_TEAM = 6NWX2DHB9Q;
    GENERATE_INFOPLIST_FILE = YES;
    INFOPLIST_KEY_NSRemindersFullAccessUsageDescription = "SingleThread needs access to show your reminders.";
    INFOPLIST_KEY_WKWatchOnly = YES;
    MARKETING_VERSION = 1.0;
    PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.SingleThread.watchkitapp;
    PRODUCT_NAME = "$(TARGET_NAME)";
    SDKROOT = watchos;
    SUPPORTED_PLATFORMS = "watchos watchsimulator";
    SWIFT_APPROACHABLE_CONCURRENCY = YES;
    SWIFT_VERSION = 6.0;
    TARGETED_DEVICE_FAMILY = 4;
    WATCHOS_DEPLOYMENT_TARGET = 26.5;
```
(Release same minus `DEBUG` flags).

g) **Add watch to project targets list** and **Products group**.

h) **Build phases** — Sources/Frameworks/Resources for watch target (all empty like the other targets).

**Strong recommendation**: Do this via Xcode GUI to avoid pbxproj UUID mismatches. Steps:
1. File → New → Target → watchOS → App
2. Name: `SingleThreadWatch`, Interface: SwiftUI, Language: Swift
3. Check "Include in SingleThread project"
4. Xcode auto-creates the target, scheme entries, embed phase, and `SingleThreadWatch/` folder
5. Delete the auto-generated `SingleThreadWatchApp.swift` content (we'll replace it)
6. Add `SingleThreadCore` package dependency to the watch target

#### 2. Create watch app entry point
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import SwiftUI

@main
struct SingleThreadWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchReminderView(
                store: ReminderStore(
                    loadsReminders: !ProcessInfo.processInfo.arguments.contains("--ui-testing")))
        }
    }
}
```

#### 3. Create watch reminder view
**File**: `SingleThreadWatch/WatchReminderView.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import SwiftUI

struct WatchReminderView: View {
    // MARK: Lifecycle

    /// Accepts a pre-configured store (production or preview).
    init(store: ReminderStore) {
        self.store = store
    }

    // MARK: Internal

    var body: some View {
        Group {
            switch store.authorizationStatus {
            case .notDetermined:
                ProgressView("Requesting access…")
            case .fullAccess:
                reminderContent
            default:
                Text("Enable Reminders access in Settings")
                    .multilineTextAlignment(.center)
            }
        }
        .task {
            await store.start()
        }
    }

    // MARK: Private

    private let store: ReminderStore

    private var reminderContent: some View {
        Group {
            if store.visibleReminders.isEmpty && !store.reminders.isEmpty {
                VStack {
                    Text("All Done")
                        .font(.headline)
                    Text("Pull down to see all")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let reminder = store.visibleReminders.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reminder.title)
                        .font(.headline)
                        .lineLimit(3)
                    if let due = reminder.dueDateComponents?.date {
                        Text(due, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let noteText = ReminderNotesFormatter.format(reminder.notes) {
                        Text(noteText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack {
                        Button {
                            Task { await store.completeCurrentReminder() }
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle.fill")
                        }
                        .tint(.green)

                        Button {
                            store.skipCurrentReminder()
                        } label: {
                            Label("Skip", systemImage: "circle.slash")
                        }
                        .tint(.orange)
                    }
                }
                .padding()
            } else {
                Text("No Reminders")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

Key design notes:
- Single-reminder display (no `ForEach`), matching the iOS paradigm
- Buttons instead of swipeActions (watchOS has no swipe actions)
- Drives `ReminderStore` directly — same lifecycle as iOS

#### 4. Add watch target to xcscheme
**File**: `SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThread.xcscheme`
**Action**: modify — add a `BuildActionEntry` for the watch target so `xcodebuild -scheme SingleThread build` builds both:

```xml
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="YES" buildForAnalyzing="YES">
    <BuildableReference
        BuildableIdentifier = "primary"
        BlueprintIdentifier = "51AA3F22..."
        BuildableName = "SingleThreadWatch.app"
        BlueprintName = "SingleThreadWatch"
        ReferencedContainer = "container:SingleThread.xcodeproj">
    </BuildableReference>
</BuildActionEntry>
```

### Verification
#### Automated
- [ ] `xcodebuild -scheme SingleThread -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -configuration Debug build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` succeeds
- [ ] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build-for-testing SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` — iOS build still works

#### Manual
- [ ] Launch watch app on a paired watchOS Simulator (Apple Watch Series 11 46mm)
- [ ] Grant Reminders access when prompted
- [ ] See the next incomplete reminder due today-or-earlier
- [ ] Complete button works — reminder marked done, next appears
- [ ] Skip button works — reminder hidden, next appears
- [ ] "All Done" state shown when all are skipped
- [ ] "No Reminders" shown when none exist

---

## Phase 4: WatchConnectivity skip sync

Add `SkippedReminderSyncService` to the package and wire it into both apps so a skip/clear on either device pushes the full skip array. The receiver resolves + re-saves via `ReminderSkipLogic.resolve`.

### Changes

#### 1. Create sync protocol + service
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift` (new)
**Action**: create

```swift
import Foundation

#if os(iOS) || os(watchOS)
import WatchConnectivity

/// Test seam: WCSession is not mockable, so we abstract the calls we need.
public protocol SkipSyncSession: AnyObject {
    func activate()
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
}

extension WCSession: SkipSyncSession {}

/// Pushes and receives the skip-set between phone and watch via WatchConnectivity.
/// Uses `updateApplicationContext` — latest-wins, auto-delivers on (re)connect.
@MainActor
public final class SkippedReminderSyncService: NSObject, WCSessionDelegate {
    // MARK: Lifecycle

    public init(session: any SkipSyncSession, skipStore: SkippedReminderStore) {
        self.session = session
        self.skipStore = skipStore
        super.init()
    }

    // MARK: Public

    public func activate() {
        guard let wcSession = session as? WCSession else { return }
        wcSession.delegate = self
        session.activate()
    }

    /// Push the full skip array to the counterpart.
    public func pushSkipIDs(_ ids: [String]) {
        do {
            try session.updateApplicationContext(["skippedReminderIdentifiers": ids])
        } catch {
            print("[\(Date.now.timeIntervalSince1970)] pushSkipIDs error \(error)")
        }
    }

    // MARK: WCSessionDelegate

    public func session(
        _ wcSession: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let receivedIDs = applicationContext["skippedReminderIdentifiers"] as? [String] else { return }
        // Merge with local IDs; resolve prunes stale entries next time reload runs.
        let localIDs = skipStore.load()
        let merged = Array(Set(localIDs + receivedIDs))
        skipStore.save(merged)
    }

    public func session(_ wcSession: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        if let error {
            print("[\(Date.now.timeIntervalSince1970)] WCSession activation error \(error)")
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ wcSession: WCSession) {}
    public func sessionDidDeactivate(_ wcSession: WCSession) {
        wcSession.activate()
    }
    #endif

    // MARK: Private

    private let session: any SkipSyncSession
    private let skipStore: SkippedReminderStore
}
#endif
```

Notes:
- Guarded `#if os(iOS) || os(watchOS)` — compiles to an empty file on macOS/visionOS.
- `didReceiveApplicationContext` does a simple set-merge of IDs. `reminderSkipLogic.resolve` is not called here because we don't have the fetched IDs at receive time. Instead, the next `reload()` on the receiver naturally prunes stale IDs via `resolve(fetched:skipped:)` which the store already calls. The merge is additive — any extra IDs from the counterpart that don't match local fetched reminders will be pruned on the next reload.
- The `sessionDidBecomeInactive`/`sessionDidDeactivate` are iOS-only delegate requirements.

#### 2. Wire sync into iOS app
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

```swift
import SingleThreadCore
import SwiftUI
import WatchConnectivity                                    // CHANGED: new import

@main
struct SingleThreadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
                loadsReminders: !ProcessInfo.processInfo.arguments.contains("--ui-testing"))
        }
    }

    init() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let syncService = SkippedReminderSyncService(session: session, skipStore: SkippedReminderStore())
        syncService.activate()
        // Wire into the ReminderStore — the ContentView creates its own store,
        // so we set the static onSkipSetChanged hook via an alternate approach:
        // ContentView.init now accepts an optional onSkipSetChanged closure.

        // Alternative: expose the sync service via an environment value or
        // inject it into ContentView's init. See note below.
    }
}
```

**Design note for the implementer**: The cleanest approach is to pass the sync hook through `ContentView`'s init chain. Update `ContentView`'s initializers:

```swift
init(loadsReminders: Bool = true, onSkipSetChanged: (([String]) -> Void)? = nil) {
    _store = State(initialValue: ReminderStore(loadsReminders: loadsReminders))
    __onSkipSetChanged = onSkipSetChanged              // store in a separate Optional
}

init(loadsReminders: Bool, reminders: [EKReminder], skippedIDs: Set<String>, authorizationStatus: EKAuthorizationStatus, onSkipSetChanged: (([String]) -> Void)? = nil) {
    _store = State(initialValue: ReminderStore(loadsReminders: loadsReminders, reminders: reminders, skippedIDs: skippedIDs, authorizationStatus: authorizationStatus))
    __onSkipSetChanged = onSkipSetChanged
}
```

And in `.onAppear` (or a new `.task`), set `store.onSkipSetChanged = onSkipSetChanged`.

Then `SingleThreadApp` becomes:

```swift
@main
struct SingleThreadApp: App {
    private let onSkipSetChanged: (([String]) -> Void)?

    init() {
        if WCSession.isSupported() {
            let syncService = SkippedReminderSyncService(
                session: WCSession.default,
                skipStore: SkippedReminderStore())
            syncService.activate()
            onSkipSetChanged = { [syncService] ids in syncService.pushSkipIDs(ids) }
        } else {
            onSkipSetChanged = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                loadsReminders: !ProcessInfo.processInfo.arguments.contains("--ui-testing"),
                onSkipSetChanged: onSkipSetChanged)
        }
    }
}
```

#### 3. Wire sync into watch app
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify — same pattern as iOS:

```swift
import SingleThreadCore
import SwiftUI
import WatchConnectivity

@main
struct SingleThreadWatchApp: App {
    private let onSkipSetChanged: (([String]) -> Void)?

    init() {
        if WCSession.isSupported() {
            let syncService = SkippedReminderSyncService(
                session: WCSession.default,
                skipStore: SkippedReminderStore())
            syncService.activate()
            onSkipSetChanged = { [syncService] ids in syncService.pushSkipIDs(ids) }
        } else {
            onSkipSetChanged = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchReminderView(
                store: ReminderStore(
                    loadsReminders: !ProcessInfo.processInfo.arguments.contains("--ui-testing")))
                // Note: WatchReminderView also needs the hook wired.
        }
    }
}
```

**Note**: `WatchReminderView` also needs to wire `onSkipSetChanged`. Update its init to accept the closure or set it on the store after construction. Simplest: set `store.onSkipSetChanged = onSkipSetChanged` in the `SingleThreadWatchApp.body` before passing to `WatchReminderView`.

#### 4. Update ContentView init chain
**File**: `SingleThread/ContentView.swift`
**Action**: modify — add `onSkipSetChanged` parameter to both initializers and wire into the store.

Changes applied inline with Phase 2's already-refactored ContentView.

#### 5. Update WatchReminderView if needed
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify — pass through `onSkipSetChanged` or expose a method to set it on the store. The simplest approach: in `SingleThreadWatchApp`, assign `store.onSkipSetChanged = onSkipSetChanged` after creating the store but before passing it to the view:

```swift
var body: some Scene {
    WindowGroup {
        let store = ReminderStore(
            loadsReminders: !ProcessInfo.processInfo.arguments.contains("--ui-testing"))
        store.onSkipSetChanged = onSkipSetChanged
        WatchReminderView(store: store)
    }
}
```

#### 6. Add unit tests for sync service
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift` (new)
**Action**: create

```swift
import SingleThreadCore
import Testing

// MARK: - Fake session for testing

private final class FakeSession: SkipSyncSession {
    var activated = false
    var lastContext: [String: Any]?
    var pushShouldThrow = false

    func activate() { activated = true }
    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        if pushShouldThrow { throw NSError(domain: "test", code: 1) }
        lastContext = applicationContext
    }
}

@MainActor
struct SkippedReminderSyncServiceTests {
    @Test
    func activateSetsDelegateAndActivates() {
        let fake = FakeSession()
        let store = SkippedReminderStore(defaults: .standard, key: "test-sync-activate")
        let service = SkippedReminderSyncService(session: fake, skipStore: store)
        service.activate()
        #expect(fake.activated)
    }

    @Test
    func pushSkipIDsUpdatesApplicationContext() throws {
        let fake = FakeSession()
        let store = SkippedReminderStore(defaults: .standard, key: "test-sync-push")
        let service = SkippedReminderSyncService(session: fake, skipStore: store)
        service.pushSkipIDs(["A", "B", "C"])
        let context = try #require(fake.lastContext)
        let ids = try #require(context["skippedReminderIdentifiers"] as? [String])
        #expect(Set(ids) == ["A", "B", "C"])
    }

    @Test
    func pushSkipIDsHandlesError() {
        let fake = FakeSession()
        fake.pushShouldThrow = true
        let store = SkippedReminderStore(defaults: .standard, key: "test-sync-push-error")
        let service = SkippedReminderSyncService(session: fake, skipStore: store)
        // Should not crash/throw — error is logged internally
        service.pushSkipIDs(["A"])
        #expect(Bool(true)) // reached without crashing
    }

    @Test
    func receiveContextMergesIDs() {
        let fake = FakeSession()
        let key = "test-sync-receive-\(UUID().uuidString)"
        let store = SkippedReminderStore(defaults: .standard, key: key)
        // Pre-populate local store with ["A"]
        store.save(["A"])
        let service = SkippedReminderSyncService(session: fake, skipStore: store)
        // Simulate receiving ["B", "C"] from counterpart
        service.session(WCSession.default, didReceiveApplicationContext: ["skippedReminderIdentifiers": ["B", "C"]])
        let saved = store.load()
        #expect(Set(saved) == ["A", "B", "C"])
    }

    @Test
    func receiveContextHandlesEmptyPayload() {
        let fake = FakeSession()
        let key = "test-sync-receive-empty-\(UUID().uuidString)"
        let store = SkippedReminderStore(defaults: .standard, key: key)
        store.save(["A"])
        let service = SkippedReminderSyncService(session: fake, skipStore: store)
        service.session(WCSession.default, didReceiveApplicationContext: [:])
        #expect(store.load() == ["A"]) // unchanged
    }

    @Test
    func receiveContextHandlesMalformedPayload() {
        let fake = FakeSession()
        let key = "test-sync-receive-bad-\(UUID().uuidString)"
        let store = SkippedReminderStore(defaults: .standard, key: key)
        store.save(["A"])
        let service = SkippedReminderSyncService(session: fake, skipStore: store)
        service.session(WCSession.default, didReceiveApplicationContext: ["wrongKey": 42])
        #expect(store.load() == ["A"]) // unchanged
    }
}
```

Test uses unique `UserDefaults` keys per test to avoid leakage between parallel executions.

### Verification
#### Automated
- [ ] `./scripts/test.sh --unit-only` — all tests pass including the 6 new `SkippedReminderSyncServiceTests`

#### Manual
- [ ] **Hardware required**: Pair Apple Watch with iPhone
- [ ] Skip a reminder on iPhone → after a brief WatchConnectivity round-trip, the same reminder appears as skipped on the watch
- [ ] Skip a reminder on watch → after a round-trip, the same reminder appears as skipped on iPhone
- [ ] Clear all skips ("All Done" pull-to-refresh on iPhone) → watch also clears

---

## Phase 5: CI & pipeline integration

Fold the watch build, package, and watch folder into the existing build/test/lint tooling.

### Changes

#### 1. Makefile
**File**: `Makefile`
**Action**: modify

Add watch build target and extend lint/format scopes:

```makefile
WATCH_SIM := platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)
SIM := platform=iOS Simulator,name=iPhone 17
DERIVED_DATA := DerivedData

.PHONY: build test ui-test check clean lint format periphery watch-build

build:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build-for-testing SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

watch-build:
	xcodebuild -scheme SingleThread -destination '$(WATCH_SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

# ... test, ui-test, check, clean unchanged ...

lint:
	swiftformat --lint SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadTests/ SingleThreadUITests/
	swiftlint lint --strict

format:
	swiftformat SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadTests/ SingleThreadUITests/
	swiftlint --fix

periphery:
	periphery scan --strict -- -destination "platform=iOS Simulator,name=iPhone 17"
```

Note: `periphery` destination stays iPhone-only (Periphery indexes the iOS build; the watch source is in the package which the iOS build compiles). The `SingleThreadWatch/` folder is included in the report scope via `.periphery.yml` (see below).

#### 2. scripts/test.sh
**File**: `scripts/test.sh`
**Action**: modify

In the full pipeline, after formatting and before Periphery, add a watch build step:

```bash
# (after SwiftLint, before Periphery)
echo ""
echo "==> Watch build…"
xcodebuild -scheme "$SCHEME" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```

Extend the format/lint file lists to include `SingleThreadCore/` and `SingleThreadWatch/`:

```bash
swiftformat SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadTests/ SingleThreadUITests/
swiftformat --lint SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadTests/ SingleThreadUITests/
```

#### 3. .github/workflows/ci.yml
**File**: `.github/workflows/ci.yml`
**Action**: modify

a) **Lint job** — extend SwiftFormat check and SwiftLint dirs:

```yaml
- name: SwiftFormat check
  timeout-minutes: 5
  run: swiftformat --lint SingleThread/ SingleThreadCore/ SingleThreadWatch/ SingleThreadTests/ SingleThreadUITests/

- name: SwiftLint
  timeout-minutes: 5
  run: swiftlint lint --strict
```

b) **Cache keys** — add `SingleThreadCore/**` and `SingleThreadWatch/**` to `hashFiles` in both `unit-tests` and `ui-tests` jobs:

```yaml
key: derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ github.ref_name }}-${{ hashFiles('SingleThread/**', 'SingleThreadTests/**', 'SingleThreadUITests/**', 'SingleThreadCore/**', 'SingleThreadWatch/**', 'SingleThread.xcodeproj/project.pbxproj') }}
```

c) **Add watch build step** to the lint job (before Periphery), or add a separate `watch-build` job. To keep things simple, add to the lint job since it already does a Periphery build:

```yaml
- name: Watch build
  timeout-minutes: 15
  run: |
    xcodebuild -scheme SingleThread \
      -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" \
      -configuration Debug \
      build \
      SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
      -showBuildTimingSummary
```

d) **Watch simulator pre-boot** — pre-boot a watch simulator before the watch build (same pattern as iPhone):

```yaml
- name: Pre-boot watch simulator
  run: |
    WATCH_UDID=$(xcrun simctl list devices available | grep 'Apple Watch Series 11 (46mm) (' | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    xcrun simctl boot "$WATCH_UDID" || true
```

#### 4. .swiftlint.yml
**File**: `.swiftlint.yml`
**Action**: modify — add `SingleThreadCore` and `SingleThreadWatch` to the `included` list:

```yaml
included:
  - SingleThread
  - SingleThreadCore
  - SingleThreadWatch
  - SingleThreadTests
  - SingleThreadUITests
```

Also add a test-specific disabler for `SingleThreadWatch/` if needed (no UI tests on watch, so `force_unwrapping` is not needed disabled there).

#### 5. .swiftformat
**File**: `.swiftformat`
**Action**: modify — no file-scope change needed (the `format` target in the Makefile already lists the new dirs explicitly; the `.swiftformat` config applies to all files). No change required.

#### 6. .periphery.yml
**File**: `.periphery.yml`
**Action**: modify — add the watch folder to the exclusion-allowlist (Periphery currently excludes `SingleThreadUITests/**`; keep that, but ensure `SingleThreadWatch/` is scanned):

```yaml
report_exclude:
  - "**/SingleThreadUITests/**"
```

No other change — Periphery already scans the whole index store, and the watch sources are compiled by the watch target (which feeds the same index store).

### Verification
#### Automated
- [ ] `./scripts/test.sh` — full pipeline exits 0: format, SwiftFormat check, SwiftLint, iOS build, watch build, Periphery, unit tests, UI tests
- [ ] `make lint` — zero warnings in `SingleThreadCore/` and `SingleThreadWatch/`
- [ ] `make watch-build` — succeeds

#### Manual
- [ ] Verify CI YAML is valid: `yamllint .github/workflows/ci.yml` or GitHub Actions editor
- [ ] Check that the watch simulator name (`Apple Watch Series 11 (46mm)`) is available on the CI runner image (`macos-26`)

---

## Implementation Order & Checkpoints

- **Phase 1 gate**: Package builds + all tests green + app unchanged. Commit.
- **Phase 2 gate**: Store extraction done + all tests green + app unchanged. Commit.
- **Phase 3 gate**: Watch target builds + manual smoke test passes. Commit.
- **Phase 4 gate**: Sync service tests green + hardware round-trip verified. Commit.
- **Phase 5 gate**: `./scripts/test.sh` exits 0 end-to-end. Commit.
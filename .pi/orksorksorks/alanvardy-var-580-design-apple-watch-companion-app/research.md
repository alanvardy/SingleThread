# Research Findings

All line references are relative to the git root
(`/Users/vardy/dev/alanvardy-var-578-add-an-apple-watch-app`). The project is a
single `SingleThread.xcodeproj` with three targets and no watch support of any
kind today.

## Q1: Platforms, device families, bundle IDs, signing, and target structure

### Findings
- Project uses `objectVersion = 77` and filesystem-synchronized root groups
  (`PBXFileSystemSynchronizedRootGroup`), so there are **no `PBXBuildFile` /
  per-source `PBXFileReference` entries** — source membership is implicit by
  folder. `project.pbxproj:6` (objectVersion), `:32-48` (three synchronized
  groups `SingleThread` / `SingleThreadTests` / `SingleThreadUITests`).
- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"`
  on all three targets (Debug + Release):
  `project.pbxproj:421, 466, 492, 518, 543, 568`. **No `watchos`/`watchsimulator`**
  anywhere (`grep -i watch` on the pbxproj is empty).
- `TARGETED_DEVICE_FAMILY = "1,2,7"` (iPhone=1, iPad=2, visionOS=7) on all
  targets: `project.pbxproj:427, 472, 497, 523, 548, 573`. Watch family `4` is
  absent.
- Deployment targets are all `26.5`: `IPHONEOS_DEPLOYMENT_TARGET`
  (`:411, 456, 485, 511, 536, 561`), `MACOSX_DEPLOYMENT_TARGET`
  (`:414, 459, 486, 512, 537, 562`), `XROS_DEPLOYMENT_TARGET`
  (`:428, 473, 499, 525, 550, 575`). No `WATCHOS_DEPLOYMENT_TARGET`.
- Bundle IDs: `app.alanvardy.SingleThread` (`:416, 461`),
  `app.alanvardy.SingleThreadTests` (`:488, 514`),
  `app.alanvardy.SingleThreadUITests` (`:539, 564`).
  `GENERATE_INFOPLIST_FILE = YES` everywhere — no `.plist` files on disk.
- Code signing: `CODE_SIGN_STYLE = Automatic` (`:392, 437, 481, 507, 532, 557`),
  `DEVELOPMENT_TEAM = 6NWX2DHB9Q` at project level (`:306, 368`) and per-target
  (`:394, 439, 483, 509, 534, 559`). **No `CODE_SIGN_ENTITLEMENTS` setting and
  no `.entitlements` file exists.** `REGISTER_APP_GROUPS = YES` is set on the
  app target only (`:418, 463`) but is unbacked by any group ID or entitlement.
- Three `PBXNativeTarget`s — `SingleThread` (`com.apple.product-type.application`,
  `:118`), `SingleThreadTests` (`bundle.unit-test`, `:141`), `SingleThreadUITests`
  (`bundle.ui-testing`, `:164`). Test targets depend on the app via
  `PBXTargetDependency` (`:258-267`); unit tests are hosted (`TEST_HOST` `:498, 524`),
  UI tests use `TEST_TARGET_NAME = SingleThread` (`:549, 574`).
- Target↔source wiring: each target binds exactly one synchronized folder via
  `fileSystemSynchronizedGroups` (`:110-112` app→`SingleThread`,
  `:133-135` tests→`SingleThreadTests`, `:156-158` uitests→`SingleThreadUITests`).
  Source `Sources` build phases are empty (`files = ()`, `:233-255`).
- How a file becomes available to >1 target: currently there is **no** shared
  folder, no second synchronized group on any target, and no per-file membership —
  a file is compiled by exactly the target whose folder it resides in. The only
  cross-target access mechanism in use is `@testable import SingleThread`
  (`SingleThreadTests/SingleThreadTests.swift:1`,
  `SingleThreadTests/ReminderSkipTests.swift:1`).
- Scheme: single shared scheme `SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThread.xcscheme`
  builds/runs `SingleThread` and lists `SingleThreadTests` + `SingleThreadUITests`
  as testables.

## Q2: Scene and entry-point structure

### Findings
- `@main struct SingleThreadApp: App` — `SingleThread/SingleThreadApp.swift:3-4`.
- Single `Scene` via `var body: some Scene` wrapping a `WindowGroup` —
  `SingleThreadApp.swift:5-6`.
- Root view is `ContentView`, constructed with
  `loadsReminders: !ProcessInfo.processInfo.arguments.contains("--ui-testing")` —
  `SingleThreadApp.swift:7-8`.
- No `ModelContainer`, `.modelContainer(...)`, `@Environment`, `@StateObject`,
  `AppStorage`, or SwiftData import exist in app source. The app is a plain
  SwiftUI `App`-lifecycle window with no SwiftData. (Note: `AGENTS.md:48-53`
  describes a SwiftData `Item` `@Model` + `ModelContainer` that does **not**
  exist in code — see Cross-Cutting Observations.)
- `ContentView` is a value-type `View` (`SingleThread/ContentView.swift:20`)
  holding state in `@State` (`:70-72`) plus stored `let`s `loadsReminders`,
  `store = EKEventStore()`, `skipStore = SkippedReminderStore()` (`:74-76`).
- Two initializers: default `init(loadsReminders: Bool = true)` (`:23-25`) and a
  preview/test pre-populating `init(loadsReminders:reminders:skippedIDs:authorizationStatus:)`
  that seeds `@State` via underscored bindings (`:28-37`).
- Lifecycle hooks are `.onAppear` (`ContentView.swift:50`) and `.task`
  (`ContentView.swift:53`); `.task` short-circuits with
  `guard loadsReminders else { return }` (`:54`).

## Q3: "Skipped reminders" persistence and App Group / sync configuration

### Findings
- `SkippedReminderStore` — `SingleThread/ReminderSkip.swift:54`.
  - `init(defaults: UserDefaults = .standard, key: String = "skippedReminderIdentifiers")`
    (`:57`) → targets **`UserDefaults.standard`**, key `"skippedReminderIdentifiers"`.
  - `load() -> [String]` reads `defaults.stringArray(forKey: key) ?? []` (`:64-66`).
  - `save(_ identifiers: [String])` writes `defaults.set(identifiers, forKey: key)`
    (`:68-70`).
- Single instantiation: `private let skipStore = SkippedReminderStore()` at
  `ContentView.swift:76`. No `suiteName` / `UserDefaults(suiteName:)` anywhere.
- Call sites (all in `ContentView.swift`): read on load via
  `ReminderSkipLogic.resolve(..., skipped: skipStore.load())` (`:245-247`); write on
  skip (`skipStore.save(updated)` `:194`); clear via `skipStore.save([])` (`:243`)
  and on the "All Done" pull-to-refresh (`:116`).
- **No App Group, no entitlements, no container/synchronization config exists.**
  Verified absences: no `.entitlements` file, no `CODE_SIGN_ENTITLEMENTS`,
  no `suiteName`, no `NSUbiquitous*`, no `CKContainer`, no `application-groups`
  entitlement. The only related marker is the unbacked `REGISTER_APP_GROUPS = YES`
  build setting (`project.pbxproj:418, 463`).
- Persistence is therefore local-only, per-device, via `UserDefaults.standard`.

## Q4: ContentView rendering, interaction, and EventKit patterns

### Findings
- `extension EKReminder: @retroactive @unchecked Sendable {}` —
  `ContentView.swift:4` (Swift 6 retroactive, unchecked).
- Layout primitives: root `ZStack` over `Color(.systemBackground).ignoresSafeArea()`
  (`:42-43`); `GeometryReader` computing `viewHeight` (`:102-105`); two
  `ScrollView` branches for all-skipped (`:107`) and empty (`:119`); a `List`
  with a single `VStack` row driven by `visibleReminders.first` (`:131-133` — no
  `ForEach`; single-reminder-at-a-time); three `ContentUnavailableView`s
  (`:94-97` "Reminders Access", `:108-111` "All Done", `:120-123` "No Reminders").
- Interactions: leading `swipeActions` "Complete" → `Task { await completeReminder() }`
  (`:158-165`); trailing `swipeActions` "Skip" → `skipReminder()` (`:166-173`);
  three `.refreshable` modifiers (`:115-117`, `:127-129`, `:177-179`).
- `.task` (`:53-65`) reads `EKEventStore.authorizationStatus(for: .reminder)`,
  sets `authorizationStatus`, then `loadReminders()` on `.fullAccess` else
  `requestAccess()`.
- EventKit patterns:
  - Authorization: `try await store.requestFullAccessToReminders()` in
    `requestAccess()` (`:210-225`).
  - Fetch: `store.predicateForIncompleteReminders(withDueDateStarting: nil,
    ending: ReminderDateFilter.endOfToday(), calendars: nil)` (`:229-232`) then
    `store.fetchReminders(matching:)` wrapped in `withCheckedContinuation` +
    `DispatchQueue.main.async` (`:233-239`).
  - Complete: `reminder.isCompleted = true; try store.save(reminder, commit: true)`
    (`:201-202`).
- `ReminderDateFilter.endOfToday()` (nonisolated enum, `:7-18`) returns the last
  instant of today; incomplete reminders due today-or-earlier only.
- Skip flow: `skipReminder()` (`:184-196`) computes via `ReminderSkipLogic.skipping`,
  then updates state + persists inside an unstructured `Task` after a 200 ms sleep.

## Q5: Pure-logic components, dependencies, tests, reusability

### Findings
- `ReminderSkipLogic` (nonisolated enum) — `ReminderSkip.swift:5`; `resolve`
  (`:12-15`), `skipping` (`:19-24`). Only `Foundation` (`Set`/`Array`/`String`).
- `ReminderNotesFormatter` (nonisolated enum) — `ReminderSkip.swift:28`; `format`
  (`:32-41`), private `leadingPrefixChars` containing only `"t"` (`:46-50`).
  Only `Foundation` (`String`/`CharacterSet`).
- `SkippedReminderStore` (plain struct) — `ReminderSkip.swift:54`; `load`/`save`
  (`:64-70`). Only `Foundation` (`UserDefaults`).
- `ReminderDateFilter` (nonisolated enum) — `ContentView.swift:7`; `endOfToday`
  (`:9-18`). Only `Foundation` (`Calendar`/`Date`), but it physically lives in
  `ContentView.swift`, which imports `EventKit` and `SwiftUI` (`:1-2`).
- Reusability traits: the three enums + store are `nonisolated`, have no
  `@MainActor`, and import only `Foundation` — no UIKit/SwiftUI/EventKit/AppKit.
  There is **no** shared framework/package target; reuse outside the app target
  would require moving these files (or adding a shared target).
- Unit tests (Swift Testing, `import Testing`):
  - `ReminderSkipLogicTests` (5 `resolve` + 5 `skipping`) and
    `ReminderNotesFormatterTests` (15 `format`) — `ReminderSkipTests.swift:4-95`
    and `:97-173`. No `@MainActor`; no EventKit.
  - `ReminderDateFilterTests` (4 tests, fixed UTC calendar) —
    `SingleThreadTests/SingleThreadTests.swift:25-66`.
  - `@MainActor struct SingleThreadTests` exercises `ContentView(loadsReminders: false)`
    body rendering — `SingleThreadTests/SingleThreadTests.swift:6-22`.
  - `SkippedReminderStore` itself has **no** tests.

## Q6: Build / test / lint pipeline

### Findings
- `Makefile`: `SIM := platform=iOS Simulator,name=iPhone 17` (`Makefile:1`); targets
  `build` (`:6-7`), `test` → `scripts/test.sh --unit-only` (`:9-10`), `ui-test`
  (`:12-13`), `check` → full pipeline (`:15-16`), `clean` (`:18-19`), `lint`
  (`:21-23`), `format` (`:25-27`), `periphery` (`:29-30`). `build` passes
  `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`.
- `scripts/test.sh` (bash, `set -euo pipefail`): `SIM`/`SCHEME`/`DERIVED_DATA`
  at `:5-7`; full mode runs format → SwiftFormat check → SwiftLint `--strict` →
  `build-for-testing` → Periphery (`--skip-build --index-store-path`) → unit tests
  (`-only-testing:SingleThreadTests`) → UI tests (`-only-testing:SingleThreadUITests`)
  (`:26-74`); `--unit-only` (`:76-99`) and `--ui-only` (`:101-120`) branches.
  `-parallel-testing-enabled YES` throughout.
- `.github/workflows/ci.yml`: three jobs — `unit-tests` (`:14`), `ui-tests`
  (`:74`), `lint` (`:126`), all `runs-on: macos-26` with `setup-xcode` `26.6`.
  `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on all xcodebuild invocations (`:52, 63,
  112, 123`). Simulator pre-boot greps `iPhone 17 (` (`:40, 100`). CI blanks
  `DEVELOPMENT_TEAM` (`:27-28, 87-88`). Lint job runs swiftformat `--lint`,
  `swiftlint lint --strict`, `periphery scan --strict` (`:147-157`).
- Warning settings: `SWIFT_TREAT_WARNINGS_AS_ERRORS` is **not** in `project.pbxproj`;
  it is applied only as a CLI override (Makefile/`test.sh`/ci.yml).
- Concurrency settings: `SWIFT_VERSION = 6.0` (`project.pbxproj:426, 471, 496, 522,
  547, 572`), `SWIFT_APPROACHABLE_CONCURRENCY = YES` (`:422, ...`),
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (app target only, `:423, 468`).
- Toolchain pinned in `.mise.toml` (swiftlint `0.65.0`, swiftformat `0.62.1`,
  periphery `3.8.0`); `.swift-version` = `6.0`.
- Watch fit: there is **no** watch target, scheme, platform, or simulator
  destination today. Contact points that currently hardcode target/destination/
  filter/lint-scope: `Makefile:1`, `scripts/test.sh:5-6`, `ci.yml:17, 77` (+
  pre-boot `:40, 100`), `-only-testing` filters (`scripts/test.sh:59, 68, 84, 93,
  108, 117`; `ci.yml:51, 62, 111, 122`), lint dir lists (`Makefile:22, 26`,
  `ci.yml:149`, `.swiftlint.yml:2-5`, `.swiftformat:21`), scheme testables
  (`SingleThread.xcscheme`, `shouldAutocreateTestPlan = YES`), target registration
  (`project.pbxproj:201-206`), and CI cache key hashing (`ci.yml:33, 93`).

## Q7: How tests avoid EventKit prompts; fixtures and previews

### Findings
- UI tests: `app.launchArguments = ["--ui-testing"]` at
  `SingleThreadUITests/SingleThreadUITests.swift:19`; the app reads the same flag
  and injects `loadsReminders: false` (`SingleThreadApp.swift:8`).
- `loadsReminders == false` short-circuits **all** EventKit work: body renders
  `reminderList` instead of `authGatedContent` (`ContentView.swift:44-48`) and
  `.task` returns before any EventKit call (`ContentView.swift:54`). This is the
  only prompt-suppression mechanism; no `launchEnvironment` anywhere.
- Unit tests use constructor injection, not launch args:
  `ContentView(loadsReminders: false)` at
  `SingleThreadTests/SingleThreadTests.swift:9, 17`. Pure-logic tests touch no
  EventKit at all (`ReminderSkipTests.swift`).
- `SingleThreadUITestsLaunchTests.swift:22` calls `app.launch()` with **no**
  launch arguments (does not suppress the EventKit path; screenshot-only).
- Inaccuracy in the UI-test comment: `SingleThreadUITests.swift:21-24` claims the
  app shows `ProgressView("Requesting access…")`, but with `loadsReminders: false`
  the app renders `reminderList` → "No Reminders" (`ContentView.swift:120-123`).
- `EKReminder` fixture: the single `mockReminder` at `ContentView.swift:256-265`
  constructs `EKReminder(eventStore: EKEventStore())` and sets `title`,
  `dueDateComponents`, `notes`, `url`. No `EKReminder` fixtures exist in test
  targets.
- Previews: four `#Preview` blocks at `ContentView.swift:268-294` ("Empty",
  "With Reminder", "All Skipped", "No Access"), all driven by the
  dependency-injected initializer (`:28-37`) and `mockReminder`.
- Reminders usage string: `INFOPLIST_KEY_NSRemindersUsageDescription` at
  `project.pbxproj:400, 445`.

## Cross-Cutting Observations
- **Docs/code mismatch:** `AGENTS.md:48-53` describes a SwiftData `Item` `@Model`,
  `ModelContainer`, and `@Query`-driven `ContentView`; the actual app uses
  EventKit (`EKEventStore`/`EKReminder`) and has no SwiftData. `AGENTS.md:19-25`
  also says `.modelContainer(for: Item.self, inMemory: true)` is used in
  previews/tests, which is not present in code.
- **No watch footprint:** no `watchos` platform, no family `4`, no watch target/
  scheme/folder/destination, no `WATCHOS_DEPLOYMENT_TARGET`.
- **No cross-device sync:** persistence is `UserDefaults.standard`; the only
  App-Group-adjacent artifact is the unbacked `REGISTER_APP_GROUPS = YES`.
- Pure logic (`ReminderSkipLogic`, `ReminderNotesFormatter`, `ReminderDateFilter`,
  `SkippedReminderStore`) is Foundation-only and `nonisolated` — no
  iOS-specific framework dependency — but everything lives in the single app
  target's synchronized folder; there is no shared target today.
- Single-reminder-at-a-time UI (no `ForEach`; `visibleReminders.first`).
- Warnings-as-errors is enforced only via CLI flags, not in the project file.

## Open Areas
- The `SkippedReminderStore` persistence wrapper has no unit tests (only
  `ReminderSkipLogic`, `ReminderNotesFormatter`, `ReminderDateFilter`, and
  `ContentView` are tested).
- `ReminderDateFilter` lives in `ContentView.swift` (which imports `EventKit`
  and `SwiftUI`), so extracting it into a shared target would require moving it
  out of that file — a factual constraint, not a recommendation.
- The UI-test comment (`SingleThreadUITests.swift:21-24`) describing the
  "Requesting access…" ProgressView does not match the actual
  `loadsReminders: false` rendering path.
- No findings describe what `mockReminder`'s `calendarItemIdentifier` resolves to
  for an unsaved `EKReminder` (used by the "All Skipped" preview), which was not
  verifiable from static source.

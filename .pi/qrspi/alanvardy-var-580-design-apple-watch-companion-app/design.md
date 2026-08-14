# Design Discussion — Apple Watch Companion App

## Current State

SingleThread is a single `SingleThread.xcodeproj` (`objectVersion = 77`,
`project.pbxproj:6`) with three targets — app, unit tests, UI tests — each bound
to one filesystem-synchronized folder (`project.pbxproj:110-112, 133-135,
156-158`). There is **no watch footprint**: no `watchos` platform
(`SUPPORTED_PLATFORMS` at `project.pbxproj:421, 466, 492, 518, 543, 568`), no
`TARGETED_DEVICE_FAMILY` value `4` (only `1,2,7`, `project.pbxproj:427`), no
`WATCHOS_DEPLOYMENT_TARGET`, and no `.entitlements` file anywhere. Bundle ID is
`app.alanvardy.SingleThread` (`project.pbxproj:416`); all deployment targets are
`26.5`.

The app is a SwiftUI `App`-lifecycle window: `@main struct SingleThreadApp: App`
→ `WindowGroup` → `ContentView` (`SingleThread/SingleThreadApp.swift:3-8`), with
`loadsReminders` injected from a `--ui-testing` launch arg (`:7-8`). No SwiftData
exists despite `AGENTS.md:48-53` (known doc/code mismatch).

`ContentView` (`SingleThread/ContentView.swift`) holds the entire feature: a
single-reminder-at-a-time `List` (`:131-133`), Complete/Skip `swipeActions`
(`:158-173`), `.refreshable` + `.task` lifecycle (`:53-65`, `:115-117`), and all
EventKit orchestration — authorization (`:210-225`), fetch via
`predicateForIncompleteReminders(ending: ReminderDateFilter.endOfToday())`
(`:229-239`), complete (`:201-203`), skip (`:184-196`).

The "skipped reminders" list lives in `SkippedReminderStore`
(`SingleThread/ReminderSkip.swift:54`), a thin wrapper over
`UserDefaults.standard` key `"skippedReminderIdentifiers"` (`:57`, `:64-70`),
instantiated once at `ContentView.swift:76`. No App Group or any cross-device
sync exists (`REGISTER_APP_GROUPS = YES` at `project.pbxproj:418, 463` is
unbacked by any entitlement).

Pure logic — `ReminderSkipLogic` (`ReminderSkip.swift:5`),
`ReminderNotesFormatter` (`:28`), `ReminderDateFilter`
(`ContentView.swift:7-18`), `SkippedReminderStore` — is Foundation-only and
`nonisolated`, but all of it lives in the app-only synchronized folder; there is
no shared target/package. `ReminderDateFilter` is physically inside
`ContentView.swift` (which imports EventKit + SwiftUI), a constraint on extraction.

Tests: Swift Testing unit suites (`ReminderSkipTests.swift:4-95, 97-173`;
`SingleThreadTests.swift:25-66`) and XCTest UI tests; EventKit prompts are
suppressed via `loadsReminders: false` (constructor injection + `--ui-testing`
arg, `SingleThreadUITests.swift:19`). Build runs through `Makefile:1`,
`scripts/test.sh`, `.github/workflows/ci.yml`, with `SWIFT_TREAT_WARNINGS_AS_ERRORS`
as a CLI-only override and Periphery/SwiftLint/SwiftFormat in `--strict` mode.

## Desired End State

An embedded watchOS companion app — new `SingleThreadWatch` target, bundle ID
`app.alanvardy.SingleThread.watchkitapp` — that runs the same reminder loop as
the phone: show the next incomplete reminder due today-or-earlier, complete it,
or skip it. The watch queries EventKit **directly** (untethered from the phone)
using the same `ReminderDateFilter` + `ReminderSkipLogic` + `SkippedReminderStore`
pipeline. The skip set (app-private state) is reconciled between iPhone and watch
via WatchConnectivity; reminder completion itself already syncs through the
user's Reminders account (iCloud/Exchange) and is **not** re-synced by us.

Verification: (1) watch target builds for `platform=watchOS Simulator`; (2) the
shared logic stays covered by the existing unit suites (now importing the
package); (3) a skip performed on either device appears on the other after a
WatchConnectivity round-trip; (4) full `./scripts/test.sh` passes.

## Patterns to Follow

- **Pure logic stays `nonisolated` + Foundation-only** (`ReminderSkip.swift:5-70`,
  `ContentView.swift:7-18`). These are the files the package will own, unchanged
  in semantics. `ReminderDateFilter` must be **moved out** of `ContentView.swift`
  (it currently imports EventKit/SwiftUI only incidentally — `ContentView.swift:1-2`).
- **`SkippedReminderStore` as the single persistence seam** (`ReminderSkip.swift:57`)
  — keep the `UserDefaults` key/init signature; both devices keep their own local
  `UserDefaults.standard` copy and reconcile through sync. Do **not** introduce
  `UserDefaults(suiteName:)`/App Groups (they don't cross devices).
- **Dependency injection for testability**: `loadsReminders: Bool` + the
  pre-populating `init(loadsReminders:reminders:skippedIDs:authorizationStatus:)`
  (`ContentView.swift:23-37`) and `--ui-testing` arg (`SingleThreadApp.swift:8`)
  are the established seams; the extracted store must preserve equivalent seams.
- **Single-reminder-at-a-time UI** (`ContentView.swift:131-133`) — carry this to
  the watch (no `ForEach`).
- **Warnings-as-errors via CLI, not pbxproj** (`Makefile`, `scripts/test.sh`,
  `ci.yml`) — new targets inherit this by being built through the same paths.

**Anti-patterns to avoid** (found in research):
- The unbacked `REGISTER_APP_GROUPS = YES` (`project.pbxproj:418, 463`) — don't
  copy this to the watch; either remove it or back it with a real entitlement,
  but App Groups are *not* the sync mechanism.
- `AGENTS.md:48-53`'s SwiftData description — does not match code; do not follow
  it when writing watch/package code.
- The stale UI-test comment claiming `ProgressView("Requesting access…")`
  (`SingleThreadUITests.swift:21-24`) — correct it while touching the test file.
- Copying pure-logic files into the watch folder (drift risk) — the package is
  the single source of truth.

## Design Decisions

1. **Watch data source — direct EventKit.** The watch runs its own
   `EKEventStore` flow (`requestFullAccessToReminders`, `predicateForIncompleteReminders`,
   `fetchReminders`, `isCompleted = true; save`), mirroring
   `ContentView.swift:201-247`. Works untethered; requires a separate Reminders
   prompt on the watch and `NSRemindersFullAccessUsageDescription` in the watch
   Info.plist (EventKit's full-access API needs watchOS 10+).

2. **Skip-list sync — WatchConnectivity.** One `WCSession` per device; on every
   skip/clear mutation, push the full `[String]` skip array via
   `updateApplicationContext(["skippedReminderIdentifiers": ids])`; on
   `didReceiveApplicationContext`, apply
   `ReminderSkipLogic.resolve(fetched: localFetchedIDs, skipped: received)` and
   re-save. Latest-wins, eventual convergence; acceptable because single-user,
   low-frequency, and `updateApplicationContext` auto-delivers the last state on
   (re)connect. Chosen over iCloud KVS because reminders already sync via the
   Reminders account, so the only app-private state is small and WatchConnectivity
   adds no iCloud dependency/entitlement.

3. **Code sharing — local Swift Package `SingleThreadCore`** (platforms
   iOS 26.5 + watchOS 26.5). Owns `ReminderSkipLogic`, `ReminderNotesFormatter`,
   `ReminderDateFilter` (moved out of `ContentView.swift`), `SkippedReminderStore`,
   plus two new types: `ReminderStore` (the EventKit/state orchestration extracted
   from `ContentView.swift:53-247`, made UI-free) and `SkippedReminderSyncService`
   (the WatchConnectivity wrapper, guarded `#if os(iOS) || os(watchOS)`).
   App + watch targets both depend on it.

4. **Packaging — embedded companion app.** New `SingleThreadWatch` target
   (`com.apple.product-type.application`, bundle ID `app.alanvardy.SingleThread.watchkitapp`)
   embedded in the iOS app; `SUPPORTED_PLATFORMS = "watchos watchsimulator"`,
   `TARGETED_DEVICE_FAMILY = 4`, `WATCHOS_DEPLOYMENT_TARGET = 26.5` (matches the
   project's `26.5` posture). Single watch app target with a SwiftUI `@main`
   `App`/`WindowGroup`; no separate WatchKit extension target.

5. **Watch UI — buttons, not swipeActions.** `swipeActions` is iOS-only, so the
   watch gets a `WatchReminderView` using a `VStack` with explicit "Complete"
   (green) and "Skip" (orange) buttons, showing title / due date / formatted
   notes, one reminder at a time. It drives the shared `ReminderStore`; only the
   thin view layer is watch-specific (the iOS `ContentView` keeps its
   swipeActions/List/GeometryReader body and is refactored to drive the same
   `ReminderStore`).

6. **Testing.** Existing unit suites switch to `import SingleThreadCore`
   (e.g. `ReminderSkipTests.swift:1`); pure-logic tests are unchanged in intent.
   New `ReminderStore`/`SkippedReminderSyncService` tests go in
   `SingleThreadTests` (hosted app target, iOS simulator). Watch gets a build in
   CI + a minimal watch UI smoke test (see risks). The `--ui-testing` /
   `loadsReminders: false` seam is extended to the watch target so watch UI tests
   never hit the real EventKit prompt.

7. **Build/CI integration.** Add `SingleThreadWatch` (and the package) to the
   `SingleThread` scheme; add a second `xcodebuild` build for
   `platform=watchOS Simulator` in `Makefile`, `scripts/test.sh`, and `ci.yml`
   (current destinations are iPhone-only, `Makefile:1`, `ci.yml:40,100`); extend
   SwiftLint/SwiftFormat/Periphery scopes to `SingleThreadCore/` and the watch
   folder (`.swiftlint.yml:2-5`, `.swiftformat:21`, `Makefile:22,26`,
   `ci.yml:149`). Package does **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`;
   `ReminderStore` is explicitly `@MainActor`, pure logic stays `nonisolated`.

## What We're NOT Doing

- **Not** syncing reminder data ourselves — completion/completion edits propagate
  via the user's Reminders account; WatchConnectivity carries only the skip set.
- **Not** App Groups, iCloud KVS, CloudKit, or SwiftData for sync.
- **Not** a standalone watch app, complications, or widgets.
- **Not** a multi-reminder list on the watch (single-at-a-time, matching iOS).
- **Not** extending skip-list sync to macOS/visionOS — WatchConnectivity is
  iPhone↔watch only, so Mac/visionOS builds of `SingleThread` keep today's
  local-only `UserDefaults` behavior (guarded out via `#if os(iOS) || os(watchOS)`).
- **Not** fixing the SwiftData `AGENTS.md` mismatch or the stale UI-test comment
  unless touched incidentally (logged for cleanup, not in this task's scope).

## Open Risks

- **`ReminderStore` extraction refactor**: `ContentView` is self-contained with
  `@State` + preview seams (`ContentView.swift:28-37`, `:70-76`); extracting a
  shared `@MainActor` store touches the app's most-tested view. Mitigate by
  preserving the injection seams and running `./scripts/test.sh` after the
  extraction, before adding the watch.
- **WatchConnectivity on simulator**: `updateApplicationContext`/`transferUserInfo`
  behave unreliably in paired-simulator scenarios; round-trip sync must be
  verified on real hardware. `updateApplicationContext` (latest-wins) chosen over
  `transferUserInfo` to reduce this.
- **Last-writer-wins conflicts**: concurrent skips on both devices could drop one
  skip. Accepted for v1 (single user, low frequency); revisit with a merge log
  only if it surfaces.
- **EventKit on watchOS**: full-access APIs need watchOS 10+ and the correct
  `NSRemindersFullAccessUsageDescription`; watch-side authorization flow
  (`requestFullAccessToReminders`) is untested in this project today.
- **CI surface growth**: a new platform means new destinations, `-only-testing`
  filters, and lint scopes in `Makefile`/`scripts/test.sh`/`ci.yml` — the most
  likely place for warnings-as-errors breakage.
- **`calendarItemIdentifier` of unsaved fixtures** (`mockReminder`,
  `ContentView.swift:256-265`) resolves unpredictably; skip-set tests should use
  synthetic IDs, not `EKReminder` fixtures.

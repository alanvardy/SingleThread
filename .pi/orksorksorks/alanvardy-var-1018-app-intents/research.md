# Research Findings

Sources: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` (Q1, Q3),
`SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift` (Q2),
`SingleThreadWidget/NextThingWidget.swift` (Q2, Q3), `SingleThread/SingleThreadApp.swift`
and `SingleThreadApp+Commands.swift` (Q2), `SingleThread/AppViewModel.swift`,
`SingleThread/ContentViewModel.swift`, `SingleThread/ContentView.swift` (Q3),
`SingleThread.xcodeproj/project.pbxproj` (Q3), Apple developer docs for AppIntents (Q4).
All `file:line` references are to the repo root.

## Q1: ReminderStore — current/next computation, complete, skip, empty cases

### Findings
- **Actor model**: `ReminderStore.swift:14-16` — `@MainActor @Observable public final class ReminderStore`. Every member runs on the main actor; every mutating method is main-actor-bound.
- **Current-next definition**: `visibleReminders` getter (`ReminderStore.swift:155-162`) filters out `skippedIDs` and excluded-list titles, then sorts via `ReminderSort.areInIncreasingOrder` (`ReminderSort.swift:9-22`, comparators `:24-68`) using `sortOption` (default `.priority`). "Current next task" is `visibleReminders.first` everywhere.
- **Empty / all-done / hidden cases**:
  - `allSkipped` (`ReminderStore.swift:164-168`): reminders exist but none visible (all skipped/excluded).
  - `hasHidden` (`ReminderStore.swift:71`; seeded `:52-53`, set by `reload()` `:476,:485` via `hasHiddenFor` `:119-124`): incomplete reminders exist outside the current window.
  - `listContent` (`ReminderStore.swift:171-180`) returns in canonical order `.allDone` → `.reminder(ReminderDisplay)` → `.empty(hasHidden:)`; `ListContent.swift:5-17` defines the enum and documents at `:6-7` that the store never returns `.noAccess` (auth is target-local).
- **Complete**:
  - `completeCurrentReminder()` (`ReminderStore.swift:271-274`): `@discardableResult public func async … -> Bool`; guards `visibleReminders.first`, delegates, returns `false` when nothing visible (the clean no-op case).
  - `completeReminder(identifier:)` (`ReminderStore.swift:228-261`): `async -> Bool`; guards `canMutate` (`:229-232`, entitlement/freemium cap `:112-115`) → `false`.
    - watchOS branch (`#if os(watchOS)` `:233-259`): local remove + `pendingCompletionStore` persist + `onCompleteReminder`, no EventKit write.
    - iOS branch (`:260-273`): `isCompleted = true`, `eventStore.save(reminder, commit: true)`, increments `completionCounter`/`dailyCompletion`, retains `undoStore`, `resetSkipCount`, then **`await settle()` and `await reload()`** before returning `true`; on catch logs and returns `false`.
  - `settle` is an injected `ReminderStoreSettle` (`ReminderStore.swift:12` type alias; default `Task.sleep(nanoseconds: 200_000_000)` `:35-39`) — the save is durable before the awaited settle+reload return.
- **Skip**:
  - `skipCurrentReminder()` (`ReminderStore.swift:393-414`): sync `Void`; guards `canMutate` + `visibleReminders.first`; `incrementSkipCount` (6th skip fires `onSkipNudgeRequested` and returns early `:401-406`); computes `updatedSkipSet` (`:575-582` via `ReminderSkipLogic.skipping`), captures `skipGeneration`, spawns `Task { await settle(); if applySkipSet(updated, generation:) { await reload() } }` `:407-413` — fire-and-forget, save applied after the settle sleep, refetch generation-gated.
  - `skipCurrentReminderImmediately()` (`ReminderStore.swift:434-449`): `@discardableResult … -> Bool`; guards `canMutate` + first-visible (`false` otherwise); increments skip count, then `applySkipSet(updated)` **synchronously before returning** `true`. No `settle()`, no `reload()`. Comment `:428-433`: WidgetKit may suspend the process right after `perform()` returns, so the interactive settle sleep is unsafe from that path.
  - `applySkipSet` (`ReminderStore.swift:627-643`): generation gate → sets `skippedIDs`, `skipStore.save(updated)`, fires `onSkipSetChanged`/`onRemindersChanged`, returns discarable Bool.
- **Test corroboration**: `ReminderStoreTests.swift:20-114` (visible/priority/empty), `:268-372` (skip paths), `:397-439` (complete paths); `ListContentTests.swift:9-47`.

### Method summary
| Method | Signature | Await-settle/reload | Returns |
|---|---|---|---|
| `visibleReminders` | getter | n/a | `[EKReminder]` sorted+filtered |
| `listContent` | getter | n/a | `.allDone`/`.reminder`/`.empty(hasHidden:)` |
| `completeReminder` / `completeCurrentReminder` | `async -> Bool` | `await settle(); await reload()` (iOS) | `true` success; `false` no-match/gated/failure |
| `skipCurrentReminder` | sync `Void` | settle+reload fire-and-forget in `Task` | none |
| `skipCurrentReminderImmediately` | sync `-> Bool` | none (writes before returning) | `true` skipped; `false` gated/empty |

## Q2: Existing intent structure and surfacing

### Findings
- **Definitions** (`SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift`):
  - `CompleteReminderIntent` (`:7-26`): `public struct …: AppIntent`, empty public `init()` (`:9`), `static let title: LocalizedStringResource = "Complete Reminder"` (`:12`), `static let isDiscoverable = false` (`:13`), `@MainActor public func perform() async throws -> some IntentResult` (`:15-17`). Body (`:18-23`): construct fresh `ReminderStore(loadsReminders: true)` → `setSortOption(SortOptionStore().load())` → `await store.reload()` → `await store.completeCurrentReminder()` → return plain `.result()`.
  - `SkipReminderIntent` (`:29-50`): same shape; `title = "Skip Reminder"` (`:35`), `isDiscoverable = false` (`:36`); calls `store.skipCurrentReminderImmediately()` **without awaiting** (`:46-49`) then `.result()` (`:50`). Comment `:43-45`: skip is routed through the store (persistence + `onSkipSetChanged`/`onRemindersChanged`) rather than writing UserDefaults directly.
  - Only `.result()` plain is used — no `.result(dialog:)`/`.result(value:)` variants anywhere (`ReminderIntents.swift:23,50`).
- **Widget invocation** (`SingleThreadWidget/NextThingWidget.swift`): `StaticConfiguration(kind: "NextThing", …)` (`:104`); `CompleteReminderIntent` button (checkmark, `.tint(.green)`, a11y id `completeButton`, `:155-163`) and `SkipReminderIntent` button (`.tint(.orange)`, id `skipButton`, `:164-172`) inside `actionButtons` (`:153`), rendered in the `.reminder(display)` case (`:237`). No widget-scene `AppIntentConfiguration`/`.intent(...)` family exists.
- **App target** (`SingleThread/SingleThreadApp.swift`): `@main struct SingleThreadApp: App` (`:13`) hosts one `WindowGroup` → `ContentView` (`:17-20`). `.commands { appCommands(...) }` and `MenuBarExtra` are `#if os(macOS)` (`:25-29`, `:35-42`); iOS only gets `@UIApplicationDelegateAdaptor(AppDelegate.self)` (`:57-59`). No iOS App-level intent surface.
  - `appCommands` (`SingleThread/SingleThreadApp+Commands.swift:12`, file-wide `#if os(macOS)` `:1`): a `@CommandsBuilder` func (not AppIntents). The `CommandMenu(reminder)` buttons (`:28-42`) call `store.completeCurrentReminder()` / `store.skipCurrentReminder()` directly inside `Task { @MainActor … }` — they bypass the AppIntent structs entirely.
- **iOS Siri/Shortcuts/app-icon surface: does not exist.** Grep across `*.swift` finds no `AppShortcutsProvider`, `commandsAppShortcuts`, `SiriShortcuts`, `INIntent` usage. Only consumers of the AppIntent structs are the widget buttons and the test target.
- **Tests** (`SingleThreadTests/ReminderIntentsTests.swift`): `completeIntentIsConfigured` / `skipIntentIsConfigured` (`:12-25`) only check `isDiscoverable == false` and that titles resolve from the `.main` catalog (comment `:15-16`: the Core catalog doesn't hold AppIntent keys). No behavior/perform() test.

## Q3: ReminderStore construction and background access

### Findings
- **Initializer** (`ReminderStore.swift:20-56`): single `init` with `eventStore: any EventKitStoring = EKEventStore()`, `skipStore: SkippedReminderStore()`, `skipCountStore`, `pendingCompletionStore`, `excludeStore`, `loadsReminders: Bool = true`, plus test-injection params (`reminders`, `skippedIDs`, `authorizationStatus = .notDetermined`, `excludedListTitles`, `hasHidden`, `dailyCompletion`, `completionCounter`, `entitlementStore`) and the `settle` hook. All stored on `self` (`:41-56`).
- **Composition root** (`SingleThread/AppViewModel.swift:17-20`, doc `:15`: "the app's composition root"): `init(arguments:)` (`:23`) builds the store via `Self.makeStore(arguments:)` (`:25`), holds `let store: ReminderStore` (`:60`), loads sort (`:27`), wires `store.onRemindersChanged -> WidgetCenter.shared.reloadAllTimelines()` + macOS notification scheduling (`:36-44`), attaches `SkippedReminderSyncService` on iOS (`:31`, `:370+`).
  - `makeStore` (`:204`): production `(ReminderStore(loadsReminders: loads), false)` (`:271`); `loads` suppressed only with `--ui-testing`/`--no-reminders` (`:269-270`). UI-test seams: `InMemoryEventStore` + `.fullAccess` (`:252,:260`), `--seed` `seededStore` (`:297`), `--ui-testing-noop-settle` injects a `{}` no-op settle (`:332-351,:360-380`).
- **Isolation/project settings** (`SingleThread.xcodeproj/project.pbxproj:777,:827` app, `:961,:989` watch): `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + `SWIFT_VERSION = 6.0` on iOS app and watch app targets **only**. Widget targets (`51AA3F4B…/51AA3F4C…`) set Swift 6 but **not** default isolation — widget/intent code must annotate `@MainActor` explicitly (existing intents do, `ReminderIntents.swift:15,38`).
- **Store access paths**:
  - `start()` (`ReminderStore.swift:206-214`): guards `loadsReminders`, reads `eventStore.authorizationStatus(for: .reminder)`, `reload()` if `.fullAccess` else `requestAccess()` (`:213`). Doc: "Call from `.task` in the view layer." Invoked from `SingleThread/ContentViewModel.swift:135`, triggered by `ContentView.swift:273-278` `.task`.
  - `reload()` (`ReminderStore.swift:452-531`): guards `loadsReminders`, `refreshSourcesIfNecessary()`, reconciles visible/hidden/skip/excluded/pending-completions, fires `onRemindersChanged?()`.
  - `requestAccess()` (`:537-549`): awaits `eventStore.requestFullAccessToReminders()`; grant → `.fullAccess` + `reload()`.
- **Widget's out-of-lifecycle pattern** (`SingleThreadWidget/NextThingWidget.swift`): `getTimeline` (`:46-56`) spawns `Task { await Self.makeEntry() }` with a 5-minute `.after(refresh)` policy — the entire staleness mechanism. `makeEntry()` (`:61-91`, `@MainActor`) checks `EKEventStore.authorizationStatus(for: .reminder)` inline (`:70`); only on `.fullAccess` does it build a **fresh** `ReminderStore(loadsReminders: true)` (`:73`), apply prefs + `setSortOption(SortOptionStore().load())` (`:74-75`), `await store.reload()` (`:76`), read `store.listContent` (`:78`). Any other status → `.noAccess` entry (`:82-88`). The widget **never** calls `requestAccess()`/prompts — same for the intents.
- **Three independent store instances** per refresh/tap: widget timeline + each intent `perform()` constructs its own store, never shared with the app process; the app pushes refreshes via `WidgetCenter.shared.reloadAllTimelines()` (`AppViewModel.swift:38-39`).

## Q4: AppIntents framework — result shapes and surfaces (iOS 17 / Swift 6)

Source: Apple Developer docs (developer.apple.com/documentation/appintents), App Shortcuts HIG, WWDC22/23 intents videos.

### Findings
- **`perform()` shape**: `func perform() async throws -> some IntentResult`; you declare `some IntentResult & <capability>` return types and construct via the `.result(...)` builder family — you never conform to `IntentResult` directly ([IntentResult](https://developer.apple.com/documentation/appintents/intentresult)).
- **Result builders** ("Indicates the AppIntent finished performing"): plain `.result()`; `.result(dialog: IntentDialog)` (Siri voice/text response); `result<Value>(value:)`; combined `result(value:dialog:)`; `result(opensIntent:)`; `result(dialog:content:)` (custom SwiftUI view); plus `snippetIntent:`/`actionButtonIntent:` variants in newer SDKs. Capability protocols: `ReturnsValue<T>`, `ProvidesDialog`, `ShowsSnippetView`, `OpensIntent`/`OpensAppIntent` (aliases `Returns`, `Opens`, `Provides`, `Shows`).
- **Fidelity is enforced**: protocols in the declared return type must match what `.result(...)` supplies, else a fatal runtime error (e.g. "Did not declare ProvidesDialog but provided one").
- **Failure is a throw**: `async throws` — signal failure by throwing; for user-facing text conform the error to `CustomLocalizedStringResourceConvertible` (raw `LocalizedError` text is not shown in Shortcuts). A successful no-op is `.result()` optionally with `.result(dialog:)` — dialog is described as **required for voice-only contexts**.
- **Intent lifecycle knobs**: `static var openAppWhenRun: Bool` launches the app when the intent runs; iOS 16.4+ `ForegroundContinuableIntent` for background-then-foreground flows (`needsToContinueInForegroundError()`). `isDiscoverable` (iOS 17.0+): default `true`; `false` restricts the intent to in-app/widget use (excludes Siri/Spotlight/Shortcuts) ([isDiscoverable](https://developer.apple.com/documentation/appintents/appintent/isdiscoverable-95nxm)).
- **System surface**: `AppShortcutsProvider` protocol on a top-level app-target struct with `static var appShortcuts: [AppShortcut]`; each `AppShortcut(intent:, phrases:, shortTitle:, systemImageName:)` exposes the intent with zero user setup. Phrase rules: every phrase must contain `\(.applicationName)`; ≤10 shortcuts, ≤1000 phrases across localizations; `updateAppShortcutParameters()` for dynamic options; `shortcutTileColor` required in newer SDKs. One intent definition surfaces in Home Screen, Home Screen Quick Actions (**app-icon long-press menu**), Lock Screen, Siri, the Shortcuts app, Spotlight. App Shortcuts are not auto-discovered by Siri — they must be registered via `AppShortcutsProvider`.
- **`commandsAppShortcuts` is not a documented AppIntents identifier** — not found in Apple docs; it resembles a conflation with SwiftUI `Commands` (scene menu-bar) or the separate UIKit `UIApplicationShortcutItem` Quick Actions API.

## Cross-Cutting Observations
- **Established intent recipe**: fresh `ReminderStore(loadsReminders: true)` per `perform()`, `setSortOption(SortOptionStore().load())`, `await store.reload()`, mutate, return — never a shared store, never `start()`/`requestAccess()`. This is the repo's existing pattern for running outside the app lifecycle (`ReminderIntents.swift:18-23,41-46`; `NextThingWidget.swift:61-91`).
- **Await-the-save requirement maps to two existing behaviors**: iOS `completeReminder` awaits `settle()` + `reload()` internally before returning `true` (`ReminderStore.swift:260-273`); skip's app-lifecycle path (`skipCurrentReminder`) is fire-and-forget `Task`, while the widget-safe path (`skipCurrentReminderImmediately`) writes synchronously before returning (`:434-449`). A persisted-then-suspended outcome is exactly the WidgetKit hazard already documented at `:428-433`.
- **No-next-task is already modeled**: `completeCurrentReminder` returns `false`; `skipCurrentReminderImmediately` returns `false`; `listContent` distinguishes `.allDone`/`.empty(hasHidden:)`. The intent layer has nothing that surfaces these — existing intents return plain `.result()` regardless.
- **`isDiscoverable = false` today**: both widget intents are excluded from system discovery; making intents reachable from Siri/Shortcuts requires `isDiscoverable = true` and/or an `AppShortcutsProvider` (per Q4), neither present in the repo.
- **Concurrency is explicit in non-app targets**: Core/widget/test targets have no default isolation; `@MainActor` annotations are required and already used — Swift 6 `some IntentResult` return types compile in Core today.

## Open Areas
- **`.finished(result:)` API literal** could not be confirmed in Apple docs (only the `.result(...)` "finished performing" family). Verify against the SDK/simulator compile if the exact shape matters.
- **App Shortcuts phrase/catalog details for THIS app** (how the app's `.main` catalog interacts with Shortcut phrases; widget coexistence) are not knowable from the repo — no surface exists to inspect.
- **Behavioral (perform()) test story** for intents: existing tests only check configuration/titles (`ReminderIntentsTests.swift`); no unit test invokes `perform()` against `InMemoryEventStore`, and the ticket says testing is manual via Shortcuts/app-icon.
- **Dialog content for the no-next-task case** is a design decision; the framework requires `ProvidesDialog`/`.result(dialog:)` for voice-only contexts but the repo has zero dialog-construction precedents.
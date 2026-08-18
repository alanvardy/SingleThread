# Research Findings

Primary subject: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
(227 lines) — a `@MainActor @Observable public final class` (`ReminderStore.swift:4-6`)
that owns the app's single `EKEventStore` instance (`ReminderStore.swift:200`).

---

## Q1: Full inventory of EventKit API surface and lifecycle points

### Findings
`ReminderStore` is the sole owner of an `EKEventStore`; every EventKit call
funnels through it. Direct EventKit surface, mapped to lifecycle:

| EventKit symbol | Location | Lifecycle method |
|---|---|---|
| `import EventKit` | `ReminderStore.swift:1` | module |
| `EKEventStore()` default arg | `ReminderStore.swift:13` | `init` (production) |
| `EKEventStore()` literal | `ReminderStore.swift:31` | `init` (preview/test) |
| `EKEventStore.authorizationStatus(for: .reminder)` (static) | `ReminderStore.swift:69` | `start()` |
| `EKEventStore.authorizationStatus(for: .reminder)` (static) | `ReminderStore.swift:221`, `:224` | `requestAccess()` (deny/error paths) |
| `eventStore.requestFullAccessToReminders()` (async) | `ReminderStore.swift:216` | `requestAccess()` |
| `eventStore.refreshSourcesIfNecessary()` | `ReminderStore.swift:155` | `reload()` — `#if !os(watchOS)` |
| `eventStore.predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` | `ReminderStore.swift:157-160` | `reload()` |
| `eventStore.fetchReminders(matching:completion:)` | `ReminderStore.swift:208` | `reload()` via private `fetchReminders` |
| `eventStore.save(_:commit: true)` | `ReminderStore.swift:91` | `completeReminder` (non-watchOS) |
| `eventStore.save(_:commit: true)` | `ReminderStore.swift:125` | `addReminder` (non-watchOS) |
| `eventStore.defaultCalendarForNewReminders()` | `ReminderStore.swift:193` | `addReminder` via `makeReminder` |
| `EKReminder(eventStore:)` | `ReminderStore.swift:186` | `addReminder` via `makeReminder` |
| `EKReminder` property reads (`calendarItemIdentifier`, `title`, `dueDateComponents`, `priority`) | `ReminderStore.swift:60,88,102,138-140` | `visibleReminders`, `completeReminder`, `completeCurrentReminder`, `skipCurrentReminder` |
| `EKRecurrenceRule` type (param) | `ReminderStore.swift:114`, `:185` | `addReminder` signature, `makeReminder` |

- **Lifecycle call graph**: `start()` (`:67`) → static status check (`:69`) → `.fullAccess`
  ? `reload()` (`:72`) : `requestAccess()` (`:74`). `requestAccess()` (`:214`) →
  `requestFullAccessToReminders()` (`:216`) → grant sets `.fullAccess` + `reload()`
  (`:218-219`), deny/error re-reads static status (`:221`, `:224`). `reload()` (`:152`)
  → `refreshSourcesIfNecessary()` (`:155`, non-watchOS) → predicate (`:157`) →
  `fetchReminders` (`:161` → `:208`). `addReminder` (`:110`) → `makeReminder` (`:118-123`)
  → `save` (`:125`) → `reload()` (`:127`). `completeReminder` (`:83`) → `isCompleted = true`
  (`:90`) → `save` (`:91`) → `reload()` (`:93`).
- **Async bridge**: `fetchReminders(matching:)` wraps the completion-handler
  `fetchReminders` in `withCheckedContinuation` (`:206-212`); completion `nil` → `[]`.
- **EventKit used elsewhere that bears on the store**:
  - `ReminderDateFilter.swift:4` — `extension EKReminder: @retroactive @unchecked Sendable {}` (required for `EKReminder` to cross the `@MainActor` async boundary under Swift 6).
  - `ReminderDateFilter.swift:9-16`, `:22-30` — `endOfToday()` / `overdueCutoff()` (30-day default) bound the fetch predicate.
  - `ReminderSort.swift` — `areInIncreasingOrder(_:_:)` reads `.priority`/`.dueDateComponents?.date`/`.title` (used by `visibleReminders`, `:61`).
  - `ReminderDisplay.swift:11-16` — maps `EKReminder` fields for the widget.
  - `ReminderDictationParser.swift:220,233,242,252-264` — builds the `EKRecurrenceRule`s consumed by `addReminder`.
  - `NextThingWidget.swift:52` — static `EKEventStore.authorizationStatus(for: .reminder)` check before its own `ReminderStore(loadsReminders: true).reload()` (`:54-55`).

---

## Q2: How `ReminderStore` exposes testability

### Findings
- **Two initializers**:
  - Production init `ReminderStore.swift:12-19` — `eventStore: EKEventStore = EKEventStore()`, `skipStore: SkippedReminderStore = SkippedReminderStore()`, `loadsReminders: Bool = true`. Both framework dependencies injectable; only seam that accepts an `EKEventStore`.
  - Preview/test init `ReminderStore.swift:22-33` — takes `loadsReminders`, `reminders: [EKReminder]`, `skippedIDs: Set<String>`, `authorizationStatus: EKAuthorizationStatus`; pre-populates all state. Doc comment claims "never touches EventKit" (`:21`) but it still constructs a real `EKEventStore()` (`:31`) and `SkippedReminderStore()` (`:32`) — construction only, no I/O/prompt.
- **`loadsReminders` guards**: only `start()` (`:68`) and `reload()` (`:153`) check it. It gates the read + authorization path.
- **Public methods reaching real EventKit regardless of construction mode**:
  - `completeReminder(identifier:)` — non-watchOS branch unconditionally calls `eventStore.save` (`:91`); no `loadsReminders` check.
  - `addReminder(...)` — non-watchOS branch unconditionally calls `makeReminder` + `eventStore.save` (`:118-125`); no `loadsReminders` check.
  - `completeCurrentReminder()` (`:100-103`) — delegates to `completeReminder` (`:102`).
  - `skipCurrentReminder()` (`:136-150`) — no EventKit, but writes the real `skipStore` (App-Group UserDefaults) regardless of mode (`:146`).
  - `requestAccess()` (`:214`) and `fetchReminders(matching:)` (`:206`) are `private`; `makeReminder` (`:180`) is `internal static` (`#if !os(watchOS)`).
- **Construction sites**:
  - Tests: `ReminderStoreTests.swift` pre-populated overload (`:14-18` and many others) and `ReminderStore(loadsReminders: false)` (`:78`, `:93`, …). `ReminderDictationTests.swift:143` uses `ReminderStore(loadsReminders: false)`.
  - Previews: `ContentView.swift` `#Preview` blocks (lines ~455-485) use `ContentView(loadsReminders: false)` or the pre-populating overload; `WatchReminderView.swift` previews likewise.
  - Production: `SingleThreadApp.swift:17`, `SingleThreadWatchApp.swift:10-11`, `NextThingWidget.swift:54`, `ReminderIntents.swift` (both `loadsReminders: true`).

---

## Q3: Protocol-based test-seam precedents

### Findings
Two protocol seams exist; **EventKit is not one of them**.

**Seam 1 — `SkipSyncSession` (WatchConnectivity/WCSession)** in
`SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`:
- Protocol `SkipSyncSession: AnyObject` (`:7-14`) — `activate()`, `updateApplicationContext(_:)`, `sendMessage(_:replyHandler:errorHandler:)`.
- Empty conformance `extension WCSession: SkipSyncSession {}` (`:16`) — WCSession already matches the signatures.
- Consumer stores existential `private let session: any SkipSyncSession` (`:100`); `init(session:skipStore:)` (`:25-29`).
- `activate()` special-cases the real type: `if let wcSession = session as? WCSession { wcSession.delegate = self }` (`:40-42`), then always `session.activate()` so fakes are still exercised.
- Production injection: `SingleThreadApp.swift:22-24` (`session: WCSession.default`); watch `SingleThreadWatchApp.swift:15-17`.
- Test substitution: `FakeSession: SkipSyncSession` in `SkippedReminderSyncServiceTests.swift:8-31`, injected at ~`:41,52,64,…`; tests record `activated`/`lastContext`/`lastMessage`.

**Seam 2 — `SpeechTranscribing` (Speech/AVFoundation)** in
`SingleThread/ReminderDictation.swift`:
- Protocol `@MainActor SpeechTranscribing: AnyObject` (`:9-16`) — `authorizationStatus`, `requestAuthorization()`, `transcribe(onPartialResult:)`.
- Real conformer is the app-owned wrapper `ReminderDictation: SpeechTranscribing` (`:24`), holding `SFSpeechRecognizer` (`:60`) + `AVAudioEngine` (`:61`); no conformance extension on the framework type (unlike WCSession).
- Production injection: `ContentView.swift:13,18,33` via `speechTranscriber ?? ReminderDictation()` (nil-coalescing default).
- Test substitution: `FakeSpeechTranscriber: SpeechTranscribing` (`ReminderDictationTests.swift:9-65`, injected `:136`,`:144`); `MicToggleFakeTranscriber` (`MicrophoneToggleTests.swift:8-27`).

**Common shape**: small `AnyObject` protocol exposing only the subset of the Apple
framework actually called; existential (`any`) storage; production passes the real
type; tests pass a recording fake. `SpeechTranscribing` doc cites `SkipSyncSession`
as the pattern to follow (`ReminderDictation.swift:7-8`).

**Negative finding**: `ReminderStore` uses `EKEventStore`/`EKReminder` directly
(`ReminderStore.swift:13`, `:200`). Its test seam is the pre-populated-state
initializer (`:22-33`), not a protocol abstraction.

---

## Q4: `EKReminder` construction and mutation

### Findings
- **`EKReminder(eventStore:)` parameter**: an `EKEventStore` instance. In the factory,
  `makeReminder`'s `eventStore: EKEventStore` param (`:184`) is passed straight through
  (`:186`). The value originates from the store's `private let eventStore` (`:200`),
  supplied at the call site `eventStore: eventStore` (`:118-123`).
- **`makeReminder` factory** (`:180-195`, `static`, `internal`, `#if !os(watchOS)`):
  - `let reminder = EKReminder(eventStore: eventStore)` — `:186`
  - `reminder.title = title` — `:187`
  - `reminder.notes = notes` — `:188` (no nil-coalescing; `nil` stays `nil`, asserted by `ReminderStoreTests.swift:281-291`)
  - `reminder.dueDateComponents = dueDate` — `:189` (uses `dueDateComponents`, not `dueDate`)
  - conditional `reminder.addRecurrenceRule(recurrenceRule)` — `:190-192`
  - `reminder.calendar = eventStore.defaultCalendarForNewReminders()` — `:193`
- **`addRecurrenceRule`** is EventKit's `EKReminder.addRecurrenceRule(_:)` method,
  not defined locally; the only call is `:191`. The store never builds an
  `EKRecurrenceRule` — callers do (`ReminderDictationParser.swift:220,233,242,252-264`;
  test at `ReminderStoreTests.swift:294`).
- **`defaultCalendarForNewReminders()`** is an EventKit `EKEventStore` method, called
  once at `:193`; no local implementation/override. Pass-through is asserted at
  `ReminderStoreTests.swift:314`.
- **`isCompleted = true`** is set in exactly one place: `completeReminder` non-watchOS
  branch `:90`, immediately followed by `eventStore.save(reminder, commit: true)`
  (`:91`), a 200 ms sleep (`:92`), and `reload()` (`:93`). On watchOS (`:84-86`) the
  reminder is instead removed locally and `onCompleteReminder` fires; `isCompleted`
  is never touched there.
- **Preview construction (non-store)**: `ContentView.swift:447-448` and
  `WatchReminderView.swift:201-202` both do `let store = EKEventStore()` then
  `EKReminder(eventStore: store)`.

---

## Q5: Platform-conditional compilation

### Findings
- **Deployment targets**: `SingleThreadCore/Package.swift:6-10` — `.iOS("26.5")`,
  `.watchOS("26.5")`, `.macOS("26.5")`. One `ReminderStore.swift` compiles for all three.
- **`ReminderStore.swift` — four EventKit-affecting branches**:
  - `completeReminder`: `#if os(watchOS)` (`:84-87`) local-remove + `onCompleteReminder`; `#else` (`:87-97`) `isCompleted = true` + `save` + `reload`. watchOS is **read-only**.
  - `addReminder`: `#if os(watchOS)` (`:115-116`) `return false`; `#else` (`:117-133`) build + `save` + `reload`.
  - `reload`: `#if !os(watchOS)` (`:154-156`) `refreshSourcesIfNecessary()` only. The fetch (`:157-161`) is unconditional on all platforms.
  - `makeReminder`: `#if !os(watchOS)` (`:178-196`) — the factory does not exist in the watchOS compilation.
  - `start()` (`:67`), `requestAccess()` (`:214`), and `fetchReminders` (`:206`) are **not** platform-guarded.
- **`SkippedReminderSyncService.swift`**: `#if os(iOS) || os(watchOS)` wraps the whole file (`:3-103`); `#if os(iOS)` adds `sessionDidBecomeInactive`/`sessionDidDeactivate` (`:91-96`). Type does not exist on macOS.
- **App target** (`SingleThread/`): `SingleThreadApp.swift:3,7,20,33,50`; `ContentView.swift:97,125,232,287,308`; `AppDelegate.swift:1`; `ReminderDictation.swift:94,122`; `Color+CrossPlatform.swift:3,16`.
- **Tests**: `ReminderStoreTests.swift:90` (`#if !os(macOS)`), `:244` (`#if !os(watchOS)` for `MakeReminderTests`); `SkippedReminderSyncServiceTests.swift:1`; `AppDelegateTests.swift:1`.
- **Watch/Widget targets**: no `#if os(...)` branches; both import EventKit only for reads/previews.

---

## Q6: `ReminderStore` unit-test structure and execution

### Findings
- **File header** `SingleThreadTests/ReminderStoreTests.swift:1-7`:
  `import EventKit`, `@testable import SingleThreadCore`, `import Testing`;
  `@MainActor` (`:5`), `@Suite(.serialized)` (`:6`), `struct ReminderStoreTests` (`:7`).
  `@testable` is what exposes the `internal static makeReminder`.
- **Construction patterns**: pre-populated overload (`:14-18` etc.) and
  `ReminderStore(loadsReminders: false)` (production init with defaults) at `:78`, `:93`.
- **Fixture helper** `private func makeReminder(title:priority:dateComponents:)` at
  `:321-327` — builds a real `EKReminder(eventStore: EKEventStore())`, sets title/priority/dueDateComponents.
- **Platform guards**: `#if !os(macOS)` at `:90-97` (deterministic no-access save test
  can't run on macOS — unsigned build may still have Reminders access); `#if !os(watchOS)`
  at `:244-317` (mirrors the factory's own guard).
- **`MakeReminderTests`** (`:246-316`): six `@Test`s each calling
  `ReminderStore.makeReminder(...)` with a fresh `EKEventStore()` and asserting one
  configured field: title (`:248`), notes (`:258`), dueDate (`:268`), unset-fields-nil
  (`:281`), recurrence rule (`:293`), default calendar (`:307`).
- **Execution**: `Makefile:21-22` — `make test` → `./scripts/test.sh --unit-only`.
  `scripts/test.sh` runs `build-for-testing` then `test-without-building` with
  `-only-testing:SingleThreadTests` on `platform=iOS Simulator,name=iPhone 17`
  (`:106-118`; SIM default `:5`). Full `scripts/test.sh` also runs the unit suite on
  macOS (`:82-95`, `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`). `Makefile:18-19`
  defines `mac-test` (`-only-testing:SingleThreadTests`).

---

## Q7: Production instantiation and wiring

### Findings
- **`SingleThreadApp.init()`** (`SingleThreadApp.swift:15-38`):
  - `let loads = !ProcessInfo.processInfo.arguments.contains("--ui-testing")` (`:16`);
    `ReminderStore(loadsReminders: loads)` (`:17`). The `--ui-testing` guard disables
    `start()`/`reload()` so UI tests never touch EventKit (`ReminderStore.swift:68,153`).
  - Store held as `private let store: ReminderStore` (`:55`) — a plain `let`, not `@State`/`@StateObject`; observation works via `@Observable`.
  - `#if os(iOS)`: if `WCSession.isSupported()` builds `SkippedReminderSyncService(session: WCSession.default, ...)` (`:22-24`), `activate()` (`:25`), then wires:
    `service.onCompleteReminderReceived → store.completeReminder` (`:26-28`),
    `store.onSkipSetChanged → service.pushSkipIDs` (`:29`),
    `store.onCompleteReminder → service.requestCompleteReminder` (`:30`).
  - `#if os(iOS) || os(macOS)`: `store.onRemindersChanged → WidgetCenter.shared.reloadAllTimelines()` (`:33-37`).
  - `body` hands the same store to `ContentView(store: store)` (`:44`).
- **`ContentView` initializers** (`ContentView.swift`):
  - `init(store:speechTranscriber:)` (`:11-14`) — production injection path.
  - `init(loadsReminders:speechTranscriber:)` (`:16-19`) — creates its own store (previews).
  - preview/populated overload (`:22-34`).
  - Store stored as `private let store` (`:113`); `.task { await store.start() }`
    (`:52-54`) is what actually triggers authorization + load.
- **Hook fire points in `ReminderStore`**:
  - `onSkipSetChanged` — `:147` (in `skipCurrentReminder`) and `:166` (in `reload(clearSkipped: true)`).
  - `onCompleteReminder` — `:86`, **watchOS only** (`#if os(watchOS)` in `completeReminder`).
  - `onRemindersChanged` — `:148` and `:173` (end of `reload()`); completions/additions reach it transitively via `reload()` (`:93`, `:127`).
- **Watch side**: `SingleThreadWatchApp.init()` (`:10-21`) builds its own store with the
  same `--ui-testing` guard and wires `onSkipSetChanged`/`onCompleteReminder` to its own
  sync service (`:19-20`).
- **Widget**: `NextThingWidget.swift:52-55` constructs a **separate** independent
  `ReminderStore(loadsReminders: true)` and calls `reload()`; no hooks wired.

---

## Cross-Cutting Observations

- **Single owner of EventKit**: `ReminderStore` is the only type holding an
  `EKEventStore`; the widget, watch app, and App Intents each construct their own
  `ReminderStore` instances rather than sharing one (`NextThingWidget.swift:54`,
  `SingleThreadWatchApp.swift:10`, `ReminderIntents.swift`).
- **Read/write split by platform**: the read path (`start`, `reload`, `fetchReminders`,
  `requestAccess`) compiles everywhere; only the two write paths (`addReminder`,
  `completeReminder`) plus `refreshSourcesIfNecessary` and `makeReminder` are
  conditionally compiled. watchOS is write-disabled, relayed to the phone via
  WatchConnectivity (`SkippedReminderSyncService.swift:56-62`).
- **Consistent test-seam idiom**: `@MainActor` + `@Suite(.serialized)` suites, `@testable
  import`, file-private `EKReminder` fixtures, and `#if !os(...)` guards that mirror the
  production guards (unit tests `ReminderStoreTests.swift:90,244`).
- **Two-layer seam contrast**: non-mockable WatchConnectivity and Speech are abstracted
  behind protocols (`SkipSyncSession`, `SpeechTranscribing`), but EventKit is not —
  `ReminderStore`'s seam is constructor injection (`eventStore:` param, `:13`) plus the
  pre-populated-state initializer (`:22-33`) and the extracted static `makeReminder`
  factory (`:180`).
- **Hooks are the mutation fan-out**: `onSkipSetChanged`/`onCompleteReminder`/
  `onRemindersChanged` (`:46,51,56`) decouple the store from WatchConnectivity and
  `WidgetCenter`, wired once at app startup (`SingleThreadApp.swift:20-37`).
- **200 ms sleep before `reload()`**: both write paths sleep 200 ms post-save before
  re-fetching (`ReminderStore.swift:92`, `:126`); `skipCurrentReminder` sleeps 200 ms
  before applying skip state (`:144`).

## Open Areas

- **`onCompleteReminder` on the phone**: it is set (`SingleThreadApp.swift:30`) but only
  ever invoked from the watchOS compile branch (`ReminderStore.swift:86`); on iOS the
  `#else` path saves directly, so the phone-side hook is never fired. (Observed, not
  evaluated.)
- **Preview/test init still constructs `EKEventStore()`** (`:31`) despite its "never
  touches EventKit" doc comment (`:21`) — construction is inert, but the doc and body
  are not strictly aligned. (Observed, not evaluated.)
- The `SkipSyncSession` protocol does not include the `WCSessionDelegate` methods that
  `activate()` sets via the `as? WCSession` cast (`SkippedReminderSyncService.swift:40-42`),
  so the delegate contract is outside the seam.

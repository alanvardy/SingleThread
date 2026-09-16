# Implementation Plan

Ticket: VAR-1018 — App Intents for "What's Next", "Complete Current Task", "Skip Current Task".
Branch: `alanvardy-var-1018-app-intents`. This plan is self-contained; `file:line`
refs are to the repo root and were verified this session.

## Overview

Three discoverable `AppIntent`s in `SingleThreadCore` — `WhatsNextIntent`,
`CompleteCurrentTaskIntent`, `SkipCurrentTaskIntent` — registered by one
`AppShortcutsProvider` in the app target, reachable from Siri, Shortcuts,
Spotlight and the Home Screen app-icon long-press menu. Each `perform()` is a
thin shim: read the authorization status → build a fresh, reloaded store via
`ReminderIntentSupport.makeStore` → map a `ReminderIntentOutcome` to
`.result(value:dialog:)`. The existing widget intents
(`CompleteReminderIntent` / `SkipReminderIntent`) are untouched.

All message/empty-state logic lives in `ReminderIntentSupport` so it is
unit-testable; `perform()` keeps only the un-unit-testable result-builder
fidelity.

**Deviations from `structure.md` (all justified below, no scope expansion):**

1. `ReminderIntentOutcome` is declared `public enum …: Equatable, Sendable`
   (not `@MainActor`). It is a pure value type; a MainActor annotation on it
   would force every consumer/test to be MainActor and risks isolation errors on
   synthesized `Equatable`. `ReminderIntentSupport` remains `@MainActor`.
2. `InMemoryEventStore` gains `requestFullAccessCallCount` (3 lines) so
   `makeStoreDoesNotPromptWhenNotAuthorized` can assert no prompt. The structure
   listed this file nowhere; the counter is the only observable proof of "never
   prompts". `makeStore` still takes `authorizationStatus` as a parameter
   (design Risk 7), so no status override is added.
3. Catalog entries are added **in the phase that introduces the literal**, not
   all in Phase 4. Rationale: `catalogsHaveAllSixLanguages`
   (`SingleThreadTests/LocalizationTests.swift:63-90`) requires every key present
   in `SingleThread/Resources/Localizable.xcstrings` to carry all six languages;
   a build that auto-extracts a new app-target literal before translations exist
   would leave the phase gate red. Phase 4 still hardens messages/localization,
   adds the last outcome case, phrase variants and the cross-toolchain check.
4. Dialog/title catalog keys live in the **App** catalog
   (`SingleThread/Resources/Localizable.xcstrings`). Core authors them as plain
   `LocalizedStringResource` literals (default bundle `.main`), matching the
   existing intent titles. Contingency: if `make test` reports a
   `LocalizationTests` failure about a new **Core**-catalog key that a build
   extracted automatically, add the same six-language entry to
   `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`.

Pre-req: the branch-bootstrap `DELETEME` deletion is staged in this worktree
(`git status` shows ` D DELETEME`); `git rm DELETEME` it into the first phase
commit before merge (repo AGENTS.md).

---

## Phase 1: Walking skeleton — `WhatsNextIntent` reachable from the system

Prove the whole pipeline first (authorization gate → fresh store → real EventKit
read → sorted `visibleReminders.first` → dialog + value → system surface),
because packaged-intent eligibility for `AppShortcutsProvider` is the only
unvalidated integration (design Risk 2).

### Changes

#### 1. `ReminderIntentSupport.swift` + `ReminderIntentOutcome` — new

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderIntentSupport.swift`
**Action**: create

```swift
import AppIntents
import EventKit
import Foundation

/// What a reminder intent should say and return. Produced by the
/// `ReminderIntentSupport` factories so every message decision is unit-testable
/// without invoking `perform()`.
public enum ReminderIntentOutcome: Equatable, Sendable {
    /// Reminders access is not `.fullAccess`; an intent never prompts.
    case noAccess
    /// No visible reminder and the list is genuinely empty.
    case nothingToDo
    /// The next visible reminder's title.
    case next(String)
}

/// Shared, `@MainActor` construction + outcome/dialog logic for the three
/// discoverable reminder intents.
@MainActor
public enum ReminderIntentSupport {
    /// Builds an already-reloaded store for an intent, or `nil` when access is
    /// not `.fullAccess`. Never prompts, never calls `start()`/`requestAccess()`.
    public static func makeStore(
        eventStore: any EventKitStoring,
        authorizationStatus: EKAuthorizationStatus,
        loadsReminders: Bool = true) async -> ReminderStore? {
        guard authorizationStatus == .fullAccess else { return nil }
        let store = ReminderStore(eventStore: eventStore, loadsReminders: loadsReminders)
        store.setSortOption(SortOptionStore().load())
        await store.reload()
        return store
    }

    public static func nextOutcome(for store: ReminderStore) -> ReminderIntentOutcome {
        guard let title = store.visibleReminders.first?.title else {
            return .nothingToDo
        }
        return .next(title)
    }

    /// The value returned to Shortcuts; every non-answer returns "".
    public static func value(for outcome: ReminderIntentOutcome) -> String {
        if case let .next(title) = outcome { return title }
        return ""
    }

    /// The only place intent message text is decided.
    public static func dialog(for outcome: ReminderIntentOutcome) -> LocalizedStringResource {
        switch outcome {
        case .noAccess:
            "Enable access in Settings to see your reminders." // existing App-catalog key
        case .nothingToDo:
            "There's nothing to do right now."
        case let .next(title):
            "Your next task is \(title)."
        }
    }
}
```

#### 2. `WhatsNextIntent` — modify

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift`
**Action**: modify — add `import EventKit`, then append:

```swift
/// Returns the current next task's title, spoken and usable as a Shortcuts value.
public struct WhatsNextIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "What's Next"
    public static let isDiscoverable = true

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let eventStore = EKEventStore()
        let outcome: ReminderIntentOutcome
        if let store = await ReminderIntentSupport.makeStore(
            eventStore: eventStore,
            authorizationStatus: EKEventStore.authorizationStatus(for: .reminder)) {
            outcome = ReminderIntentSupport.nextOutcome(for: store)
        } else {
            outcome = .noAccess
        }
        return .result(
            value: ReminderIntentSupport.value(for: outcome),
            dialog: IntentDialog(ReminderIntentSupport.dialog(for: outcome)))
    }
}
```

`IntentDialog(_ string: LocalizedStringResource)` is the SDK initializer
(verified in `iPhoneOS.sdk …/AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface:4447-4450`).

#### 3. `SingleThreadShortcuts` — new

**File**: `SingleThread/AppShortcuts.swift`
**Action**: create

```swift
import AppIntents
import SingleThreadCore

/// Registers the reminder intents for Siri, the Shortcuts app, Spotlight and
/// the Home Screen app-icon long-press menu.
struct SingleThreadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: ["What's next in \(.applicationName)"],
            shortTitle: "What's Next",
            systemImageName: "list.bullet")
    }
}
```

Notes (resolve at compile time — this phase's purpose):
- `shortcutTileColor` has a protocol-extension default in the SDK, so it is
  optional. Do not add it unless the build demands it (verified:
  `AppShortcutsProvider` extension default at interface line `10734`).
- The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. If the build
  emits "main actor-isolated static property cannot satisfy nonisolated
  requirement", add `nonisolated` to `static var appShortcuts`.
- **Risk 2 fallback**: if the provider compiles but the long-press menu does
  **not** list "What's Next", stop and move `WhatsNextIntent` (and later the
  other two) into the app target before Phase 2 — the fallback reshapes every
  later slice's file list. Report to the user before proceeding.

#### 4. `InMemoryEventStore.requestFullAccessCallCount` — modify

**File**: `SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift`
**Action**: modify

```swift
/// Number of times `requestFullAccessToReminders()` was called; lets tests
/// prove an intent never prompts.
public private(set) var requestFullAccessCallCount = 0

public func requestFullAccessToReminders() async throws -> Bool {
    requestFullAccessCallCount += 1
    return true
}
```

#### 5. App catalog entries — modify

**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify — add these keys, each with all six languages
(`en`, `zh-Hans`, `es`, `ja`, `de`, `fr`). The key is the exact English literal;
`%@` are the interpolation placeholders.

| Key | en | zh-Hans | es | ja | de | fr |
|---|---|---|---|---|---|---|
| `What's Next` | What's Next | 下一步 | Qué sigue | 次のタスク | Was steht an | Prochaine tâche |
| `There's nothing to do right now.` | There's nothing to do right now. | 现在没有要做的事。 | No hay nada que hacer ahora mismo. | 今は何もすることがありません。 | Gerade ist nichts zu tun. | Il n'y a rien à faire pour le moment. |
| `Your next task is %@.` | Your next task is %@. | 你的下一个任务是%@。 | Tu próxima tarea es %@. | 次のタスクは%@です。 | Deine nächste Aufgabe ist %@. | Votre prochaine tâche est %@. |

`"Enable access in Settings to see your reminders."` already exists in the App
catalog — do **not** re-add it. Entry shape (copy an existing key such as
`All Done`):

```json
"What's Next": {
  "extractionState": "manual",
  "localizations": {
    "en":      { "stringUnit": { "state": "translated", "value": "What's Next" } },
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "下一步" } },
    "es":      { "stringUnit": { "state": "translated", "value": "Qué sigue" } },
    "ja":      { "stringUnit": { "state": "translated", "value": "次のタスク" } },
    "de":      { "stringUnit": { "state": "translated", "value": "Was steht an" } },
    "fr":      { "stringUnit": { "state": "translated", "value": "Prochaine tâche" } }
  }
}
```

#### 6. `ReminderIntentSupportTests.swift` — new

**File**: `SingleThreadTests/ReminderIntentSupportTests.swift`
**Action**: create

```swift
import EventKit
import Foundation
import SingleThreadCore
import Testing

private let noopSettle: ReminderStoreSettle = {}

@MainActor
@Suite(.serialized)
struct ReminderIntentSupportTests {
    // MARK: makeStore

    @Test
    func makeStoreReturnsNilWhenAccessDenied() async {
        let store = await ReminderIntentSupport.makeStore(
            eventStore: InMemoryEventStore(reminders: [makeReminder(title: "A")]),
            authorizationStatus: .denied)
        #expect(store == nil, "denied access builds no store")
    }

    @Test
    func makeStoreReturnsReloadedStoreWhenAuthorized() async {
        let store = await ReminderIntentSupport.makeStore(
            eventStore: InMemoryEventStore(reminders: [makeReminder(title: "Buy milk")]),
            authorizationStatus: .fullAccess)
        #expect(store?.visibleReminders.first?.title == "Buy milk", "authorized store reloads reminders")
    }

    @Test
    func makeStoreDoesNotPromptWhenNotAuthorized() async {
        let eventStore = InMemoryEventStore(reminders: [makeReminder(title: "A")])
        _ = await ReminderIntentSupport.makeStore(
            eventStore: eventStore,
            authorizationStatus: .notDetermined)
        #expect(eventStore.requestFullAccessCallCount == 0, "an intent never prompts for access")
    }

    // MARK: nextOutcome

    @Test
    func nextOutcomeNamesTheFirstVisibleReminder() {
        let low = makeReminder(title: "low", priority: 9)
        let high = makeReminder(title: "high", priority: 1)
        let store = makeStore(with: [low, high])
        #expect(ReminderIntentSupport.nextOutcome(for: store) == .next("high"))
    }

    @Test
    func nextOutcomeIsNothingToDoWhenAllSkipped() {
        let reminder = makeReminder(title: "A")
        let store = makeStore(with: [reminder], skippedIDs: [reminder.calendarItemIdentifier])
        #expect(ReminderIntentSupport.nextOutcome(for: store) == .nothingToDo)
    }

    @Test
    func nextOutcomeIsNothingToDoWhenEmpty() {
        #expect(ReminderIntentSupport.nextOutcome(for: makeStore(with: [])) == .nothingToDo)
    }

    // MARK: Fixtures

    private func makeStore(
        with reminders: [EKReminder],
        skippedIDs: Set<String> = []) -> ReminderStore {
        ReminderStore(
            eventStore: InMemoryEventStore(reminders: reminders),
            loadsReminders: false,
            reminders: reminders,
            skippedIDs: skippedIDs,
            authorizationStatus: .fullAccess,
            entitlementStore: EntitlementStore(testingWithEntitled: true),
            settle: noopSettle)
    }
}
```

`makeReminder(title:priority:)` is the shared `TestFixtures.swift:15` helper
(same test target); `noopSettle` is local to this file.

#### 7. `ReminderIntentsTests.swift` — modify

**File**: `SingleThreadTests/ReminderIntentsTests.swift`
**Action**: modify — add:

```swift
// MARK: WhatsNextIntent

@Test
func whatsNextIntentIsDiscoverable() {
    _ = WhatsNextIntent()
    #expect(WhatsNextIntent.isDiscoverable, "whats-next intent is discoverable")
}

@Test
func whatsNextIntentTitleResolves() {
    #expect(WhatsNextIntent.title.key == "What's Next", "title resolves to its catalog key")
}
```

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/ReminderIntentSupportTests` — exits
      non-zero on zero matched cases; all 6 cases ran
- [x] `scripts/test-one.sh SingleThreadTests/ReminderIntentsTests`
- [x] `make test` (macOS native unit suite; also builds the app target, so the
      provider must compile, and runs `LocalizationTests`)
- [x] `make build` (iOS simulator build of the app target)

#### Manual
- [ ] Install the built app on a simulator/device with Reminders access; long-press
      the app icon → the menu shows **"What's Next"**; run it → the current task's
      title is spoken/shown. **If absent, apply Risk 2 fallback before Phase 2.**
- [ ] Seed an empty reminder list (or deny Reminders access) → running the shortcut
      speaks the "nothing to do" / access message instead of failing.

---

## Phase 2: `CompleteCurrentTaskIntent` — complete from the system surface

### Changes

#### 1. `ReminderIntentOutcome` + `completeOutcome` — modify

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderIntentSupport.swift`
**Action**: modify

```swift
public enum ReminderIntentOutcome: Equatable, Sendable {
    case noAccess
    case nothingToDo
    case next(String)
    case completed(String)   // new
}
```

```swift
/// Captures the visible title *before* mutating (completion filters it out),
/// then awaits the durable save. No throw for the empty/gated case.
public static func completeOutcome(for store: ReminderStore) async -> ReminderIntentOutcome {
    guard let title = store.visibleReminders.first?.title else { return .nothingToDo }
    guard await store.completeCurrentReminder() else { return .nothingToDo }
    return .completed(title)
}
```

Add the `.completed` arm to `dialog(for:)`:

```swift
case let .completed(title):
    "Marked \(title) as done."
```

#### 2. `CompleteCurrentTaskIntent` — modify

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift`
**Action**: modify — append

```swift
/// Completes the current (first visible) task from a system surface.
public struct CompleteCurrentTaskIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Complete Current Task"
    public static let isDiscoverable = true

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let eventStore = EKEventStore()
        let outcome: ReminderIntentOutcome
        if let store = await ReminderIntentSupport.makeStore(
            eventStore: eventStore,
            authorizationStatus: EKEventStore.authorizationStatus(for: .reminder)) {
            outcome = await ReminderIntentSupport.completeOutcome(for: store)
        } else {
            outcome = .noAccess
        }
        return .result(dialog: IntentDialog(ReminderIntentSupport.dialog(for: outcome)))
    }
}
```

#### 3. Second `AppShortcut` — modify

**File**: `SingleThread/AppShortcuts.swift`
**Action**: modify — add to `appShortcuts`:

```swift
AppShortcut(
    intent: CompleteCurrentTaskIntent(),
    phrases: ["Complete the current task in \(.applicationName)"],
    shortTitle: "Complete Current Task",
    systemImageName: "checkmark.circle")
```

#### 4. App catalog entries — modify

**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify — add, all six languages:

| Key | en | zh-Hans | es | ja | de | fr |
|---|---|---|---|---|---|---|
| `Complete Current Task` | Complete Current Task | 完成当前任务 | Completar tarea actual | 現在のタスクを完了 | Aktuelle Aufgabe abschließen | Terminer la tâche en cours |
| `Marked %@ as done.` | Marked %@ as done. | 已将%@标记为完成。 | Se marcó %@ como hecha. | %@を完了にしました。 | %@ wurde als erledigt markiert. | %@ a été marquée comme terminée. |

#### 5. Tests — modify

**File**: `SingleThreadTests/ReminderIntentSupportTests.swift`
**Action**: modify — add

```swift
// MARK: completeOutcome

@Test
func completeOutcomeNamesTheCompletedTask() async {
    let reminder = makeReminder(title: "Buy milk")
    let store = makeStore(with: [reminder])
    #expect(await ReminderIntentSupport.completeOutcome(for: store) == .completed("Buy milk"))
}

@Test
func completeOutcomeIsNothingToDoWhenEmpty() async {
    #expect(await ReminderIntentSupport.completeOutcome(for: makeStore(with: [])) == .nothingToDo)
}

@Test
func completeOutcomeIsNothingToDoWhenMutationGated() async {
    let reminder = makeReminder(title: "Buy milk")
    let store = makeGatedStore(with: [reminder])
    #expect(await ReminderIntentSupport.completeOutcome(for: store) == .nothingToDo)
}

@Test
func completeOutcomePersistsThroughInMemoryEventStore() async {
    let reminder = makeReminder(title: "Buy milk")
    let eventStore = InMemoryEventStore(reminders: [reminder])
    let store = ReminderStore(
        eventStore: eventStore,
        loadsReminders: false,
        reminders: [reminder],
        authorizationStatus: .fullAccess,
        entitlementStore: EntitlementStore(testingWithEntitled: true),
        settle: noopSettle)
    _ = await ReminderIntentSupport.completeOutcome(for: store)
    #expect(eventStore.allReminders.first?.isCompleted == true, "completion is persisted")
}

private func makeGatedStore(with reminders: [EKReminder]) -> ReminderStore {
    let defaults = UserDefaults.standard
    let key = UUID().uuidString
    defaults.set(EntitlementStore.freemiumCap, forKey: key) // count == 100 → canMutate false
    return ReminderStore(
        eventStore: InMemoryEventStore(reminders: reminders),
        loadsReminders: false,
        reminders: reminders,
        authorizationStatus: .fullAccess,
        completionCounter: CompletionCounterStore(defaults: defaults, key: key),
        entitlementStore: EntitlementStore(testingWithEntitled: false),
        settle: noopSettle)
}
```

**File**: `SingleThreadTests/ReminderIntentsTests.swift`
**Action**: modify — add

```swift
// MARK: CompleteCurrentTaskIntent

@Test
func completeCurrentTaskIntentIsDiscoverable() {
    _ = CompleteCurrentTaskIntent()
    #expect(CompleteCurrentTaskIntent.isDiscoverable, "complete task intent is discoverable")
}
```

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/ReminderIntentSupportTests`
- [x] `scripts/test-one.sh SingleThreadTests/ReminderIntentsTests`
- [x] `make test`
- [x] `make build`

#### Manual
- [ ] Run "Complete Current Task" from the Shortcuts app **and** the app-icon
      long-press menu; confirm the Reminders item flips to completed and the
      widget/app reflect it; the dialog names the task.
- [ ] Re-run with an empty list → "nothing to do" dialog, no error.

---

## Phase 3: `SkipCurrentTaskIntent` — skip with a durable write

### Changes

#### 1. `ReminderIntentOutcome` + `skipOutcome` — modify

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderIntentSupport.swift`
**Action**: modify

```swift
public enum ReminderIntentOutcome: Equatable, Sendable {
    case noAccess
    case nothingToDo
    case next(String)
    case completed(String)
    case skipped(String)   // new
}
```

```swift
/// Skips the first visible reminder synchronously; the skip set is written
/// before this returns (`skipCurrentReminderImmediately`, never the
/// fire-and-forget `skipCurrentReminder`).
public static func skipOutcome(for store: ReminderStore) -> ReminderIntentOutcome {
    guard let title = store.visibleReminders.first?.title else { return .nothingToDo }
    guard store.skipCurrentReminderImmediately() else { return .nothingToDo }
    return .skipped(title)
}
```

Add the `.skipped` arm:

```swift
case let .skipped(title):
    "Skipped \(title)."
```

#### 2. `SkipCurrentTaskIntent` — modify

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift`
**Action**: modify — append

```swift
/// Skips the current (first visible) task from a system surface.
public struct SkipCurrentTaskIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Skip Current Task"
    public static let isDiscoverable = true

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let eventStore = EKEventStore()
        let outcome: ReminderIntentOutcome
        if let store = await ReminderIntentSupport.makeStore(
            eventStore: eventStore,
            authorizationStatus: EKEventStore.authorizationStatus(for: .reminder)) {
            outcome = ReminderIntentSupport.skipOutcome(for: store)
        } else {
            outcome = .noAccess
        }
        return .result(dialog: IntentDialog(ReminderIntentSupport.dialog(for: outcome)))
    }
}
```

#### 3. Third `AppShortcut` — modify

**File**: `SingleThread/AppShortcuts.swift`
**Action**: modify — add

```swift
AppShortcut(
    intent: SkipCurrentTaskIntent(),
    phrases: ["Skip the current task in \(.applicationName)"],
    shortTitle: "Skip Current Task",
    systemImageName: "arrow.uturn.forward")
```

#### 4. App catalog entries — modify

**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify — add, all six languages:

| Key | en | zh-Hans | es | ja | de | fr |
|---|---|---|---|---|---|---|
| `Skip Current Task` | Skip Current Task | 跳过当前任务 | Omitir tarea actual | 現在のタスクをスキップ | Aktuelle Aufgabe überspringen | Passer la tâche en cours |
| `Skipped %@.` | Skipped %@. | 已跳过%@。 | Se omitió %@. | %@をスキップしました。 | %@ wurde übersprungen. | %@ a été passée. |

#### 5. Tests — modify

**File**: `SingleThreadTests/ReminderIntentSupportTests.swift`
**Action**: modify — add

```swift
// MARK: skipOutcome

@Test
func skipOutcomeNamesTheSkippedTask() {
    let reminder = makeReminder(title: "Buy milk")
    let store = makeStore(with: [reminder])
    #expect(ReminderIntentSupport.skipOutcome(for: store) == .skipped("Buy milk"))
}

@Test
func skipOutcomeIsNothingToDoWhenEmpty() {
    #expect(ReminderIntentSupport.skipOutcome(for: makeStore(with: [])) == .nothingToDo)
}

@Test
func skipOutcomeIsNothingToDoWhenMutationGated() {
    let reminder = makeReminder(title: "Buy milk")
    let store = makeGatedStore(with: [reminder])
    #expect(ReminderIntentSupport.skipOutcome(for: store) == .nothingToDo)
}

@Test
func skipOutcomeWritesSkipSetBeforeReturning() {
    let reminder = makeReminder(title: "Buy milk")
    let store = makeStore(with: [reminder])
    _ = ReminderIntentSupport.skipOutcome(for: store)
    #expect(
        store.skippedIDs.contains(reminder.calendarItemIdentifier),
        "the skip set is durable before the intent returns")
}
```

**File**: `SingleThreadTests/ReminderIntentsTests.swift`
**Action**: modify — add

```swift
// MARK: SkipCurrentTaskIntent

@Test
func skipCurrentTaskIntentIsDiscoverable() {
    _ = SkipCurrentTaskIntent()
    #expect(SkipCurrentTaskIntent.isDiscoverable, "skip task intent is discoverable")
}
```

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/ReminderIntentSupportTests`
- [x] `scripts/test-one.sh SingleThreadTests/ReminderIntentsTests`
- [x] `make test`
- [x] `make build`

#### Manual
- [ ] Run "Skip Current Task" from the app-icon long-press menu; confirm the
      dialog names the task and the task disappears from the list.
- [ ] **Durability**: immediately relaunch the app and confirm the skipped task
      is still skipped (the synchronous write survived).

---

## Phase 4: Hardening — accurate messages, localization, SDK compatibility

### Changes

#### 1. Third outcome state + accurate fallbacks — modify

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderIntentSupport.swift`
**Action**: modify

```swift
public enum ReminderIntentOutcome: Equatable, Sendable {
    case noAccess
    case nothingToDo        // list genuinely empty
    case nothingLeftToDo    // reminders exist but all skipped/excluded/hidden
    case next(String)
    case completed(String)
    case skipped(String)
}
```

Add the shared fallback and use it in all three factories:

```swift
private static func noVisibleOutcome(for store: ReminderStore) -> ReminderIntentOutcome {
    store.allSkipped || store.hasHidden ? .nothingLeftToDo : .nothingToDo
}
```

- `nextOutcome`: replace `return .nothingToDo` with `return noVisibleOutcome(for: store)`.
- `completeOutcome` / `skipOutcome`: replace the **first** `guard` fallback
  (no visible title) with `noVisibleOutcome(for: store)`; keep the
  mutation-failure fallback as `.nothingToDo` (gated/save-failed — Phase 2/3
  tests pin this).

Add the `.nothingLeftToDo` arm:

```swift
case .nothingLeftToDo:
    "Everything is skipped for now."
```

#### 2. App catalog entry — modify

**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify — add, all six languages:

| Key | en | zh-Hans | es | ja | de | fr |
|---|---|---|---|---|---|---|
| `Everything is skipped for now.` | Everything is skipped for now. | 目前所有任务都已跳过。 | Todo está omitido por ahora. | 今はすべてスキップされています。 | Alles ist vorerst übersprungen. | Tout est passé pour le moment. |

#### 3. Phrase variants — modify

**File**: `SingleThread/AppShortcuts.swift`
**Action**: modify — final `appShortcuts`:

```swift
struct SingleThreadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: [
                "What's next in \(.applicationName)",
                "What is next in \(.applicationName)"
            ],
            shortTitle: "What's Next",
            systemImageName: "list.bullet")
        AppShortcut(
            intent: CompleteCurrentTaskIntent(),
            phrases: [
                "Complete the current task in \(.applicationName)",
                "Mark my current task done in \(.applicationName)"
            ],
            shortTitle: "Complete Current Task",
            systemImageName: "checkmark.circle")
        AppShortcut(
            intent: SkipCurrentTaskIntent(),
            phrases: [
                "Skip the current task in \(.applicationName)",
                "Skip my current task in \(.applicationName)"
            ],
            shortTitle: "Skip Current Task",
            systemImageName: "arrow.uturn.forward")
    }
}
```

Every phrase still contains `\(.applicationName)`. Do not build the phrases
array dynamically (extraction fails). Run `make build` once, then inspect
`git status SingleThread/Resources/` — if Xcode extracted the phrases, it will
have created `SingleThread/Resources/AppShortcuts.xcstrings` with the phrase
keys (`${applicationName}` placeholders). If so, fill all six languages:

- `What's next in ${applicationName}` → zh-Hans `在${applicationName}里接下来做什么`, es `Qué sigue en ${applicationName}`, ja `${applicationName}で次のタスクは？`, de `Was steht in ${applicationName} an`, fr `Quoi de prévu dans ${applicationName}`
- `Complete the current task in ${applicationName}` → zh-Hans `在${applicationName}里完成当前任务`, es `Completar la tarea actual en ${applicationName}`, ja `${applicationName}で現在のタスクを完了`, de `Aktuelle Aufgabe in ${applicationName} abschließen`, fr `Terminer la tâche en cours dans ${applicationName}`
- `Skip the current task in ${applicationName}` → zh-Hans `在${applicationName}里跳过当前任务`, es `Omitir la tarea actual en ${applicationName}`, ja `${applicationName}で現在のタスクをスキップ`, de `Aktuelle Aufgabe in ${applicationName} überspringen`, fr `Passer la tâche en cours dans ${applicationName}`

(Secondary phrases may be grouped under the first key by Xcode — translate every
key that appears. `AppShortcuts.xcstrings` is not covered by
`LocalizationTests.catalogs`, so this is verified manually.)

#### 4. Tests — modify

**File**: `SingleThreadTests/ReminderIntentSupportTests.swift`
**Action**: modify

- Rename/replace `nextOutcomeIsNothingToDoWhenAllSkipped` with:

```swift
@Test
func nextOutcomeReportsNothingLeftToDoWhenAllSkipped() {
    let reminder = makeReminder(title: "A")
    let store = makeStore(with: [reminder], skippedIDs: [reminder.calendarItemIdentifier])
    #expect(ReminderIntentSupport.nextOutcome(for: store) == .nothingLeftToDo)
}

@Test
func nextOutcomeDistinguishesHiddenFromEmpty() {
    #expect(ReminderIntentSupport.nextOutcome(for: makeStore(with: [])) == .nothingToDo)
    #expect(
        ReminderIntentSupport.nextOutcome(for: makeStore(with: [], hasHidden: true))
            == .nothingLeftToDo)
}

@Test
func everyOutcomeHasANonEmptyDialog() {
    let outcomes: [ReminderIntentOutcome] = [
        .noAccess, .nothingToDo, .nothingLeftToDo,
        .next("A"), .completed("A"), .skipped("A")
    ]
    for outcome in outcomes {
        #expect(
            !ReminderIntentSupport.dialog(for: outcome).key.isEmpty,
            "\(outcome) has a dialog")
    }
}
```

- Extend `makeStore(with:skippedIDs:)` with `hasHidden: Bool = false` and pass it
  to `ReminderStore(… hasHidden: hasHidden …)`.

**File**: `SingleThreadTests/ReminderIntentsTests.swift`
**Action**: modify — add

```swift
// MARK: Title collisions (design Risk 6)

@Test
func intentTitlesDoNotCollideWithWidgetIntentTitles() {
    #expect(CompleteCurrentTaskIntent.title.key != CompleteReminderIntent.title.key)
    #expect(SkipCurrentTaskIntent.title.key != SkipReminderIntent.title.key)
}
```

### Verification

#### Automated
- [x] `make format` (SwiftFormat; verify it did not rename any `@Test` — unit
      test names must not start with `test`)
- [x] `make lint` (`swiftformat --lint` + `swiftlint --strict`)
- [x] `scripts/test-one.sh SingleThreadTests/ReminderIntentSupportTests`
- [x] `scripts/test-one.sh SingleThreadTests/ReminderIntentsTests`
- [x] `make test`
- [x] `make build`
- [x] `make mac-build` (explicitly compiles the app + provider under the local
      Xcode 27.0 macOS SDK)

#### Manual
- [ ] Set the simulator/device locale to a non-English language (e.g. `de` or
      `ja`) and run each shortcut: dialogs and short titles render translated,
      not raw English.
- [ ] Confirm the app-icon long-press menu lists all three shortcuts with the
      expected short titles.
- [ ] **CI floor**: the `AppShortcut` initializer used is available since
      iOS 17 and `shortcutTileColor` is defaulted, so Xcode 26.6 should accept
      it; confirm via the `run-gate` subagent's iOS build (next step). If CI's
      26.6 SDK rejects the provider, add
      `static var shortcutTileColor: ShortcutTileColor { .indigo }`.
- [ ] Siri phrasing, Spotlight, and the physical-device app-icon menu are
      **manual only** and not covered by any local gate (design); spot-check
      Siri if a device is available.

---

## Testing Checkpoints

- **After Phase 1**: `ReminderIntentSupportTests` + `ReminderIntentsTests`
  green, `make test` + `make build` green, and the app-icon long-press menu
  **actually shows** "What's Next". If it does not, stop and apply Risk 2's
  fallback (move the intent structs into the app target) before Phase 2.
- **After Phase 2**: Phase 1 tests still green (no contract break) + complete
  tests green; a real completion observed in the Reminders app.
- **After Phase 3**: earlier tests green + post-relaunch durability check
  observed; `.completed` and `.skipped` dialogs both exercised manually.
- **After Phase 4**: no outcome case without a dialog test; both Xcode versions
  compile; then run the full `./scripts/test.sh` gate **once** via the
  `run-gate` skill (one async gate subagent, managed worktree, multi-hour
  timeout) — never an ad-hoc `nohup`.
- UI tests: none added — there is no UI-test seam for system intent invocation
  (justified in the PR per repo AGENTS.md).
- Known pre-existing local-only macOS failures (annotate, do not debug): three
  `EntitlementStoreTests` — `isEntitledSurvivesStoreRecreation`,
  `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`.

## Gate staging

Phase subagents verify with a build plus the targeted `-only-testing:` suites
above only. The full CI-identical `./scripts/test.sh` runs once after all four
phases commit, via the `run-gate` skill.
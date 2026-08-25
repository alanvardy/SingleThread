# Design Discussion

## Current State

### The pollution problem
`ReminderStore` has two inits (`ReminderStore.swift:13-39`):
1. **Production init** (`:13-19`) — accepts `eventStore: any EventKitStoring`, defaults to `EKEventStore()`. Already injectable.
2. **Pre-populate init** (`:24-39`) — hardcodes `eventStore = EKEventStore()`, no injection. Used everywhere tests need pre-seeded state.

Five unit tests in `ReminderStoreTests.swift` call `addReminder`/`completeCurrentReminder` through the pre-populate init (`:221-259,337-345`). When the host holds `.fullAccess` (common on macOS), `eventStore.save(commit: true)` writes to the real Reminders database. The code acknowledges this at `:231-235` — the no-access path "can't be exercised deterministically" on macOS.

### The EventKitStoring seam
The `EventKitStoring` protocol (`EventKitStoring.swift:8-42`) abstracts EventKit calls. `InMemoryEventStore` (`InMemoryEventStore.swift:13`) implements every requirement — no conformance gaps. One behavioral gap: `makeReminder` sets `calendar = calendars.first` (`InMemoryEventStore.swift:103`) vs `defaultCalendarForNewReminders()` (`EventKitStoring.swift:63`). No production code depends on this divergence.

### Test seams in the app layer
- `--seed '<json>'` → `InMemoryEventStore` injection, iOS only (`SingleThreadApp.swift:117-126`). Resets app-group state between launches. Guards WatchConnectivity activation.
- `--ui-testing` → pre-populate init with real `EKEventStore()` + one hardcoded reminder, `loadsReminders: false` (`SingleThreadApp.swift:137-150`, watch: `SingleThreadWatchApp.swift:98-135`). No writes — safe.
- Widget has no seam (`NextThingWidget.swift:59-62`), but widget extensions can't write to Reminders (read-only in codebase, `ReminderIntents.swift:19,42`).

### CI isolation
Four iOS matrix jobs on `macos-26` runners — each cell is an independent VM (`ci.yml:50-52,111-113,229-231`). Simulators are pre-provisioned, not created/erased. Unit tests run under the same VM image as the developer's simulator. No keychain usage exists. Watch tests create a standalone simulator.

### Test teardown
- UI tests: no teardown except seam-driven `resetPersistedState()` on `--seed` launches (`UITestingSeed.swift:31-42`).
- Unit tests: per-test `defer { UserDefaults.removeObject }` blocks (`ActionButtonTests.swift:54,65,77,93`). No store-level cleanup.

## Desired End State

**No test (unit or UI) can ever persist to a real Apple Reminders database.** Every code path that writes through `EventKitStoring` goes through an injected fake (`InMemoryEventStore` or `FakeEventStore`). A real `EKEventStore` is only ever constructed for fixture creation (`EKReminder` needs one), never for `save`/`remove`.

**Verification**: Run `./scripts/test.sh` locally with the host holding `.fullAccess` to Reminders. Before the fix, `addReminder` tests create "Test reminder" entries. After the fix, the Reminders app shows zero new entries from test runs.

**How we'll know it's correct**:
1. Grep the repo for `ReminderStore(loadsReminders:\s*false` — every match passes `eventStore: InMemoryEventStore()` or a `FakeEventStore`.
2. The `ReminderStore` type exposes exactly one public init. The two-init split is gone.
3. `InMemoryEventStore` covers `makeReminder` faithfully (calendar matches what the real store would do).
4. All existing tests pass with no behavioral changes.

## Patterns to Follow

- **`EventKitStoring` injection** — the `ReminderStore(eventStore:fake, loadsReminders: true)` pattern at `ReminderStoreTests.swift:367-368` and `EventKitStoringTests.swift:463-467` is the template. Every test store gets an injected fake.
- **Recording fakes** — `FakeEventStore` at `EventKitStoringTests.swift:8-98` shows the pattern: configurable return values + record arrays + did-call booleans. Follow this shape for any new fake needs.
- **`loadsReminders: false` for pre-seeded stores** — the convention (already universal in tests) is to seed `.reminders` directly and skip `start()`/`reload()`. Keep this.
- **Per-test `defer` UserDefaults cleanup** — `ActionButtonTests.swift:54` pattern. Not changing; the merged init doesn't affect this.
- **`InMemoryEventStore(reminders:calendars:deliverCompletionOffMain:)`** — already the canonical fake (`InMemoryEventStore.swift:20-25`). We add a `defaultCalendar:` parameter rather than creating a competing fake.
- **`#if !os(watchOS)` write paths** — `ReminderStore.swift:142-147,169-173,198-200`. The merged init stays watchOS-safe via the same compile guards.

### Patterns NOT to follow
- **Pre-populate init with hardcoded `EKEventStore()`** — the cause of the pollution. This init disappears.
- **`(EKEventStore() as any EventKitStoring).makeReminder(...)`** in tests (`ReminderStoreTests.swift:444,454,465,477,490`) — tests should use `InMemoryEventStore.makeReminder` instead. The only exception is `makeReminderSetsDefaultCalendar` (`:502-509`) which tests real store behavior.
- **`EKEventStore()` construction for fixture creation** — `makeReminder(title:...)` at `ReminderStoreTests.swift:515-528` uses a real store to construct `EKReminder` (required by the SDK). This is acceptable and will remain, but with explicit comments explaining it's construction-only, no save.

## Design Decisions

1. **Merge two inits into one**: `ReminderStore` gets a single init with all parameters and defaults: `eventStore: any EventKitStoring = EKEventStore()`, `skipStore: SkippedReminderStore = SkippedReminderStore()`, `excludeStore: ExcludedListStore = ExcludedListStore()`, `loadsReminders: Bool = true`, `reminders: [EKReminder] = []`, `skippedIDs: Set<String> = []`, `authorizationStatus: EKAuthorizationStatus = .notDetermined`, `excludedListTitles: Set<String> = []`, `hasHidden: Bool = false`. Production callers pass nothing (all defaults). Tests inject `eventStore: InMemoryEventStore(reminders:calendars:)` + pre-seeded `reminders:`/`skippedIDs:`. All ~40 call sites update, but each change is mechanical.

2. **`InMemoryEventStore` gets `defaultCalendar:` parameter**: `InMemoryEventStore.init` adds `defaultCalendar: EKCalendar? = nil` (`InMemoryEventStore.swift:20-25`). `makeReminder` uses `defaultCalendar ?? calendars.first`. The `--seed` path (`SingleThreadApp.swift:119-121`) passes `calendars.first` as `defaultCalendar`. `UITestingSeed.materialize()` already builds calendars from a real store (`UITestingSeed.swift:94-117`), so the first calendar matches `defaultCalendarForNewReminders()` in practice. A dedicated unit test verifies the parameter is wired correctly.

3. **`MakeReminderTests` move to `InMemoryEventStore`**: Five of six tests (`ReminderStoreTests.swift:443-492`) switch from `(EKEventStore() as any EventKitStoring).makeReminder(...)` to `InMemoryEventStore().makeReminder(...)`. The sixth (`makeReminderSetsDefaultCalendar`, `:502-509`) stays on the real store and gains a comment: "Tests real EventKit calendar behavior — intentionally uses EKEventStore." A new gap-callout test verifies `InMemoryEventStore.makeReminder` calendar behavior with `defaultCalendar:`.

4. **`--ui-testing` seams switch to `InMemoryEventStore`**: Both iOS (`SingleThreadApp.swift:137-150`) and watch (`SingleThreadWatchApp.swift:98-135`) `--ui-testing` paths build `InMemoryEventStore` instead of `EKEventStore()`. The bookstore still uses `loadsReminders: false` and pre-seeded state. This eliminates the last pre-populate-init callers in production code. No behavioral change — these paths never call save.

5. **Fixture helpers stay as-is**: `makeReminder(title:...)` at `ReminderStoreTests.swift:515-528` and similar helpers in `BackgroundCardTests.swift:128`, `ActionButtonTests.swift:95,113`, etc. continue to construct `EKReminder` with a real `EKEventStore()` — this is an SDK requirement (can't create `EKReminder` without one). They do not call `save` and cannot pollute. Each gets a brief `// Construction only — never saved through EventKit` comment.

## What We're NOT Doing

- **NOT adding cleanup/teardown** (deleting "Test reminder" entries after tests). The fake injection makes cleanup unnecessary and avoids the CI parallelism risk flagged in the task.
- **NOT changing `EKReminder` fixture construction**. SDK requires a real `EKEventStore` to instantiate `EKReminder` and `EKCalendar`. This is construction-only and safe.
- **NOT adding a widget test seam**. Widget extensions are read-only for Reminders (`ReminderIntents.swift:19,42` use `loadsReminders: true` then `completeCurrentReminder()` / `skipCurrentReminderImmediately()` — these are completion/skip operations on already-fetched reminders, not `addReminder`). No pollution risk.
- **NOT changing the `--ui-testing` launch-arg format**. The `--seed` JSON format and `--ui-testing` flag name stay the same — only the store backing changes.
- **NOT touching watchOS `#if` guards**. `completeReminder`/`deleteReminder`/`addReminder` remain no-op on watchOS (`ReminderStore.swift:142-147,169-173,198-200`). The merged init doesn't change this.
- **NOT removing the `usesInMemoryStore` flag** from `SingleThreadApp` (`SingleThreadApp.swift:21,25`). It gates WatchConnectivity activation on `--seed` and remains needed.

## Open Risks

- **Call-site count (~40 mechanical changes)** — risk of merge conflicts if other branches touch `ReminderStore` init call sites. Mitigation: do this on a short-lived branch, merge quickly.
- **`ContentView` and `WatchReminderView` preview inits** (`ContentView.swift:24,39`, `WatchReminderView.swift:22`) — the preview init currently mirrors the pre-populate init. After merging, `ReminderStore()` with all defaults creates a store with `EKEventStore()`. Previews that previously used the pre-populate init must inject `eventStore: InMemoryEventStore()` to avoid touching EventKit. Risk: forgetting one leaves a real store in a preview, which is harmless (previews don't call save) but triggers a TCC prompt if authorization is undetermined.
- **`ReminderIntents.swift` call sites** (`:19,42`) — these use `ReminderStore(loadsReminders: true)` today, which hits the production init. After merging, the default `eventStore: EKEventStore()` is identical behavior. No risk, but verify.
- **`UITestingSeed.materialize()` calendar ordering** — the `--seed` path will pass `seed.calendars.first` as `defaultCalendar`. If a seed JSON omits calendars, `defaultCalendar` is `nil` and `makeReminder` falls back to `calendars.first` (also nil). This matches current behavior where `calendars.first` is nil in the no-calendar case. No regression.
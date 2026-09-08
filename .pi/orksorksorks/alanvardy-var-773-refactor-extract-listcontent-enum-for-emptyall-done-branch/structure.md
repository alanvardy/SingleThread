# Structure Outline

## Approach

Extract the widget's nested `NextThingEntry.State` shape into one shared
`public enum ListContent` in `SingleThreadCore`, add a single post-auth resolver
`ReminderStore.listContent`, and replace the three targets' divergent `if/else`
branch chains with exhaustive no-`default` switches. Pure refactor: widget
behavior byte-for-byte unchanged; iOS/watch empty/all-done copy identical.

Layered bottom-up: **Core type + resolver first** (fully unit-tested), then each
of the three consumers migrating in sequence (widget, iOS, watch). Each consumer
stage is independently valuable and can land on its own; the shared Core layer
is the only surface with real logic, so it is the gating foundation.

## Stage 1: Core — `ListContent` enum + `ReminderStore.listContent` resolver

Delivers the shared type and the single ordering decision. Green tests prove the
ordering rule (`allDone → reminder → empty`) and the `hasHidden` payload once,
so consumers can trust the resolver instead of re-deriving it.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ListContent.swift` (new),
`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThreadTests/ListContentTests.swift` (new, auto-discovered)

**Key changes**:
- `public enum ListContent: Equatable, Sendable { case noAccess; case empty(hasHidden: Bool); case allDone; case reminder(ReminderDisplay) }` — new type. Plain `public enum` (data enum, mirrors `SortOption.swift:6`); `Equatable` for ordering asserts, `Sendable` because it threads through `NextThingEntry` (Swift 6). No `Hashable`/`Codable`/`CaseIterable`.
- `public var listContent: ListContent { get }` — new `ReminderStore` computed property (near other derived state, ~`:129-140`): `if allSkipped { .allDone }`, `if let first = visibleReminders.first { .reminder(first) }`, else `.empty(hasHidden: hasHidden)`. Post-auth — never returns `.noAccess`.

**Tests** (Swift Testing, names must NOT start with `test`):
- `listContentReturnsAllDoneWhenAllSkipped` / `…ReturnsReminderWhenVisible` / `…ReturnsEmptyWithoutHidden` / `…ReturnsEmptyWithHidden` — happy paths for all four resolver outcomes.
- `emptyStoreNeverReturnsAllDone` — sad path pinning the mutual-exclusivity invariant (`allSkipped` requires non-empty, `ReminderStoreTests.swift:480-486`).
- `emptyHasHiddenPayloadDiffers` — `Equatable`: `.empty(false) != .empty(true)`.
- Seeded via `InMemoryEventStore` / `loadsReminders:false` (no real `EKEventStore`).

**Verify**: `make test` (runs `SingleThreadTests`) green; then `make format && make lint` before commit.

---

## Stage 2: Widget — migrate `NextThingEntry` to `ListContent`

The least-guarded surface (no widget test target). Consumes the proven resolver;
its guarantee is Core unit tests (Stage 1) + compile-time exhaustiveness.

**Files**: `SingleThreadWidget/NextThingWidget.swift` (only)

**Key changes**:
- Delete nested `enum State` (`:10-15`); change `let state: State` → `let state: ListContent` (`:18`).
- `makeEntry()` (`:62-106`): auth `default:` → `.noAccess`; `.fullAccess` → `store.listContent` (drop the local `isEmpty`/guard re-derivation).
- View switch `:140-161` unchanged except type and `.empty(hasHidden)` renamed from `.empty(hasHidden)`.

**Tests**: none to add (design decision 8 — no widget test target). Compile-enforced exhaustiveness is the check.

**Verify**: `make build` (SingleThread scheme builds the widget app-extension; a dropped/extra case fails xcodebuild). Manual: exercise widget previews (`:257/:274/:286`) and a home-screen widget sanity pass. No `empty` preview exists yet — note it as out of scope.

---

## Stage 3: iOS — replace `reminderList` `if/else` chain with switch

Migrates the highest-traffic consumer. Builds on resolver + the (still-green)
iOS unit pins, and is guarded end-to-end by the existing `emptyStateTitle` UI
suite.

**Files**: `SingleThread/ContentView.swift` (and `SingleThread/ContentViewModel.swift` — unchanged copy builders, consumed)

**Key changes**:
- `reminderList` (`ContentView.swift:351-387`): keep `authGatedContent` (`:337-346`) untouched; inside `.fullAccess`, replace the `if allSkipped → isEmpty → reminder` chain with `switch store.listContent`:
  - `.allDone → allDoneStateCopy()` (no bottomBar, `.refreshable { reload(clearSkipped: true) }`)
  - `.empty(hasHidden) → emptyStateCopy(hasHidden:)` (+ bottomBar)
  - `.reminder(d) → ReminderCardView` (+ bottomBar)
  - `.noAccess → EmptyView()` — unreachable (auth already diverted); comment it.

**Tests**: run existing, no new — `contentViewEmptyStatesShowDistinctCopy` / `contentViewAllDoneShowsAllDoneCopy` (`SingleThreadTests.swift:32-56`) stay green; `make ui-test` `emptyStateTitle` assertions unchanged.

**Verify**: `make build` + `make test` + `make ui-test` green; `make format && make lint`.

---

## Stage 4: Watch — replace `reminderContent` chain with switch

Last consumer, separate build graph. Same resolver; ghost transition branch
stays view-local and out of the enum.

**Files**: `SingleThreadWatch/WatchReminderView.swift`

**Key changes**:
- Keep auth gate (`:47-54`) and ghost branch (`:79-81`) *outside* the switch; then `switch store.listContent`:
  - `.allDone → allDoneState`
  - `.empty(hasHidden) → noRemindersState(hasHidden:)`
  - `.reminder → reminderCard`
  - `.noAccess → access-denied view (or `EmptyView()`) — after the `.notDetermined` gate.

**Tests**: run existing — `ShowCompletionGlowStateTests` (transition ghost untouched), watch UI `emptyStateTitle` assertions `SingleThreadWatchUITestsFlows.swift:39-195`.

**Verify**: `make watch-build` + `make watch-test` + `make watch-ui-test` green; `make format && make lint`.

---

## Testing Checkpoints

- **After Stage 1** (`make test`): `ListContent` ordering + equality tests green; all existing `SingleThreadTests` pins green.
- **After Stage 2** (`make build`): widget compiles with exhaustive `ListContent` switch; no `switch must be exhaustive` error.
- **After Stage 3** (`make build && make test && make ui-test`): `emptyStateTitle` UI assertions + copy-builder unit pins green.
- **After Stage 4** (`make watch-build && make watch-test && make watch-ui-test`): watch UI `emptyStateTitle` + glow-suite green.
- **Full gate**: `make check` (i.e. `./scripts/test.sh`, identical to CI) run ONCE by the parent after all stages commit — not by phase workers.

## Cross-cutting notes (can't be built purely bottom-up)

- **Widget has no test target** — its "unchanged" guarantee rests on Stage-1 Core unit tests + code review, not widget automation. Explicit residual risk (design decision 8); do not add a widget test target (needs pbxproj IDs, scheme wiring, `-only-testing`, CI matrix).
- **Unreachable `.noAccess` arms** in the iOS/watch content switches (Stages 3-4) are required for exhaustiveness but dead while the auth gate is separate — worth a comment at each site so a future "collapse auth into the enum" refactor recognizes the footgun.
- **`Sendable` transitivity** depends on `ReminderDisplay` already being `Sendable` (confirmed — flows through `NextThingEntry` today); if a Scratch finding differs, drop `Sendable` and re-verify the widget build.
- **SwiftFormat `organizeDeclarations`** will reorder the new enum/extension — run `make format` before each commit to avoid phantom diffs.

Next: run `/5_plan`.
# Design Discussion — shared `ListContent` enum for empty/all-done ordering

## Current State

Three UI targets compute "what should this screen show" independently, with
three different branch shapes around the same store-derived state.

- **Widget** — a widget-local nested enum `NextThingEntry.State` with four cases
  `noAccess / empty(Bool) / allDone / reminder(ReminderDisplay)`
  (`NextThingWidget.swift:10-15`, `let state: State` at :18). `makeEntry()`
  builds it as `auth → isEmpty → allDone(guard) → reminder`
  (`NextThingWidget.swift:62-106`); the view switches exhaustively at
  `NextThingWidget.swift:140-161`. Zero test coverage: no widget test target
  exists (`project.pbxproj:240-409`, `scripts/test.sh:237-337`).
- **iOS** — auth gate (`ContentView.swift:337-346`) separate from list
  content, which is an `if/else` chain: `allSkipped` → `isEmpty` → `reminder`
  (`ContentView.swift:356-387`). Copy builders live in
  `ContentViewModel.swift:58-83` (`emptyStateCopy(hasHidden:)`, `allDoneStateCopy()`).
- **Watch** — auth gate (`WatchReminderView.swift:47-54`), then
  `ghost → allSkipped → reminder → else-empty` (`WatchReminderView.swift:79-87`);
  empty states are text-only (`WatchReminderView.swift:149-166`), no icons.

All three are semantically identical only because `ReminderStore.allSkipped`
(`ReminderStore.swift:136-140` = `!reminders.isEmpty && visibleReminders.isEmpty`)
is mutually exclusive with an empty list, so the differing empty-check placement
cannot diverge outcomes today. A future reordering would have to be replicated
in all three places manually — this is the structural divergence VAR-773 targets.

## Desired End State

A single shared enum in `SingleThreadCore`:

```swift
public enum ListContent: Equatable, Sendable {
    case noAccess
    case empty(hasHidden: Bool)
    case allDone
    case reminder(ReminderDisplay)
}
```

- `ReminderStore` exposes one resolver property `listContent` (post-auth) so the
  empty/all-done/reminder ordering lives in exactly one place.
- All three targets render via an exhaustive `switch` over `ListContent` — no
  more `if/else` chains.
- Widget behavior is byte-for-byte unchanged; iOS and watch empty/all-done copy
  semantics stay identical (same strings, same `hasHidden` flip).

### Verification

- `make test` (unit): new `ReminderStore.listContent` ordering tests pass; all
  existing pins still pass — `SingleThreadTests.swift:32-56` (copy builders),
  `ReminderStoreTests.swift:438-501` (`hasHidden`/`allSkipped`).
- `make ui-test` + `make watch-ui-test`: every `emptyStateTitle` UI assertion
  unchanged — `SingleThreadUITestsFlows.swift:34/:43/:87/:149/:167`,
  `ActionButtonsUITests.swift:40`, `SingleThreadWatchUITestsFlows.swift:39-195`.
- `make build` + `make watch-build`: exhaustiveness of the three no-default
  switches is compile-enforced (research Q4); a dropped case fails xcodebuild.

## Patterns to Follow

- **Plain `public enum` for data enums** — `ListContent` is a value/enumeration
  type, so use `public enum`, not the `public nonisolated enum` used by the
  casing/logic enums (`ReminderSkip.swift:31`, `ReminderSort.swift:4`); mirror
  `SortOption.swift:6`, which documents "pure Core logic, no SwiftUI; presentation
  lives in the app target."
- **Existing no-default exhaustive-switch discipline** — the repo's one
  multi-target Core enum `ReminderPriority.Level` (`ReminderSkip.swift:31-35`) is
  switched with no `default` in iOS (`ReminderCardView.swift:173-178`) and watch
  (`WatchReminderView.swift:272-277`). New `ListContent` switches must match:
  exhaustive, no `default`, and a new case breaks all consumers loudly (SwiftLint
  will NOT catch it — only xcodebuild; research Q4).
- **Derived state as store computed properties** — `allSkipped`/`visibleReminders`/
  `hasHidden` are `ReminderStore` properties (`ReminderStore.swift:58-62,129-140`);
  `listContent` follows the same shape.
- **Copy from `SharedStrings`, not literal** — titles/messages come from Core
  `SharedStrings` (`LocalizedString+Shared.swift:11`, members `allDone` :40,
  `noReminders` :44, `nothingDueRightNow` :64, `noRemindersYet` :68); consumers
  pass `AttributedString`/`String` to `Text(...)`.
- **Unit-test names must not start with `test`** (SwiftFormat strips them);
  UI/XCTest names keep `test…` — see `SingleThreadTests.swift:32` vs
  `SingleThreadUITestsFlows.swift:34`.

### Flags: patterns NOT to copy

- The three current `if/else` branch chains (`ContentView.swift:356-387`,
  `WatchReminderView.swift:79-87`) are **not** exhaustiveness-checked — that's the
  failure mode being removed, not a pattern to preserve.
- Icons are intentionally un-centralized (0 hits in Core, research Q6); do not
  start centralizing SF Symbols/descriptions into Core now.
- `NextThingEntry.State` has no `CaseIterable` and no test coverage (research Q7);
  don't replicate its widget-locality, but also don't add `CaseIterable` just to
  mirror it — `ListContent` doesn't need it.

## Design Decisions

1. **Payload label `empty(hasHidden:)`** — matches the existing `ReminderStore.hasHidden`
   (`ReminderStore.swift:58`) and the widget's current `.empty(store.hasHidden)`
   (`NextThingWidget.swift:75`); the task's `hasHiddenSubtle` has no referent in the
   codebase and would only add confusion.

2. **`empty` stays a plain Bool** — all three targets derive their empty-state UI
   from the single `hasHidden` bool at different granularity (iOS whole-card
   `ContentViewModel.swift:58-75`, widget message `NextThingWidget.swift:149-153`,
   watch subtitle `WatchReminderView.swift:163`). Carrying icon/copy into Core would
   violate "pure Core logic, no SwiftUI" (`SortOption.swift:2`).

3. **Post-auth resolution only** — the resolver `ReminderStore.listContent` computes
   `.empty/.allDone/.reminder` from store-derived state. Auth stays target-local:
   `.noAccess` is produced by each target's own auth switch, and iOS/watch keep their
   `.notDetermined → ProgressView(requestingAccess)` (`ContentView.swift:339-340`,
   `WatchReminderView.swift:48-49`) which has no widget equivalent. Folding auth in
   would collapse that state and change iOS/watch behavior.

4. **One shared resolver: `ReminderStore.listContent`** (computed property) with
   canonical order `allDone → reminder → empty`:

   ```swift
   public var listContent: ListContent {
       if allSkipped { return .allDone }
       if let first = visibleReminders.first { return .reminder(first) }
       return .empty(hasHidden: hasHidden)
   }
   ```

   This is order-equivalent to all three current shapes (mutual exclusivity of
   `allSkipped` vs empty, `ReminderStore.swift:138-140`) but defined once. Chosen in
   `ReminderStore.swift` near the other derived state (:129-140); testable through
   existing store seams (`InMemoryEventStore`, `loadsReminders:false`, `--seed`).

5. **Target render layout (no leftover `if/else`):**
   - iOS: keep `authGatedContent` (:337-346); the `.fullAccess` branch switches on
     `store.listContent` — `.allDone → allDoneStateCopy()`, `.empty(hasHidden) →
     emptyStateCopy(hasHidden:)`, `.reminder(d) → ReminderCardView`, `.noAccess →
     EmptyView()` (unreachable — auth already diverted; comment it).
   - Watch: keep ghost branch (:79-81) *outside* the switch, then
     `switch store.listContent` — `.allDone → allDoneState`, `.empty(hasHidden) →
     noRemindersState(hasHidden)`, `.reminder → reminderCard`, `.noAccess → access
     denied view` (or `EmptyView()`), after the existing `.notDetermined` gate.
   - Widget: delete nested `State` (`NextThingWidget.swift:10-15`); `let state:
     ListContent` (:18); `makeEntry` maps auth `default:` → `.noAccess` and
     `.fullAccess` → `store.listContent` (:62-106). The view switch (:140-161) is
     unchanged except type and `.empty(hasHidden)`.

6. **Conformance set: `Equatable` + `Sendable`, no `Hashable`/`Codable`** —
   `Equatable` for the new ordering asserts; `Sendable` because the enum is threaded
   through a `TimelineEntry` (`NextThingWidget.swift:9-22`) and Swift 6 strict
   concurrency. `ReminderDisplay` is already `Sendable` (it flows through
   `NextThingEntry` today). No Core enum is `Codable` (research Q7) — persistence is
   raw-string UserDefaults, not needed here.

7. **Watch ghost branch stays view-local, out of the enum** — it's a
   completion-transition animation overlay (`WatchReminderView.swift:79-81`,
   `ShowCompletionGlowStateTests.swift:32-222`), not a content state.

8. **No new test target.** Widget behavior "must remain unchanged" is verified by the
   shared-resolver Core unit tests plus the existing iOS/watch UI suites — a
   `SingleThreadWidgetTests` target would require pbxproj IDs, scheme wiring,
   `-only-testing` in `scripts/test.sh`, and CI matrix entries (not a file-add;
   AGENTS.md). Flagged as a residual risk, not done now.

## What We're NOT Doing

- **Not changing** `ReminderStore` derived-state logic (`allSkipped`/`hasHidden`/
  `visibleReminders`) — only consuming them via `listContent`.
- **Not centralizing** icons or empty-state descriptions into Core; presentation
  (SF Symbols, app-bundle copy like "Nothing due" `SingleThread/Resources/...:1316`)
  stays target-local.
- **Not touching** auth-gate semantics or the `.notDetermined → ProgressView` path.
- **Not unifying** the widget's direct `EKEventStore.authorizationStatus(for: .reminder)`
  call (`NextThingWidget.swift:68`) with `store.authorizationStatus` — optional
  follow-up, out of scope.
- **Not changing** any copy strings, `SharedStrings`, or the
  Core-`nothingDueRightNow` vs app-bundle-`Nothing due` split (both pinned by tests).
- **Not adding** a widget test target (see decision 8).
- **Not** adding the missing `.empty` widget preview (`NextThingWidget.swift:257-286`)
  unless it falls out naturally — cosmetic, out of scope.

## Open Risks

- **Widget is unmonitored**: no widget test target and no `emptyStateTitle`-style
  assertion on watch a11y beyond `emptyStateTitle` presence. The "unchanged" guarantee
  rests entirely on the resolver unit tests + code review, not widget automation.
- **Unreachable `.noAccess` arms** in the iOS/watch content switches: required for
  exhaustiveness but dead code if the auth gate is later refactored — a footgun for a
  future "collapse the auth gate into the enum" change.
- **`Sendable` transitivity** depends on `ReminderDisplay` already being `Sendable`;
  if Scratch findings differ, drop `Sendable` and confirm the widget build.
- **Invariant coupling**: the `allDone → reminder → empty` order assumes
  `allSkipped`'s "non-empty" conjunct (`ReminderStore.swift:139`) holds. It does today
  (verified `ReminderStoreTests.swift:480-486`); a future change to that invariant
  could surface here first.
- **SwiftFormat `organizeDeclarations`** will reorder the new enum/extension under
  `make format` — run it before commit to avoid phantom diffs (AGENTS.md).

Next: run `/4_structure`.
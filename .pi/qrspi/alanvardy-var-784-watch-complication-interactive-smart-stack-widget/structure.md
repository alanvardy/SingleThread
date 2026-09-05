# Structure Outline

## Approach

Ship a watchOS WidgetKit widget (three accessory complication families + an interactive Smart Stack)
in a **new `SingleThreadWatchWidget` extension target** embedded in the watch app, sharing today's
`visibleReminders.first` derivation via a Core `ReminderWidgetState` machine, and routing Complete/Skip
through the watch app (App Group mailbox + `openAppWhenRun`) — never WCSession from the widget process.
Built bottom-up: extraction → target/plumbing → mutation → presentation → refresh.

---

## Layer 1: Shared widget-state derivation (Core)

Extract the auth-gate → reload → branch logic from `NextThingWidget.makeEntry()` into a WidgetKit-free,
unit-testable Core function, and refactor the iOS widget onto it. This is the one tested derivation every
widget surface (iOS today, watch next layer) consumes.

**Files**: `Core/ReminderWidgetState.swift` (new), `SingleThreadWidget/NextThingWidget.swift` (consume only)

**Key changes**:
- `enum ReminderWidgetState: Equatable, Sendable { case noAccess; case empty(hasHidden: Bool); case allDone; case reminder(ReminderDisplay) }` — new type
- `@MainActor func makeWidgetState(store: ReminderStore, authorization: EKAuthorizationStatus) async -> ReminderWidgetState` — new; caller builds the fresh store + sets `showsUndatedReminders`/`sortOption`, passes the auth gate in so `.noAccess` is testable (production passes `EKEventStore.authorizationStatus(for: .reminder)`). Holds `await store.reload()` + the four-way branch (`ReminderStore.swift:358-413`, `NextThingWidget.swift:74-102`).

**Tests** (`SingleThreadTests/ReminderWidgetStateTests.swift`, injected `InMemoryEventStore` + `loadsReminders: false` + `noopSettle`): `.reminder` (seeded store), `.empty(false)`, `.empty(hasHidden: true)`, `.allDone` (all skipped) — happy; `.noAccess` for `.denied` and `.notDetermined` — sad.
**Verify**: `make test` with `-only-testing:SingleThreadTests/ReminderWidgetStateTests`; then `make build` (iOS widget refactor still compiles, behavior unchanged).

---

## Layer 2: Watch widget extension target + App Group plumbing

Stand up the build foundation: a compilable, embedded `SingleThreadWatchWidget` extension and the App Group
entitlement both watch targets need to share state. No new *behavior* yet — this is the "schema/build"
layer the watch surface is erected on.

**Files**: `SingleThread.xcodeproj/project.pbxproj` (new target + Embed App Extensions phase in `SingleThreadWatch`), `SingleThreadWatchWidget/` (stub `WidgetBundle`), two entitlement files (watch app + extension, `group.app.alanvardy.SingleThread`), `scripts/test.sh` (`EXPECTED_TARGET_LITERALS` 20 → 22, comment `8+6+6` → `8+6+8`)

**Key changes**:
- `SingleThreadWatchWidget` — `.appex`, `WATCHOS_DEPLOYMENT_TARGET 26.5`, bundle id `app.alanvardy.SingleThread.watchwidget`, embedded in watch app
- `group.app.alanvardy.SingleThread` App Group capability on `SingleThreadWatch` **and** `SingleThreadWatchWidget` (both currently entitlement-less); this moves `AppGroup.defaults` from `.standard` to the real suite on watch (one-time reset of watch skips/exclusions/sort — phone re-syncs)
- deployment-target guard counts: `20`→`22` (`8 IPHONEOS + 6 MACOSX + 8 WATCHOS`), recompute via the guard's grep before finalizing

**Tests**: none new (plumbing only) — the checkpoint is the guard + existing suites, not new assertions.
**Verify**: `make watch-build` (new target compiles + embeds); `./scripts/test.sh` deployment-target guard passes with updated counts; existing watch suites still green (`make watch-test`).

---

## Layer 3: Mutation dispatch + mailbox drain (Core + watch), no WCSession from the widget

Make Complete/Skip from the Smart Stack actually reach the phone: the widget intent records a pending
action and opens the app; the app drains it via the already-wired relay hooks. iOS behavior is unchanged
(direct EventKit write).

**Files**: `Core/PendingReminderAction.swift` (new), `Core/ReminderIntents.swift` (`#if os(watchOS)` branch), `SingleThreadWatch/WatchAppViewModel.swift` (drain on `.task`/launch)

**Key changes**:
- `struct PendingReminderAction: Codable, Equatable, Sendable { enum Kind: String, Codable { case complete, skip }; let kind: Kind; let identifier: String }` — new type (identifier = `calendarItemIdentifier`)
- `struct PendingReminderActionStore` — key `"pendingReminderAction"`, injected `UserDefaults` (default `AppGroup.defaults`), mirroring `SkippedReminderStore`; `load() -> PendingReminderAction?` / `save(_:)` / `clear()`
- `CompleteReminderIntent`/`SkipReminderIntent`: `static var openAppWhenRun: Bool { true }` (watchOS); `perform()` writes the action + returns `.result()` (no store mutation, no `SkippedReminderSyncService`)
- `WatchAppViewModel.drainPendingReminderAction() async` — load → `store.completeReminder(identifier:)` / `store.skipCurrentReminder()` (fires `onCompleteReminder`→`requestCompleteReminder` `ReminderStore.swift:210-218`, `onSkipSetChanged`→`pushAll()` `SkippedReminderSyncService.swift:167-208`) → `clear()` → `WidgetCenter.reloadAllTimelines()`

**Tests**: `SingleThreadTests/PendingReminderActionTests.swift` (Codable round-trip, store save/load/clear). `SingleThreadWatchTests/PendingActionDrainTests.swift` (fake `SkipSyncSession` + `InMemoryEventStore`, mirroring `WatchSyncPipelineTests`): drain-applies-completion-and-fires-relay, drain-skip-fires-push-all, drain-clears-mailbox, drain-no-ops-when-empty.
**Verify**: `make test` (iOS) + `make watch-test` (watch unit).

---

## Layer 4: Watch widget surface (bundle, provider, accessory views)

Render the three accessory families from `ReminderWidgetState`, wire the interactive buttons. Presentation
only — it consumes Layer 1's state and Layer 3's intents.

**Files**: `SingleThreadWatchWidget/SingleThreadWatchWidgetBundle.swift`, `WatchNextThingWidget.swift`, `WatchNextThingProvider.swift`, accessory family views (rectangular/corner/circular)

**Key changes**:
- `@main struct SingleThreadWatchWidgetBundle: WidgetBundle` — registers `WatchNextThingWidget()`
- `struct WatchNextThingWidget: Widget` — `StaticConfiguration`, `kind = "NextThingWatch"`, `supportedFamilies = [.accessoryRectangular, .accessoryCorner, .accessoryCircular]`
- `struct WatchNextThingEntry: TimelineEntry { let date: Date; let state: ReminderWidgetState }`
- `struct WatchNextThingProvider: TimelineProvider` — `getTimeline` builds a fresh store, sets `showsUndatedReminders`/`sortOption` from `AppGroup.defaults`, calls `makeWidgetState(store:authorization:)`, single-entry `.after(.now + 15*60)`
- views: `Button(intent: CompleteReminderIntent())` / `Button(intent: SkipReminderIntent())` (Smart Stack only); empty-state glyphs via `SharedStrings` (decision 6). Explicit `@MainActor` (the extension target does not enable default MainActor isolation, unlike the app/watch targets).

**Tests**: none runnable — the widget process is not XCUITest-drivable; rendering is guarded by the Layer 1 state-machine tests plus this layer's build. State the UI-test gap explicitly in the PR.
**Verify**: `make watch-build`; manual simulator smoke — complication renders all four states, Smart Stack shows buttons, tap opens the watch app.

---

## Layer 5: Refresh lifecycle + full gate (integration/hardening)

Close the freshness and quality loops, then run the single full gate.

**Files**: `SingleThreadWatch/WatchAppViewModel.swift` (add `relaunchWidgetReload` in mutation + sync-receive hooks, alongside `:165-198`), no other source

**Key changes**:
- `WidgetCenter.shared.reloadAllTimelines()` fired from the watch app's mutation and sync-receive paths (mirrors iOS `AppViewModel.swift:76-77`)
- confirm `.after(15 min)` timeline policy from Layer 4 is in place

**Tests**: none new; `WidgetCenter` isn't fakeable, so freshness is covered by the existing watch suites + manual smoke.
**Verify**: full `./scripts/test.sh` (the ONE complete gate), plus `make periphery` and `make lint`.

---

## Testing Checkpoints

- **After L1**: `make test` (`ReminderWidgetStateTests`) green + `make build` green — else do not proceed.
- **After L2**: `make watch-build` green + deployment-target guard (22) green + `make watch-test` green.
- **After L3**: `make test` + `make watch-test` green (action codec + drain suites).
- **After L4**: `make watch-build` green + L1/L3 suites still green + manual smoke (four states render, buttons wire).
- **After L5**: full `./scripts/test.sh` + `make periphery` + `make lint` green.

## Cross-cutting notes

- **The only thing not provable below the top layer is the widget's actual rendering and the
  tap→`openAppWhenRun`→app→relay handoff** (the widget process is not XCUITest-drivable). Every logical
  link in that chain is stubbed/tested one layer down: state (L1) and the mailbox+relay (L3) are unit-green
  before the views (L4) that only route between them.
- **App Group + storage shift** (L2) is the one physical side effect; it's build/guard-checked and flagged
  in the PR, with no migration code by design (phone re-syncs watch skips/exclusions).
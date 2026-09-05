# Design Discussion — Watch complication + interactive Smart Stack widget (VAR-784)

## Current State

The iPhone already ships a WidgetKit widget, and the watch ships a full app. Neither
exposes a watch-face surface yet.

- **One shared derivation, three consumers.** `ReminderStore.visibleReminders` is a pure
  function of `reminders` + `skippedIDs` + `excludedListTitles` + `sortOption`
  (`Core/ReminderStore.swift:129-135`). iOS, watch, and widget all read `visibleReminders.first`
  and build `ReminderDisplay(reminder:)` identically (`ReminderDisplay.swift:11-21`).
- **iOS widget** (`SingleThreadWidget`, iOS-only, `project.pbxproj:339-361`): `NextThingWidget`
  (`NextThingWidget.swift:113-131`) with families `.systemSmall/.systemMedium/.systemLarge`, an
  entry state machine `NextThingEntry.State` (`:7-29`), and `makeEntry()` (`:62-110`) that gates on
  `EKEventStore.authorizationStatus`, builds a **fresh** `ReminderStore(loadsReminders: true)` per
  render, and branches to `.noAccess` / `.empty(hasHidden)` / `.allDone` / `.reminder`
  (`:74-102`). Refresh is a single-entry timeline with `.after(15 min)` (`:54-55`) plus external
  `WidgetCenter.reloadAllTimelines()` from the phone app (`AppViewModel.swift:76-77`). It has **no
  test coverage and no test seam** (research Q6).
- **Watch app** (`SingleThreadWatch`, `SDKROOT watchos`, `WATCHOS_DEPLOYMENT_TARGET 26.5`,
  `project.pbxproj:965,993`): `WatchReminderView` renders the three empty states in a fixed branch
  order — completion ghost → `allSkipped` ("All Done") → `visibleReminders.first` → "No Reminders"
  (`WatchReminderView.swift:77-104`), strings via `SharedStrings` (`LocalizedString+Shared.swift:11-72`).
- **watchOS EventKit is read-only** (`SkippedReminderSyncService.swift:21-22`). Complete/delete
  mutate the local array, persist a 5-minute `PendingCompletionStore` entry, and relay the
  identifier to the phone via `sendMessage` (`ReminderStore.swift:189-226`). Those relay hooks
  (`onCompleteReminder`/`onDeleteReminder`) are wired in `WatchAppViewModel.setupSyncService`
  (`WatchAppViewModel.swift:197-198`), **not in the intents** — the intents build a bare fresh
  store with no hooks (`ReminderIntents.swift:19-22, 49`).
- **Wire discipline**: one `PayloadKey` enum in shared Core (`SkippedReminderSyncService.swift:268-281`);
  `updateApplicationContext` is full-state replace (latest-wins), `sendMessage` is command-only. No
  reminder *content* crosses the wire — each side derives its list from local EventKit.

## Desired End State

A watchOS WidgetKit widget, bundled with the watch app, providing:

- **Three accessory complication families** — `.accessoryRectangular`, `.accessoryCorner`,
  `.accessoryCircular` — showing the next reminder directly on the watch face without launching the
  app.
- **An interactive Smart Stack widget** using those same accessory families, with
  `Button(intent: CompleteReminderIntent())` / `Button(intent: SkipReminderIntent())` (watchOS 11+
  interactive Smart Stack; complications remain display-only).
- **Same derivation and empty states** as today's surfaces — `visibleReminders.first` + the
  "All Done" / "No Reminders" / "Nothing due right now" branches, adapting to the tiny families with
  compact glyphs (`SharedStrings` only, no new ad-hoc strings).
- **Working mutations**: Complete/Skip from the Smart Stack hand off to the watch app (App Group
  mailbox + `openAppWhenRun = true`), and the watch app reaches the phone through its existing
  `SkippedReminderSyncService` relay — the widget process itself never touches WatchConnectivity.
- **Refresh** through the same `.after(15 min)` cadence plus `WidgetCenter.reloadAllTimelines()`
  triggered from the watch app's mutation/sync-receive paths.

**Verification**: `make watch-build` compiles (now including the embedded `SingleThreadWatchWidget`
extension); shared entry logic covered by Swift Testing unit tests in Core (driven by
`InMemoryEventStore`); the mailbox-drain logic covered by a watch unit test (fake `SkipSyncSession`);
existing watch UI tests (`make watch-ui-test`) still pass; the `scripts/test.sh` deployment-target
guard compiles with the updated literal counts (decision 1).

## Patterns to Follow

- **`visibleReminders.first` + `ReminderDisplay(reminder:)`** — never re-derive filtering/sorting;
  reuse the store (`ReminderStore.swift:129-135`, `ReminderDisplay.swift:11-21`).
- **Fresh store per render** for the widget (`NextThingWidget.swift:70`), with
  `showsUndatedReminders`/`sortOption` read from defaults and `await store.reload()` — the widget
  must not share the app's long-lived store (`AppViewModel.swift:16`).
- **`SharedStrings` for every user-facing string** (`LocalizedString+Shared.swift:11-72`) — matches
  `ReminderIntentsTests`' expectation that titles resolve from the app/widget bundle, and
  `LocalizationTests`' four-catalog cross-check. **Do NOT** add raw literals like the existing
  "Enable Reminders access in Settings" in `WatchReminderView.swift:52-54`.
- **App Group for anything persisted and shared with the watch** — `AppGroup.defaults`
  (`AppGroup.swift:11-17`), which collapses to `.standard` on watchOS; use the same explicit
  construction the watch app already uses (`WatchAppViewModel.swift:155-161`).
- **Hook naming convention**: `on*Changed` (local), `on*Received` (sync receive), `onCompleteReminder`/
  `onDeleteReminder` (watch→phone relay) — write-only, wired once before `activate()`.
- **Test seams**: `InMemoryEventStore` (`Core/InMemoryEventStore.swift`), `loadsReminders: false`,
  `noopSettle` — the shared entry builder must accept an injected store so Core tests drive all four
  states without a real `EKEventStore`.
- **Do NOT introduce a relative due-date formatter.** No surface formats due dates relatively today;
  they all render `Text(due, style: .date)` (`ReminderCardView.swift:78`, `WatchReminderView.swift:242`,
  `NextThingWidget.swift:222`). The complication should reuse `ReminderDisplay.dueDate` as-is (folding
  on the tiny families) rather than invent a "Today/Tomorrow" layer that `localization` would have to
  carry.

## Design Decisions

1. **New watchOS Widget Extension target `SingleThreadWatchWidget`, embedded in the watch app.** A
   WidgetKit complication/Smart Stack widget is delivered by a separate `.appex` extension with its own
   `@main WidgetBundle`, bundle id, and `NSExtension`/Info.plist — it cannot live in the watch app
   target. Add `SingleThreadWatchWidget` (`WATCHOS_DEPLOYMENT_TARGET 26.5`, bundle id
   `app.alanvardy.SingleThread.watchwidget`; exact suffix confirmed at implementation) and embed it in
   `SingleThreadWatch` (Embed App Extensions copy phase). This is real target plumbing: new pbxproj
   object IDs, two new `WATCHOS_DEPLOYMENT_TARGET` literals (Debug + Release) that move
   `scripts/test.sh`'s `EXPECTED_TARGET_LITERALS` from 20 → 22 and the `8+6+6` comment to `8+6+8`
   (recompute via the guard's grep, `test.sh:114-192`), and watch-scheme wiring. The iOS
   `SingleThreadWidget` extension is not reusable (iOS-only, system families).

2. **App Group entitlements on both watch targets + one-time storage shift.** The widget extension and
   the watch app are separate processes with separate `.standard` — without an App Group the widget
   reads empty skip/exclude/undated state and a mailbox the app can't see. Add the App Groups
   capability (`group.app.alanvardy.SingleThread`) to `SingleThreadWatch` and `SingleThreadWatchWidget`
   (both currently have no entitlements). Consequence: `AppGroup.defaults` stops collapsing to
   `.standard` on watchOS and resolves the real suite, so watch-side skips/exclusions/sort reset once.
   That is acceptable — watch skips/exclusions are phone-mirrored and re-sync on the next
   WatchConnectivity exchange (documented in the PR; no migration code). The widget must read/write via
   `AppGroup.defaults`, never `UserDefaults.standard`.

3. **Share the entry state machine in Core, keep views per-target.** Extract a WidgetKit-free
   `ReminderWidgetState` enum (`.noAccess` / `.empty(Bool)` / `.allDone` / `.reminder(ReminderDisplay)`)
   plus `makeWidgetState(store:authorization:)` into `SingleThreadCore`, holding the auth gate → reload
   → branch logic now in `NextThingWidget.makeEntry()` (`:62-110`). Refactor the iOS widget to consume
   it. Each target keeps its own `TimelineEntry`/`TimelineProvider` and views: iOS system families vs.
   watch accessory families render with different SwiftUI APIs, so sharing views is not worth it. This
   is what makes the state machine unit-testable.

4. **Mutations pass through the watch app — App Group mailbox + `openAppWhenRun`, never WCSession from
   the widget.** A widget extension process is not a WatchConnectivity peer; wiring
   `SkippedReminderSyncService` inside `perform()` (the prior design) cannot deliver. On watchOS,
   `CompleteReminderIntent`/`SkipReminderIntent.perform()` write a pending action (kind +
   `calendarItemIdentifier`) to a single `AppGroup.defaults` key (`pendingReminderAction`), declare
   `openAppWhenRun = true` so the system opens the watch app after the tap, and return. The watch app
   drains the mailbox on `.task`/launch and applies the action through its existing mutation entry
   points, whose relay hooks are already wired (`onCompleteReminder` → `requestCompleteReminder`
   `ReminderStore.swift:210-218`, `onSkipSetChanged` → `pushAll()` `SkippedReminderSyncService.swift:167-208`),
   then clears the mailbox and calls `WidgetCenter.reloadAllTimelines()`. The existing 5-minute
   `PendingCompletionStore` hide covers the window until the phone confirms. iOS behavior is unchanged
   (direct local EventKit write).

5. **One watch widget, three accessory families, interactive in Smart Stack only.**
   `supportedFamilies = [.accessoryRectangular, .accessoryCorner, .accessoryCircular]`; render
   `Button(intent:)` actions (mirroring `NextThingWidget.swift:166-186`) — WidgetKit only surfaces
   them in Smart Stack, so complications stay read-only with no risk of losing the button.

6. **Empty-state fidelity adapted to tiny families.** `.accessoryRectangular` can carry a compact
   label + glyph per state ("All Done" checkmark, "No Reminders", "Nothing due right now" when
   `hasHidden`) using `SharedStrings`; `.accessoryCorner`/`.accessoryCircular` fall back to a single
   compact glyph (e.g. checkmark.circle for all-done, lock for no-access) so the complication is never
   blank. Keep the `hasHidden` second broad fetch identical to iOS (`ReminderStore.swift:380-391`)
   via `makeWidgetState`.

7. **Refresh: `.after(15 min)` cadence + watch-side `reloadAllTimelines`.** Mirror the iOS timeline
   policy (`NextThingWidget.swift:54-55`) and add `WidgetCenter.reloadAllTimelines()` to the watch
   app's mutation and sync-receive hooks (alongside `WatchAppViewModel.swift:165-198`) so foreground
   app use refreshes the widget promptly. This is watch-local; the phone already triggers its own
   widget reload via `AppViewModel.swift:76-77`.

8. **Testing.** Shared `makeWidgetState` covered by Swift Testing unit tests in `SingleThreadTests`
   using `InMemoryEventStore` + `loadsReminders: false` for all four states and the authorization
   gates; the mailbox payload and drain (watch app applies a pending action and fires the right relay
   hooks) covered by watch unit tests using a fake `SkipSyncSession`, mirroring `WatchSyncPipelineTests`
   in `SingleThreadWatchTests`; watch-app regression stays on the existing `--ui-testing` seam
   (`WatchAppViewModel.swift:96-135`). `SingleThreadWatchWidget` is a widget extension, not a new test
   *target*, so `Makefile`/`scripts/test.sh` `-only-testing` lists and the CI matrix are unchanged
   (the deployment-target guard counts DO change — decision 1).

## What We're NOT Doing

- **Not adding a new test target** — `SingleThreadWatchWidget` is a widget extension, so
  `Makefile`/`scripts/test.sh` `-only-testing` lists and the CI matrix are unchanged (the
  deployment-target guard counts still change — decision 1).
- **Not syncing reminder content over WatchConnectivity** — the widget derives from local EventKit
  exactly like the watch app; the wire stays identifiers/prefs only.
- **Not building an iOS-family-agnostic shared view** across the iOS widget and watch widget — those
  render with different WidgetKit APIs; only the state machine and display model are shared.
- **Not introducing relative due-date strings** ("Today"/"Tomorrow") or new localization keys beyond
  reusing `SharedStrings`; no new catalogs.
- **Not changing iOS widget behavior** beyond the mechanical refactor onto `makeWidgetState`.
- **Not making complications interactive** — buttons are a Smart Stack affordance only.

## Open Risks

1. **`openAppWhenRun = true` changes the tap UX** — the Smart Stack button performs its action and then
   opens the watch app to drain the mailbox and relay. This is the platform-sanctioned handoff, but the
   interaction does not stay "in place" in the Smart Stack. If the app is slow to launch, the action is
   still queued and drains on next foreground. Acceptable for v1; note in the PR.
2. **Timeline refresh latency in Smart Stack**: the 15-minute timer and watch-app-driven reload are
   best-effort; a reminder completed on the phone may take up to the next timeline refresh to vanish from
   the watch complication. Acceptable for v1, but worth noting in the PR.
3. **Widget-process UI test gap**: the `--ui-testing` seam (`WatchAppViewModel.swift:96-135`) drives the
   watch *app*, not the system-launched widget extension; complication/Smart-Stack rendering is not
   XCUITest-drivable the same way. Unit tests on `makeWidgetState` plus the mailbox-drain test are the
   regression guards here — say so explicitly in the PR.
4. **`identifier_name`/lint on compact glyph code** and the `.swiftformat` `organizeDeclarations` rules —
   follow the repo's SwiftFormat/SwiftLint gate (`make lint`/`make format`) for the new watch files.
5. **App Group entitlement + one-time storage shift on device**: adding the App Groups capability to the
   two watch targets requires the entitlement in the watch provisioning profile (simulator suites always
   exist, so a device-only mismatch is possible — verify on hardware). `AppGroup.defaults` moving from
   `.standard` to the real suite resets watch-side skips/exclusions/sort once; the phone re-syncs them
   on the next WatchConnectivity exchange.
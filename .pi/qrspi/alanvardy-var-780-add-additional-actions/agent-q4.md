# Q4 — The three state-change operations in ReminderStore (skip / reschedule / delete)

All claims verified by reading the cited lines directly. Repo layout: `SingleThreadCore/Sources/SingleThreadCore/` (model layer shared by iOS/macOS/watchOS/widget), `SingleThread/` (iOS/macOS app), `SingleThreadWatch/` (watchOS app), `SingleThreadWidget/`.

Core file: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` — `@MainActor @Observable public final class ReminderStore` (ReminderStore.swift:42-44). Single init with injected stores and a `settle` hook defaulting to a 200 ms `Task.sleep` (ReminderStore.swift:47-99; settle closure at ReminderStore.swift:70-73, documented at :31-35).

---

## 0. Shared gating: canMutate (entitlement + freemium cap)

- `public var canMutate: Bool` — ReminderStore.swift:167-172: `entitlementStore.isEntitled || completionCounter.count < EntitlementStore.freemiumCap`.
- `EntitlementStore.freemiumCap = 100` (strict-<; gate closes at exactly 100) — `SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift:52-57`.
- Remote-store properties: `entitlementStore` ReminderStore.swift:122; `completionCounter` ReminderStore.swift:118; `undoStore` is `#if !os(watchOS)` only (ReminderStore.swift:124-128, UndoStore.swift:8-10).
- All three ops begin with `guard canMutate`. No EventKit authorization check inside the mutations — auth resolves once in `start()` / `requestAccess()` (ReminderStore.swift:185-198, 443-453) before a surface can mutate; the mutations never read `authorizationStatus`.

## 5. Platform constraint matrix (observed)

- **watchOS** — EventKit is read-only. Skip works locally (counts + skip set in App Group/UserDefaults; nudge interrupt active; skip set propagates implicitly because `applySkipSet` fires `onSkipSetChanged` -> `pushAll()` — WatchAppViewModel.swift:210). Reschedule compiles to `return false` (no watch surface). Delete removes locally + relays via `onDeleteReminder`.
- **iOS** — full EventKit writes (`save`/`remove` with `commit: true`), 200 ms settle + `reload()`, nudge sheet with date+time picking (time preserved only when the reminder had a due time).
- **macOS** — EventKit writes work; the nudge interrupt is compiled out (`#else` :382-383), so skips never interrupt on macOS. `undoStore` compiles on macOS. `onDeleteReminder` never fires (only the watchOS branch calls it).
- **Widget extension** — `skipCurrentReminderImmediately()` only (synchronous, no settle) because WidgetKit may suspend the process right after `perform()` (ReminderStore.swift:404-410; ReminderIntents.swift:49).

---

## 1. skipCurrentReminder() — sync entry, settle-delayed apply (all non-widget platforms)

Body — ReminderStore.swift:370-399:

```swift
public func skipCurrentReminder() {
    guard canMutate else { return }
    guard let reminder = visibleReminders.first else { return }
    let identifier = reminder.calendarItemIdentifier
    #if os(iOS) || os(watchOS)
        if incrementSkipCount(for: identifier) {
            // 6th skip: interrupt the cycle and prompt instead of advancing.
            onSkipNudgeRequested?(identifier)
            return
        }
    #else
        _ = incrementSkipCount(for: identifier)
    #endif
    let updated = updatedSkipSet(afterSkipping: identifier)
    let capturedGeneration = skipGeneration
    Task {
        await settle()
        // Refetch only when the skip actually applied — a clear that raced
        // ahead discards it (generation gate) so no stale refetch runs.
        if applySkipSet(updated, generation: capturedGeneration) {
            await reload()
        }
    }
}
```

Flow / side effects:
1. Gate `guard canMutate` (:371) then picks `visibleReminders.first` (:372) — the sort-ordered first visible reminder (filtered by `skippedIDs` + excluded list titles; `visibleReminders` at ReminderStore.swift:111-117).
2. Skip-count mutation is **synchronous and persists immediately**: `incrementSkipCount(for:)` (ReminderStore.swift:561-568) loads `skipCountStore.load()`, writes `new = old + 1` via `skipCountStore.save(counts)`, returns `SkipCountLogic.crossedThreshold(from: old, to: new)`.
3. Nudge interrupt (iOS/watchOS only, `#if` :374-381): on the **first crossing** of the threshold, hook `onSkipNudgeRequested?(identifier)` fires (hook decl :95) and `skipCurrentReminder()` **returns without skipping** — the reminder stays visible and `skippedIDs` is untouched. macOS (`#else` :382-383) increments the count but the interrupt is compiled out and the skip proceeds.
4. Normal path: `updatedSkipSet(afterSkipping:)` (ReminderStore.swift:552-555) -> `ReminderSkipLogic.skipping(identifier, fetched:, skipped:)` (`ReminderSkip.swift:19-26`; pure prune + append).
5. Generation capture (:386), then a `Task`: (a) `await settle()` (200 ms production sleep; test seam injects a no-op — ReminderStore.swift:70-73), (b) `applySkipSet(updated, generation:)`, (c) on apply success `await reload()`. `applySkipSet` (ReminderStore.swift:604-614) discards the apply when `generation != skipGeneration` (clear-skipped race), else sets `skippedIDs = Set(updated)`, persists `skipStore.save(updated)`, fires `onSkipSetChanged?(updated)` (watch push) and `onRemindersChanged?()` (widget timelines). `skipGeneration` is bumped only by `clearSkippedState()` (`&+= 1`, :591-597; property :548), which runs inside `reload(clearSkipped: true)` via `reconcileSkipState` (:661-674).
6. `reload()` (ReminderStore.swift:431-485) refetches (EventKit predicate), reconciles skip/excluded state via `ReminderSkipLogic.resolve` (ReminderSkip.swift:12-17), prunes stale skip IDs and skip counts (`reconcileSkipCounts` :579-587), then fires `onRemindersChanged?()`.

Widget sibling: `skipCurrentReminderImmediately()` ReminderStore.swift:411-425 — synchronous `applySkipSet(updated)` with no generation arg and no settle sleep (WidgetKit-suspension safety, doc :404-410); fires `onSkipNudgeRequested?` but still applies the skip. Called by `SkipReminderIntent.perform()` (`ReminderIntents.swift:30-51`, call :49); widget button `SingleThreadWidget/NextThingWidget.swift:152`.

Call sites of `skipCurrentReminder()`: iOS trailing swipe `ContentView.swift:480-487`; iOS bottom-bar Skip gated by `showsActionButtons` (`ContentView.swift:526-534`; gate at ContentViewModel.swift:39-42); macOS `actionButtons` + `s` shortcut (`ContentView.swift:344-353`); watchOS `WatchReminderView.swift:130-134`; iOS/macOS funnel through `ContentViewModel.skipCurrentReminder()` (ContentViewModel.swift:116-118). Skip is synchronous at every call site (complete/delete are async).

### Skip-count store & nudge threshold — SingleThreadCore/Sources/SingleThreadCore/SkipCountStore.swift

- `SkipCountLogic.defaultThreshold = 6` (SkipCountStore.swift:9); `shouldNudge(_ count:)` is `count >= threshold` (:12-14); `crossedThreshold(from:to:)` is `old < threshold && new >= threshold` (:19-21) — fires **once** at the 5→6 crossing, never again until the count resets (e.g. complete/delete/reschedule).
- `SkipCountStore` persists `[String: Int]` (identifier → count) in UserDefaults, key `skipCounts`, defaults suite `AppGroup.defaults` (SkipCountStore.swift:25-36) — App Group `group.app.alanvardy.SingleThread` with `.standard` fallback when the group is unavailable (watchOS, unregistered simulators, previews) — `AppGroup.swift:8-17`.
- Skip-count reset paths (`resetSkipCount(for:)` ReminderStore.swift:571-577; filters the key out, no-op when absent): complete (iOS :236, watchOS :227), delete (:294, :302), reschedule (:361). `reload()` prunes out-of-window counts via `reconcileSkipCounts` (:579-587).
- Test-verified threshold behavior: `nudgeInterruptsSixthSkipAndKeepsReminderVisible` (ReminderStoreTests.swift:559-582 — seeds 5, asserts hook fires with the ID, count == 6, reminder still visible, `skippedIDs` empty), `nudgeDoesNotFireAtFive` (:583-607), `seventhSkipAdvancesWithoutRenudging` (:609-633), `completeResetsSkipCount` (:635-653), `deleteResetsSkipCount` (:655-672), `rescheduleResetsSkipCount` (:674-694, `#if !os(watchOS)`), `reconcilePrunesSkipCountForAbsentIdentifier` (:696-720). Pure logic: `SkipCountStoreTests.swift` (`shouldNudgeFiresOnlyAtOrPastThreshold`, `crossedThresholdFiresOnlyOnce`, ~:52-90).

---

## 2. rescheduleReminder(identifier:to:) — iOS-only reschedule (watch compiled out)

Body — ReminderStore.swift:344-367 (verified by `sed -n 286,400p`):

```swift
@discardableResult
public func rescheduleReminder(identifier: String, to due: DateComponents) async -> Bool {  // :348
    guard canMutate else { return false }                                                    // :349
    #if os(watchOS)
        return false                                                                         // :350-352
    #else
        guard let reminder = reminders.first(where: {
            $0.calendarItemIdentifier == identifier
        }) else { return false }                                                             // :353-355
        do {
            reminder.dueDateComponents = due
            try eventStore.save(reminder, commit: true)                                      // :356-358
            resetSkipCount(for: identifier)                                                  // :361
            await settle()                                                                   // :362
            await reload()                                                                    // :363
            return true
        } catch {
            Self.logger.error("Failed to reschedule reminder: \(error.localizedDescription, privacy: .public)")  // :365-366
            return false
        }
    #endif
}
```

Platform notes: `#if os(watchOS)` compiles to bare `return false` with zero side effects — EventKit is read-only on watch. On iOS: sets `EKReminder.dueDateComponents` in place, `eventStore.save(reminder, commit: true)` through the `EventKitStoring` protocol (ReminderStore.swift:472-479), then `resetSkipCount(for: identifier)` (nudge history restarts), `settle()`, `reload()`. Lookup miss or save error → `false` (error logged via `Self.logger`, category "ReminderStore", :376-382). Single caller: `ContentViewModel.rescheduleNudgedReminder(to:)` (ContentViewModel.swift:205-212), which clears `nudgeIdentifier` only on success. There is **no** dedicated reschedule-gating unit test (grep for reschedule+gate across the test suites returned nothing); `guard canMutate` is the only gate.

### Nudge-sheet DatePicker flow — SingleThread/ContentView+iOS.swift (iOS only)

- Sheet state: `@State var isShowingNudgeSheet = false` (ContentView.swift:135-137) and `@State var rescheduleDate = Date().addingTimeInterval(86400)` defaulting to tomorrow (:139-141). Presented iOS-only: `.sheet(isPresented: $isShowingNudgeSheet, onDismiss: { viewModel.dismissNudge() }) { nudgeSheetContent }` (ContentView.swift:275-278).
- Sheet entry: the in-card nudge banner. `let openNudgeSheet = { isShowingNudgeSheet = true }` (ContentView.swift:429), passed as `onNudgeTap` with `showNudge: viewModel.isNudged(reminder.calendarItemIdentifier)` (ContentView.swift:430-442). The banner is a tappable `Button(action: onNudgeTap)` styled orange, accessibility label "Skipped 6 times — tap to manage", ID `skipNudgeBanner` (ReminderCardView.swift:137-159; `showNudge` :60-61).
- `nudgeSheetContent` (ContentView+iOS.swift:59-85): NavigationStack with headline "This reminder keeps coming back." (ID `nudgeSheetTitle`) + DatePicker + 3 buttons (Reschedule / View in Reminders / Delete) + Cancel toolbar item (:79-83).
- **DatePicker** (ContentView+iOS.swift:66-69): `DatePicker("Reschedule to", selection: $rescheduleDate, displayedComponents: nudgedReminderHasDueTime ? [.date, .hourAndMinute] : [.date])`.
- **Date-only vs dated**: `nudgedReminderHasDueTime` (ContentView+iOS.swift:91-101) resolves `viewModel.nudgeIdentifier` against `viewModel.store.visibleReminders`, reads `reminder.dueDateComponents`, returns `components.hour != nil`; defaults to `false` when unresolvable. The picker offers a time spinner only to reminders that had a due time.
- **Reschedule button** `nudgeRescheduleButton` (ContentView+iOS.swift:107-123): builds `Calendar.current.dateComponents(nudgedReminderHasDueTime ? [.year,.month,.day,.hour,.minute] : [.year,.month,.day], from: rescheduleDate)` (:109-113) — hour/minute are **omitted** for date-only reminders "so a date-only reminder stays date-only" (comment :103-106) — then `Task { if await viewModel.rescheduleNudgedReminder(to: components) { isShowingNudgeSheet = false } }` (:114-118).
- **View in Reminders button** (:129-142): `viewModel.openInReminders(identifier:)` — ReminderDeepLink built in ContentViewModel (ContentViewModel.swift:174-181), routed through the injected `urlOpener` (the `--url-opener-spy` UI-test seam at :133-137); closes the sheet.
- **Delete button** (:145-155): `Task { await viewModel.deleteNudgedReminder(); isShowingNudgeSheet = false }`; `deleteNudgedReminder()` (ContentViewModel.swift:196-200) calls `store.deleteReminder(identifier:)` then clears `nudgeIdentifier`.
- Dismiss always clears the banner: sheet `onDismiss` → `viewModel.dismissNudge()` (ContentView.swift:276; ContentViewModel.swift:191-193). Watch equivalent (no DatePicker) is a `.confirmationDialog` Delete-only flow — WatchReminderView.swift:230-244.

---

## 3. deleteReminder(identifier:) — local remove + watch relay vs EventKit remove

Body — ReminderStore.swift:285-307:

```swift
/// On iOS: removes the whole `EKReminder` object from EventKit and reloads.
/// On watchOS (where EventKit is read-only): removes it locally and relays the
/// deletion to the iPhone via `onDeleteReminder`.
public func deleteReminder(identifier: String) async {          // :290
    guard canMutate else { return }                             // :291
    #if os(watchOS)
        reminders.removeAll { $0.calendarItemIdentifier == identifier }  // :293
        resetSkipCount(for: identifier)                         // :294
        onDeleteReminder?(identifier)                            // :295
    #else
        guard let reminder = reminders.first(where: { $0.calendarItemIdentifier == identifier }) else { return }  // :297-299
        do {
            try eventStore.remove(reminder, commit: true)       // :301
            resetSkipCount(for: identifier)                     // :302
            await settle()                                       // :303
            await reload()                                       // :304
        } catch {
            Self.logger.error("Failed to delete reminder: \(error.localizedDescription, privacy: .public)")  // :306-307
        }
    #endif
}
```

Also `deleteCurrentReminder()` (ReminderStore.swift:308-311): `visibleReminders.first` → `await deleteReminder(identifier:)`.

- **watchOS branch** (:292-296): pure local removal from the in-memory `reminders` array, `resetSkipCount`, and fire-and-forget `onDeleteReminder?(identifier)` (hook decl ReminderStore.swift:105). Unlike watch `completeReminder` (ReminderStore.swift:216-227), it does **not** touch `pendingCompletionStore` — no pending-deletion set exists; pending completions are the only relay-persisted set. No settle/reload (no EventKit write to settle).
- **iOS branch** (:297-307): identifier lookup in `reminders`, `eventStore.remove(reminder, commit: true)` (through `EventKitStoring`, ReminderStore.swift:472-479), `resetSkipCount`, `await settle()`, `await reload()`. The `reload()` path (ReminderStore.swift:431-485) runs `reconcileSkipState` + `ReminderSkipLogic.resolve` (ReminderSkip.swift:12-17), which drop stale `skippedIDs` entries for a deleted reminder automatically.

### Watch-side relay wiring (send + receive + inert phone send)

- Watch send hooks: `store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }` and `store.onDeleteReminder = { identifier in service.requestDeleteReminder(identifier) }` — `SingleThreadWatch/WatchAppViewModel.swift:213-214`.
- Service send: `SkippedReminderSyncService.requestDeleteReminder(_:)` (SkippedReminderSyncService.swift:230-237) → `session.sendMessage([PayloadKey.deleteReminderIdentifier: identifier], replyHandler: nil) { error in ...logged... }` (same shape as `requestCompleteReminder`, :220-228). Delegate hook declarations are `nonisolated(unsafe)`, write-once-before-`activate()` (doc :85-90).
- Phone receive: `service.onDeleteReminderReceived = { [weak store] identifier in Task { await store?.deleteReminder(identifier: identifier) } }` — `SingleThread/AppViewModel.swift:49-51` (complete receive :45-47). `WCSessionDelegate session(_:didReceiveMessage:)` decodes `PayloadKey.deleteReminderIdentifier` and invokes `onDeleteReminderReceived` (SkippedReminderSyncService.swift:247-255); payload key literal `deleteReminderIdentifier` (:283). The deletion executes on the phone through the same iOS branch (EventKit `remove` + settle + reload).
- Phone-side send hook is inert by design: `store.onDeleteReminder = { identifier in service.requestDeleteReminder(identifier) }` on iOS is documented as "the iPhone's `deleteReminder` never fires `onDeleteReminder` (only the watchOS branch does), so this is inert on iOS but kept for symmetry with the completion path" — AppViewModel.swift:64-68.
- Watch UI call sites: Refresh/Delete confirmation dialog `Button(SharedStrings.deleteAction, role: .destructive) { Task { await viewModel.store.deleteCurrentReminder() } }` (WatchReminderView.swift:224-227, ID `deleteButton`); nudge banner → `.confirmationDialog(SharedStrings.skipNudgeTitle, ...)` with destructive Delete (`nudgeDeleteButton`, WatchReminderView.swift:230-244). iOS surfaces: context-menu Delete (ContentView.swift:463-469) and macOS `d`-shortcut row (ContentView.swift:360-368).
- Tests: `SkippedReminderSyncServiceTests.swift` — `requestDeleteReminderSendsMessage` (:317-326) asserts the `deleteReminderIdentifier` payload key carries the ID; `receiveMessageTriggersDeleteHook` (:328-336); `receiveMessageIgnoringDeleteKeyIsNoOp` (:338-348). Watch-side delete is **not** unit-tested at the store level: `SingleThreadWatchTests/ReminderStoreWatchTests.swift` covers only `completeReminder` relay/pending-completion behavior (:30-108).

---

## 4. Error / entitlement gating summary

| Operation | Gate | Error handling |
|---|---|---|
| `skipCurrentReminder()` | `guard canMutate` (:371) | none needed — no EventKit write; skip-count save is non-throwing UserDefaults |
| `skipCurrentReminderImmediately()` | same (:412) | none |
| `rescheduleReminder(identifier:to:)` | `guard canMutate` (:349); watch `return false` (:350-352) | `catch` logs + `false` (:365-366); lookup miss → `false` (:353-355) |
| `deleteReminder(identifier:)` | `guard canMutate` (:291) | iOS `catch` logs + swallows (:306-307); watch branch non-throwing |
| `completeReminder(identifier:)` (reference) | `guard canMutate` (:215) | iOS `catch` logs + `false` (ReminderStore.swift:246-250); success path: `completionCounter.increment()` / `undoStore.retain(reminder)` at :240-241, then `resetSkipCount` :242, `settle` :243, `reload` :244 |

Free-tier cap semantics: the gate closes exactly at lifetime-completion count 100 for non-entitled users — `ReminderStoreGateTests.swift` `canMutateFalseWhenCountAt100AndNotEntitled` / `canMutateTrueWhenCountAt100AndEntitled` (:28-51), gated no-ops `completeReminderReturnsFalseWhenGated` (:54-69), `skipCurrentReminderNoOpsWhenGated` (:88-102), `deleteReminderNoOpsWhenGated` (:126-140), ungated success paths (:72-86, :105-124). Watch side: `completionCount` syncs phone→watch via `PayloadKey.completionCount` into `AppGroup.defaults` (`onCompletionCountReceived`, WatchAppViewModel.swift:187-193), so `canMutate` gates on the phone's real count; the watch shows an "Upgrade on your iPhone" prompt when gated (WatchReminderView.swift:246-248).

## 6. Things not answerable from the codebase / observed gaps

- No store-level unit test for the watchOS delete branch (local removal + relay) — `ReminderStoreWatchTests.swift` covers complete-only; delete relay tested only at `SkippedReminderSyncServiceTests` level.
- No explicit reschedule-gating unit test; the gate exists only as `guard canMutate` (ReminderStore.swift:349).
- No persistence of a deleted-ID set on watch: the phone processes the relay and the next `reload()` prunes stale skip IDs (`ReminderSkipLogic.resolve`); the relay is fire-and-forget (no retry/ack beyond WCSession built-in delivery).
- The 200 ms settle delay is a literal init default (ReminderStore.swift:70-73), not a named constant.
- `ReminderStore` mutations never verify EventKit `authorizationStatus` themselves; they assume the `start()`/`requestAccess()` handshake ran and rely on `canMutate` for entitlement gating.

---

## 7. Acceptance report

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Research-only task: no code was changed; the report documents existing behavior with verified file:line references across ReminderStore.swift, SkipCountStore.swift, SkippedReminderSyncService.swift, ContentView+iOS.swift, ContentView.swift, ContentViewModel.swift, ReminderCardView.swift, WatchAppViewModel.swift, AppViewModel.swift, WatchReminderView.swift, EntitlementStore.swift, and the test suites."
    },
    {
      "id": "criterion-2",
      "status": "satisfied",
      "evidence": "Every claim cites exact file:line and was verified by reading the cited regions (read tool + sed/grep over exact ranges). Dense structured report grouped by sub-topic with signatures, EventKit write patterns, side effects, entitlement gating, and an explicit gaps section; output persisted to the configured path."
    }
  ],
  "changedFiles": [],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {
      "command": "rg/grep + read over SingleThreadCore, SingleThread, SingleThreadWatch, SingleThreadTests, SingleThreadWatchTests",
      "result": "passed",
      "summary": "All cited regions read and verified; line numbers confirmed via grep -n and sed -n output."
    }
  ],
  "validationOutput": [
    "Cross-checked 40+ file:line references against source content; no discrepancies found.",
    "Confirmed: watch delete relay has a store-level test gap; reschedule has no dedicated gate test (reported in section 6)."
  ],
  "residualRisks": [
    "No live test-suite run was performed (analysis-only task); line references verified by reading source, not running tests.",
    "The 200 ms settle delay is a literal init default, not a named constant."
  ],
  "noStagedFiles": true,
  "diffSummary": "No diff — research report written to the configured output path only.",
  "reviewFindings": [
    "no blockers: report covers all requested sub-topics (signatures, EventKit write patterns, side effects, nudge threshold, watch relay, DatePicker date-only handling, entitlement gating) with verified citations."
  ],
  "manualNotes": "Output written to /Users/vardy/.pi/agent/sessions/--Users-vardy-dev-alanvardy-var-780-add-additional-actions--/subagent-artifacts/outputs/ccad3141-bcf5-4650-972b-ec87124a55d3/.pi/qrspi/alanvardy-var-780-add-additional-actions/agent-q4.md"
}
```

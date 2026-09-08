# Research Findings

All paths relative to repo root. Watch UI lives in one view file
(`SingleThreadWatch/WatchReminderView.swift`), one view model
(`SingleThreadWatch/WatchReminderViewModel.swift`), one composition root
(`SingleThreadWatch/WatchAppViewModel.swift`); domain/delete/refresh logic in
`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`.
Line numbers pinned with `grep -n` unless noted.

## Q1: Card tap → `isShowingRefreshConfirmation` → confirmationDialog

### Findings
- Card renders only via `reminderContent` → `listContent` `case .reminder` → `reminderCard(visibleReminders.first)`
  (`WatchReminderView.swift:104-108`). The completion-transition "ghost" card renders at `:91-93` instead while
  `isShowingCompletionTransition` is true; the reload spinner overlays both (`:113-117`).
- Tap target is the card's `ScrollView` (`WatchReminderView.swift:241-244`); `.onTapGesture` at `:245-247` has
  **one** side effect: `viewModel.isShowingRefreshConfirmation = true` (`:246`).
- `@Bindable var viewModel = viewModel` inside `reminderCard` (`:239`) provides the mutable `$` binding for
  `isPresented:` (an MVVM refactor requirement, recorded in `.pi/qrspi/alanvardy-var-697-…/implement.md`).
- Tap affordance: `.accessibilityAddTraits(.isButton)` (`:248`) — the **only** accessibility modifier on the
  tap target; no label, no identifier, no element container.
- Dialog: `.confirmationDialog("Reminder", isPresented: $viewModel.isShowingRefreshConfirmation)` (`:249`).
  Title is the literal `"Reminder"`, no message, no `onDismiss`.
- Dialog buttons:
  - Refresh `Button("Refresh")` (`:250-253`): no `role:`; `.accessibilityIdentifier("refreshButton")` (`:253`);
    action `Task { await viewModel.refresh(clearSkipped: viewModel.store.allSkipped) }` (`:251`).
  - Delete `Button(SharedStrings.deleteAction, role: .destructive)` (`:255-258`): id `"deleteButton"` (`:258`);
    action `Task { await viewModel.store.deleteCurrentReminder() }` (`:256`). `SharedStrings.deleteAction = "Delete"`
    (`LocalizedString+Shared.swift:20-22`). No `.cancel` button anywhere in this dialog or the other watch dialogs.
- **Full lifecycle of the flag** (repo-wide `rg`):
  - Declared `WatchReminderViewModel.swift:50` (`var isShowingRefreshConfirmation = false`).
  - Write sites: exactly one — `WatchReminderView.swift:246`. No button handler writes it.
  - Read sites: exactly one — `WatchReminderView.swift:249`.
  - Reset: only via the SwiftUI two-way `isPresented:` binding on dismissal (Cancel / tap-outside / action).
    No `.onAppear`/`.onDisappear`/`.task` exists on the watch view; the only lifecycle modifier is
    `.task { await viewModel.task() }` (`:59-61`) → `store.start()` (`WatchReminderViewModel.swift:82-83`),
    which never touches the flag. The repo's only `.onDismiss` is iOS (`SingleThread/ContentView.swift:309`).
- Interacting flags on the same VM (all `WatchReminderViewModel.swift`): `isRefreshing` (`:49`, spinner `View:113-117`
  and `.disabled` `View:205`); `isShowingActionMenu` (`:62`, second `confirmationDialog` `View:284`);
  `isShowingNudgeDialog` (`:58`, third dialog `View:269`); `isShowingRescheduleSheet` (`:65`, sheet `View:287`);
  `isShowingCompletionTransition`/`transitionReminder` (`:72`, `:76`, glow flow); `nudgeIdentifier` (`:54`).
  No `isShowingDeleteConfirmation` flag exists anywhere — deletion is confirmed via the Refresh/Delete dialog itself.
- Downstream: Refresh → `WatchReminderViewModel.refresh` (`:121-133`, see Q2) → `ReminderStore.reload`
  (`ReminderStore.swift:439`). Delete → `ReminderStore.deleteCurrentReminder()` (`:315-317`) →
  `deleteReminder(identifier:)` (`:296-314`), watchOS branch removes locally + fires `onDeleteReminder` relay
  (`:299-301`; relay wired `WatchAppViewModel.swift:219`).
- UI-test coverage of the lifecycle: `SingleThreadWatchUITestsFlows.swift:224-241` (tap card → dialog Delete →
  empty state) — see Q5.

## Q2: Refresh end-to-end (`WatchReminderViewModel.refresh` → `ReminderStore.reload`)

### Findings
- `WatchReminderViewModel.refresh(clearSkipped:)` (`WatchReminderViewModel.swift:121-133`):
  `guard !isRefreshing else { return }` (`:122`) is the sole re-entrancy protection (every UI path fires it in a
  `Task { await … }`); `isRefreshing = true` (`:123`); `startedAt` (`:124`); `await store.reload(clearSkipped:)`
  (`:125`); min-display pad `MinimumDisplayDuration.remainingSleep(elapsed:minimum:)` (`:126-128`,
  definition `SingleThreadCore/Sources/SingleThreadCore/MinimumDisplayDuration.swift:10-12`, `max(0, minimum - elapsed)`);
  `try? await Task.sleep(...)` (`:129-131`); `isRefreshing = false` (`:132`).
  - **No `try`/`catch`, no `defer`**: a throw from `reload` escapes into the caller's Task and leaves
    `isRefreshing == true` (spinner stuck). Contrast iOS sibling `ContentViewModel.refreshManual`
    (`SingleThread/ContentViewModel.swift:176-188`, `defer { isRefreshing = false }` `:181-182`).
  - Spinner minimum display: `refreshMinimumDisplayDuration = 1` s (`WatchReminderViewModel.swift:137-139`),
    unit-tested in `SingleThreadTests/MinimumDisplayDurationTests.swift:11-30`
    (`remainingSleepScalesWithElapsed`, table `(0.0,1.0),(0.4,0.6),(1.0,0.0),(1.5,0.0)`).
- `ReminderStore.reload(clearSkipped:)` (`ReminderStore.swift:439-491`) on watchOS:
  - `guard loadsReminders else { return }` (`:440`) → no-op (previews/`--ui-testing` stores built with
    `loadsReminders: false`); covered by `SingleThreadTests/ReminderStoreTests.swift:430-435`.
  - `eventStore.refreshSourcesIfNecessary()` is `#if !os(watchOS)` (`:441-443`) — the watch never refreshes
    EventKit sources; it fetches what is already available (`EventKitStoring.swift:26-27` declares it iOS-only).
  - Date window (`:444-452`): `showsUndatedReminders` (`:140-145`) → both bounds nil, else
    `ReminderDateFilter.overdueCutoff()`…`endOfToday()` (`ReminderDateFilter.swift:11-46`).
  - Fetch (`:453-458`): `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:nil)` then
    `await fetchReminders(matching:)` (`:628-642`) — `withCheckedContinuation` off-main, resumed on main —
    the suspension point the 1 s pad paces.
  - In-window filter (`:459-462`); `hasHidden` broad nil/nil fetch (`:463-476`, `Self.hasHiddenFor` `:71-73`);
    pending-completion filter (`:477-482`, `applyingPendingCompletionFilter` `:644-653`,
    `PendingCompletionLogic.swift:10-24`); `reminders = shown` (`:482`, stored unsorted — sorting happens only in
    computed `visibleReminders` `:147-152`).
  - Skip/excluded reconciliation (`:487` → `reconcileSkipState` `:671-686`):
    `clearSkipped == true` → `clearSkippedState` (`:601-606`: `skipGeneration &+= 1`, `skippedIDs = []`,
    `skipStore.save([])`, `onSkipSetChanged?([])`) — generation bump invalidates in-flight skip applies
    (`applySkipSet` `:614-624`). `clearSkipped == false` → prune persisted skip set to fetched intersection
    (`:675-680`, `ReminderSkip.swift:12-15`). Both end at `reconcileSkipCounts` (`:590-599`).
  - `prunePendingCompletions` (`:490`/`:655-665`); `onRemindersChanged?()` (`:491`, wired only by iOS for widget
    timelines `:113-116`).
  - `clearSkipped` behavior: both watch call sites pass `viewModel.store.allSkipped`
    (`ReminderStore.swift:156-158` = `!reminders.isEmpty && visibleReminders.isEmpty`), so **"All Done" → Refresh
    un-skips everything in the window**.
- **Exactly two UI sites invoke `refresh`** (repo-wide grep `viewModel.refresh(`):
  - Site A — `refreshButton` (`WatchReminderView.swift:201-207`): `.disabled(viewModel.isRefreshing)` (`:205`),
    id `"refreshButton"` (`:206`); instantiated in both empty branches — `allDoneState` (`:181`) and
    `noRemindersState` (`:233`).
  - Site B — the card-tap dialog Refresh (`WatchReminderView.swift:250-253`): **no** `.disabled`; the VM guard
    absorbs re-entrant taps. Same id `"refreshButton"` reused (`:253`).
  - No pull-to-refresh on watch (`.refreshable` is iOS-only: `SingleThread/ContentView.swift:393-395, 406-408,
    488-490`); no settings/onAppear refresh. WatchConnectivity receive hooks call `store.reload()` **directly**,
    bypassing the VM, so no spinner: `WatchAppViewModel.swift:176-179` (undated), `:185` (skipped ids), `:188`
    (skip counts).
- Spinner rendering: one shared overlay `if viewModel.isRefreshing { ProgressView() … alignment: .top, padding 8 }`
  (`WatchReminderView.swift:113-117`), drawn over whichever branch is underneath, below the glow overlay (`:118-121`).
  The `.notDetermined` `ProgressView(SharedStrings.requestingAccess)` (`:51`) is the auth screen, unrelated.

## Q3: Delete-reminder reachability, `ActionMenuGate`, skip-nudge banner

### Findings
- Delete is reachable at **exactly three** watch UI sites; all three call `store.deleteCurrentReminder()`:
  1. **Card-tap dialog** `WatchReminderView.swift:255-258` (id `deleteButton` `:258`) — gated only by the
     `isShowingRefreshConfirmation` flag (`WatchReminderViewModel.swift:50`); store still guards `canMutate`
     (`ReminderStore.swift:297`).
  2. **Action menu** (`actionMenuDialogButtons` `WatchReminderView.swift:211-221`; Delete `:219-220`, `role:
     .destructive`, no identifiers) presented by `.confirmationDialog("Reminder", isPresented:
     $viewModel.isShowingActionMenu)` (`:284-285`). Gate is the inline computed `canShowActionMenu`
     (`:81-85`) = `showEnableActionButtonsState.isEnabled && store.canMutate && visibleReminders.first != nil`.
     Skip button routes to the menu (`isShowingActionMenu = true`, `:144`) when the gate passes, else skips
     directly (`:146-148`); toggle-off path is byte-identical to pre-menu behavior (comment `:77-80`).
  3. **Skip-nudge banner dialog** (`WatchReminderView.swift:261-274`): banner button (id `skipNudgeBanner` `:268`)
     sets `isShowingNudgeDialog = true` (`:263`); dialog (`:269`) holds only the destructive Delete
     (id `nudgeDeleteButton` `:273`). Gated by `isNudged(_:)` (`WatchReminderViewModel.swift:92-93`).
- `ActionMenuGate` (`SingleThreadCore/Sources/SingleThreadCore/ActionMenuGate.swift:7-14`) is the shared pure
  predicate (`showsActionMenu(enableActionButtons:canMutate:hasVisibleReminder:)`, AND of all three, `:12`).
  **The watch does not use it** — `canShowActionMenu` (`WatchReminderView.swift:81-85`) is the identical
  predicate inlined; repo-wide grep finds no `ActionMenuGate` reference under `SingleThreadWatch/`. iOS calls
  it (`SingleThread/ContentView+ActionMenu.swift:18-23`, macOS `:89-94`). Default OFF on every platform
  (`ContentView.swift:96-97` `@AppStorage` false; `ShowEnableActionButtonsState` absent-key → false
  `ShowEnableActionButtonsState.swift:14-16`). Truth table: `SingleThreadTests/ActionMenuGateTests.swift:6-31`.
- `--ui-testing-action-menu` seam: `WatchAppViewModel.swift:61-67` — applied only when `--ui-testing` is present
  (`:14`); `showEnableActionButtonsState.apply(arguments.contains("--ui-testing-action-menu"))` (`:67`) writes
  App Group key `"enableActionButtons"` and publishes (`ShowEnableActionButtonsState.swift:23-26`). Every other
  `--ui-testing` launch therefore resets the toggle OFF (comment `:63-65`: value persists across relaunches in
  the App-Group-backed defaults). Production toggle path: push `SkippedReminderSyncService.swift:209`; watch
  receive `:448-452` → hook `WatchAppViewModel.swift:280-283`.
- **Nudge ⇆ skip/delete dependency**: on the skip that crosses the threshold (≥ 6 default;
  `SkipCountLogic.crossedThreshold`, `SkipCountStore.swift:16-20`, via `incrementSkipCount`
  `ReminderStore.swift:571-579`), `skipCurrentReminder()` fires `onSkipNudgeRequested?(identifier)` (`:386-389`,
  hook declared `:95`) and **returns early — the reminder is NOT skipped and the card stays**. Watch wiring:
  `WatchReminderViewModel.swift:30-31` sets `nudgeIdentifier`. Banner lifetime: `nudgeIdentifier` has exactly
  one write (init) and one read (`isNudged` `:92-93`) on watch; **nothing ever sets it to nil** in the watch
  target (the `:53` comment "cleared on delete/dismiss/refresh" has no code behind it) — the banner disappears
  only implicitly when the reminder leaves the visible list (delete removes it from `store.reminders`,
  `ReminderStore.swift:299`, so `isNudged` can't match). Contrast iOS: explicit clears in
  `dismissNudge()` / `deleteNudgedReminder()` (`SingleThread/ContentViewModel.swift:221-222, 226-230`) and
  `.onDismiss { viewModel.dismissNudge() }` (`SingleThread/ContentView.swift:309`). `resetSkipCount`
  (`ReminderStore.swift:581-587`) erases the count (re-arming the 1→6 climb) on delete (`:299-300`), complete
  (`:236, :248`), and iOS reschedule (`:369`).
- watchOS deletion mechanics: EventKit is read-only on watch (doc `ReminderStore.swift:292-295`); the watchOS
  branch of `deleteReminder` removes the reminder from the local array, resets the skip count, and relays via
  `onDeleteReminder` (`:299-301`, hook `:105`) → `service.requestDeleteReminder(identifier)`
  (`WatchAppViewModel.swift:219`). Same relay pattern for complete (`:213`) and reschedule (`:214-216`).
- Widget note: `skipCurrentReminderImmediately` also fires the nudge hook but still applies the skip (no nudge
  UI on the widget; persisted count lets phone/watch surface it later) (`ReminderStore.swift:421-428`).

## Q4: Accessibility exposure + UI audit

### Findings
- Tap target: only `.accessibilityAddTraits(.isButton)` (`WatchReminderView.swift:248`); no label/id/element.
- Dialog buttons: Refresh id `"refreshButton"` (`:253`), Delete id `"deleteButton"` (`:258`); neither has an
  explicit label or trait. Action-menu buttons: **no identifiers** (`:211-221`). Nudge banner id
  `"skipNudgeBanner"` (`:268`); nudge delete id `"nudgeDeleteButton"` (`:273`); reschedule confirm id
  `"rescheduleConfirmButton"` (`:318`); sheet Cancel (`:322-325`) has none. Complete/Skip carry the full
  label + id + trait stack (`:138-140`, `:153-155`; labels `SharedStrings.completeReminderAccessibility` /
  `skipReminderAccessibility`, `LocalizedString+Shared.swift:29-35`).
- In-progress refresh indicator: the `ProgressView` overlay (`WatchReminderView.swift:113-117`) has **no
  accessibility treatment** (no hidden/label/value). The only a11y-visible trace of refresh state is the
  standalone button's `.disabled(viewModel.isRefreshing)` (`:205`). No UI test asserts the spinner.
- Glow seams: `completionGlowOverlay` (`WatchReminderView.swift:189-199`) —
  `.accessibilityHidden(!isGlowUITesting)` (`:193`, production always hidden), `.accessibilityElement(children:
  .ignore)` (`:195`, the only `accessibilityElement` in the watch target), id `"completionGlowOverlay"` (`:196`),
  label `SharedStrings.completionGlow` (`:197`). `isGlowUITesting = --ui-testing-glow` (`:73-75`; seam also
  extends glow duration to 2.0 s, `WatchAppViewModel.swift:52-59`). Fade gated on reduce-motion
  (`@Environment(\.accessibilityReduceMotion)` `:66-67`; `.animation(reduceMotion ? nil : .easeInOut(0.4))`
  `:123-126`). Driver: `CompletionGlow` (`SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift:13-33`,
  0.5 s default).
- **UI accessibility audit** (watch): `SingleThreadWatchUITests.swift:30-42`
  `testAccessibilityAudit` — launches `["--ui-testing"]` (`:32-33`), waits for the seeded title (`:35-36`),
  then `#if os(watchOS)` (`:38`) → `performAccessibilityAudit(for: [.dynamicType, .hitRegion,
  .sufficientElementDescription, .trait])` (`:39-40`); no `#else`. Audits the seeded card in its **rest** state:
  exercises the `.isButton` tap target, Complete/Skip stacks, priority marker; opens no dialogs, `isRefreshing`
  is never true, so the spinner and the dialog buttons are absent from the audit.
- iOS analogues for the audit convention: `SingleThreadUITests/SingleThreadUITests.swift:27-66` — CI carve-out
  (`CI == "true"`, `:53-56`) reduces to `[.sufficientElementDescription, .trait]`; local runs the full four
  (`:58-60`; comment `:46-52`: full traversal hangs GitHub virtualized runners); `#else` macOS defaults
  (`:62-65`). `ActionButtonsUITests.swift:55-77` runs the full four. `NotificationsUITests.swift` is whole-file
  `#if os(iOS)` (`:1`) with the reduced set (`:14`). `contrast` and `textClipped` are deliberately never
  enabled (comment `SingleThreadUITests.swift:42-44`). No `auditConfiguration` anywhere; the API surface is
  `performAccessibilityAudit(for:)`.
- CI wiring: `watch-ui-tests` job (`.github/workflows/ci.yml:369-429`) runs
  `-only-testing:SingleThreadWatchUITests`, so the watch audit runs in CI with the full four-category set.
  AGENTS.md:167-174 documents local audits being stricter than CI (`.hitRegion`, `.dynamicType`) and the
  SwiftLint opt-ins `accessibility_label_for_image` / `accessibility_trait_for_button` (`.swiftlint.yml:45-46`).

## Q5: UI-test suites, element queries, launch seams

### Findings
- Watch UI-test target `SingleThreadWatchUITests/` (pbxproj:362-384; CI runs it under the `SingleThreadWatch`
  scheme). Three files:
  - `SingleThreadWatchUITests.swift` — `testTapRevealsConfirmationDialog` (`:9-27`),
    `testAccessibilityAudit` (`:30-42`).
  - `SingleThreadWatchUITestsFlows.swift` — 14 tests (`:13, :25, :39, :58, :76, :92, :110, :134, :159, :189,
    :224, :243, :262, :282`) + private `launchApp()` helper (`:317-322`).
  - `SingleThreadWatchUITestsLaunchTests.swift` — `runsForEachTargetApplicationUIConfiguration = true`
    (`:5-8`), `testLaunch` with `["--ui-testing"]` (`:15-24`).
- Card-tap/dialog coverage: `testTapRevealsConfirmationDialog` (`SingleThreadWatchUITests.swift:9-27`) and
  `testDeleteViaConfirmationDialogRemovesReminder` (`SingleThreadWatchUITestsFlows.swift:224-241`). Both tap
  the card and assert on the dialog. `SingleThreadUITests/` (iOS) has zero watch coverage.
- **Element queries — the label/identifier rule** (documented in `SingleThreadWatchUITests.swift:20-22`):
  - Card content by **visible text label**: `app.staticTexts["Buy groceries"]` — the title `Text` has no
    identifier (`WatchReminderView.swift:339-340`). Interactions are taps only (no watch swipes).
  - Dialog actions by **button label** (watchOS `confirmationDialog` actions surface their label, not the
    SwiftUI identifier): `app.buttons["Refresh"]` (`SingleThreadWatchUITests.swift:23`),
    `app.buttons["Delete"]` (`Flows:231`; also `:144-148` action menu, `:212-214` nudge),
    `app.buttons["Skip"]` (`:121-125`), `app.buttons["Reschedule"]` (`:169-173`). SwiftUI identifiers
    (`refreshButton`/`deleteButton`/`nudgeDeleteButton`) exist but are **not** used for dialog queries.
  - Non-dialog buttons by **accessibility identifier**: `completeButton` (`Flows:80-82, :249-251`;
    View:139), `skipButton` (`:96-98, :116-118, :140-142, :165-167, :197-199, :249-251`; View:154),
    `refreshButton` (empty/all-done states, `Flows:255`; View:206), `rescheduleConfirmButton` (sheet,
    `Flows:175-179`; View:318).
  - State markers by identifier: `emptyStateTitle` (View:180, :228 — asserted post-flow at numerous Flows
    lines), `priorityMarker` (`Flows:34`; View:337), `completionGlowOverlay` (`Flows:304`, a11y-visible only
    under `--ui-testing-glow`), `upgradePrompt` (`Flows:272`; View:171), `skipNudgeBanner` (`Flows:204-208`).
- **Launch seams** — all parsed in `WatchAppViewModel.init(arguments: ProcessInfo.processInfo.arguments)`
  (`WatchAppViewModel.swift:13`); base gate `isUITesting = arguments.contains("--ui-testing")` (`:14`):
  - `--ui-testing` → store fixture `uiTestingStore` (`:108-168`): scratch `EKEventStore` + `EKReminder`
    ("Buy groceries", priority 5, notes; `:111-113`) → `InMemoryEventStore` (`:159-168`;
    `SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift:13`) →
    `ReminderStore(loadsReminders: false, … authorizationStatus: .fullAccess)`.
  - `--ui-testing-priority <n>` (`:119-121`), `--ui-testing-skip-count <n>` (`:130-133`, writes
    `AppGroup.defaults` `"skipCounts"`), `--ui-testing-excluded-list <list>` / `--ui-testing-live-excluded
    <list>` (shared loop `:143-157`; live delivery via `scheduleUITestLiveExcludedDelivery` `:286-299`,
    gated on `WCSession.isSupported()` `:173`), `--ui-testing-gated` (`:26-27`,
    `completionCount = EntitlementStore.freemiumCap`), `--ui-testing-glow` / `--ui-testing-glow-disabled`
    (`:50-59`), `--ui-testing-action-menu` (`:61-67`, see Q3).
  - `--seed "<json>"` is **iOS-only**: parsed in `SingleThread/AppViewModel.swift:201`
    (`UITestingSeed.fromLaunchArguments`, `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift:48-58`;
    `resetPersistedState` clears both `AppGroup.defaults` and `UserDefaults.standard` `:62-71`).
    Zero `UITestingSeed` refs in `SingleThreadWatch/` — the watch app never parses `--seed`; watch fixtures
    are the `--ui-testing*` arguments above.
  - **Persistence rule** (AGENTS.md): every seam write round-trips through `AppGroup.defaults`
    (`UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard`, `AppGroup.swift:11, 16-17`).
    `--ui-testing-skip-count` and the `--ui-testing-gated` counter land in the App Group suite (falling back to
    `.standard` where no suite is registered); `--ui-testing-glow*` explicitly uses
    `BoolPreferenceStore(defaults: .standard, key: "showCompletionGlow")`
    (`ShowCompletionGlowState.swift:20-30`).
- Launch pattern: `XCUIApplication()` + `launchArguments` + `launch()` only; **no `launchEnvironment`** anywhere
  in `SingleThreadWatchUITests/`. **No simulator pairing required**: CI deliberately creates an *unpaired*
  standalone watch simulator (`.github/workflows/ci.yml:391-405`, comment `:392-398`: name-only destinations
  are ambiguous on runners that also ship iPhone-paired watches) and pins `-destination
  "platform=watchOS Simulator,id=$WATCH_UDID"` (`:411-429`). The sync service is a no-op without sessions
  (`WatchAppViewModel.swift:173`); the live-excluded test calls
  `service.session(WCSession.default, didReceiveApplicationContext:)` directly (`:291-299`).

## Q6: Direct actions vs dialogs; in-flight conventions

### Findings
- The watch surface has exactly **8 interaction points** in `WatchReminderView.swift` (no settings toggles on
  watch — every preference is phone-side, applied through WatchConnectivity receive hooks into passive
  `Show*State` holders, `WatchAppViewModel.swift:238-301`):
  | # | Interaction | Construct | Handler |
  |---|---|---|---|
  | 1 | Complete | icon button, **immediate** | `WatchReminderView.swift:131-140`, `:132` |
  | 2 | Skip | icon button; immediate OR menu | `:142-155`; gate `:143-148` |
  | 3 | Action-menu dialog (Skip/Reschedule/Delete) | `.confirmationDialog` | `:284-285`, bodies `:211-223` |
  | 4 | Reschedule sheet (DatePicker + confirm/cancel) | `.sheet` | `:287`, body `:297-325` |
  | 5 | Card tap (Refresh/Delete) | `.confirmationDialog` | `:245-249`, dialog `:249-259` |
  | 6 | Skip-nudge banner → Delete dialog | Button + `.confirmationDialog` | `:261-268`, dialog `:269-274` |
  | 7 | Empty/all-done Refresh | `refreshButton`, **immediate** | `:201-207`; used `:181`, `:233` |
  | 8 | Upgrade-on-iPhone prompt | static VStack — not interactive | `:159-178`, shown `:278-280` |
  Non-interactive/system: `.task` → `store.start()` (`:59-61`; `WatchReminderViewModel.swift:82-83`); watch→phone
  relays wired on store hooks (`WatchAppViewModel.swift:199-216`); auth `ProgressView` (`:51`).
- Classification summary: **immediate** = Complete (`:132`), direct Skip (toggle off, `:146-148`), empty/all-done
  Refresh (`:202-203` — from the all-done state this clears the entire skipped set with no confirmation).
  **confirmationDialog** = all three Delete paths, the Skip action menu, the card-tap Refresh-bundled-with-Delete.
  **sheet** = reschedule (needs input + confirm/cancel). The nudge dialog holds only the destructive Delete.
- **In-flight conventions**:
  - `isRefreshing` is the **only** in-flight flag (`WatchReminderViewModel.swift:49`); re-entry guard `:122`;
    the **only** `.disabled()` in the entire watch target is `refreshButton` (`WatchReminderView.swift:205`);
    spinner overlay `:113-117`. Dialog buttons are never `.disabled` (guard absorbs re-entry).
  - Completion: re-entry guard `guard !isShowingCompletionTransition` (`WatchReminderViewModel.swift:97`);
    buttons never disabled; feedback is the auto-dismissing green glow overlay (`View:118-121, 189-199`;
    `CompletionGlow` 0.5 s) plus the ghost card held for glow + 0.5 s buffer (`:96-117`).
  - Skip: **no in-flight flag** — synchronous store write + settle/reload Task; `skipGeneration`
    (`ReminderStore.swift:558`, bumped by clear `:601-604`, checked in `applySkipSet` `:614-616`) discards a
    stale reload when a clear-skipped refresh raced ahead.
  - Store-level mutation gate: every mutating entry guards `canMutate` (`ReminderStore.swift:221, 297, 357, 381`);
    a freemium-capped user sees the non-interactive upgrade prompt instead of the action buttons
    (`View:278-280`), and `canShowActionMenu` additionally requires `canMutate` (`:81-85`).
- Stated convention: **destructive ⇒ dialog-confirmed** — every Delete sits in a `confirmationDialog` with
  `role: .destructive` (`View:219-220, 255-258, 270-273`); no standalone unconfirmed Delete exists. **Direct ⇒
  reversible/low-stakes** (complete, skip, refresh). Refresh is the only action that is both direct and able to
  clear the skip set, and the only one with `disabled()` + spinner while in flight.

## Cross-Cutting Observations
- Single-file surface: all watch UI in `WatchReminderView.swift`; all presentation flags + refresh flow in
  `WatchReminderViewModel.swift`; composition/seams/sync in `WatchAppViewModel.swift`.
- Presentation-flag lifecycle convention: flags default `false` (`WatchReminderViewModel.swift:50, 58, 62, 65`),
  set `true` by a UI action, reset by the framework's two-way `isPresented:` binding (no explicit `false`
  writes) — except `isShowingActionMenu` → `false` + `isShowingRescheduleSheet` → `true` on the Reschedule
  button (`WatchReminderView.swift:215-217`), and explicit `isShowingRescheduleSheet = false` on confirm/cancel
  (`:312, :315, :323`).
- Identifier reuse: `"refreshButton"` shared between the standalone button (`View:206`) and the dialog Refresh
  (`:253`); `"emptyStateTitle"` shared by all-done (`:180`) and no-reminders (`:228`) states; `deleteAction`
  "Delete" string shared by all three dialogs.
- watchOS EventKit is read-only: all watch mutations are local-list edits + WatchConnectivity relays
  (`ReminderStore.swift:292-301`; relay wiring `WatchAppViewModel.swift:212-219`), so dialog Delete, Complete,
  and Reschedule all depend on the paired phone to persist.
- Seam persistence: AGENTS.md mandates App Group round-tripping; on watch `AppGroup.defaults` falls back to
  `.standard` (`AppGroup.swift:11, 16-17`), and `--ui-testing-action-menu` relies on the cross-relaunch
  persistence (resetting OFF on every plain `--ui-testing` launch, `WatchAppViewModel.swift:61-67`).
- Doc-vs-code gap: `nudgeIdentifier`'s "cleared on delete/dismiss/refresh" comment (`WatchReminderViewModel.swift:53`)
  has no clearing code in the watch target — banner lifetime is implicit (card removal) only.

## Open Areas
- Q2's step-by-step `ReminderStore.reload` line numbers (`:439-491` internals) come from one agent's grep;
  cross-checked against `grep -n` for the main symbols (`:439, :440, :441-443, :447-452, :453-458, :482,
  :487, :490, :491, :558, :571, :581, :590, :601, :614, :628, :644, :655, :671`) — all match; exact inner-window
  line boundaries not independently verified.
- `InMemoryEventStore.swift:13` class location confirmed; its full fetch/skip behavior was not re-verified.
- Whether the missing `nudgeIdentifier` clearing is intentional is not answered by the code (documented as-is).
- Watch unit-test details (`WatchSyncPipelineTests.swift:521-560`, `ShowEnableActionButtonsStateTests.swift`,
  `ReminderStoreWatchTests`) were characterized at file level only in Q3/Q5; see `conventions.md` inventory.
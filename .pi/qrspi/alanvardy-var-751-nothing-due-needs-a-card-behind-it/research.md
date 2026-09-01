# Research Findings

Research for `alanvardy-var-751` — how the "nothing due"/empty/reminder content
states are structured, styled, and tested across iOS, watchOS, and the widget.
All `file:line` refs verified against the working tree.

---

## Q1: Store-driven state branching (iOS app)

### Findings

- **Top-level branch**: `ContentView.body` (`SingleThread/ContentView.swift:64-82`)
  is a `ZStack` stacking `Color.systemBackground.ignoresSafeArea()` (`:66`),
  iOS-only `BackgroundPhotoLayer` (`:68-72`), then `viewModel.store.loadsReminders`
  ? `authGatedContent` : `reminderList` (`:76-80`).
- `loadsReminders` is a store init param (default `true`),
  `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:18,54`. Production
  sets it at `SingleThread/AppViewModel.swift:265` (`!launch-args contains
  "--ui-testing"/"--no-reminders"`); every preview and the UI-test seam pass
  `false` (`ContentView.swift:770-813`). When `false`, `store.start()` no-ops
  (`ReminderStore.swift:148`), so the auth gate is skipped entirely.
- **Auth gate** `authGatedContent` (`ContentView.swift:333-344`): switches on
  `viewModel.store.authorizationStatus` (`ReminderStore.swift:53`) — `.notDetermined`
  → `ProgressView("Requesting access…")`, `.fullAccess` → `reminderList`, any other
  case → `ContentUnavailableView("Reminders Access", systemImage: "lock.shield",
  description: …)`. Status is written by `start()` (`ReminderStore.swift:147-157`)
  and `requestAccess()` (`:401-413`; `requestFullAccessToReminders` protocol
  requirement at `SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:16`).
  Only `.fullAccess` ever reaches `reminderList`.
- **`reminderList`** (`ContentView.swift:347-453`) wraps everything in a single
  `GeometryReader` computing `viewHeight = size.height - safeAreaInsets.top -
  safeAreaInsets.bottom` (`:348-350`), used to center each branch.
- **All-Done branch** (`:352-364`): `store.allSkipped` → `ScrollView` with a
  centered `ContentUnavailableView` built from `ContentViewModel.allDoneStateCopy()`
  ("All Done" / `checkmark.circle` / "Pull to refresh to see all your reminders
  again.", `ContentViewModel.swift:71-76`), `.scrollBounceBehavior(.always)`,
  `.refreshable { await viewModel.reload(clearSkipped: true) }` (`:359-363`).
  No `bottomBar` in this branch.
- **Empty branch** (`:365-382`): `store.reminders.isEmpty` → `ZStack(alignment: .bottom)`
  of a `ScrollView`-centered `ContentUnavailableView` + `bottomBar`; copy from
  `ContentViewModel.emptyStateCopy(hasHidden:)` (`ContentViewModel.swift:58-67`):
  `hasHidden == true` → "Nothing due" / `calendar` / "Only today's and overdue
  reminders show here — pull to refresh."; else "No Reminders" / `checklist` /
  "You don't have any reminders yet." `.refreshable` → `viewModel.reload()`.
- **Populated branch** (`:383-449`): `List` (`.listStyle(.plain)`,
  `.scrollContentBackground(.hidden)` + `.background(Color.clear)` for iPadOS
  photo show-through, `:441-445`) with a single row: `visibleReminders.first` as
  `ReminderCardView`, `.listRowBackground(viewModel.rowChromeBackground)`
  (`:392`), `.padding(.horizontal, 40).padding(.vertical, 12)`,
  `.frame(maxWidth: .infinity/.center)` + `.frame(minHeight: viewHeight)`
  (`:393-397`), `.listRowSeparator(.hidden)` (`:398`), iOS `.contextMenu`
  (View in Reminders / Delete, `:401-414`), leading Complete / trailing Skip
  `.swipeActions` (`:415-435`), `.refreshable → reload()`; `bottomBar` overlays
  bottom-aligned (`:449`).
- **`bottomBar`** (`:455-490`): `VStack(spacing: 8)` with the dictation error /
  creation-feedback / recording / mic UI; iOS chain: `store.canMutate`
  (`ReminderStore.swift:132-134`, `entitlementStore.isEntitled || count < 100`)
  → freemium `upgradePrompt`; else `viewModel.showsActionButtons`
  (`ContentViewModel.swift:44-50`, UserDefaults `enableActionButtons` &&
  `visibleReminders.first != nil`) → Complete/Mic/Skip `actionCluster`; else plain
  `micButton`.
- **Store computations**:
  - `reminders` — `ReminderStore.swift:43`, sole writer `reload()`
    (`reminders = shown`, `:356`); seeds pre-populate via init (`:19`).
  - `visibleReminders` — `:117-123`: `reminders` minus `skippedIDs`
    (`calendarItemIdentifier`) and `excludedListTitles` (`calendar?.title`),
    sorted by `ReminderSort.areInIncreasingOrder` (`ReminderSort.swift:9,14`).
  - `allSkipped` — `:126-129`: `!reminders.isEmpty && visibleReminders.isEmpty`.
  - `hasHidden` — `:50`, set inside `reload()` (`:343-355`): when
    `showsUndatedReminders` a broad fetch is already in hand
    (`hasHiddenFor(shown:allIncomplete:)`, `:139-143`, true when any
    `allIncomplete` id is absent from `shown`); otherwise a second nil/nil
    predicate fetch reveals out-of-window reminders (`:347-354`). Window =
    `ReminderDateFilter.overdueCutoff()/endOfToday()` (`ReminderDateFilter.swift:9-30`).
  - `skippedIDs` resolved in `reload()` via `ReminderSkipLogic.resolve`
    (`:362-369`; `ReminderSkip.swift:10-16`), persisted through `skipStore`; the
    All-Done refresh path calls `clearSkippedState()` (`:363`, `:442-447`).
- The store is `@Observable` (`ReminderStore.swift:1`), so writes to
  `reminders`/`skippedIDs`/`hasHidden`/`authorizationStatus` re-evaluate `body` and
  re-pick the branch; `reload()` fires `onRemindersChanged?()` (`:375`).

---

## Q2: Card/plate visual surface (iOS app)

### Findings

- **Card plate** — `SingleThread/ReminderCardView.swift:47-54`:
  `.padding(12)` → `.background { RoundedRectangle(cornerRadius: 10)
  .fill(Self.plateFill(for: colorScheme)) }` → `.padding(-12)`.
  The padding pair grows the view for the plate then restores the outer layout
  frame, so `List` row metrics are unchanged (comment `:47-48`); the plate extends
  12pt beyond the text on every side.
- **`plateFill(for:)`** (`:61-63`): dark → `Color.black`; light →
  `Color(red: 0.96, green: 0.95, blue: 0.94)`. Scheme comes from
  `@Environment(\.colorScheme)` (`:67-68`), resolved at render time (`:52`); no
  `preferredColorScheme` on the card — the environment follows the app's
  appearance override (`AppDelegate.applyAppearance` via
  `ContentViewModel.swift:115-120`). Extracted *specifically as a unit-test seam*:
  "the rendered paint can't be asserted headlessly" (comment `:57-60`).
- **`promptBoxFill`** (`:35`): `static let Color(red: 0.16, green: 0.17, blue: 0.18)`
  — fixed dark grey, deliberately not scheme-adaptive so it reads on both the
  off-white light and black dark plates (comment `:30-34`). Applied with the same
  `RoundedRectangle(cornerRadius: 10)` recipe at `:186-192` (no `-12` restore —
  the prompt is its own full-width block).
- **Other plate-like surfaces**:
  - `ControlPlateModifier` (`SingleThread/ControlPlateModifier.swift:3-31`) — the
    one *shared* plate: 56×56 `Circle()` fill (`plateSize = 56`, `:33`), scheme
    adaptive `fill ?? (dark ? .black : Color(white: 0.92))` / glyph
    `(dark ? .white : Color(white: 0.15))` (`:21-22`), `.shadow(radius: 4)` (`:27`).
    Public `controlPlate(fill:glyph:)` (`:51-54`); 7 call sites, all in
    `ContentView.swift` (`:89,105,504,516,544,553,627`).
  - `rowChromeBackground` — always `Color.clear` computed seam
    (`ContentViewModel.swift:51-54`), consumed at `ContentView.swift:392`.
  - `Color+CrossPlatform.swift` (`:15-21`) — only `static var systemBackground`
    (map to `UIColor.systemBackground` / `NSColor.windowBackgroundColor`), the
    root layer at `ContentView.swift:66`, not a plate.
- **Shared vs. duplicated**: only `controlPlate()` and `Color.systemBackground`
  are shared. The card-plate recipe (`RoundedRectangle(10)` + 12pt inset) is
  written inline twice in one file (`ReminderCardView.swift:49-54` and `:186-192`);
  the "black in dark / off-white in light" pattern is re-implemented with different
  values in `ReminderCardView.plateFill` (`:62`) and `ControlPlateModifier`
  (`:21-22`). Grep for `RoundedRectangle|Capsule(|Circle(` across the iOS target
  hits only `ReminderCardView.swift`, `ControlPlateModifier.swift`, and a capsule
  purchase button (`PurchaseSettingsView.swift:186`); watch and widget targets
  contain none.

---

## Q3: Empty & reminder states on the watch

### Findings

- **Auth gate** (`SingleThreadWatch/WatchReminderView.swift:42-57`): switch on
  `viewModel.store.authorizationStatus` — `.notDetermined` → `ProgressView`,
  `.fullAccess` → `reminderContent`, default → bare centered
  `Text("Enable Reminders access in Settings")` (`:53-54`). No SF Symbol, no plate
  (contrast with iOS `ContentUnavailableView` lock).
- **`reminderContent` dispatcher** (`:77-104`): `ZStack` with priority
  `isShowingCompletionTransition && transitionReminder != nil` → ghost
  `reminderCard` (glow transition, managed in
  `WatchReminderViewModel.completeCurrentReminder()` `:65-88`), then
  `store.allSkipped` → `allDoneState`, then
  `store.visibleReminders.first` → `reminderCard`, else → `noRemindersState`.
  A top `ProgressView` overlays while refreshing (`:89-92`); `completionGlowOverlay`
  (`Color.green.opacity(0.3)`, `:170-180`) overlays the whole thing.
- **`allDoneState`** (`:146-152`): `VStack(spacing: 6)` of
  `Text("All Done").font(.headline)` + `refreshButton` (`:182-186`, disabled while
  refreshing; calls `viewModel.refresh(clearSkipped: store.allSkipped)`).
- **`noRemindersState`** (`:154-166`): `VStack(spacing: 6)` of
  `Text("No Reminders").foregroundStyle(.secondary)`, then
  `Text(store.hasHidden ? "Nothing due right now" : "No reminders yet")`
  `.font(.caption2)` `.foregroundStyle(.secondary)` (`.multilineTextAlignment(.center)`),
  plus `refreshButton`. No SF Symbol hero, no plate.
- **Populated `reminderCard`** (`:190-217`): `VStack(alignment: .leading, spacing: 6)`
  of a `ScrollView`ed `reminderDetails` (`:220-260`: priority marker `.headline`
  tinted, title `.headline`, due date `.caption`, list `.caption2`, recurrence
  `Label("repeat")`, alarms `Label("Alert","bell")`, notes `.caption2` — all
  non-title rows `.foregroundStyle(.secondary)`) + `confirmationDialog`
  (Refresh/Delete, `:201-210`) + `upgradeOniPhonePrompt` or `actionButtons`
  (`:106-131`: bare icon-only tinted Labels, no `controlPlate`). Whole card is
  `.padding()` (`:216`) — **no background plate at all**.
- **Difference from iOS card**: iOS = `.font(.title)` + plate over photo/wallpaper
  (`ReminderCardView.swift:93,98`); watch = `.headline` fonts, no plate, no
  background-photo layer, no `TextSizeModifier` (`ContentView.swift:156`), scrollable
  full card, no swipe actions/context menu/undo. iOS empty states use
  `ContentUnavailableView` + SF Symbols; watch uses plain text + a Refresh button.
- **State authority**: everything reads `viewModel.store.*`
  (`ReminderStore.swift` is the shared source of truth) plus per-surface
  `Show*State` holders (`ShowDateState.swift:8-28` etc.), updated only via
  WatchConnectivity hooks (`WatchAppViewModel.swift:186-230`).
- Previews cover every state (`WatchReminderView.swift:275-340`), including
  "Nothing Due" (`hasHidden: true`, `:303-307`).

---

## Q4: Empty & reminder states on the widget

### Findings

- **State model** — `NextThingEntry.State` (`SingleThreadWidget/NextThingWidget.swift:7-15`):
  `noAccess`, `empty(Bool /*hasHidden*/)`, `allDone`, `reminder(ReminderDisplay)`.
  Provider `makeEntry()` (`:58-73`) picks it from `EKEventStore.authorizationStatus`
  then the store: `reminders.isEmpty` → `.empty(store.hasHidden)`;
  `visibleReminders.first == nil` → `.allDone`; else `.reminder(...)`.
- **Dispatch** (`:135-152`): `.noAccess`, `.empty(hasHidden)`, and `.allDone` all
  render via the single shared **`messageView`** (`:178-195`) — `VStack(spacing: 6)`
  of an SF Symbol (`Image(systemName:)`, `.title2`, `.secondary`,
  `.accessibilityHidden(true)`), a `.headline` title, and an optional `.caption2`
  `.secondary` message (`nil` for `.allDone`). `.reminder` renders `reminderView`
  (`:197-238`): title `.headline .lineLimit(2)`, dated/list/recurrence/alarm rows
  gated by `entry.shows*`, notes `.lineLimit(2)`, `Spacer`, then Complete/Skip
  bordered buttons (`.tint(.green)/.tint(.orange)`).
- **Copy** mirrors the watch string forms: `.empty(true)` → "Nothing due right now",
  `.empty(false)` → "No reminders yet", `.noAccess` → "Reminders Access" /
  `lock.shield` / "Open SingleThread to enable access." (`:138-147`).
- **Backgrounds**: exactly ONE plate in the widget —
  `.containerBackground(.fill.tertiary, for: .widget)` on the shared
  `NextThingWidgetView` (`:113-121`, `.containerBackground` at `:119`). All four
  states sit on the same `.fill.tertiary` container plate; there are no per-state
  backgrounds, no inner plates (`plate` search in the widget target returns
  nothing), no `.widgetAccentable`. Content styling is foreground/typography only.
- Previews exist for `Reminder`, `No Access`, `All Done` (`:241-291`) — none for
  `.empty(hasHidden)`.

---

## Q5: Testing & assertion seams for visual decisions

### Findings

- **Decision-constant seam (primary headless seam)**: extracted static functions/
  constants name a visual decision and are asserted directly — documented inline as
  "the rendered paint can't be asserted headlessly, so tests assert this decision
  instead":
  - `ReminderCardView.plateFill(for:)` (`ReminderCardView.swift:61-64`), asserted
    in `SingleThreadTests/BackgroundCardTests.swift:69-78` (light off-white `:71`,
    dark pure black `:77`).
  - `ReminderCardView.promptBoxFill` (`ReminderCardView.swift:35`), asserted at
    `SingleThreadTests/SwipePromptTests.swift:34-36`.
  - `ContentViewModel.rowChromeBackground == .clear`
    (`ContentViewModel.swift:51-54`), asserted at
    `BackgroundCardTests.swift:52-66` (photo on/off both stay clear — the iPad
    opaque-row regression fix).
  - `EmptyStateCopy` factory (`ContentViewModel.swift:27-33,58-76`): full-field
    assertions in `SingleThreadTests/SingleThreadTests.swift:33-53` ("No Reminders"
    vs "Nothing due" vs "All Done"). This is the only place the "Nothing due"
    string is asserted — no UI test exercises it.
- **String-snapshot tests** (`String(describing: view.body)`): substring
  presence/absence for gated rows and shapes —
  `ShowDateTests.swift:10-41` (date row via `FormatStyleStorage`), `ShowAlarmsTests.swift:10-17`
  (bell row via `NamedImageProvider` — `Image(systemName:)` never prints the symbol),
  `ShowRecurrenceTests.swift:10-18`, `SwipePromptTests.swift:11-27` (asserts
  `"RoundedRectangle"` present only with the prompt plate, `:17`), plus
  `SettingsViewTests/ActionButtonTests/MicrophoneToggleTests`. Documented limits:
  a11y label strings never serialize (`SwipePromptTests.swift:41-45`), and runtime
  `_ConditionalContent` branches both appear in reflected names
  (`ActionButtonTests.swift:8-16`, `BackgroundCardTests.swift:36-41`) — for those,
  tests assert the *gate decision* instead.
- **UI tests asserting `staticTexts`** — `SingleThreadUITests/SingleThreadUITestsFlows.swift`
  driven by the `--seed '<json>'` seam (`:16-21`, backed by `InMemoryEventStore`,
  `UITestingSeed.swift:29-35`): empty state "No Reminders" (`:45-51`), "All Done"
  after skip-all (`:89-101`), "No Reminders" after complete/delete (`:106-137`),
  priority marker matched by a11y label "High priority" (`:76-87`), aggregated
  label gathering for attributed code text (`:333-366`). Absence via
  `XCTAssertFalse(...exists)`: glow overlay, Dismiss button, undo button
  (`:470-471, 525-537, 619-663`). `ActionButtonsUITests.swift:31-50` also asserts
  "All Done".
- **Accessibility audit**: `SingleThreadUITests/SingleThreadUITests.swift:27-66` —
  launches `["--ui-testing","--reset-swipe-preference"]` (audits the No Reminders
  empty branch, `:31-37`); local categories
  `[.dynamicType, .hitRegion, .sufficientElementDescription, .trait]`, CI trims to
  the non-rendering two (`:48-62`); **contrast and textClipped deliberately
  excluded** (`:44-47`) — the audit cannot tell whether a plate exists behind text.
- **Seams for "is a background plate present behind a view?"**:
  1. Decision constants (`plateFill`/`promptBoxFill`/`rowChromeBackground`) — the
     only headless plate assertions that exist.
  2. Reflection (`String(describing:)`) — works for `if`-gated shapes
     (`SwipePromptTests.swift:17`), not `_ConditionalContent`.
  3. `accessibilityIdentifier` overlay seam — the *only* observable
     behind-content layer in the repo: `completionGlowOverlay`
     (`ContentView.swift:562-572`, `.accessibilityHidden(true)` normally, exposed
     under `--ui-testing-glow` `:275-279`), asserted for presence AND absence
     (`SingleThreadUITestsFlows.swift:470-471,485-489`).
  4. Element-existence proxies — e.g. the accessibility-hidden swipe-prompt text
     is observed through its accessible Dismiss child (`ReminderCardView.swift:155-167`;
     `SingleThreadUITestsFlows.swift:506-539`).
- **What does NOT exist**: no pixel/snapshot-image tests; no UI query of
  `app.images`/background photo; no UI test of the "Nothing due" string;
  `testBackgroundRefreshButtonExists` explicitly declines asserting the fetched
  image (`SingleThreadUITestsFlows.swift:326-328`). Rendered paint is terminal at
  manual verification: `docs/SimulatorManualVerification.md:106-139`
  (row-chrome/plate-over-photo screenshot slots).

---

## Cross-Cutting Observations

- **One state authority, three renderers**: all three surfaces branch on the same
  `ReminderStore` properties from `SingleThreadCore` — `authorizationStatus`,
  `allSkipped`, `reminders.isEmpty`/`visibleReminders.first`, `hasHidden`
  (`ReminderStore.swift:43-54,117-129,321-375`). The iOS app, watch, and widget
  each re-derive their copy from it independently; there is no shared
  empty-state-copy type across targets (`EmptyStateCopy` lives only in
  `ContentViewModel.swift:27-33`).
- **"Nothing due" lives in three places with two spellings**: iOS title "Nothing
  due" (`ContentViewModel.swift:61`); watch + widget message "Nothing due right
  now" (`WatchReminderView.swift:158`, `NextThingWidget.swift:145`). The iOS
  version is the only one with a plate-less design question — it renders
  `ContentUnavailableView` text directly over the photo background with no card
  surface, while the populated iOS card always sits on `plateFill`.
- **Plate vocabulary is duplicated, not shared**: scheme-adaptive round
  `controlPlate()` (shared, 7 call sites) vs per-view card plate
  (`plateFill`, inlined twice in `ReminderCardView`) vs the widget's single
  `.fill.tertiary` container plate vs watch's absence of any plate.
- **Empty states differ in richness**: iOS = `ContentUnavailableView` (symbol +
  title + description) inside ScrollView with refreshable; watch = plain text +
  Refresh button; widget = symbol + title + optional message on the container
  plate. Only iOS gates the empty state with `bottomBar`.
- **The consistency story is test-seam shaped**: every headless test asserts a
  *decision* (color constant, copy string, gate bool), never rendered paint;
  rendered look is manual (documented in `docs/SimulatorManualVerification.md`).
  The one decorative overlay observable in UI tests is explicitly exposed via an
  `accessibilityIdentifier` + launch-arg seam.

## Open Areas

- No UI test covers the `hasHidden == true` "Nothing due" iOS title — only the
  factory unit test (`SingleThreadTests.swift:33-45`) and previews pin it.
- No unit or UI test exists for the widget at all (widget target has no test
  bundle; empty/preview coverage is `#Preview`-only).
- Watch empty-state copy ("Nothing due right now" / "No reminders yet") is asserted
  only through watch UI tests for the non-hidden path (`SingleThreadWatchUITests`
  asserts "No Reminders"/"All Done" — no `hasHidden` UI path found).
- How the iPhone's `hasHidden` value is mirrored to the watch/widget (via
  `AppGroup.defaults` watch-only key vs in-store recomputation) wasn't fully
  traced beyond `ReminderStore.reload()` recomputing it per-surface.
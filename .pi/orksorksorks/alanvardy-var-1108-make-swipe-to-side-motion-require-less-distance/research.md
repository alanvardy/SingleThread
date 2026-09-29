# Research Findings

Task: iOS reminder card swipe-to-side gesture needs less travel. Findings are
factual descriptions of the current interaction, list geometry, gesture
surface, prompt, and tests. Line numbers verified against the current checkout
of `SingleThread/ContentView.swift` unless noted.

## Q1: How the `.reminder` `List` builds card rows + card geometry

### Findings
- The reminder list is only reachable at `.fullAccess`. `authGatedContent`
  switches on `viewModel.store.authorizationStatus`; `case .fullAccess`
  renders `reminderList`, other states divert to `ContentUnavailableView`
  (`ContentView.swift:385-397`, grep-confirmed `391`).
- `reminderList` (`ContentView.swift:400`) opens a `GeometryReader` that
  provides `geometry.size.height/width` and `geometry.safeAreaInsets`; computes
  `viewHeight = geometry.size.height − top − bottom` (`ContentView.swift:402-405`).
- `switch viewModel.store.listContent` (`ContentView.swift:407`): `.allDone` →
  `EmptyStateCard` in a `ScrollView.refreshable` (`ContentView.swift:407-421`);
  `.empty(hasHidden)` → `ZStack` `bottomBar` + `ScrollView` `EmptyStateCard`
  (`.refreshable`, `ContentView.swift:423-434`); **`.reminder`** arm at
  `ContentView.swift:437-517`.
- The `.reminder` arm is a `ZStack(alignment: .bottom)` stacking the `List`
  over `bottomBar` (`ContentView.swift:438-517`). An inner
  `if let reminder = viewModel.store.visibleReminders.first` (`ContentView.swift:443`)
  keeps the `EKReminder` in scope and displays **only the first visible
  reminder**.
- One `ReminderCardView(...)` is built (`ContentView.swift:446-457`) with args:
  `display: ReminderDisplay(reminder:)`, `showDate/showList/showRecurrence/
  showAlarms` from preferences, `showSwipePrompt: swipePromptBinding`,
  `showNudge: viewModel.isNudged(...)`, `onNudgeTap: openNudgeSheet`, and
  `maxWidth: CardWidth.maxContentWidth(viewportWidth:)`.
- Row modifiers chained on the card (`ContentView.swift:459-466`):
  `.listRowBackground(viewModel.rowChromeBackground)`,
  **`.padding(.horizontal, 40)`** and `.padding(.vertical, 12)` (these are the
  ~40pt horizontal insets that compound swipe travel),
  `.frame(maxWidth: .infinity, alignment: .center)` (centers the plate),
  `.frame(minHeight: viewHeight, alignment: .center)` (row = full content
  height, card vertically centered), `.listRowSeparator(.hidden)`.
- SwiftUI. iOS-only `.contextMenu` (View in Reminders / Delete red-tinted,
  `deleteButton`) is `#if os(iOS)` guarded (`ContentView.swift:467-486`); the
  two `.swipeActions` sit **after** that guard (`ContentView.swift:488`,
  `496`) — they are iOS-context-independent but only reachable on iOS.
- `List`-level modifiers (`ContentView.swift:505-516`): `.listStyle(.plain)`,
  `.scrollContentBackground(.hidden)` (iPadOS opaque default would hide the
  photo, `ContentView.swift:506-509`), `.background(Color.clear)` (after the
  scroll-content hide, wins on iPadOS 18, `ContentView.swift:510-512`),
  `.refreshable { await viewModel.reload() }` (`ContentView.swift:514-516`).
- Card content geometry (`ReminderCardView.swift`): `struct ReminderCardView`
  (`:14`), default `maxWidth: CGFloat = 340` (`:28`); `body` a
  `VStack(spacing: 20)` (`:33`): inner `VStack(alignment: .leading, spacing: 4)`
  of `content` + optional `nudgeBanner` (`:34-45`), optional
  `if showSwipePrompt { prompt }` (`:47-48,52`), outer `.frame(maxWidth:)`
  (`:51`). `content` (`:62-147`) is a leading VStack of priority marker + title,
  date/list HStack, recurrence, list-name, alarms, notes, wrapped in
  `.accessibilityElement(children: .combine)` (`:141-146`).
- Width cap: `CardWidth.maxContentWidth(viewportWidth) → min(340,
  viewportWidth * 0.6)` (`CardWidth.swift:11-13`). Plate styling in
  `CardPlate.swift`: `cornerRadius = 10` (`:17`), `plateFill(for:)` (`:23`),
  `skipHintColor`/`completeHintColor` (`:32`,`:39`).

## Q2: Swipe/gesture modifiers in the repo

### Findings
- Exactly **two** `.swipeActions(edge:)` call sites, both in `ContentView.swift`:
  - **Leading (complete)** `ContentView.swift:488-494`: `Button {
    Task { await viewModel.completeCurrentReminder() } } label: {
    Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill") }
    .tint(.green)`.
  - **Trailing (skip)** `ContentView.swift:496-503`: `Button {
    viewModel.skipCurrentReminder() } label: { Label(SharedStrings.skipAction,
    systemImage: "circle.slash") } .tint(.orange)` (no extra modifiers beyond
    the orange tint / `circle.slash` icon).
- Grep for `DragGesture|gesture|drag|swipeDistance|dragDistance|draggable|
  threshold|Gesture` across `SingleThread/`, `SingleThreadCore/`,
  `SingleThreadWatch/` found **no custom drag/gesture recognizer**:
  - `ReminderCardView.swift:182` — comment noting the swipe hint is
    visual-only ("swipe-gesture vocabulary").
  - `SingleThreadWatch/WatchReminderView.swift:245` — `.onTapGesture` (a tap,
    not a swipe; the watch is button-tap based).
  - `StaleReminderRechecker.swift:15` — prose comment ("without a user gesture").
  - All `threshold` hits unrelated: SwiftLint file-length thresholds
    (`.swiftlint.yml:20`), and the skip-count nudge threshold
    (`SkipCountStore.swift:5-18`, `defaultThreshold = 6`) — data-driven, not
    a gesture threshold.
- **There is no `DragGesture` type, no swipable/recognizeGesture modifier, no
  gesture-threshold constant anywhere.** The swipe affordance is purely the two
  stock SwiftUI `.swipeActions` blocks. No custom gesture pattern exists to
  copy.

## Q3: List / ScrollView / pull-to-refresh & background configuration

### Findings
- `body` is a single `ZStack` (`ContentView.swift:169`):
  `Color.systemBackground.ignoresSafeArea()` base (`:171`),
  `BackgroundPhotoLayer(...)` (`:172-175`), then
  `if viewModel.store.loadsReminders { authGatedContent } else { reminderList }`
  renders the scroll surface on top (`:176-179`). The photo/system color stay
  fixed; the scrolling surface passes over them.
- Three arms share one `reminderList` surface:
  - `.allDone` `ScrollView` (`.scrollBounceBehavior(.always)` `:418`,
    `.refreshable { await viewModel.reload(clearSkipped: true) }` `:419-421`).
  - `.empty(hasHidden)` `ScrollView` (`.scrollBounceBehavior(.always)` `:431`,
    `.refreshable { await viewModel.reload() }` `:432-434`).
  - `.reminder` `List` (`.listStyle(.plain)` `:506`,
    `.scrollContentBackground(.hidden)` `:510`, `.background(Color.clear)`
    `:513`, `.refreshable { await viewModel.reload() }` `:514-516`).
- The photo/system background is **outside** the `List` (in the outer `body`
  ZStack, `ContentView.swift:169-179`), not inside. The `List`'s two opaque
  layers are both cleared so the fixed background shows through as it scrolls.
- `.scrollBounceBehavior(.always)` is applied to the two empty/allDone
  `ScrollView`s (`ContentView.swift:418`, `431`) but **not** to the reminder
  `List`.
- No `.scrollDismissesKeyboard`, `.scrollIndicators`, `.scrollTargetBehavior`,
  `.safeAreaPadding`, `.contentMargins`, `.defaultScrollAnchor`, or
  `.scrollPosition` anywhere in `ContentView.swift`. The only scroll-surface
  modifiers are `scrollContentBackground`, `background`, `listStyle`,
  `refreshable`, `scrollBounceBehavior`.
- Pull-to-refresh is wired on all three arms via `.refreshable`, each calling
  `viewModel.reload()` — List no args (`:515`), empty none (`:433`), allDone
  `clearSkipped: true` (`:420`).

## Q4: The swipe-instruction prompt

### Findings
- The prompt is a **visual-only** guidance plate ("Swipe right to complete" /
  "Swipe left to skip") rendered below the card, gated by `showSwipePrompt`.
- Rendered in `ReminderCardView.swift:43-53`: `if showSwipePrompt { prompt }`
  in the outer `VStack`, below the `cardPlate`-wrapped content. `prompt`
  (`:177-224`): a `VStack` with two hint lines — `Text("Swipe right to
  complete")` + `arrow.right` (`:186-190`), then `arrow.left` +
  `Text("Swipe left to skip")` (`:192-196`). Hint colors adapt via
  `CardPlate.completeHintColor`/`skipHintColor` (`:191`,`:197`).
- A `Button` "Dismiss" writes `showSwipePrompt = false` through the binding
  (`:198-203`), styled `.borderedProminent`, `.contentShape(Rectangle())`,
  `.accessibilityLabel("Dismiss swipe prompt")`,
  `.accessibilityIdentifier("swipePromptDismissButton")` (`:204-221`). The hint
  text block is `.accessibilityHidden(true)` — visual-only (`:200`); only the
  Dismiss button is reachable.
- The prompt is a standalone plate using `CardPlate.plateFill(for:)`, NOT
  nested in the card plate.
- Card state: `@Binding private var showSwipePrompt: Bool` (`:61`), defaulted
  `.constant(false)` in `init` (`:19`); Dismiss writes `false` (`:202`).
- Source of truth: iOS-only `@AppStorage("showSwipePrompt") var
  showSwipePrompt = true` in `ContentView.swift:104-105` (key matches the
  `AppGroup.defaults` key in the `UITestingSeed` purge list,
  `UITestingSeed.swift:102`).
- `ContentView.swift:380-384` `swipePromptBinding` — iOS returns
  `$showSwipePrompt`, other platforms `.constant(false)` (passed into the card
  at `ContentView.swift:451-452`). So iOS-only scoping for the prompt is
  handled entirely by this binding; the card itself has no platform guard.
- Settings chain: `makeSettingsBag()` builds
  `SettingsBindings(showSwipePrompt:)` from the `@AppStorage` value
  (`ContentView+Settings.swift:48-50`); bag round-trips on Settings
  (`SettingsView.swift:50`); write-back `.onChange(of: bag.showSwipePrompt) { _,
  new in showSwipePrompt = new }` (`ContentView+Settings.swift:27`).
  `SettingsBindings.swift:32,45,62`; toggle in
  `InterfaceSettingsView.swift:131-142` (label "Show swipe prompt",
  `.accessibilityIdentifier("showSwipePromptToggle")`).
- First-launch/testing seam (`AppViewModel.swift:257-265`): under `--ui-testing`
  swipe-prompt defaults ON on fresh sim; `--reset-swipe-preference` removes the
  key, otherwise `set(false, ...)` to keep it from hiding the
  Complete/Skip/mic cluster.
- Localized strings in `Localizable.xcstrings`: "Swipe left to skip" `:3451`,
  "Swipe right to complete" `:3492`, "Show swipe prompt" `:3041`,
  "Dismiss swipe prompt" `:693`.

## Q5: Unit and UI test patterns for cards / swipe prompt / list

### Findings
- All focused swipe-behavior coverage is **unit tests via SwiftUI view
  reflection**; no UI/XCTest performs a swipe gesture or asserts the prompt in
  the app.
- `SingleThreadTests/SwipePromptTests.swift:7-64` — the focused swipe-prompt
  suite. `promptShownWhenEnabled` (`:7`) reflects `String(describing: ...body)`
  asserting labels "Swipe left to skip"/"Swipe right to complete", document
  order (complete above skip), and `CardPlateModifier`/`Dismiss` presence
  (`:12-15,19-24,44-46`). `promptHiddenWhenDisabled` (`:37`) asserts absence
  when `false`. `dismissButtonHasAccessibilityLabel` (`:44`) asserts `Button<`,
  `BorderedProminentButtonStyle`, `AccessibilityAttachmentModifier` (`:51-53`).
  `makeCard(showSwipePrompt:)` builds `ReminderCardView(display:, showDate:,
  showSwipePrompt: .constant(...))` (`:58-63`).
- `SingleThreadTests/SettingsViewTests.swift` — `settingsBindingsCarriesShow
  SwipePrompt` (`:29`, default true / explicit-false round-trip `:31-33`),
  renders "Show swipe prompt" caption + "Show a hint when there are swipeable
  reminders." via `InterfaceSettingsView` (`:121,134-136`).
- Card row tests: `ReminderDisplayRowTests.swift:11,17,23,29` (caption text
  parts + title via `String(describing:)`); `ShowAlarmsTests.swift:25-26`,
  `ShowDateTests.swift:34-36`, `ShowRecurrenceTests.swift:25-26` construct
  `ReminderCardView` directly. `FilteredRemindersListViewTests.swift:9,25`
  drives `FilteredRemindersListView(displays: [...])`.
- Domain list/ordering: `ReminderStoreTests.swift` — stores constructed with
  `loadsReminders: false` (e.g. `:27-29,41-43,52-54`) or explicit
  `InMemoryEventStore()` (`:149`).
- Testing seams / launch args:
  - `UITestingSeedTests.swift:180-183` — `UITestingSeed.fromLaunchArguments`
    malformed/no-JSON/absent seed → nil; `:186` `--seed` JSON →
    `InMemoryEventStore(reminders:, calendars:)` with `loadsReminders: true`;
    `:220-223` `resetPersistedState` clears "showSwipePrompt".
  - `--reset-swipe-preference` consumed by `AppViewModel.swift:262-265`; **no
    XCTest** in `SingleThreadUITests/` launches with it.
- UI XCTest (`SingleThreadUITests/SingleThreadUITests.swift`) launches with
  `app.launchArguments = ["--ui-testing"]` (`:38,82,154`); `testLaunchAndRenderSmoke`
  seeds one reminder and asserts cards/complete/skip/dictate buttons + priority
  marker via `app.staticTexts`/`app.buttons` `waitForExistence` (`:43-67`), plus
  iOS a11y audit (`:68-77`). Other UI tests cover language switching. Grep for
  `swipe|Swipe` in `SingleThreadUITests/` returned **no matches**.
- **Not findable in budget / absent:** no UI test that performs a `.swipeActions`
  flick; no UI test asserting the swipe prompt renders in-app; no dedicated test
  file for `.refreshable`/`.scrollBounceBehavior` scroll behavior.

## Cross-Cutting Observations
- The entire swipe/refresh affordance is stock SwiftUI (`.swipeActions`,
  `.refreshable`); **no custom gesture, drag recognizer, or threshold constant
  exists anywhere** in iOS, Core, or Watch — so no in-repo gesture pattern to
  follow.
- iOS-only scoping is handled via `swipePromptBinding` (iOS `$showSwipePrompt`,
  else `.constant(false)`); `.contextMenu` is the only thing under `#if os(iOS)`.
  The swipe actions themselves sit outside any platform guard but are only
  reachable on iOS.
- The horizontal insets that compound swipe travel are `.padding(.horizontal, 40)`
  applied to the card row (`ContentView.swift:460`); the card is centered in a
  full-width row via `.frame(maxWidth: .infinity, alignment: .center)`.
- Only the **first** visible reminder is rendered in the `List`
  (`ContentView.swift:443`), so this is a single-row list, and the swipe
  gesture would apply to that one row.
- Pull-to-refresh lives on the `List` via `.refreshable` (`ContentView.swift:514`),
  coexisting with `.swipeActions` on the same row — horizontal swipe vs
  vertical pull already coexist on one surface today.

## Open Areas
- Exact SwiftUI `.swipeActions` full-swipe-trigger threshold semantics (what
  distance/velocity triggers the edge action vs. reveal) are not
  inspectable from app source — that is SwiftUI built-in behavior, not
  configured here.
- Whether `List`'s `.refreshable` and the row's `.swipeActions` interact at the
  gesture-recognition level (can a partial horizontal drag also pull-refresh?)
  is not determinable from source alone.
- `bottomBar`'s definition lives in a `ContentView+*.swift` extension file not
  opened in the tool budget; its exact contents are unverified.
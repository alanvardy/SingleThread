# Research Findings

## Q1: How does `ContentView` render a reminder's due date?

### Findings
- The reminder card lives inside `reminderList`, a `GeometryReader`-wrapped `List`
  (`SingleThread/ContentView.swift:196` `GeometryReader { geometry in }`; `List {`
  at `:229`). The `List` is reached from `authGatedContent`'s `.fullAccess` case
  (`ContentView.swift:196` area) and gated at top level by the
  `if allSkipped` / `else if store.reminders.isEmpty` / `else` branches.
- The card is a single `if let reminder = store.visibleReminders.first`
  (`ContentView.swift:230`). `visibleReminders` is `[EKReminder]`
  (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:59`).
- Layout is one `VStack(alignment: .leading, spacing: 4)` (`ContentView.swift:231`)
  with three rows in order:
  1. **Title row** — `HStack(alignment: .firstTextBaseline, spacing: 4)`
     (`:232`): optional priority marker `if let level = ReminderPriority.level(for: reminder.priority)`
     wrapping `Text(ReminderPriority.marker(for: reminder.priority))` (`:233-234`),
     styled `.font(.title)` (`:235`), `.foregroundStyle(priorityColor(level))` (`:236`),
     `.accessibilityLabel("\(level.displayName) priority")` (`:237`); then
     `Text(reminder.title).font(.title)` (`:239-240`). `priorityColor` maps
     low→green, medium→yellow, high→red (`ContentView.swift:371-376`).
  2. **Due date** — `if let due = reminder.dueDateComponents?.date` (`:242`)
     wraps `Text(due, style: .date)` (`:243`), styled `.font(.caption)` (`:244`)
     and `.foregroundStyle(.secondary)` (`:245`). Sits **below** the title row and
     **above** notes. `.date` style only (no `.time`).
  3. **Notes** — `if let noteText = ReminderNotesFormatter.format(reminder.notes)`
     (`:247`) wraps `Text(noteText)` (`:248`), styled `.font(.callout)` (`:249`),
     `.foregroundStyle(.secondary)` (`:250`), `.lineLimit(3)` (`:251`).
- The three optional fields are independently gated with `if let …`:
  priority (`:233`, level is `nil` unless priority is 1/5/9 — see
  `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift:50`), due date
  (`:242`), notes (`:247`; `format` returns `nil` for nil/empty — `ReminderSkip.swift:93`).
- Card-level modifiers: `.padding(.horizontal, 40)` (`:254`), `.padding(.vertical, 12)`
  (`:255`), `.frame(minHeight: viewHeight, alignment: .center)` (`:256`),
  `.listRowSeparator(.hidden)` (`:257`), iOS `.contextMenu` "View in Reminders"
  (`:259`), `.swipeActions(edge: .leading)` "Complete" and `.trailing` "Skip" (`:271`, `:279`).
- **Key observation**: `ContentView` does **not** use `ReminderDisplay`. It reads the
  due date straight from the `EKReminder` via `reminder.dueDateComponents?.date`
  (`ContentView.swift:242`). `ReminderDisplay` mirrors the same mapping
  (`ReminderDisplay.swift:14`) but is only consumed by the widget and unit tests
  (doc comment `ReminderDisplay.swift:3-4`).

## Q2: How does due-date data flow through `SingleThreadCore`?

### Findings
- **Source of truth** is EventKit's `EKReminder.dueDateComponents` (`DateComponents?`).
  The only write happens in `EventKitStoring.makeReminder`:
  `reminder.dueDateComponents = dueDate`
  (`SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:53`).
- **`ReminderDisplay.init(reminder:)`** maps `dueDate = reminder.dueDateComponents?.date`
  (`SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift:14`), storing
  `public let dueDate: Date?` (`:34`). `ReminderDisplay` is `Equatable, Sendable`
  (`:6`) and also derives `title`, `notes` (via `ReminderNotesFormatter.format`, `:13`),
  and `priorityMarker` (`:15`). A second direct initializer supplies `dueDate`
  explicitly for previews/placeholders/tests (`:19-28`).
- **`ReminderSort.areInIncreasingOrder`** (`ReminderSort.swift:7`) is `nonisolated`
  (`:6`). Order keys are **priority first, then due date**:
  - Priority rank via `ReminderPriority.rank(for:)`; lower rank (high) first; `nil`
    after any ranked reminder (`ReminderSort.swift:8-19`).
  - Due date via `let lhsDate = lhs.dueDateComponents?.date` / `rhsDate` (`:21-22`),
    with `.some` vs `.none` implementing "dated before undated" (`:23-30`).
  - Title tiebreak `localizedCaseInsensitiveCompare == .orderedAscending` (`:33`).
- **`ReminderDateFilter`** (`nonisolated`, `ReminderDateFilter.swift:26`):
  - `endOfToday()` = start of today + 1 day − 1 second (`:28-36`); doc says it excludes
    reminders due tomorrow (`:27`).
  - `overdueCutoff(days: 30)` = start of today − 30 days (`:41-50`); doc says the 30-day
    bound keeps the EventKit fetch bounded (`:38-40`). Both static, with `calendar`/`now`
    defaults for testability.
- **`ReminderStore.reload()`** builds the fetch predicate bounded by those two dates:
  - `eventStore.predicateForIncompleteReminders(withDueDateStarting: ReminderDateFilter.overdueCutoff(),
    ending: ReminderDateFilter.endOfToday(), calendars: nil)` (`ReminderStore.swift:164-167`),
    then `fetchReminders(matching:)` (`:168`) into `reminders` (`:169`).
  - `fetchReminders` async-bridges EventKit via `withCheckedContinuation` (`:232-237`).
  - `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` is the
    `EventKitStoring` test seam (`EventKitStoring.swift:14-17`), so date bounds are injectable.
- **`visibleReminders`** filters skipped IDs then sorts via
  `ReminderSort.areInIncreasingOrder` (`ReminderStore.swift:59-63`).
- **End-to-end**: EventKit populates `dueDateComponents` → `reload()` bounds fetch to
  `[overdueCutoff(), endOfToday()]` → `visibleReminders` sorts (priority → due date,
  dated-before-undated → title) → `ReminderDisplay.init(reminder:)` (or, in `ContentView`,
  direct `dueDateComponents?.date`) re-derives a `Date?` for display.

## Q3: How are user preferences persisted and read?

### Findings
- **`@AppStorage` keys in `ContentView`** (`SingleThread/ContentView.swift`):
  - `@AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system` (`:115-116`)
  - `@AppStorage("textSize") private var textSize = TextSize.system` (`:118-119`)
  - `#if os(iOS) @AppStorage("allowsLandscape") private var allowsLandscape = true` (`:121-124`)
  - `@AppStorage("showMicrophoneButton") private var showMicrophoneButton = true` (`:126-127`)
  - These persist to `UserDefaults.standard` (default `@AppStorage` store) under literal
    string keys; SwiftUI auto-republishes.
- **Consumption in the body**: `appearanceMode` → `.preferredColorScheme(appearanceMode.colorScheme)`
  (`:65`); `textSize` → `.modifier(TextSizeModifier(textSize: textSize))` (`:66`), which
  applies `.dynamicTypeSize` only when non-`.system` (`:420-433`); `showMicrophoneButton`
  gates the mic: `else if canDictate, showMicrophoneButton { micButton }` (`:324`);
  `allowsLandscape`/`showMicrophoneButton` are passed as `Binding`s into `SettingsView`
  (`:67-79`).
- **Enum pattern** — `AppearanceMode` and `TextSize` are `String, CaseIterable` with
  `title`/`systemImage` (plus a behavior-mapping property):
  - `enum AppearanceMode: String, CaseIterable { case system, light, dark }`
    (`SingleThread/AppearanceMode.swift:8-11`); `colorScheme: ColorScheme?` maps
    `.system → nil` (follow device), light/dark → `.light`/`.dark` (`:16-21`);
    `systemImage` (`:25-30`); `title` (`:34-39`).
  - `enum TextSize: String, CaseIterable { case system, small, medium, large, extraLarge }`
    (`SingleThread/TextSize.swift:8-13`); `dynamicTypeSize: DynamicTypeSize?`
    (`.system → nil`, others map up to `.xLarge`) (`:18-25`); `systemImage` (`:29-36`);
    `title` (`:40-47`).
- **`AppGroup.defaults` vs `UserDefaults.standard`**:
  - `AppGroup.suiteName = "group.app.alanvardy.SingleThread"`
    (`SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:8`).
  - `AppGroup.defaults = UserDefaults(suiteName: suiteName) ?? .standard` (`:13-14`),
    with the `?? .standard` fallback documented for "watchOS, unregistered simulators,
    and previews" (`:10-12`).
  - So `AppGroup.defaults` is the shared cross-process store (used for skipped-reminder
    IDs), while the `@AppStorage` preference keys above are `UserDefaults.standard`
    (the app's own sandbox), **not** the App Group.
- **`AppDelegate` reads a key straight from `UserDefaults` at launch**:
  - `AppDelegate` is `#if os(iOS)` and bridges UIKit orientation locking (`SingleThread/AppDelegate.swift:1-9`),
    registered via `@UIApplicationDelegateAdaptor` in `SingleThread/SingleThreadApp.swift`.
  - `application(_:supportedInterfaceOrientationsFor:)` reads
    `UserDefaults.standard.object(forKey: "allowsLandscape") != nil` (`AppDelegate.swift:34`)
    then `UserDefaults.standard.bool(forKey: "allowsLandscape")` (`:35-36`), returning
    `.allButUpsideDown` or `.portrait` (`:38`). Doc comment explains the direct read means
    the persisted lock applies "before any SwiftUI view appears" to avoid an orientation
    flash (`:7-9`).
  - A static `applyLock(allowsLandscape:)` recomputes the mask and requests a geometry
    update, called from SwiftUI when the toggle changes (`AppDelegate.swift:17-26`).
- `allowsLandscape` is the one preference with a dual read path: `@AppStorage` in
  `ContentView` (settings `Toggle` binding) and raw `UserDefaults.standard` in
  `AppDelegate` (launch-time orientation mask) — same key, same store.

## Q4: How is `SettingsView` structured and presented?

### Findings
- `SettingsView` (`SingleThread/SettingsView.swift`) "owns no state — every preference
  is bound back to `ContentView`'s `@AppStorage` values" (doc `:8-9`).
- **Binding initializer with platform variants**:
  - iOS `init` takes four bindings (`appearanceMode`, `textSize`, `allowsLandscape`,
    `showMicrophoneButton`) (`SettingsView.swift:10-20`).
  - `#else` variant omits `allowsLandscape` and takes three (`:21-29`).
  - Bindings stored via underscore-prefixed assignment, e.g. `_appearanceMode = appearanceMode`
    (`:14-17`, `:24-27`).
- **Form rows** (`Form` inside `NavigationStack`, `:35-36`):
  - `Picker("Appearance", selection: $appearanceMode)` over `AppearanceMode.allCases`
    with `Label(mode.title, systemImage: mode.systemImage)` (`:37-42`).
  - `Picker("Text Size", selection: $textSize)` over `TextSize.allCases` (`:43-48`).
  - `#if os(iOS)` `Toggle(isOn: $allowsLandscape)` "Allow Landscape" with
    `.onChange(of: allowsLandscape) { _, newValue in AppDelegate.applyLock(...) }`
    (`:49-56`).
  - `Toggle(isOn: $showMicrophoneButton)` "Show Microphone" on all platforms (`:57-59`).
- **Toolbar Done**: `.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }`
  (`:61-66`); `dismiss` from `@Environment(\.dismiss)` (`:81-82`).
- **Sheet-level modifiers**: `.preferredColorScheme(appearanceMode.colorScheme)` and
  `.modifier(TextSizeModifier(textSize: textSize))` apply the selections to the sheet
  itself (`:69-70`).
- **Presentation from `ContentView`**: a `Button { isShowingSettings = true }` in a
  top-trailing `.overlay(alignment: .topTrailing)` (`ContentView.swift:47-49`) with an
  `Image(systemName: "gearshape")` label (`:51`), 44×44 hit target via
  `.frame(width: 44, height: 44)` + `.contentShape(Rectangle())` (`:54-55`),
  `.accessibilityLabel("Settings")` + `.accessibilityAddTraits(.isButton)` (`:57-58`).
  State `@State private var isShowingSettings = false` (`:133`). The
  `.sheet(isPresented: $isShowingSettings)` (`:67`) builds the platform-specific
  `SettingsView` (`:68-79`), binding its controls back to the `@AppStorage` values.

## Q5: How does `WatchReminderView` render a reminder and its due date?

### Findings
- `body` switches on `store.authorizationStatus`: `.notDetermined` → `ProgressView("Requesting access…")`,
  `.fullAccess` → `reminderContent`, default → "enable access" text
  (`SingleThreadWatch/WatchReminderView.swift:28-40`); starts the store via
  `.task { await store.start() }` (`:41-43`).
- `reminderContent` picks among `allDoneState`, `reminderCard` (using
  `store.visibleReminders.first`), `noRemindersState`, plus a refresh `ProgressView`
  (`:60-73`).
- `reminderDetails` (`:143-170`) is a `VStack(alignment: .leading, spacing: 6)` (`:144`):
  - Title row `HStack(alignment: .firstTextBaseline, spacing: 3)` (`:145-153`); priority
    marker gated by `if let level = ReminderPriority.level(for:)` (`:146-150`) with
    `.font(.headline)`, `priorityColor(level)`, accessibility label; title
    `Text(reminder.title).font(.headline)` (`:152-153`).
  - **Due date** gated by `if let due = reminder.dueDateComponents?.date` (`:155`):
    `Text(due, style: .date)` with `.font(.caption)` and `.foregroundStyle(.secondary)`
    (`:156-159`). `.date` style only.
  - Notes gated by `if let noteText = ReminderNotesFormatter.format(reminder.notes)`
    (`:160`), `.font(.caption2)` secondary (`:160-164`).
  - Stack `.frame(maxWidth: .infinity, alignment: .leading)` (`:169`).
- `priorityColor(_:)` maps low/medium/high → green/yellow/red (`:190-196`).
- **Watch preferences/settings: none.** The watch target has only two Swift files
  (`SingleThreadWatchApp.swift`, `WatchReminderView.swift`); a grep of `SingleThreadWatch/`
  for `UserDefaults`, `@AppStorage`, `AppGroup`, `AppearanceMode`, `TextSize`, `standard`,
  `defaults` returns **zero matches**. `SingleThreadWatchApp` only wires a
  `ReminderStore` and `SkippedReminderSyncService` over `WCSession`
  (`SingleThreadWatch/SingleThreadWatchApp.swift:10-21`) and presents
  `WatchReminderView(store: store)` in a `WindowGroup` (`:27-29`). The only cross-process
  state the watch touches is skipped-reminder IDs via WatchConnectivity, not `UserDefaults`.

## Q6: How does `NextThingWidget` render a due date and read persisted state?

### Findings
- `NextThingEntry: TimelineEntry` carries a `State` enum: `.noAccess`, `.empty`,
  `.allDone`, `.reminder(ReminderDisplay)` (`SingleThreadWidget/NextThingWidget.swift:8-17`).
- `NextThingProvider: TimelineProvider` (`:23`): `placeholder`/`getSnapshot` return
  hardcoded `ReminderDisplay(title:)` entries (`:28-36`); `getTimeline` wraps
  `await Self.makeEntry()` in a `Task` and schedules the next refresh after 15 min
  (`:39-44`).
- **`makeEntry`** (`@MainActor private static`, `:50`):
  1. Checks `EKEventStore.authorizationStatus(for: .reminder)` directly (`:52`).
  2. `.fullAccess` → `ReminderStore(loadsReminders: true)`, `await store.reload()` (`:53-55`).
  3. `store.reminders.isEmpty` → `.empty` (`:57-58`); `store.visibleReminders.first == nil`
     → `.allDone` (`:59-61`); else `ReminderDisplay(reminder: current)` (`:63-64`);
     non-`.fullAccess` → `.noAccess` (`:66`).
- **`dueDate` population**: `ReminderDisplay.init(reminder:)` → `dueDate = reminder.dueDateComponents?.date`
  (`ReminderDisplay.swift:14`; stored `:34`).
- **`dueDate` → `Text(dueDate, style: .date)`**: body switches on `entry.state` and the
  `.reminder(display)` case calls `reminderView(display)` (`NextThingWidget.swift:88-108`).
  `reminderView` is a `VStack(alignment: .leading, spacing: 4)` (`:157`); inside, an
  `HStack` shows `Text(display.priorityMarker)` (guarded by `!display.priorityMarker.isEmpty`)
  + `Text(display.title)` (`:158-167`), then
  `if let dueDate = display.dueDate { Text(dueDate, style: .date).font(.caption).foregroundStyle(.secondary) }`
  (`:169-172`), then notes `if let notes = display.notes` (`:173-177`), a `Spacer`, and
  `actionButtons` (`:178-179`).
- **Persisted state — App Group vs standard defaults**:
  - The widget does **not** read the app's `@AppStorage` preferences (`appearanceMode`,
    `textSize`, `allowsLandscape`, `showMicrophoneButton`).
  - It reads the skip list through `ReminderStore`, whose `skipStore` defaults to
    `SkippedReminderStore()` (`ReminderStore.swift:15`). `SkippedReminderStore` defaults to
    `AppGroup.defaults` with key `"skippedReminderIdentifiers"` (`ReminderSkip.swift:111-114`),
    and `AppGroup.defaults` is the `group.app.alanvardy.SingleThread` suite falling back
    to `.standard` (`AppGroup.swift:8,13-14`).
  - `ReminderStore.reload()` calls `skipStore.load()` and prunes against fetched IDs
    (`ReminderStore.swift:177` area); `visibleReminders` filters skipped then sorts
    (`ReminderStore.swift:59-63`).
  - Skip/complete writes flow through `SkipReminderIntent.perform()` →
    `store.skipCurrentReminderImmediately()` → `applySkipSet` → `skipStore.save(updated)`
    (`ReminderIntents.swift:40-47`; doc "writes directly to the App Group-backed store"
    `ReminderIntents.swift:28-30`), and `CompleteReminderIntent` constructs its own
    `ReminderStore(loadsReminders: true)` (`ReminderIntents.swift:18-22`).
  - Widget config: `StaticConfiguration(kind: "NextThing", provider:)`,
    `.supportedFamilies([.systemSmall, .systemMedium, .systemLarge])` (`:70-83`).

## Q7: How are the settings preferences and reminder views tested?

### Findings
- **`SettingsViewTests`** (`SingleThreadTests/SettingsViewTests.swift`, `@MainActor struct`,
  Swift Testing `@Test`):
  - `settingsViewContainsAllPreferenceRows()` (`:10`) builds a `SettingsView` with
    `.constant(...)` bindings; `#if os(iOS)` adds the `allowsLandscape` binding
    (`:12-21`).
  - `let bodyDescription = String(describing: view.body)` (`:24`) then asserts
    `#expect(bodyDescription.contains(...))` for `"Appearance"`, `"Text Size"`,
    `"Microphone"`, `"Done"` (`:28-31`) and `"Landscape"` under `#if os(iOS)` (`:33`).
  - A comment explains this works because `Form` content (unlike `.sheet` content) is
    reflected in the `body` description (`:25-26`).
- **`MicrophoneToggleTests`** (`SingleThreadTests/MicrophoneToggleTests.swift`):
  - Fake `MicToggleFakeTranscriber: SpeechTranscribing` (`:8`) returns a stored
    `authorizationStatus`, empty `transcribe` (`:19-27`).
  - `settingsGearButtonIsPresent()` (`:34`) asserts `contains("Settings")`, noting the
    assertion targets the accessibility label because `Image(systemName:)` describes as a
    `NamedImageProvider` so `"gearshape"` never appears (`:36-45`).
  - `micButtonHiddenWhenSpeechDenied()` (`:49`) sets
    `UserDefaults.standard.set(true, forKey: "showMicrophoneButton")` with
    `defer` cleanup (`:53-55`), injects a `.denied` fake via
    `ContentView(loadsReminders: false, speechTranscriber: fake)`, asserts
    `!bodyDescription.contains("mic.fill")` (`:58-64`).
  - `micButtonAbsentWhenToggleOff()` (`:69`) / `micButtonWithToggleEnabledDoesNotCrash()`
    (`:82`) set the same key to false/true with `defer` cleanup and assert only
    non-empty body (no-crash) (`:71-91`).
  - The `SpeechTranscribing` seam is **in the app target**, not core:
    `@MainActor protocol SpeechTranscribing: AnyObject` (`SingleThread/ReminderDictation.swift:10`),
    doc "Test seam" (`:7-8`); real conformer `ReminderDictation` (`:24`). `ContentView`
    default-injects `ReminderDictation()` via nil-coalescing (3 initializers,
    `ContentView.swift:13,18,33`); `canDictate` derives from
    `speechTranscriber.authorizationStatus` (`:145-148`). `EventKitStoring.swift` only
    *cites* the seam as a pattern in its doc comment (`EventKitStoring.swift:4-6`).
- **`ReminderDisplayTests`** (`SingleThreadTests/ReminderDisplayTests.swift`): `mapsTitle`
  (`:7`), `formatsNotes` (`:13`), `mapsNilNotes` (`:21`); `mapsDueDate` (`:27`) sets
  `dueDateComponents = DateComponents(year: 2025, month: 2, day: 3)` and verifies via
  `Calendar.current.dateComponents`; `mapsNilDueDate` (`:44`); `mapsHighPriorityMarker`
  (priority 1 → `"!!!"`, `:50`); `mapsEmptyMarkerForNoPriority` (priority 0 → `""`, `:57`);
  `directConstructorStoresFields` (`:64`); file-private `makeReminder(title:)` fixture
  building an `EKReminder(eventStore: EKEventStore())` (`:78`).
- **Other unit tests** (`SingleThreadTests/SingleThreadTests.swift`): `ContentView`
  init-without-reminders and body-contains-`"refreshable"` assertions via
  `String(describing:)` (`:7-22`); `ReminderDateFilterTests` exercise `endOfToday` and
  the 30-day `overdueCutoff` boundary (`:25-69`).
- **UI-test accessibility audit** (`SingleThreadUITests/SingleThreadUITests.swift`,
  XCTest): `testAccessibilityAudit()` (`:17`) launches with `--ui-testing` (`:18`) and
  waits for a `staticText` because UI-testing mode shows a `ProgressView`
  (`:20-26`); iOS runs `performAccessibilityAudit(for: [.dynamicType, .hitRegion,
  .sufficientElementDescription, .trait])` (`:32`), skipping `contrast` and `textClipped`
  (comment `:26-27`); macOS runs default `performAccessibilityAudit()` (`:37`).
  `SingleThreadUITestsLaunchTests.swift` uses `runsForEachTargetApplicationUIConfiguration`
  with screenshot attachment (`:13`, `:18-29`).

## Cross-Cutting Observations
- **Due-date derivation is repeated, not centralized**: the `dueDateComponents?.date`
  mapping is duplicated in `ReminderDisplay.swift:14`, `ReminderSort.swift:21-22`, and the
  three view surfaces (`ContentView.swift:242`, `WatchReminderView.swift:155`,
  `NextThingWidget.swift:169` via `display.dueDate`). All render with
  `Text(due, style: .date)` + `.font(.caption)` + `.foregroundStyle(.secondary)`.
- **Reminder card layout is near-identical across three surfaces**: the
  `VStack(alignment: .leading, spacing: 4)` with a `.firstTextBaseline` title `HStack`
  (priority marker + title), a due-date row, then a notes row in
  `ContentView.swift:231-251`, `WatchReminderView.swift:144-164`, and
  `NextThingWidget.swift:157-177`. Priority color mapping (green/yellow/red) exists in
  both `ContentView.swift:371-376` and `WatchReminderView.swift:190-196`.
- **Two distinct persistence domains coexist**:
  1. App preferences via `@AppStorage` → `UserDefaults.standard` (`appearanceMode`,
     `textSize`, `allowsLandscape`, `showMicrophoneButton`).
  2. Cross-process skipped-reminder IDs via `SkippedReminderStore` → `AppGroup.defaults`
     (`group.app.alanvardy.SingleThread`, `?? .standard` fallback), read by app, widget,
     and (via WatchConnectivity) watch.
- **`ReminderDisplay` is a boundary type**: `Sendable`/`Equatable` snapshot decoupled from
  `EKReminder` (`ReminderDisplay.swift:3-15`), used by the widget and unit tests — but not
  by `ContentView` or `WatchReminderView`, which operate on `EKReminder` directly.
- **Sorting is priority-then-date, not date-first**: `ReminderSort` orders by priority
  rank, then due date (dated before undated, soonest first), then title
  (`ReminderSort.swift:7-34`). The EventKit fetch is a date *window*
  (today-or-overdue, 30-day floor) rather than a sort.
- **Testing style is string-snapshot of `view.body`** (`String(describing: view.body)`),
  using protocol-based fake seams (`SpeechTranscribing`) and direct `UserDefaults.standard`
  key manipulation with `defer` cleanup — no ViewInspector, no rendered snapshot tests.

## Open Areas
- `@AppStorage` preferences are **not** shared across phone/watch/widget today (standard
  defaults per platform; App Group only for skipped IDs). Whether that is intended is
  outside this research scope.
- `allowsLandscape`'s post-launch orientation change (`AppDelegate.applyLock`,
  `AppDelegate.swift:14`) is wired in `SettingsView.onChange` (`SettingsView.swift:53`),
  but the runtime geometry-update behavior was not exercised here.
- The widget's 15-minute refresh (`NextThingWidget.swift:43`) and per-family layout
  details were outside the specific questions; only the due-date/persistence flow was traced.
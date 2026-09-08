# Research Findings

## Q1: Reminder data flow — EKReminder → ReminderDisplay → rendering surfaces

### Findings
- `ReminderStore` holds raw EventKit objects, not display models:
  `public private(set) var reminders: [EKReminder]` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:47`).
- Fetch path: `reload()` at `ReminderStore.swift:251-307` builds an incomplete-reminders predicate
  (`:265`), bridges to async via `fetchReminders(matching:)` (`:379-390`), stores result at `:291`.
  `visibleReminders` filters skipped IDs + excluded projects and sorts (`ReminderStore.swift:107-112`);
  every surface renders `visibleReminders.first`.
- `ReminderDisplay` (`SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`) has four fields,
  populated in `init(reminder: EKReminder)` at lines 11–16:
  - `title` (:32) ← `reminder.title` (:12)
  - `notes` (:33) ← `ReminderNotesFormatter.format(reminder.notes)` (:13)
  - `dueDate` (:34) ← `reminder.dueDateComponents?.date` (:14)
  - `priorityMarker` (:35) ← `ReminderPriority.marker(for:)` (:15)
- **`ReminderDisplay` is consumed only by the widget** (and unit tests). iOS and watch card views read
  `EKReminder` directly and re-apply the same formatters inline.
- Widget (`SingleThreadWidget/NextThingWidget.swift`): `NextThingEntry.State.reminder(ReminderDisplay)` (:9);
  `makeEntry()` builds its own `ReminderStore(loadsReminders: true)`, reads shared prefs (:60-62), converts
  once at :73; render reads all four fields at :167-185. Refresh `.after(Date + 15 min)` (:46).
- iOS card (`SingleThread/ReminderCardView.swift`): `init(reminder: EKReminder, showDate:, showsOverPhoto:)`
  (:15), stores `EKReminder` (:70), formats priority/title/date/notes inline at :25-39.
  Called from `ContentView.reminderList` (`SingleThread/ContentView.swift:342-345`) with `store.visibleReminders.first`.
- Watch card (`SingleThreadWatch/WatchReminderView.swift`): `reminderCard(_ reminder: EKReminder)` (:137),
  details at :161-178 read raw fields inline; date gated on local `@AppStorage("showDate")` (:172-173).
  Watch has its own `ReminderStore(loadsReminders: true)` (`SingleThreadWatch/SingleThreadWatchApp.swift:14-17`);
  complete/delete are relayed to the phone (watchOS has no EventKit writes).
- WatchConnectivity carries **no reminder content** — only context keys
  (`SkippedReminderSyncService.swift:234-241`): skipped IDs, excluded project titles, showUndatedReminders,
  sortOption, showDate; plus `sendMessage` complete/delete identifiers (:149,:159). Phone wiring
  `SingleThreadApp.swift:25-68`; watch wiring `SingleThreadWatchApp.swift:24-49`.
- `ReminderDateFilter.swift:6-22` documents a retroactive `EKReminder: @unchecked Sendable` conformance with a
  stated "REMOVAL PLAN" to convert continuation results to `ReminderDisplay`.

## Q2: Calendar/list access and abstractions

### Findings
- Exactly two runtime `calendar.title` read sites, both in Core:
  - Exclusion filter: `!excludedProjectTitles.contains($0.calendar?.title ?? "")` (`ReminderStore.swift:110`)
  - Available projects: `eventStore.calendars(for: .reminder).map(\.title)` deduped/sorted into
    `availableProjects` (`ReminderStore.swift:287-291`; declared :56).
- `EventKitStoring` protocol (`EventKitStoring.swift:7-45`, `@MainActor`, AnyObject): `calendars(for:)` (:12),
  `predicateForIncompleteReminders(...calendars:)` (:16-19), fetch/auth requirements; write ops gated
  `#if !os(watchOS)` (:26-42). `EKEventStore` conforms via extension (:45-66); `makeReminder` assigns
  `defaultCalendarForNewReminders()` (:63).
- Conformers of the seam: `EKEventStore` (SDK-satisfied), `InMemoryEventStore`
  (`SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift:13`; seeded reminders+calendars,
  reports `.fullAccess`), test-only `FakeEventStore` (`SingleThreadTests/EventKitStoringTests.swift:8`;
  `returnedCalendars`, `calendarFetchCallCount`).
- Persistence: `ExcludedProjectStore` (`ExcludedProjectStore.swift:4-27`) — key `"excludedProjectTitles"`,
  `AppGroup.defaults`. Loaded during `reload()` (`ReminderStore.swift:301`); mutated via
  `setExcludedProjectTitles(_:)` (:311-317, fires hooks) and `refreshExcludedProjectTitles(_:)` (:320-326,
  watch-receive path). Synced to watch via `onExcludedProjectsChanged` → WC context
  (`SingleThreadApp.swift:56`); watch seeds statically (`SingleThreadWatchApp.swift:89`).
- UI: `SettingsView.ExcludedProjectsView` renders per-project toggles
  (`SingleThread/SettingsView.swift:12-53`, ForEach :25, toggle insert/remove :43-52); bindings from
  `ContentView.swift:142-143,155-156,233-236`.
- UI-test seeding: `UITestingSeed` JSON includes `"calendars"` and `"excludedProjects"`
  (`UITestingSeed.swift:12-15,77-78`); `materialize()` sets `calendar.title` (:95-99) and attaches
  `reminder.calendar` (:108); applied in `SingleThreadApp.makeStore` (`SingleThreadApp.swift:113-127`).

## Q3: Boolean preferences end-to-end

### Findings
- All `@AppStorage` declarations live in `SingleThread/ContentView.swift`:
  | Key | Store | Ref |
  |---|---|---|
  | `appearanceMode` | .standard | :188 |
  | `textSize` | .standard | :191 |
  | `allowsLandscape` (iOS) | .standard | :195 |
  | `showMicrophoneButton` | .standard | :199 |
  | `backgroundEnabled` | .standard (explicit) | :202 |
  | `backgroundFadePercent` | .standard (explicit) | :205 |
  | `enableActionButtons` (iOS) | .standard | :209-211 |
  | `showUndatedReminders` | **AppGroup.defaults** | :213-214 |
  | `sortOption` | **AppGroup.defaults** | :216-217 |
  | `showDate` | **AppGroup.defaults** (iOS/widget) / .standard (watch) | :219-220 |
- Suite split: `AppGroup.defaults` = `UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard`
  (`SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:7-15`). Only the three shared prefs
  (showUndatedReminders, sortOption, showDate) use the App Group so the widget can read them;
  everything else is `.standard`-local. Skipped IDs and excluded titles use dedicated stores, not `@AppStorage`.
- SettingsView owns no state — pure bindings back to ContentView (`SettingsView.swift:58-59,211-225`).
  Toggle rows: "Allow Landscape" :143-147, "Show Microphone" :150, "Background" :153, "Background Fade"
  picker :156, "Enable action buttons" :162, "Show Undated" :166, "Show Date" :169 (+ onChange reload).
- Widget propagation — only two `WidgetCenter` call sites:
  `SettingsView.swift:174` (showDate toggle) and `store.onRemindersChanged → reloadAllTimelines()`
  (`SingleThreadApp.swift:67-69`). The widget also reads prefs straight from the shared container at
  render time (`NextThingWidget.swift:55,61`).
- Watch propagation chain: ContentView `.onChange(of: showUndatedReminders)` → `store.showsUndatedReminders`
  → hook `showsUndatedReminders.didSet` fires `onShowUndatedRemindersChanged` (`ReminderStore.swift:99-104`)
  → wired in `SingleThreadApp.init` (:54-56) → `SkippedReminderSyncService.push` via application context
  (:87-105) → watch `onShowUndatedRemindersReceived` → `store.showsUndatedReminders = value; reload()`
  (`SingleThreadWatchApp.swift:30-35`). `showDate` pushes separately (`SingleThreadApp.swift:79-81`,
  `pushShowDate` :137-151); watch persists received showDate under `.standard`
  (`ShowDatePreference(defaults: .standard)`, `SingleThreadWatchApp.swift:26-29`) while iOS uses App Group.

## Q4: "Show Undated" / "Enable action buttons" label occurrences

### Findings
- App code — exactly one occurrence each, both in `SingleThread/SettingsView.swift`:
  - `Toggle(isOn: $enableActionButtons) { Label("Enable action buttons", systemImage: "hand.tap") }`
    inside `#if os(iOS)` (:162-164)
  - `Toggle(isOn: $showUndatedReminders) { Label("Show Undated", systemImage: "calendar.badge.minus") }`
    — ungated (:166-168)
- Unit tests — `SingleThreadTests/SettingsViewTests.swift`: `#expect(bodyDescription.contains("Show Undated"))`
  (:53, ungated); iOS-gated `contains("Landscape")` and `contains("Enable action buttons")` (:58-60).
  Pattern: `String(describing: view.body)` substring assertions (Swift Testing `@Test`).
- UI tests assert neither string (`testSettingsOpensAndShowsControls`,
  `SingleThreadUITests/SingleThreadUITestsFlows.swift:126-141` checks "Appearance"/"Text Size"/"Sort By"/"Show Date").
- Neither string appears in SingleThreadCore, SingleThreadWidget, or SingleThreadWatch targets.
- Conventions observed: hardcoded English labels, no localization anywhere (zero `*.strings` files);
  every settings row pairs `Label(title, systemImage:)` with an SF Symbol; casing is mixed — most rows
  Title Case ("Show Microphone", "Show Date", "Allow Landscape") but "Enable action buttons" is sentence case,
  and "Show Undated" truncates the underlying key name `showUndatedReminders`.
- Gating conventions: `#if os(iOS)` for iPhone-only rows and their bindings/init params
  (init :66-92 iOS vs :93-119 macOS; stored binding :209-211); `#if os(iOS) || os(macOS)` for WidgetCenter
  code (:3-5, :172-176).

## Q5: ReminderCardView conditional rows, contrast, tests

### Findings
- `struct ReminderCardView` (`SingleThread/ReminderCardView.swift:11`); inputs `reminder: EKReminder` (:70),
  `showDate: Bool` (:71), `showsOverPhoto: Bool` (:73-74, defaults false); `@Environment(\.colorScheme)` (:67-68).
- Doc comment (:5-10): the view deliberately lives outside `List` so conditional rows stay observable in
  string-snapshot tests (`List` type-erases conditionals).
- Conditional rows in `VStack(spacing: 4)` body (:23):
  - Priority marker shown only when `ReminderPriority.level(for:) != nil` (:25), colored by level, with
    `.accessibilityLabel("\(level.displayName) priority")` (:29); title always renders (:31-32).
  - Due-date row requires BOTH preference and data:
    `if showDate, let due = reminder.dueDateComponents?.date` → `Text(due, style: .date)` (:34-38).
  - Notes row gated by formatter output: `if let noteText = ReminderNotesFormatter.format(reminder.notes)`
    → secondary text, `lineLimit(3)` (:39-43).
- Accessibility: `.accessibilityElement(children: .combine)` (:50) merges the whole card into one element
  (comment :46-49 explains hit-region audit rationale).
- Contrast/photo plate: when `showsOverPhoto`, padding sandwich (+12/-12, :55/:62) and a
  `RoundedRectangle(cornerRadius: 10)` filled `colorScheme == .dark ? Color.black : Color.white` (:56-61).
  Call site clears list row chrome: `.listRowBackground(backgroundDisplayed ? Color.clear : nil)`
  (`ContentView.swift:346`); gate = `backgroundEnabled && backgroundImage.imageData != nil`
  (`ContentView.swift:76-78`).
- Unit-test patterns:
  - String-snapshot on rendered body (`SingleThreadTests/ShowDateTests.swift`): `String(describing: body)`;
    hidden case asserts absence of `"FormatStyleStorage"` (:11-17), shown case asserts presence (:19-23).
    Factory makes a real `EKReminder(eventStore:)` with due components (:26-32).
  - Preference round-trip tests over `ShowDatePreference(defaults:key:)` with UUID keys
    (`ShowDatePreferenceTests.swift:6-40`), including missing-key-must-default-true (:32-40).
  - `BackgroundCardTests.swift` covers only the boolean gate (:44-88), not the plate rendering branch.

## Q6: UI-testing seams for toggles and card content

### Findings
- Launch args handled in `makeStore(arguments:)` (`SingleThreadApp.swift:96-128`):
  - `--seed '<json>'` → `UITestingSeed.resetPersistedState()` + `InMemoryEventStore` seeded with
    reminders/calendars + excluded projects applied (:104-106). Schema documented at
    `UITestingSeed.swift:1-16`; parser `fromLaunchArguments` (:23-32); reset removes both suites' keys
    incl. `showUndatedReminders`, `showDate`, `sortOption` (:47-58) but **not** `enableActionButtons`.
  - `--ui-testing` (iOS-only fallback) → force-sets `UserDefaults.standard` `enableActionButtons=true`
    (:111-113), returns one hard-coded "Buy groceries" reminder without touching EventKit (:115-124).
  - `--no-reminders` → suppresses production load (:126-128). WCSession wiring skipped when seeded (:21).
- Watch seam: `--ui-testing` → `uiTestingStore(arguments:)` (`SingleThreadWatchApp.swift:11-15,66-97`);
  extra `--ui-testing-excluded "<project>"` assigns reminder to that calendar and pre-excludes it (:74-77).
- **No `accessibilityIdentifier` exists anywhere** in app or test targets; queries match visible labels
  (e.g., `app.switches["Background"]`, `buttons["Complete reminder"]`, `staticTexts["Buy groceries"]`).
- Toggle assertion pattern (`SingleThreadUITestsFlows.swift:145-170`):
  `toggle.value as? String == "1"` default check → `flipToggle` → relaunch with `--ui-testing` (**not**
  `--seed`, which would wipe the persisted key) → value `"0"`. `flipToggle(_:target:)` (:175-190) taps the
  nested switch inside SwiftUI Form rows up to 3× polling the value.
- Card-content assertions: seeded title/notes (`:29-36`), empty/"No Reminders" (`:39-44`),
  skip ordering (`:48-65`), "All Done" (`:68-81`), swipe-complete (`:85-97`), context-menu delete (`:101-112`).
- Settings controls asserted in `testSettingsOpensAndShowsControls` (:126-140).
- Action buttons: `ActionButtonsUITests.swift:22-43` asserts Complete/Skip buttons render and Skip advances
  to "All Done"; accessibility audit at :46-63.
- Watch flows (`SingleThreadWatchUITestsFlows.swift`): card content :14-24, exclusion suppression :27-41,
  complete/skip/delete/refresh :44-108; all launch with `--ui-testing` (:113-118).

## Cross-Cutting Observations
- Three parallel persistence mechanisms exist side by side: `@AppStorage` (split between `.standard` and
  App Group), dedicated typed stores (`SkippedReminderStore`, `ExcludedProjectStore`, `SortOptionStore`,
  `ShowDatePreference`), and in-memory state on `ReminderStore`. Shared-with-widget prefs must go through
  `AppGroup.defaults`.
- Field parity across iOS/watch/widget cards is maintained by hand: `ReminderDisplay.init(reminder:)`
  encapsulates formatting that `ReminderCardView.swift:25-39` and `WatchReminderView.swift:164-178`
  duplicate inline against raw `EKReminder`. Priority marker is colorized on iOS/watch but uncolored on
  the widget; notes lineLimit is 3 (iOS) vs 2 (widget).
- `showDate` has divergent storage per platform: App Group on iOS/widget (`ContentView.swift:219`),
  `.standard` on watch (`SingleThreadWatchApp.swift:26-29`).
- Widget refresh rides two paths: explicit `reloadAllTimelines` on showDate toggle and the broad
  `onRemindersChanged` hook; other preference changes reach the widget only because it re-reads
  UserDefaults at timeline build time.
- Tests rely entirely on user-visible strings for XCUI queries; no stable identifiers anywhere.
- The `--seed` seam resets persisted defaults, so persistence-across-relaunch tests must use `--ui-testing`
  instead — an established pattern in `SingleThreadUITestsFlows.swift:145-170`.

## Open Areas
- No unit test exercises `showsOverPhoto: true` rendering (the color-scheme plate branch) or the notes-row /
  priority-marker conditionals; snapshot coverage applies only to the due-date row.
- Whether watch-side `.standard` persistence of synced `showDate` is intentional could not be confirmed
  from code alone beyond comments in `SkippedReminderSyncService.pushShowDate` (:137-151).
- The macOS branch of `ContentView`/`SettingsView` exists but no question targeted its behavior in depth.

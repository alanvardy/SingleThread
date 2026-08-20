# Research Findings

## Q1: How does ContentView render its placeholder states?

### Findings
- Content body splits on `store.loadsReminders`: `if store.loadsReminders { authGatedContent } else { reminderList }` — `SingleThread/ContentView.swift:43-46`. In the production app the store always has `loadsReminders: true`, so the rendered branch is the auth-gated one; in previews/tests it is `false` and renders `reminderList` directly.
- `reminderList` (`ContentView.swift:235`) is wrapped in `GeometryReader { geometry in ... }` and computes `viewHeight = size.height − safeAreaInsets.top − safeAreaInsets.bottom` (`ContentView.swift:236-238`). Every placeholder uses this height to `.frame(minHeight: viewHeight, alignment: .center)`.
- Branch order inside `reminderList` (`ContentView.swift:240-311`):
  - **All Done** (`if allSkipped`, `ContentView.swift:240`): `ScrollView { ContentUnavailableView(...) }.frame(minHeight: viewHeight, alignment: .center)` (`ContentView.swift:242-246`), `.scrollBounceBehavior(.always)` (`:248`) and `.refreshable { await store.reload(clearSkipped: true) }` (`:249-250`). No `bottomBar`.
  - **No Reminders** (`else if store.reminders.isEmpty`, `ContentView.swift:251`/`:254`): `ZStack(alignment: .bottom) { ScrollView { ContentUnavailableView(...) }.frame(...) .scrollBounceBehavior(.always) .refreshable { await store.reload() }  bottomBar }` (`ContentView.swift:253-265`). Only this branch (and the populated-list branch) overlays `bottomBar`.
  - **Populated list** (`else`, `ContentView.swift:267`): `ZStack(alignment: .bottom) { List { if let reminder = store.visibleReminders.first { ReminderCardView(...) } } .listStyle(.plain) .refreshable { await store.reload() }  bottomBar }` (`ContentView.swift:268-311`).
- `ContentUnavailableView` is a **SwiftUI framework view** (imported via `SwiftUI`, not defined in this repo) that takes a `(title, systemImage:, description:)`. All three usages in the codebase are below, and all live in `ContentView.swift`:
  - Auth-denied: `ContentUnavailableView("Reminders Access", systemImage: "lock.shield", description: Text("Enable access in Settings to see your reminders."))` — `ContentView.swift:228`.
  - All Done: `ContentUnavailableView("All Done", systemImage: "checkmark.circle", description: Text("Pull to refresh to see all your reminders again."))` — `ContentView.swift:242`.
  - No Reminders: `ContentUnavailableView("No Reminders", systemImage: "checklist", description: Text("You don't have any reminders yet."))` — `ContentView.swift:255`.
- `authGatedContent` (`ContentView.swift:221`, `@ViewBuilder`) is a `switch store.authorizationStatus`: `.notDetermined → ProgressView("Requesting access…")`; `.fullAccess → reminderList`; default → the `ContentUnavailableView("Reminders Access")` denied state (`ContentView.swift:223-228`).
- The settings gear overlay and the `.task { store.showsUndatedReminders = ...; await store.start() }` and `.onChange(of: showUndatedReminders) { ... await store.reload() }` all surround the `ZStack` (`ContentView.swift:41-70`).

### Patterns observed
- The same `ContentUnavailableView(title, systemImage:, description:)` affordance is reused for all three non-list surfaces (auth-denied, All Done, No Reminders) with distinct icon strings (`lock.shield` / `checkmark.circle` / `checklist`).
- Refresh is expressed at the container level via `.refreshable`, not as a visible button.

## Q2: What store state distinguishes empty vs. all-hidden?

### Findings
- Store properties and declarations (`ReminderStore.swift`):
  - `public private(set) var reminders: [EKReminder] = []` — `ReminderStore.swift:56`
  - `public private(set) var skippedIDs: Set<String> = []` — `ReminderStore.swift:57`
  - `public private(set) var excludedProjectTitles: Set<String> = []` — `ReminderStore.swift:58`
  - `public private(set) var availableProjects: [String] = []` — `ReminderStore.swift:59`
  - `public private(set) var authorizationStatus = .notDetermined` — `:60`
  - `public let loadsReminders: Bool` — `:61`
- `visibleReminders` is a **computed** property, not stored (`ReminderStore.swift:92-96`): filters `reminders` to exclude `skippedIDs.contains(calendarItemIdentifier)` then exclusions on `calendar?.title`, then `.sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }`.
- `reload(clearSkipped: Bool = false)` (`ReminderStore.swift:145`) is the single population point:
  - `guard loadsReminders else { return }` (`:146`) and `eventStore.refreshSourcesIfNecessary()` (`:149`).
  - Builds a date predicate: `showsUndatedReminders ? (nil,nil) : (ReminderDateFilter.overdueCutoff(), ReminderDateFilter.endOfToday())` (`:150-161`), fetches incomplete reminders (`:161-166`), and assigns `reminders = shown` (`:170`).
  - `availableProjects = Set(eventStore.calendars(for: .reminder).map(\.title).filter { !$0.isEmpty }).sorted()` (`:171-176`).
  - **clearSkipped path**: `skippedIDs = []`, `skipStore.save([])`, `onSkipSetChanged?([])` (`:180-184`).
  - **normal path**: `skippedIDs = Set(ReminderSkipLogic.resolve(fetched: shown.map(\.calendarItemIdentifier), skipped: skipStore.load()))` and `excludedProjectTitles = Set(excludeStore.load())` (`:186-190`).
  - Fires `onRemindersChanged?()` at the end (`:193`) — wired in `SingleThreadApp.swift:51-52` to `WidgetCenter.shared.reloadAllTimelines()`.
- `SkippedReminderStore` persists `skippedReminderIdentifiers` in `UserDefaults` (`ReminderSkip.swift:97-124`); `ExcludedProjectStore` persists `excludedProjectTitles` (`ExcludedProjectStore.swift:8-26`). `ReminderSkipLogic.resolve` prunes skipped IDs not present in fetched (`ReminderSkip.swift:10-16`). So an all-hidden state is generally **not sticky**: if a skipped reminder leaves the fetched window, the next `reload()` prunes its ID (`ReminderSkip.swift:17-25`).
- Conditions tested in the view (`ContentView.swift:181-182` and `:240-251`):
  - **allSkipped** = `!store.reminders.isEmpty && store.visibleReminders.isEmpty` (`ContentView.swift:181-182`) → "All Done" branch (`:240`).
  - **No Reminders** = `store.reminders.isEmpty` → `else if store.reminders.isEmpty` (`ContentView.swift:254`).
  - So the empty state is driven solely by `reminders` being empty; the all-hidden state requires `reminders` non-empty but `visibleReminders` empty.
- `setExcludedProjectTitles(_:)` writes `excludedProjectTitles`, persists, and fires `onExcludedProjectsChanged` + `onRemindersChanged` (`ReminderStore.swift:196-202`). ContentView binds it via `excludedProjectsBinding` (`ContentView.swift:172-179`) and passes `store.availableProjects` to SettingsView (`ContentView.swift:92,102`).

## Q3: How are the placeholder states previewed / unit-tested / accessibility-audited?

### Findings
- Previews in `ContentView.swift`:
  - `#Preview("Empty") { ContentView(loadsReminders: false) }` — `ContentView.swift:470-473` (exercises the No-Empty / empty `reminders` state).
  - `#Preview("With Reminder")` (reminders + `.fullAccess`) — `:475-479`.
  - `#Preview("All Skipped")` (reminders + skippedIDs all) — `:483-489` (All-nonempty state).
  - `#Preview("All Excluded")` (reminders in excluded project) — `:491-497`.
  - `#Preview("No Access")` (`.denied`) — `:499-506`.
- The pre-populated `init(loadsReminders:, reminders:, skippedIDs:, authorizationStatus:, excludedProjectTitles:)` is defined at `ContentView.swift:22-35`, passing through to the store preview init (`ReminderStore.swift:38-48`).
- Unit tests that build `ContentView(loadsReminders: false)`: `SingleThreadTests/SingleThreadTests.swift:10,18`; `MicrophoneToggleTests.swift:35,57,75,88`; `ReminderDictationTests.swift:136,143`. The dictation tests build it to assert the body doesn't crash (`String(describing: view.body).isEmpty == false`), not to check placeholder text (`ReminderDictationTests.swift:134-144`).
- The **only** placeholder-adjacent assertion is `SingleThreadTests.swift:17-22`: `testContentViewBodyContainsRefreshableModifier` (`ContentView(loadsReminders: false)`) asserts `description.contains("List") || description.contains("refreshable")`.
- **No existing unit test asserts the placeholder body strings** — nothing checks `"No Reminders"`, `"All Done"`, `"You don't have any reminders yet"`, `"Pull to refresh..."`, or the icons. This is an unanswered gap (see Open Areas).
- `--ui-testing` initial state: `SingleThreadApp.swift:16-17` sets `loads = !ProcessInfo...arguments.contains("--ui-testing")` then `ReminderStore(loadsReminders:)`. So under UI tests with `--ui-testing` and an empty store, the view renders the **No Reminders empty branch** (`store.loadsReminders == false` renders `reminderList`; `reminders` is empty; `authorizationStatus` stays `.notDetermined` because `start()` returns early — `ReminderStore.swift:103-112`).
- The UI test comments contradict the current body: `SingleThreadUITests.swift:22-23` claims the app "skips Reminders access in UI testing mode, showing a ProgressView with 'Requesting access…'", but the current `ContentView.swift:43-46` gates the ProgressView behind `store.loadsReminders`, so with `loadsReminders: false` the empty "No Reminders" branch renders instead. `testAccessoryAudit()` only waits for any static text (`:19-25`) and does not assert on the string.
- `testAccessibilityAudit()` sets `app.launchArguments = ["--ui-testing"]` (`SingleThreadUITests.swift:19`) and runs dynamic-type / hit-region / element-description / trait categories (`:24-33`). `SingleThreadUITestsLaunchTests.swift:9-21` just screenshots the launch screen.

## Q4: How are the same placeholder states represented on companion surfaces?

### Findings
- **Watch (`SingleThreadWatch/WatchReminderView.swift`)**:
  - `body` does its **own** auth switch instead of `ContentUnavailableView` (`WatchReminderView.swift:19-34`): `.notDetermined → ProgressView("Requesting access…")`, `.fullAccess → reminderContent`, default → plain `Text("Enable Reminders access in Settings")` (no icon).
  - `reminderContent` branches on `allSkipped` (defined `:71-73` as `visibleReminders.isEmpty && !reminders.isEmpty`) → `allDoneState`; else `visibleReminders.first` → summaryCard; else → `noRemindersState` (`:51-77`).
  - `allDoneState`: `Text("All Done").font(.headline)` + `refreshButton` — no icon, no description (`:101-108`).
  - `noRemindersState`: `Text("No Reminders").foregroundStyle(.secondary)` + `refreshButton` (`:110-116`).
  - `refreshButton` is a labeled `Button("Refresh") { refresh() }` (`:118-121`); `refresh()` sets `clearSkipped = allSkipped` then `await store.reload(clearSkipped:)` with a minimum-display spinner (`:142-166`). Watch previews: `#Preview("All Skipped")` / `#Preview("No Reminders")` (`:230-240`).
- **Widget (`SingleThreadWidget/NextThingWidget.swift`)**:
  - `NextThingProvider.makeEntry()` switches on `EKEventStore.authorizationStatus`: `.fullAccess → store.reload()`, then `if store.reminders.isEmpty → .empty` else `guard let current = store.visibleReminders.first else { .allDone }` (`:53-66`).
  - `NextThingWidgetView.body` switches on `entry.state` → `messageView(...)` for `.noAccess` / `.empty` / `.allDone` (`:88-104`).
  - `messageView(title, systemImage, message)` is a shared `VStack` of `Image(systemName:)` + `Text(title)` + optional caption `message`, `.accessibilityHidden(true)` on the icon, `.frame(maxWidth/.maxHeight: .infinity)` (`:145-160`).
  - Widget placeholders: `.noAccess` → "Reminders Access" / `lock.shield` / "Open SingleThread to enable access." (`:89-91`); `.empty` → "No Reminders" / `checklist` / nil message (`:95-96`); `.allDone` → "All Done" / `checkmark.circle` / nil (`:99-101`).
  - Refresh: no in-view affordance. The provider's `getTimeline` supplies a single entry with `policy: .after(refresh)` where `refresh = 15 * 60` seconds (`NextThingWidget.swift:42-46`); the iOS app nudges all timelines on any `onRemindersChanged` (`SingleThreadApp.swift:51-53`).
- **Divergences vs iOS** (iOS presentment in ContentView, see Q1):
  - iOS shows a description body on all three `ContentUnavailableView`s ("You don't have any reminders yet.", "Pull to refresh..."). The watch empty state has no description; the widget has `message: nil` for both empty & allDone.
  - iOS All Done has **no refresh affordance** other than pull-to-refresh (`.refreshable`); the watch shows an explicit "Refresh" button in both empty states; the widget has none.
  - iOS and watch use `.secondary`/no styling on some text; widget and iOS both use the same icon strings (`checklist`, `checkmark.circle`, `lock.shield`), while the watch uses plain `Text` with no icon at all.
  - Watch empty title is `.secondary` colored; iOS "No Reminders" uses the default `ContentUnavailableView` styling.

## Q5: What actions are available from each placeholder state?

### Findings
- **iOS pull-to-refresh** dispatches by branch:
  - All Done (`.refreshable` at `ContentView.swift:249-250`): `await store.reload(clearSkipped: true)`.
  - No Reminders (`.refreshable` at `ContentView.swift:262-263`): `await store.reload()` (no clear).
  - Populated list (`.refreshable` at `ContentView.swift:308-309`): `await store.reload()`.
  - Both placeholder ScrollViews use `.scrollBounceBehavior(.always)` (`ContentView.swift:248` and `:261`).
- **bottomBar / mic in the Empty state**: only the empty (and populated) branches include `bottomBar` (`ContentView.swift:265`, `:311`); the All-Done branch does not. `bottomBar` (`ContentView.swift:317-344`) renders the mic button when `canDictate && showMicrophoneButton` (`:342-343`), where `canDictate = speechTranscriber.authorizationStatus == .authorized || .notDetermined` (`ContentView.swift:185-186`). Dictation enters `startDictation()` which guards speech authorization and calls `store.addReminder(...)` (`ContentView.swift:379-399`). `micButton` uses `Image(systemName: "mic.fill")`, 56pt, blue circle (`ContentView.swift:348-357`). On macOS it additionally renders `actionButtons` only when `store.visibleReminders.first != nil` (`ContentView.swift:319-320`).
- **Authorization gating**:
  - Store `start()` gates loading on `loadsReminders`: null additional `guard`, then reads `authorizationStatus = eventStore.AuthStatus(for: .reminder)`; on `.fullAccess` it `await reload()`, else `await requestAccess()` (`ReminderStore.swift:107-119`).
  - View-level gating: `if store.loadsReminders { authGatedContent } else { reminderList }` (`ContentView.swift:43-45`).
  - `authGatedContent` (`.fullAccess → reminderList`, else → ProgressView/denied `ContentUnavailableView`) (`ContentView.swift:221-228`). So with access denied the placeholder branches are never reached; the user sees "Reminders Access"/lock.shield instead.
  - `requestAccess()` sets `authorizationStatus = granted ? .fullAccess : current` and reloads on grant (`ReminderStore.swift:283-294`).

## Cross-Cutting Observations
- **One distinction everywhere**: the all-hidden state is `!reminders.isEmpty && visibleReminders.isEmpty`, and the empty state is `reminders.isEmpty`. This is encoded independently in `ContentView.swift:181-182`, `WatchReminderView.swift:71-73`, and `NextThingWidget.swift:62-66`.
- **Three placeholder-presentation mechanisms across surfaces**: there is no shared view. iOS uses SwiftUI's `ContentUnavailableView(title, systemImage:, description:)`; watch uses handwritten `Text` + `Button` (`VStack`); widget uses a shared private `messageView(title, systemImage, message)` helper. The iOS companion surfaces therefore do not reuse `ContentUnavailableView` at all.
- **System icon names are shared** by convention: "checklist" (No Reminders) and "checkmark.circle" (All Done) appear in both iOS and the widget; the watch uses none.
- **Refresh is uniformly `store.reload(clearSkipped:)` = All Done, `store.reload()` = empty**, on iOS and configured in Ready. The watch derives `clearSkipped = allSkipped` dynamically; iOS hard-codes per branch.
- **The empty branch always keeps dictation reachable** by overlaying `bottomBar` (mic + creation feedback), unlike the allDone branch which drops it.
- **Persistence is centralized in Core**: skip/excluded lists live in `UserDefaults` (AppGroup) and are mounted in `reload()`; the widget/watch rely on the remotes push and 15-min page policy rather than re-reading EventKit each render.

## Open Areas
- **No test asserts the placeholder strings.** No unit test greps "No Reminders", "All Done", "You don't have any reminders yet", or the icons in `body` descriptions; the closest is `SingleThreadTests.swift:17-22` asserting `"List" || "refreshable"`. The actual body text is unverified in automated tests.
- **Previews exercise empty vs all-hidden separately, but not auth-denied empty**: `#Preview("No Access")` sets `.denied` but still relies on the empty store (`ContentView.swift:499-506`); no preview combines a denied-auth view with nonempty data.
- **UI-test comment vs. implementation mismatch**: `SingleThreadUITests.swift:22-23` claims `--ui-testing` shows a "Requesting access…" ProgressView, but `ContentView.swift:43-45` maps `loadsReminders: false` to the empty `reminderList` branch, not the auth gate. The test only waits for any text, so the divergence is currently silent.
- **`ContentUnavailableView` exact rendering** (its layout/style/icon placement) is not inspectable in this repo because it's a SwiftUI framework type.
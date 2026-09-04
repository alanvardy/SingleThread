# Research Findings

Branch: `alanvardy-var-773-refactor-extract-listcontent-enum-for-emptyall-done-branch` (HEAD `f6471cd`, 2026-09-04)

## Q1: Widget `NextThingEntry.State` — declaration, construction, exhaustive switch, external consumers

### Findings
- `NextThingEntry` is a `TimelineEntry` struct at `SingleThreadWidget/NextThingWidget.swift:9-22`; its nested `enum State` is `NextThingWidget.swift:10-15` with four cases: `.noAccess` (:11), `.empty(Bool)` (:12, payload `hasHidden` — "true when reminders exist but are out-of-window"), `.allDone` (:13), `.reminder(ReminderDisplay)` (:14). `let state: State` at :18.
- `NextThingProvider.makeEntry()` (`NextThingWidget.swift:62-106`) builds State in this order:
  1. `.noAccess` — outer `switch EKEventStore.authorizationStatus(for: .reminder)` (:68); non-`.fullAccess` hits `default:` (:99) → `state: .noAccess` (:100).
  2. `.empty(store.hasHidden)` — inside `.fullAccess`, `if store.reminders.isEmpty` (:74) → `state: .empty(store.hasHidden)` (:75-82).
  3. `.allDone` — only when `reminders` non-empty but `guard let current = store.visibleReminders.first` fails (:83) → `state: .allDone` (:84-91).
  4. `.reminder(...)` — fall-through when `visibleReminders.first` exists (:92-98).
  - So: auth fail → noAccess; else empty→allDone→reminder. `isEmpty` (:74) is evaluated before the `visibleReminders.first` guard (:83); an empty store never reaches allDone.
  - `placeholder` (:30-37) and `getSnapshot` (:40-47) hardcode `state: .reminder(...)`; `getTimeline` (:51-58) is the single production path via `makeEntry()` (:53). `makeEntry` configures store prefs from `AppGroup.defaults` (:71-72).
- The view switches exhaustively on `entry.state` at `NextThingWidget.swift:140-161` (in `NextThingWidgetView.body`, :140): `.noAccess` :141-147 (lock.shield + `SharedStrings.remindersAccess`), `.empty(hasHidden)` :149-152 (`noReminders` title, checklist icon, message = `hasHidden ? nothingDueRightNow : noRemindersYet`), `.allDone` :154-157, `.reminder(display)` :159-160 → `reminderView(display)` (:208-247). `messageView` helper :188-206.
- **External consumers: none.** `grep -rn NextThingEntry --include=*.swift` matches only `NextThingWidget.swift` and the bundle registration `SingleThreadWidget/SingleThreadWidgetBundle.swift:7`. No `.swift` in iOS/watch/Core/test targets references it (previews at :257/:274/:286 stage `.reminder`/`.noAccess`/`.allDone`; no `.empty` preview).

## Q2: iOS vs watch list-content branch order and shared semantics

### Findings
- **iOS gate** — `ContentView.swift:337-346` (`authGatedContent`): `switch viewModel.store.authorizationStatus` (:338): `.notDetermined` → `ProgressView(SharedStrings.requestingAccess)` (:339-340), `.fullAccess` → `reminderList` (:341-342), `default:` → `ContentUnavailableView(remindersAccess, "lock.shield")` (:343-346). Wired at :152-157 — only when `store.loadsReminders` (:155).
- **iOS list order** — `reminderList` (`ContentView.swift:351`, GeometryReader :352-354):
  1. `if viewModel.store.allSkipped` :356 → `allDoneStateCopy()` :357, EmptyStateCard in ScrollView with `.refreshable { reload(clearSkipped: true) }` :360-366 — **no bottomBar** in this branch.
  2. `else if viewModel.store.reminders.isEmpty` :369 → `emptyStateCopy(hasHidden: viewModel.store.hasHidden)` :370-371, EmptyStateCard + bottomBar :372-383.
  3. `else` :387 → `if let reminder = store.visibleReminders.first` :388 → ReminderCardView; inner else falls through showing only bottomBar.
  - Ordering rule: `allSkipped` is checked before `isEmpty` (ContentView.swift:356/369).
- **Watch gate** — `WatchReminderView.swift:47-54`: same `authorizationStatus` switch (.notDetermined :48-49, .fullAccess :50-51, `default:` :52-53).
- **Watch list order** — `reminderContent` (`WatchReminderView.swift:77`):
  0. completion-transition ghost: `if viewModel.isShowingCompletionTransition, let reminder = viewModel.transitionReminder` :79-81.
  1. `else if viewModel.store.allSkipped` :82 → `allDoneState` :83 (definition :149-156, `Text(SharedStrings.allDone)` :151).
  2. `else if let reminder = viewModel.store.visibleReminders.first` :84 → `reminderCard` :85.
  3. `else` :86 → `noRemindersState` :87 (definition :158-166; title `SharedStrings.noReminders` :160, subtitle `hasHidden ? nothingDueRightNow : noRemindersYet` :163).
  - Watch has **no explicit `reminders.isEmpty` test** — empty is the trailing `else`; iOS instead special-cases `reminders.isEmpty` before the reminder branch.
- **Identical semantics despite different order**: both branch first on the shared `ReminderStore.allSkipped` (`ReminderStore.swift:138` = `!reminders.isEmpty && visibleReminders.isEmpty`), making all-skipped and empty **mutually exclusive by definition** — so allDone wins whenever reminders exist but none visible, and empty wins whenever the list is empty, in both targets regardless of where the empty check sits. Both use the same SharedStrings copy (iOS: `allDoneStateCopy` `ContentViewModel.swift:77-83` and `emptyStateCopy` `:58-75`; watch uses SharedStrings directly at :151/:160/:163). Both refresh with `clearSkipped:` (iOS `ContentView.swift:363`; watch `WatchReminderView.swift:189/,209`).
- **Copy/icon split**: iOS icons are hardcoded SF Symbols in `ContentViewModel.swift` (`"calendar"` :62, `"checklist"` :70, `"checkmark.circle"` :80); watch empty states are text-only with no icon (`WatchReminderView.swift:149-166`); descriptions are inline app-bundle strings, titles come from SharedStrings.

## Q3: Conventions for adding a shared, non-persisted type to `SingleThreadCore`

### Findings
- **Visibility**: the `internal` keyword appears nowhere in Core. Two tiers: `public` (default for every shared top-level type) and package-internal (type with no `public`, e.g. `PendingCompletionLogic.swift:6`, `ReminderDateFilter.swift:26`). Nested helpers are `private`.
- **Enum forms**: casing/logic enums use `public nonisolated enum` (`ReminderSkip.swift:31`, `ReminderSort.swift:4`, `MinimumDisplayDuration.swift:6`, `ReminderDeepLink.swift:8`, `ReminderRecurrenceFormatter.swift:10`); data/enumeration types use plain `public enum` (`SortOption.swift:6` — String-backed, `SharedStrings` at `LocalizedString+Shared.swift:11`, `AppGroup.swift:8`). Structs are `public struct` with `Equatable`/`Sendable`/`Codable` conformance where relevant (`ReminderDisplay.swift:6`, `SkippedReminderStore.swift:121`, `SortOptionStore.swift:22`, all `Show*Preference.swift:8` and `ExcludedListStore.swift:4`). `ReminderPriority.Level` is nested: `ReminderSkip.swift:32` `public enum Level: CaseIterable, Equatable, Sendable` inside a `public nonisolated enum`.
- **SwiftUI-free?** Nearly — exactly one guarded import: `CodeSpanFormatter.swift:3-5` (`#if canImport(SwiftUI) / import SwiftUI / #endif`, used only for `attributed.backgroundColor` at :121/:130). No `import UIKit` in Core. `SortOption.swift:2` documents "pure Core logic, no SwiftUI; presentation lives in the app target."
- **AttributedString in Core**: yes — `ReminderDisplay.titleAttributed` (`ReminderDisplay.swift:57-60`) and `notesAttributed` (:64-67) return `AttributedString` via `CodeSpanFormatter.format(_:)` (`CodeSpanFormatter.swift:22`). There is **no `.formatted(...)` init anywhere in Core** (grep: 0 matches); strings are built via `AttributedString()` + `.append(...)` (:23/:48/:52/:60). Consumers pass the value directly to `Text(...)` (`ReminderCardView.swift:73/:109`, `WatchReminderView.swift:238/:261`, `NextThingWidget.swift:217/:243`).
- **Package layout**: `SingleThreadCore/Package.swift` — tools 6.0 (:1), platforms iOS 18.7 / watchOS 26.5 / macOS 26.5 (:5-9), single library product (:11), `.process("Resources")` (:16). Linked into all 7 targets via `XCLocalSwiftPackageReference` (`project.pbxproj:459`) and product deps (:260-403: SingleThread, SingleThreadTests, SingleThreadUITests, SingleThreadWatch, SingleThreadWidget, SingleThreadWatchUITests, SingleThreadWatchTests).

## Q4: Precedent — shared Core enum exhaustively switched by multiple targets

### Findings
- `ReminderPriority.Level` (`ReminderSkip.swift:31-35`): `public nonisolated enum ReminderPriority { public enum Level: CaseIterable, Equatable, Sendable { case high, medium, low } }`. **Not `@frozen`** (no @frozen anywhere in repo).
- **Exhaustive switches, no `default`**:
  - Core-internal: `ReminderSkip.swift:41` (displayName), :50 (marker), :83 (rank over `Level?` with `case nil`).
  - iOS: `ReminderCardView.swift:173-178` (`priorityColor`) — no default.
  - Watch: `WatchReminderView.swift:272-277` (`priorityColor`) — no default.
  - Widget: no switch over Level — renders `display.priorityMarker` guard on non-empty (`NextThingWidget.swift:211-212`).
- Non-switch recovery paths (don't break on new cases): `level(for:)` has `default: nil` (`ReminderSkip.swift:61-65`); `level(forMarker:)` uses `allCases.first` (`ReminderSkip.swift:70-71`); `marker(for:)` nil-coalesces (:76-78).
- **How exhaustiveness is kept when a new case is added**: Core is a separate SwiftPM module built **without** `enableLibraryEvolution` (no flag in `Package.swift`), i.e. non-resilient. Verified empirically (Swift 6.3.3, scratch cross-module build, `/tmp/rq4-exp`): adding a 4th case produces hard `error: switch must be exhaustive` + `note: add missing case:` at **every** no-default switch, in-module and cross-module. With `-enable-library-evolution` (not used) the same switch becomes a warning/`@unknown default` requirement.
- **Lint cannot catch it**: `make lint` (`Makefile:106-108`) = `swiftformat --lint` + `swiftlint lint --strict`; verified SwiftLint 0.65.0 reports 0 violations for a switch missing a case. Only the compiler (xcodebuild) rejects missing cases.
- **History**: the case set {high, medium, low} has never changed since introduction in `74b089d` (2026-08-15), which added the enum and all initial no-default consumers atomically (Core switches, watch `priorityColor`, tests). iOS `priorityColor` arrived later in `2c07e21` with all cases. Subsequent commits were additive API changes only (CaseIterable `24a814b`, mapping range rescope `799e9a1`, localization `fe3f362`). `git log -S` for any new case: no matches.
- Related: `SortOption` (`SortOption.swift:6`, `String`-backed) is exhaustively switched only on iOS (`SortOption+Presentation.swift:11-19/:20-30`, no default); the watch stores/syncs but never switches it. `ReminderPriority.Level` is the sole in-repo example of one Core enum switched exhaustively in **both** iOS and watch.

## Q5: `ReminderStore` derived state semantics (`allSkipped`, `hasHidden`, `visibleReminders`)

### Findings
- `hasHidden` — `ReminderStore.swift:58-62`: `public private(set) var hasHidden = false`; doc: "true when incomplete reminders exist outside the current date window (or are undated while showsUndatedReminders is off)". Init seam `ReminderStore.swift:29/:45`; written in `reload()` at :382 and :391 via `hasHiddenFor(shown:allIncomplete:)` (:159-162), which is true when any incomplete id in the broad fetch is absent from the in-window `shown` set (matched by `calendarItemIdentifier`).
- `visibleReminders` — `ReminderStore.swift:129-134`: `reminders.filter { !skippedIDs.contains(id) }.filter { !excludedListTitles.contains(calendar?.title) }.sorted { ReminderSort.areInIncreasingOrder(...) }`.
- `allSkipped` — `ReminderStore.swift:136-140`: `!reminders.isEmpty && visibleReminders.isEmpty`. **Claim verified**: line 139's first conjunct guarantees `allSkipped` is only true when the loaded `reminders` array is non-empty. Corroborated by `ReminderStoreTests.swift:480-486` (empty store → `#expect(!empty.allSkipped)`), :479 (all-skipped positive), :501 (excluded-list positive).
- Nuances (facts): `allSkipped` operates purely on the in-memory `reminders` array (no EventKit calls); completed reminders were already dropped by `applyingPendingCompletionFilter` in `reload()` (`ReminderStore.swift:397`). Because consumers only consult `hasHidden` inside a `reminders.isEmpty` branch, `allSkipped == true` and `hasHidden`-as-reason are mutually exclusive in reachable UI states.
- **`hasHidden` meaning per consumer** — same store property, same guard (`reminders.isEmpty`), same high-level meaning ("incomplete reminders exist outside the loaded in-window projection"), different presentation granularity:
  - iOS: selects an entirely different empty card — `hasHidden true` → `"Nothing due"` (app-bundle literal, `ContentViewModel.swift:61`), `"calendar"` icon, pull-to-refresh description (:62-64); `false` → `SharedStrings.noReminders`, `"checklist"`, "You don't have any reminders yet." (:69-74). Read at `ContentView.swift:370-371` (only when `allSkipped` false AND `reminders.isEmpty`).
  - Widget: fixed empty card (`SharedStrings.noReminders` title, checklist icon) with `hasHidden` flipping only the message (:149-153). Payload constructed at `NextThingWidget.swift:74-77`.
  - Watch (sibling): subtitle flip `WatchReminderView.swift:163`.
  - Neither associates `hasHidden` with skip/excluded filtering — that case is drained earlier by `allSkipped`/`.allDone`.

## Q6: Copy strings/icon centralization + UI-test dependence on ordering

### Findings
- The SharedStrings enum is in `LocalizedString+Shared.swift:11` (not `SharedStrings.swift`); members are `public static var ...: String { String(localized:..., table: "Localizable", bundle: .module) }`. Requested members: `allDone` :40, `noReminders` :44, `nothingDueRightNow` :64, `noRemindersYet` :68. Header doc (:1-9): keys shared by 2+ targets live only in this catalog.
- Core catalog `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings` (1435 lines): six languages (en, zh-Hans, es, ja, de, fr) per key. Key positions: "All Done" :86, "No Reminders" :941, "No reminders yet" :982, "Nothing due right now" :1023. Catalog validity is asserted by `LocalizationTests.swift:27-50`.
- **Icons are NOT centralized in Core** (grep: 0 hits). iOS: `ContentViewModel.swift:62/:70/:80`; watch empty states have no icons; widget uses `"lock.shield"`/`"checklist"`/`"checkmark.circle"` at `NextThingWidget.swift:143/:151/:155`.
- App-bundle strings distinct from Core: "Nothing due" (`SingleThread/Resources/Localizable.xcstrings` key :1316, value :1322), "Only today's and overdue reminders show here — pull to refresh." (:1357), "Pull to refresh to see all your reminders again." (:1562), "You don't have any reminders yet." (:3079). Watch catalog has only 4 keys (none are empty-state); widget catalog 5 keys.
- **UI-test dependence on branch ordering** (all keyed on the `emptyStateTitle` accessibility identifier emitted at `EmptyStateCard.swift:28`):
  - `SingleThreadUITestsFlows.swift:34` `testEmptyListShowsNoRemindersState` (seed `{"reminders":[]}`) — depends on `reminders.isEmpty` + `hasHidden false` branch.
  - `SingleThreadUITestsFlows.swift:43` `testNothingDueShowsWhenRemindersHidden` (seed `{"reminders":[],"hasHidden":true}`) — the only test asserting the literal "Nothing due" (:47); pins the `empty(hasHidden:true)` variant.
  - `SingleThreadUITestsFlows.swift:87` `testSkipAllShowsAllDoneState`; `ActionButtonsUITests.swift:40` — skip → `allSkipped`/All Done branch.
  - `SingleThreadUITestsFlows.swift:149/:167`, `NotificationSchedulingUITests.swift:109`, `ActionButtonsUITests.swift:40` — complete/delete → empty branch.
  - **No test asserts all-done hides the bottom bar**; the claim exists only as a comment (`ActionButtonsUITests.swift:38`). The behavior is real in code (allSkipped branch omits bottomBar `ContentView.swift:356-382`; list branch has it :455; macOS gates action buttons on `visibleReminders.first != nil` :605).
  - Watch UI tests assert `emptyStateTitle`, never literal text: `SingleThreadWatchUITestsFlows.swift:39` (excluded list → All Done), :58, :76 (complete → No Reminders), :92 (skip → All Done), :108 (delete → No Reminders), :127 (Refresh button present :139), :166 (glow then No Reminders).
  - Unit pins: `SingleThreadTests.swift:32-48` (`contentViewEmptyStatesShowDistinctCopy` — pins `emptyStateCopy(hasHidden:)` both variants incl. app-bundle "Nothing due" at :42) and `:51-56` (`contentViewAllDoneShowsAllDoneCopy`).

## Q7: Test coverage of State enums, ordering, and enum round-trips

### Findings
- **Test targets**: 7 targets in pbxproj (:240-409) — including `SingleThreadWatchTests` (pbxproj:387) — but **no `SingleThreadWidgetTests` target exists**. CI/scripts run SingleThreadTests, SingleThreadUITests, SingleThreadWatchUITests, SingleThreadWatchTests only (`scripts/test.sh:237-337`; `ci.yml:16-18,:62,:130,:191,:250,:312,:416-438`).
- **Widget `NextThingEntry.State`: zero test coverage.** No test file references it; it is staged only in previews (`NextThingWidget.swift:257/:274/:286`; no `.empty` preview). `LocalizationTests.swift:171/:182/:223/:236` cover the widget catalog/Info.plist only. The enum has **no `CaseIterable`** (`NextThingWidget.swift:10`).
- **iOS empty/all-done logic**: unit — `SingleThreadTests.swift:32/:51`, `ReminderStoreTests.swift:471` (`allSkippedReflectsState`), :440 (`hasHiddenReflectsSeedsAndSets`), `ActionButtonTests.swift:62` (`buttonsHiddenWhenAllSkipped`; whole file `#if os(iOS)` :8-134), `UITestingSeedTests.swift:109/:120`. UI — `SingleThreadUITestsFlows.swift:34/:43/:87/:149/:167`, `ActionButtonsUITests.swift:40`, `NotificationSchedulingUITests.swift:109` (whole file `#if os(iOS)` :1-135), `SingleThreadUITests.swift:31` (audit running under `--ui-testing`, doc comment :35-36 notes it renders the No Reminders branch).
- **Watch ordering**: UI tests `SingleThreadWatchUITestsFlows.swift:39-195` (All Done vs No Reminders via `emptyStateTitle`); **no unit test asserts the view-level branch order** — `ShowCompletionGlowStateTests.swift` covers the completion-transition prerequisite (:32-222, `@Suite(.serialized)` :26); `ReminderStoreWatchTests`/`WatchSyncPipelineTests` cover store/sync, not ordering.
- **Enum-equality / round-trip**: no test named "round-trip" anywhere. Persistence round-trips via save/load + raw-value decode: `SortOptionTests.swift:62-66` (`saveAndLoadRoundTrip`), `AppearanceModeTests.swift:55-70` (raw decode/fallback), `EntitlementStoreTests` (:12-80), `CompletionCounterStoreTests` (:9-90). All-cases equality: `SortOptionTests.swift:15-17`, `AppearanceModeTests.swift:74-75`, `TextSizeTests.swift:33-34`. Parameterized mapping over every case: `ReminderSkipTests.swift:60-101` (raw priorities 0–9 → Level, displayName, marker/rank), `MinimumDisplayDurationTests.swift:10-16`. **No Core enum is `Codable`** (persistence is via UserDefaults raw strings).
- **Exhaustive-switch coverage mechanism**: no runtime "switch over every case" tests; relied on (1) compiler-enforced exhaustiveness on production switches (widget `:140-166`; `ContentView.swift:338-344` auth switch) — if/else chains (`ContentView.swift:356-379`, `WatchReminderView.swift:79-87`) are **not** exhaustiveness-checked — and (2) `allCases` equality + `@Test(arguments:)` enumerations.
- **Seams for deterministic UI state**: iOS `--seed '<json>'` (`UITestingSeed.swift`; `AppViewModel.swift:235/:280/:291`; fields incl. `hasHidden` :39/:111/:128/:155/:166), `--ui-testing` (`AppViewModel.swift:245/:275`), `--ui-testing-glow`, `--ui-testing-notifications`; watch `--ui-testing`, `--ui-testing-priority <n>`, `--ui-testing-excluded-list`, `--ui-testing-live-excluded`, `--ui-testing-gated`, `--ui-testing-glow` (watch has no `--seed`).

## Cross-Cutting Observations
- **Three targets, three branch shapes, one store contract**: widget `isEmpty → allDone(guard) → reminder` (NextThingWidget.swift:74/:83); iOS `allSkipped → isEmpty → reminder` (ContentView.swift:356/:369/:387); watch `transition-ghost → allSkipped → reminder → else` (WatchReminderView.swift:79-87). All converge because `allSkipped` (`ReminderStore.swift:138`) is mutually exclusive with an empty list — the differing empty-check placement cannot diverge outcomes.
- **Copy is centralized in Core; icons and descriptions are not.** Only the four titles/messages come from `SharedStrings`; iOS hardcodes SF Symbols and app-bundle descriptions, watch renders text-only. Note the parallel "Nothing due"-type strings: Core `nothingDueRightNow` ("Nothing due right now", `LocalizedString+Shared.swift:64`) vs iOS app-bundle "Nothing due" (`ContentViewModel.swift:61`) — distinct keys, pinned by tests at both levels.
- **Exhaustive enums are a compile-time discipline**: new cases fail `xcodebuild` loudly at every no-default switch but pass SwiftLint; the repo has never actually added a case to `ReminderPriority.Level` (introduced complete in `74b089d`).
- **Widget state logic is the least-guarded surface**: no widget test target, no `CaseIterable`, no `.empty` preview, single-purpose files.
- **`hasHidden` is a "why is it empty" signal**, not a filtering state — it answers nothing-due-right-now vs no-reminders-at-all, and is only ever consumed inside an empty-list branch.

## Open Areas
- The branch title references an "extract ListContent enum for empty/all-done branch ordering" refactor, but **no such enum exists in the tree**: `rg ListContent` = 0 matches; commit `92fc040` (same title) added only a 1-line `DELETEME` marker (verified via `git show --stat`; the file is not present at HEAD). This is the gap the questions are evidently scoping — the closest precedents for the target shape are `NextThingEntry.State` (widget-local, exhaustive) and `ReminderPriority.Level` (Core-shared, exhaustive, multi-target).
- Watch branch-order line cites in agent reports varied slightly (rq2 vs rq7); verified directly: `WatchReminderView.swift:79-87` — ghost :79-81, allSkipped :82, reminder :84, else :86.
- Whether a shared `ListContent`-style enum could/would live in Core, and how `ReminderDisplay` payloads would flow through it, is out of scope for this research (no existing implementation to document).
# Design Discussion — Organized Settings Menu

## Current State

The settings screen (`SingleThread/SettingsView.swift`) is a single 357-line
file holding two views: `SettingsView` (lines 74–295) and `ExcludedListsView`
(lines 13–72). `SettingsView` wraps a `NavigationStack` > `Form` with 13
preferences rendered as direct rows — pickers, toggles, one `NavigationLink`
to `ExcludedListsView`, and an Unsplash photo-credit footer (lines 157–262).
State ownership is cleanly separated:

- **`ContentView`** is the single `@AppStorage` owner for all 13 preferences
  (`ContentView.swift:101–161`). It constructs `SettingsView` in a `.sheet`
  (`ContentView.swift:85–131`), passing every value via `$` bindings and the
  `excludedListsBinding` computed projection (`ContentView.swift:76–79`).
- **`SettingsView`** is a pure `@Binding` presentational shell — 15–17
  `@Binding` props depending on platform, no state of its own
  (`SettingsView.swift:267–282, 77–154`).
- **`SettingsViewModel`** is a stateless 27-line side-effect delegator
  (`SingleThread/SettingsViewModel.swift:1–27`): `allowsLandscapeChanged`
  (iOS-only, → `AppDelegate.applyLock`) and `showPreferenceChanged` (→
  `WidgetCenter.shared.reloadAllTimelines()`).
- **Watch sync** is driven from `AppViewModel` (`AppViewModel.swift:26–94`)
  via `SkippedReminderSyncService` store-hooks and
  `UserDefaults.didChangeNotification` observation on `AppGroup.defaults`
  (`AppViewModel.swift:157–190`).

Two persistence tiers exist: `.standard` for phone-only cosmetics (7 keys),
`AppGroup.defaults` for widget/watch-shared prefs (7 keys). The single
embedded `#if os(iOS)` gating `allowsLandscape` and `enableActionButtons`
appears identically across `ContentView`, `SettingsView` (init + stored props
+ body rows), and both `#Preview` blocks.

The unit test `settingsViewContainsAllPreferenceRows` (`SettingsViewTests.swift:13–34`)
asserts exactly 14 (non-iOS) or 16 (iOS) label strings appear in the body
description. UI test `testSettingsOpensAndShowsControls`
(`SingleThreadUITestsFlows.swift:126–139`) asserts "Appearance", "Text Size",
"Sort By" are visible without scrolling, then one `swipeUp()` reveals
"Show date". The `Background` and `Show list` toggle-persistence tests
(`SingleThreadUITestsFlows.swift:145–226`) address their switches by
`app.switches["Background"]` and `app.switches["Show list"]`.

## Desired End State

The single flat `Form` is replaced by four themed sub-views pushed from a
root `List`-based menu inside the existing `NavigationStack`. All settings
function identically — same persistence, same widget reloads, same watch sync,
same `.onChange` side effects.

### Grouping

| Group | Row | Persistence tier | `.onChange` | Platform |
|---|---|---|---|---|
| **Interface** | Appearance | `.standard` | ContentView-level | all |
| | Text Size | `.standard` | (none, TextSizeModifier) | all |
| | Allow landscape | `.standard` | `allowsLandscapeChanged` → orientation lock | iOS |
| | Show microphone | `.standard` | none | all |
| | Show action buttons | `.standard` | none | iOS |
| **Reminder** | Show date | `AppGroup` | widget reload + watch sync | all |
| | Show list | `AppGroup` | widget reload + watch sync (new) | all |
| | Recurrence indicator | `AppGroup` | widget reload + watch sync | all |
| | Reminder alerts | `AppGroup` | widget reload + watch sync | all |
| **Filtering & Sorting** | Sort by | `AppGroup` | ContentView-level + watch sync | all |
| | Show undated reminders | `AppGroup` | ContentView-level + watch sync | all |
| | Excluded Lists | `AppGroup` (via store) | store hooks + watch sync | all |
| **Background** | Background | `.standard` | none | all |
| | Background Fade | `.standard` | none | all |
| | Photo credit | (derived) | none | all |

### Verification

1. **Unit test `settingsViewContainsAllPreferenceRows`** must pass — the label
   assertions move to the four new sub-view tests (same label strings, split
   across four test functions).
2. **UI test `testSettingsOpensAndShowsControls`** must pass after adjusting
   for the menu tap (e.g. `app.staticTexts["Interface"].tap()` before
   asserting Appearance/Text Size).
3. **Toggle-persistence relaunch tests** (`Background`, `Show list`) must pass
   unchanged — they address elements by switch label, not by position.
4. **`./scripts/test.sh`** (format + lint + periphery + build + unit + UI)
   passes green — no regressions.
5. **`showList` appears in the watch sync payload** and is correctly
   transmitted and received (new `ShowListPreference`-backed store on the
   service, new `sendsShowList` init param, new payload key, new
   `handlePreferencesChanged` comparison). The `WatchSyncPipelineTests` pass.

## Patterns to Follow

- **`@Binding` presentational views.** `SettingsView` owns no state; every
  sub-view follows the same pure-binding pattern (`SettingsView.swift:267–283`).
- **`ExcludedListsView` as sub-view template** (`SettingsView.swift:13–72`):
  manual `init` storing `@Binding`, `Form` with `Section`, own
  `.navigationTitle`, projection helpers. The four new sub-views replicate
  this structure.
- **`NavigationLink` push from `List` root** (`SettingsView.swift:233–238` for
  `ExcludedListsView`). Replacing the root `Form` with a `List` is deliberate
  — a settings menu with four entry points benefits from `List`'s lighter
  weight and automatic disclosure indicators.
- **`SettingsViewModel` as side-effect delegator** (`SettingsViewModel.swift:13–24`):
  sub-views call the same `allowsLandscapeChanged` / `showPreferenceChanged`
  methods. No new view model required.
- **`SettingsBindings` bag** (`@Observable` class): follows the established
  pattern in `ContentViewModel` (`ContentViewModel.swift`) and `AppViewModel`
  (`AppViewModel.swift:15–17` where `@MainActor @Observable` wraps injected
  dependencies). The bag is owned by `SettingsView`, passed into sub-views
  via `@Bindable`. Each sub-view unwraps only the bindings it needs.
- **`.onChange` on rows in sub-views** (`SettingsView.swift:182,209,220,228`):
  each sub-view owns its `.onChange` hooks, matching the existing placement.
- **`#if os(iOS)` gating** (`SettingsView.swift:179–184`): iOS-only rows
  (Allow landscape, Show action buttons) stay gated inside their sub-view's
  `Form`, identical to today.
- **Two-platform `#Preview` blocks** (`SettingsView.swift:296–357`): each new
  sub-view gets both iOS (17-arg) and macOS (15-arg) previews.

### Patterns to Avoid

- Do NOT mix `@AppStorage` into sub-views — `ContentView` remains the single
  owner (`ContentView.swift:101–161`). Sub-views never read from UserDefaults
  directly.
- Do NOT centralize `.onChange` hooks in the root `SettingsView` — they live
  with the rows that trigger them (per Q4 decision).
- Do NOT keep the root as a `Form` — the root `List` is the intentional
  design choice for a menu-of-menus (per Q2 decision).
- Do NOT add `showList` sync as a separate push path — it follows the same
  `pushAll()` combined-snapshot pattern as `showDate`/`showRecurrence`/
  `showAlarms` (`SkippedReminderSyncService.swift:127–145`).

## Design Decisions

1. **Separate files per group**: each of `InterfaceSettingsView.swift`,
   `ReminderSettingsView.swift`, `FilterSortSettingsView.swift`,
   `BackgroundSettingsView.swift` is ~80–120 lines. `SettingsView` shrinks to
   ~120 lines: root `List`, `SettingsBindings` bag, init, previews. The
   `ExcludedListsView` stays where it is (moves into
   `FilterSortSettingsView.swift` or remains in its own file — TBD at plan
   time based on cohesion).

2. **Root `List` with `NavigationLink` rows**: replaces the root `Form`. Each
   row is a `Label(title, systemImage:)` wrapped in a `NavigationLink`
   pushing the sub-view. Icons: `paintpalette` (Interface), `bell.badge`
   (Reminder), `line.3.horizontal.decrease` (Filtering & Sorting),
   `photo.on.rectangle` (Background).

3. **`SettingsBindings` `@Observable` bag**: a single `@MainActor @Observable`
   class owned by `SettingsView.init`, holding all `@AppStorage`-backed
   `@Published`-equivalent properties (Observable tracks field access
   automatically). `SettingsView` passes `@Bindable var bindings:
   SettingsBindings` to each sub-view; sub-views deconstruct via
   `$bindings.showDate`, etc. This eliminates the 17-arg init explosion while
   keeping each sub-view explicit about which bindings it consumes.

4. **`.onChange` hooks in sub-views**: `InterfaceSettingsView` owns the
   `allowsLandscape` `.onChange` → `viewModel.allowsLandscapeChanged`.
   `ReminderSettingsView` owns `showDate`/`showRecurrence`/`showAlarms`
   `.onChange` → `viewModel.showPreferenceChanged()`. Sub-views receive
   `SettingsViewModel` by injection (default-valued param, same as today).
   `showUndatedReminders`/`sortOption`/`appearanceMode` `.onChange` hooks
   remain in `ContentView` where they are today.

5. **Fix `showList` watch sync**: add `showListStore: ShowListPreference` and
   `sendsShowList: Bool` to `SkippedReminderSyncService.init`
   (`SkippedReminderSyncService.swift:27–53`), add `"showList"` PayloadKey
   (line 209–220), include in `pushAll()` conditional on `sendsShowList`
   (lines 127–145), decode in `apply(context:)` (lines 241–280), add
   `onShowListReceived` hook, and add `showList` comparison to
   `AppViewModel.handlePreferencesChanged()` (AppViewModel.swift:178–190).
   Update the `SettingsView` doc comment at line 63 to remove "show list"
   from the synced list and add a note pointing to the sync service. The
   `@AppStorage("showList", store: AppGroup.defaults)` in ContentView
   (ContentView.swift:183–184) is already backed by the App Group suite, so
   the watch-side read path will pick up changes automatically once the
   payload key exists.

6. **Unit test split**: `SettingsViewTests.swift` gains four focused test
   functions — `interfaceSettingsViewContainsExpectedRows`,
   `reminderSettingsViewContainsExpectedRows`,
   `filterSortSettingsViewContainsExpectedRows`,
   `backgroundSettingsViewContainsExpectedRows` — each asserting the labels
   for its group. The existing `settingsViewContainsAllPreferenceRows` is
   replaced by these four.

7. **UI test adjustments**: `testSettingsOpensAndShowsControls` taps
   `"Interface"` before asserting Appearance/Text Size; adds a second tap
   path for Reminder group after navigation back. The toggle-persistence
   relaunch tests update their `swipeUp()` offsets since rows move into
   sub-views.

## What We're NOT Doing

- **NOT** adding a watchOS settings UI — the watch has no settings screen and
  this task doesn't create one.
- **NOT** changing persistence tiers — no key moves between `.standard` and
  `AppGroup.defaults`. The two-tier split is preserved exactly.
- **NOT** refactoring widget reload logic — `WidgetCenter.shared.reloadAllTimelines()`
  stays in `SettingsViewModel.showPreferenceChanged()` and the
  `onRemindersChanged` hook in `AppViewModel`.
- **NOT** changing `SortOption` or `AppearanceMode` model types — they're in
  `SingleThreadCore` and shared with the widget and watch targets.
- **NOT** inlining `ExcludedListsView` — it remains a dedicated view type,
  pushed from the Filtering & Sorting sub-view (moved from the root).
- **NOT** changing the `ReminderDictation` / microphone button behavior —
  that's a separate feature area.

## Open Risks

- **`SettingsBindings` `.onChange` surface.** `@Observable` property changes
  don't automatically trigger the two-phase `.onChange(of:)` the way
  `@Binding`+`@AppStorage` does today. If `showDate` changes through the
  bindings bag, the `.onChange` hook in `ReminderSettingsView` may need to
  observe `bindings.showDate` differently (e.g. `.onChange(of:
  bindings.showDate)`). This is the riskiest single change and should be
  verified early with the `showDate`/widget-reload path.
- **`List` vs `Form` accessibility traits.** The root `List` may audit
  differently than `Form` in `testAccessibilityAudit`. If the audit fails,
  adding `.accessibilityIdentifier` or keeping a `Form` shell around the
  `List` is a fallback.
- **UI test `swipeUp()` offsets.** `testBackgroundToggleHidesAndPersistsAcrossRelaunch`
  currently `swipeUp()` to reach the Background toggle. After the
  reorganization, the Background toggle lives in the Background sub-view
  (reached by tapping "Background" in the root menu), eliminating the swipe
  but requiring a navigation tap instead. The relaunch tests need updating.
- **File count.** Four new files plus the `SettingsBindings` type is a
  material expansion. The `SettingsView.swift` file shrinks from 357 to ~120
  lines. Total line count across the new files is ~400–500 added, ~200
  removed from the original — net ~250 lines, consistent with the task
  scope.
- **`showList` sync on watchOS side.** Adding `showList` to the sync payload
  requires the watch side to receive and apply it. The `WatchAppViewModel`
  (`SingleThreadWatch/WatchAppViewModel.swift`) must be checked for existing
  `showList` handling — if absent, the receive path in `apply(context:)` +
  `onShowListReceived` needs a watch-side consumer.
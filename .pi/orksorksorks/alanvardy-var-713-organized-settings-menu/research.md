# Research Findings

## Q1: Structure of `SingleThread/SettingsView.swift` — Form rows, `#if` gating, `@Binding` plumbing, `NavigationLink`/`NavigationStack`, toolbar & titles

### Findings

- **File scope.** Two top-level views: `ExcludedListsView` (lines 13–72) and `SettingsView` (lines 74–295). A file-global `#if os(iOS) || os(macOS) import WidgetKit` (line 4) is the only file-level gate; all other gating is inside the types. Line count: 357 lines.

- **`SettingsView` owns no state.** It is a purely presentational `@Binding`-backed view; the doc comment states "Owns no state — every preference is bound back to `ContentView`'s `@AppStorage` values" (lines 76–77).
  - 13 stored `@Binding` props (lines 267–282): `appearanceMode`, `textSize`, `sortOption`, `showMicrophoneButton`, `backgroundEnabled`, `backgroundFadePercent`, `showUndatedReminders`, `excludedLists`, `showDate`, `showList`, `showRecurrence`, `showAlarms`, plus `@Environment(\.dismiss)` (line 283).
  - Two bindings are gated to iOS only: `allowsLandscape` and `enableActionButtons` (lines 270–272).

- **Two platform-gated initializers.** `#if os(iOS) init(...)` (lines 77–115) accepts 17 params including `allowsLandscape` and `enableActionButtons`; `#else init(...)` (lines 117–154) has the same signature **minus those two** (15 params). Both default `viewModel: SettingsViewModel = SettingsViewModel()` (lines 113, 152). This mirrors `ContentView`'s two gated construction sites (Q2).

- **Body structure** (lines 157–262):
  - `NavigationStack` (line 158) wraps a single `Form` (line 159). No `.navigationTitle` on the root `SettingsView`.
  - Direct rows in order: `Picker` "Appearance" (160), `Picker` "Text Size" (166), `Picker` "Sort By" (172), iOS-gated `Toggle` "Allow landscape" (179–184), `Toggle` "Show microphone" (186), `Toggle` "Background" (189), `Picker` "Background Fade" (192), iOS-gated `Toggle` "Show action buttons" (198–200), `Toggle` "Show undated reminders" (202), `Toggle` "Show date" (205), `Toggle` "Show list" (213), `Toggle` "Recurrence indicator" (216), `Toggle` "Reminder alerts" (224).
  - Then `Section` (232) with the `NavigationLink { ExcludedListsView(...) } label: { Label("Excluded Lists", systemImage: "eye.slash") }` (233–239) — this is the one pushed subview.
  - Footer `Section` (241) rendering "Photo by … on Unsplash" via `Link`/`Text` for `backgroundPhotographer`/`backgroundPhotographerURL` (lines 242–250).

- **`ExcludedListsView` declaration & push.** Declared at lines 13–72. Takes `Binding<Set<String>>` and `[String]` via a manual `init` (lines 13–22 in file; init body stores `_excludedLists`). Renders `Form` > `Section` > `ForEach(availableLists, id: \.self)` of `Toggle(isOn: excludedBinding(for: list))` (lines 24–31), footer "Excluded lists are hidden from the reminder list." (line 33), and sets its own `.navigationTitle("Excluded Lists")` (line 35). The `excludedBinding(for:)` helper (lines 44–51) projects the `Set<String>` binding to a per-list `Bool` via `get: contains` / `set: insert/remove`. It is **pushed by the root `NavigationStack`** via the `NavigationLink` at lines 233–238, passing inline `$excludedLists` plus read-only `availableLists`.
  - **Note:** `excludedLists` is NOT an `@AppStorage` — it is projected from the store in `ContentView` (Q2, `excludedListsBinding` at `ContentView.swift:...`).

- **Root toolbar "Done"** (lines 254–260): `.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }` attached to the `Form`. `dismiss` is the `@Environment(\.dismiss)` binding (line 283), closing the modal (the sheet, set up in `ContentView`. It is NOT platform-gated — identical code on iOS and macOS.
- **`navigationTitle`:** the only title is `"Excluded Lists"` on the subview (line 35). The root `SettingsView` has no `.navigationTitle`; the root title is either inherited from/presented context.
- **`TextSizeModifier`** applied at the outer level (line 262): `.modifier(TextSizeModifier(textSize: textSize))`.
- Previews: iOS has two (`#Preview("Default")` 296, `#Preview("Dark + Extra Large")` 318) passing all 17 args; `#else` macOS has one (339) with the 15-arg form.

## Q2: Where settings state is owned and how it flows in/out of the view

### Findings
- **Single owner of record: `ContentView`.** All preferences are `@AppStorage`-backed stored props on `ContentView` (lines 101–161 in `SingleThread/ContentView.swift`). `SettingsView` holds only `Binding` copies; the sheet (ContentView.swift:273–311) feeds them in via `$` bindings.
- **Sheet construction sites** (ContentView.swift). `#if os(iOS)` branch builds `SettingsView` with `allowsLandscape`/`enableActionButtons` (lines 274–298); `#else` branch omits them (lines 299–310). Both pass the same remaining bindings + `excludedLists: excludedListsBinding`, `availableLists: viewModel.store.availableLists`, `backgroundPhotographer`/`URL`, plus `viewModel: SettingsViewModel()`.

- **Every `@AppStorage` key (ContentView.swift), its backing store, and gating:**

| Key | Type | Default | Store | Lines (ContentView.swift) |
|---|---|---|---|---|
| `appearanceMode` | `AppearanceMode` | `.system` | implicit `.standard` | 151–152 |
| `textSize` | `TextSize` | `.system` | implicit `.standard` | 154–155 |
| `allowsLandscape` | `Bool` | `true` | implicit `.standard` | **iOS-only** 157–159 |
| `showMicrophoneButton` | `Bool` | `true` | implicit `.standard` | 161–162 |
| `enableActionButtons` | `Bool` | `false` | implicit `.standard` | **iOS-only** 164–166 |
| `backgroundEnabled` | `Bool` | `true` | explicit `.standard` | 168–169 |
| `backgroundFadePercent` | `Int` | `BackgroundFade.defaultValue` (50) | explicit `.standard` | 171–172 |
| `showUndatedReminders` | `Bool` | `false` | `AppGroup.defaults` | 174–175 |
| `sortOption` | `SortOption` | `.priority` | `AppGroup.defaults` (key = `SortOption.defaultsKey`) | 177–178 |
| `showDate` | `Bool` | `true` | `AppGroup.defaults` | 180–181 |
| `showList` | `Bool` | `false` | `AppGroup.defaults` | 183–184 |
| `showRecurrence` | `Bool` | `true` | `AppGroup.defaults` | 186–187 |
| `showAlarms` | `Bool` | `true` | `AppGroup.defaults` | 188–189 |

- **Backing store definitions.** `AppGroup.defaults` = `UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard` with `.standard` fallback (SingleThreadCore/AppGroup.swift:8,13–14). `BackgroundEnabled`/`BackgroundFade` are the only `.standard` keys that pass an explicit `store: .standard`; the rest use `@AppStorage`'s implicit standard store (currently `.standard`).

- **`excludedLists` is NOT `@AppStorage`.** In `ContentView`, `excludedListsBinding` is a computed `Binding<Set<String>>` whose `get` reads `viewModel.store.excludedListTitles` and `set` calls `viewModel.setExcludedListTitles($0)` (ContentView.swift:76–79). The excluded-list set is persisted separately via `ExcludedListStore` (key `"excludedListTitles"` — see Q3).
- **Platform-gated bindings:** only `allowsLandscape` and `enableActionButtons` are iOS-only, in both `ContentView` (@AppStorage, ContentView.swift:157–166) and `SettingsView` (@Binding, SettingsView.swift,270–272).

- **Phone-only vs Watch-synced (per design + code):**
  - **Phone-only cosmetics (NOT synced):** `appearanceMode`, `textSize`, `showMicrophoneButton`, `backgroundEnabled`, `backgroundFadePercent`, plus iOS `allowsLandscape`, `enableActionButtons` (SettingsView.swift:73–76 comment lists these 7).
  - **Watch-synced:** sort option, show-undated, show date, show recurrence, show alarms, excluded lists, skip set (SettingsView.swift:63–64 comment).
  - **Discrepancy (important):** the doc comment at SettingsView.swift:63–64 lists **"show list"** as synced, and the code gives `showList` an App-Group-backed `@AppStorage` (ContentView.swift:183–184) — but **`showList` is NOT in the WatchConnectivity payload.** There is no `showList` PayloadKey (SkippedReminderSyncService.swift:244–251) and it is absent from both `pushAll()` (lines 153–168) and the `sendShowList` machinery. So `showList` persists to App Group but is never transmitted to the watch. This is a genuine contradiction between the doc comment and the actual sync code.

## Q3: What happens when a setting changes at runtime

### Findings
- **`SettingsViewModel` is a thin stateless delegator** (`SingleThread/SettingsViewModel.swift`, 27 lines total):
  - `allowsLandscapeChanged(_:)` (iOS-only, lines 13–16): `AppDelegate.applyLock(allowsLandscape: value)`.
  - `showPreferenceChanged()` (iOS/macOS, lines 20–24): `WidgetCenter.shared.reloadAllTimelines()`.
  - Annotated `@MainActor @Observable` (lines 7–9).

- **`.onChange` hooks within the settings `Form`** (SettingsView.swift) — each attached directly to its own row:
  - `allowsLandscape` toggle (line 179) → `.onChange(of: allowsLandscape)` (line 182) → `viewModel.allowsLandscapeChanged(newValue)` → `AppDelegate.applyLock` (see orientation below). iOS-only.
  - `showDate` toggle (205) → `.onChange(of: showDate)` gated `#if os(iOS) || os(macOS)` (lines 208–211) → `showPreferenceChanged()` → **`WidgetCenter.reloadAllTimelines()`**.
  - `showRecurrence` toggle (216) → same `.onChange` wiring (219–222) → widget reload.
  - `showAlarms` toggle (224) → same (227–230) → widget reload.
  - **`allowsLandscape`/`enableActionButtons` changes do NOT reload widgets or sync to watch.** Only the three "show-date/show-recurrence/show-alarms" rows trigger the widget reload, and only iOS wires the landscape toggle to the view model.

- **App-lock orientation** — full chain: `allowsLandscape` binding → SettingsView `.onChange` (line 182) → `SettingsViewModel.allowsLandscapeChanged` (SettingsViewModel.swift:13) → `AppDelegate.applyLock` (AppDelegate.swift:31). `AppDelegate.swift:31–45`: `applyLock` builds `mask` = `.allButUpsideDown` if true else `.portrait`, calls `controller.setNeedsUpdateOfSupportedInterfaceOrientations()` (line 39) + `scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))` (line 40). AppDelegate.swift:53–57 reads the persisted `"allowsLandscape"` directly from `.standard` for the launch mask.

- **ContentView-level `.onChange` (NOT in `SettingsView`, not via `SettingsViewModel`)** (ContentView.swift:162–169):
  - `.onChange(of: showUndatedReminders)` → `viewModel.handleShowUndatedReminders(newValue)`
  - `.onChange(of: sortOption)` → `viewModel.handleSortOption(newValue)`
  - `.onChange(of: appearanceMode)` → `viewModel.handleAppearanceMode(newValue)`
  - Also `.modifier(TextSizeModifier(textSize:))` (line 170). These mutate store state, which then triggers sync hooks.
  - ContentViewModel.swift:81–92: `handleShowUndatedReminders` sets store `showsUndatedReminders` and reloads; `handleSortOption` → `store.setSortOption(option)`; `handleAppearanceMode` → `AppDelegate.applyAppearance` (iOS) / `MacAppDelegate.applyAppearance` (macOS). `setExcludedListTitles` (ContentViewModel.swift:118) → `store.setExcludedListTitles` → persists via `excludeStore` and fires change hooks.

- **Watch sync wiring (`Skipped...SyncService`)** — NOT driven by `SettingsViewModel`. The service is instantiated in `AppViewModel.init` (AppViewModel.swift:26–38, iOS-only). Pushes are triggered by store hooks set up in AppViewModel.swift:53–56 and `onSortOptionChanged` (64–66), each calling `service.pushAll()`. `pushAll()` (SkippedReminderSyncService.swift:127–145) builds a single combined app-context dict with `skippedReminderIdentifiers`, `excludedListTitles`, `showUndatedReminders`, `sortOption` and (conditionally) `showDate`/`showRecurrence`/`showAlarms`, then `session.updateApplicationContext(context)`.
  - `showDate`/`showRecurrence`/`showAlarms` are `@AppStorage` in ContentView so do not pass through the store; their sync is driven by `setupSyncObservation()`/`handlePreferencesChanged()` in AppViewModel (lines 164, 178) observing `UserDefaults.didChangeNotification` on `AppGroup.defaults` and diffing cached `Show*Preference` values before calling `syncService?.pushAll()`.
  - `SkippedReminderSyncService.swift` is gated `#if os(iOS) || os(watchOS)` (line 6). `PayloadKey` enum (lines 244–251), `apply(context:)` (lines 253–295) is the single receive path decode→persist→notify. Receive hooks (e.g. `onSkippedIdentifiersReceived`, `onShowDateReceived`) wired in AppViewModel.swift:40–52.
  - AppViewModel data `onExcludedListsChanged`. The conversation: `exclude` list change → `.onExcludedListsChanged` → `pushAll()`. Also `onShowUndated` → pushAll.

- **`showList` does not trigger watch sync** (consistent with Q2 — not in the payload). Its only effect is local rendering (ContentView passes it into `ReminderCardView` at ContentView.swift:201,203).

Summary table of `.onChange` wiring:

| Row | onChange (attached to row) | Side effect |
|---|---|---|
| `allowsLandscape` (iOS) | SettingsView.swift:182 | `SettingsViewModel.allowsLandscapeChanged` → `AppDelegate.applyLock` (orientation) |
| `showDate` | SettingsView.swift:209 | `showPreferenceChanged` → `WidgetCenter.reloadAllTimelines` |
| `showRecurrence` | SettingsView.swift:220 | → widget reload |
| `showAlarms` | SettingsView.swift:228 | → widget reload |
| `showUndatedReminders` (ContentView) | ContentView.swift:163 | `handleShowUndatedReminders` → store → watch sync |
| `sortOption` (ContentView) | ContentView.swift:165 | `handleSortOption` → store → SortOptionStore.save + watch sync |
| `appearanceMode` (ContentView) | ContentView.swift:167 | `handleAppearanceMode` → appearance apply |

## Q4: Preference value models and their picker rendering

### Findings
**`AppearanceMode`** — `SingleThread/AppearanceMode.swift` — `enum: String, CaseIterable` (line 15): cases `system`, `light`, `dark`. Presentation labels on the enum itself, no `defaultsKey`:
- `systemImage` (line 46): `"circle.lefthalf.filled"`/`"sun.max.fill"`/`"moon.fill"`; `title` (line 55): `"System"`/`"Light"`/`"Dark"`.
- Persistence via hardcoded `@AppStorage("appearanceMode")` in ContentView.swift:151–152, plus `load(from:)` static reading literal `.standard` key `"appearanceMode"` (AppearanceMode.swift:83) defaulting to `.system`. Also platform apply props: `windowOverrideStyle` (iOS) and `appKitAppearance` (macOS).

**`TextSize`** — `SingleThread/TextSize.swift` — `String, CaseIterable` (line 9): cases `system`, `small`, `medium`, `large`, `extraLarge`. Presentation on the enum:
- `dynamicTypeSize` (line 18): maps system→nil, small→`.small`, medium→`.medium`, large→`.xLarge`, extraLarge→`.xxxLarge`; `systemImage` (line 29; shares `"textformat.size.larger"` for large & extraLarge); `title` (line 40): `"System"`/`"Small"`/`"Medium"`/`"Large"`/`"Extra Large"`.
- Persistence literal `@AppStorage("textSize")` (ContentView.swift:154–155). No `defaultsKey`.

**`BackgroundFade`** — `SingleThread/BackgroundFade.swift` — NOT an enum-with-cases; a static-value namespace (line 10):
- `defaultValue = 50` (13), `step = 10` (16), `allValues = Array(stride(from: 0, through: 90, by: 10))` (19), private `minValue = 0`(30)/`maxValue = 90`(31). `opacity(for:)` = `1 - percent/100`, clamped (lines 24–25). Persistenced `@AppStorage("backgroundFadePercent", store: .standard)` default `BackgroundFade.defaultValue` (ContentView.swift:171–172).

**`SortOption`** — `SingleThreadCore/Sources/SingleThreadCore/SortOption.swift` — `public enum: String, CaseIterable, Sendable` (line 8): cases `priority`, `dueDate`, `title`, and a real **`defaultsKey = "sortOption"`** (line 18). Companion `SortOptionStore` (lines 25–46) persists to `AppGroup.defaults` with `load()` default `.priority` and `save(_:)`. Presentation labels live in the app target at `SingleThread/SortOption+Presentation.swift` (reference `SortOption` from Core, SwiftUI-free): `title` (line 10) – `"Priority"`/`"Due Date"`/`"Title"`; `systemImage` (line 19) – `"exclamationmark.3"`/`"calendar"`/`"textformat.abc"`. `SortOptionStore` loaded at launch in AppViewModel.init, WatchAppViewModel, and Widget.

### Picker rendering in SettingsView.swift
- Enum pickers (`Form` rows) use string-backed tag values via `case`:
  - `Picker("Appearance")` with `ForEach(AppearanceMode.allCases, id: \.self)` + `Label(mode.title, systemImage: mode.systemImage).tag(mode)` (lines 160–166).
  - `Picker("Text Size")` (166–170), `Picker("Sort By")` (172–176) — same pattern.
- **`BackgroundFade` min-max mechanics** (int-based, no `case`/`tag` on a type): rendered as `Picker("Background Fade", selection: $backgroundFadePercent)` over `ForEach(BackgroundFade.allValues, id: \.self) { percent in Text("\(percent)%").tag(percent) }` (lines 192–196). This is the only non-enum picker.
- `BackgroundFade.opacity` applied in ContentView layer `BackgroundPhotoLayer(... opacity: BackgroundFade.opacity(for: backgroundFadePercent))` (ContentView.swift: ... `.opacity` usage).

## Q5: Automated tests exercising the settings screen

### Findings
**Unit tests (Swift Testing, `SingleThreadTests`):**

`SettingsViewTests.swift` — single test `settingsViewContainsAllPreferenceRows` (lines 13–34):
- Constructs `SettingsView` with `.constant(...)` bindings via a `settingsView()` helper (both iOS and non-iOS variants).
- Asserts every row label appears in `String(describing: view.body)` via `#expect(bodyDescription.contains(label))`.
- **Common labels asserted (lines 20–30):** `"Appearance"`, `"Text Size"`, `"Sort By"`, `"Show microphone"`, `"Background"`, `"Background Fade"`, `"Unsplash"`, `"Show undated reminders"`, `"Show date"`, `"Show list"`, `"Recurrence indicator"`, `"Reminder alerts"`, `"Excluded Lists"`, `"Done"`.
- **iOS-only additions (line 23):** `"Allow landscape"`, `"Show action buttons"`.
- **Invariant:** any re-layout that renames/removes these labels breaks the test. Comment (lines 10–12) notes Form content is reflected in `body` description (unlike `.sheet`).

`SettingsViewModelTests.swift`:
- `initializesWithoutCrash` (6–9): `SettingsViewModel()` + `#expect(Bool(true))`.
- `allowsLandscapeChangedDoesNotCrash` (iOS, 12–16): calls `allowsLandscapeChanged(true/false)`.
- `showPreferenceChangedDoesNotCrash` (iOS/macOS, 19–24): calls `showPreferenceChanged()`.
- **Invariant:** `SettingsViewModel` must keep methods `allowsLandscapeChanged(_:)` and `showPreferenceChanged()`.

- Independent preference-persistence unit tests (do not touch row layout but assert the `.AppSettings` keys): `ShowListPreferenceTests.swift`, `ShowDatePreferenceTests.swift`, `AppearanceModeTests.swift`, `ShowAlarmsPreferenceTests.swift`, `ShowRecurrencePreferenceTests.swift`, `MicrophoneToggleTests.swift`, `BackgroundImageStoreTests.swift`, `BackgroundFadeTests.swift`. (Convention: unique `"showlist-test-<uuid>"`-style keys.)

**UI tests** — XCTest:

`SingleThreadUITestsFlows.swift`:
- **`testSettingsOpensAndShowsControls`** (lines 126–139): `app.buttons["Settings"].tap()` → asserts `staticTexts["Appearance"]`, `["Text Size"]`, `["Sort By"]` exist near the top; then `app.swipeUp()` → asserts `staticTexts["Show date"]`. **Invariant:** gear button exposed as `app.buttons["Settings"]` (also used in other flows), rows at top must show without scroll; "Show date" reachable after one swipeUp.
- **`testBackgroundToggleHidesAndPersistsAcrossRelaunch`** (145–172): `app.switches["Background"]`, defaults `value == "1"`; taps `Done`, `.terminate()`, relaunch with only `["--ui-testing"]` (comment: `--seed` would call `resetPersistedState()` and wipe the key), reopens Settings, asserts `switches["Background"].value == "0"`.
- **`testShowListTogglePersistsAcrossRelaunch`** (177–204): uses `--ui-testing` both launches; `switches["Show list"]` defaults `"0"`, `swipeUp()` before flipping, `flipToggle(toggle, target: "1")`, relaunch asserts `"1"`.
- **`flipToggle(_:target:)` helper** (206–226): taps `toggle.switches.firstMatch` up to 3× polling the value (SwiftUI Form rows nest a switch).
- **Invariant:** toggle rows addressable as `app.switches["Background"]` / `app.switches["Show list"]`; layout must place "Show list" one swipeUp down; `--ui-testing` launch must not reset those `.standard`-backed keys.

`SingleThreadUITests.swift`:
- **`testAccessibilityAudit`** (27–66): launches `["--ui-testing"]`; on iOS CI runs `performAccessibilityAudit(for: [.sufficientElementDescription, .trait])`, locally adds `[.dynamicType, .hitRegion]`; macOS uses default audit. **Invariant:** settings/UI elements must satisfy these trait & description audits.

`ActionButtonsUITests.swift`:
- **`testActionButtonsAccessibilityAudit`** (46–78): asserts `app.buttons["Complete reminder"]`/`["Skip reminder"]` exist, then audits dynamicType/hitRegion/sufficientElementDescription/trait.
- **`testActionButtonsRenderAndSkipAdvancesCard`** (20–41): `--ui-testing` seeds reminder and turns action-buttons on.

## Cross-Cutting Observations
- **State ownership pattern:** `ContentView` is the single `@AppStorage` owner; `SettingsView` is a pure `@Binding` presentational view; `SettingsViewModel` is a stateless side-effect (orientation/widget) delegator; the store (`ReminderStore`) + `AppViewModel` drive watch sync. Three distinct "owners" by concern. (Settings doc comment lines 73–79; ContentView 133–150; SettingsViewModel 7–16.)
- **Two persistence tiers:** `.standard` for phone-only cosmetics (appearanceMode, textSize, micro button, background*, allowsLandscape, enableActionButtons); `AppGroup.defaults` for widget/watch-shared prefs (showUndated, sortOption, showDate, showList, showRecurrence, showAlarms, excluded lists, skip set).
- **`#if` gating is scoped and duplicated**: the iOS-only bindings (`allowsLandscape`, `enableActionButtons`) are gated identically in `ContentView` (`@AppStorage`), `SettingsView` (init + `@Binding`), and previews. The `showDate`/`showRecurrence`/`showAlarms` `.onChange` widget-reload hooks are gated `#if os(iOS) || os(macOS)`.
- **Watch sync is store/notification-driven, not view-driven.** Showing-date etc. flow via `AppGroup.defaults` `didChangeNotification` (AppViewModel.swift:164–190) and store hooks (`onShowUndatedRemindersChanged`, `onSortOptionChanged`, `onExcludedListsChanged`, `onSkipSetChanged`) → single combined `pushAll()` app context.
- **Widget reload is a narrow trigger:** only the three "show display" toggles (`showDate`/`showRecurrence`/`showAlarms`) reload all widget timelines via `WidgetCenter`.

## Open Areas
- **`showList` sync. contradiction.** Doc comment claims it is synced (SettingsView.swift:63); code has no `showList` payload key (SkippedReminderSyncService.swift:244–253) and never transmits it. It's App-Group-backed but phone-only effect. Whether this is intended vs a latent bug cannot be determined from code alone.
- **Watch-UI setting coverage:** the watchOS use has no Settings UI of its own (watch receives prefs only). If VAR relies on watchConfig, not here.
- **`AppBuilder`/scene orientation edge cases:** `AppDelegate.applyLock` depends on existing keyWindow and `requestGeometryUpdate` error path; does-up behavior under landscape-launch is not fully addressed in these settings-only files.
- **`toggle` default values** asserted in UI tests differ by platform/store — e.g. Background defaults "1", Show list "0" — but no central settings-default spec was found beyond the per-property `@AppStorage` initializers.

---

_Notes on method: This document was produced by reading the source directly and via five parallel agent passes; line references reflect the actual file contents at read time._
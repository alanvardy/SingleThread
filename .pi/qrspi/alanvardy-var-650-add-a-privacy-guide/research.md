# Research Findings

Branch: `alanvardy-var-650-add-a-privacy-guide` · Topic: settings surface, data tiers, text/footer/Link patterns, and test invariants.

Note: This research concerns ONLY the settings/transparency surface and its data tiers. It answers the four research questions; no implementation is proposed.

## Q1: How the pushed settings sub-views are declared and surfaced

### Findings

- `SettingsView.swift` is a `NavigationStack { List { ... } }` — `NavigationStack` at `SettingsView.swift:32`, `List` at `:33`.
- Root pushes **four** sub-views, each via a uniform `NavigationLink { SubView(...) } label: { Label("Title", systemImage:) }` row:
  - **Interface** → `InterfaceSettingsView` — `NavigationLink` at `SettingsView.swift:34`, `Label("Interface", systemImage: "paintpalette")` at `:51`.
  - **Reminder** → `ReminderSettingsView` — `NavigationLink` row at `:53`, label `Label("Reminder", systemImage: "bell.badge")` at `:61`.
  - **Filtering & Sorting** → `FilterSortSettingsView` — row at `:63`, label `Label("Filtering & Sorting", systemImage: "line.3.horizontal.decrease")` at `:70`.
  - **Background** → `BackgroundSettingsView` — row at `:72`, label `Label("Background", systemImage: "photo.on.rectangle")` at `:79`.
- `.navigationTitle("Settings")` at `SettingsView.swift:82`; a trailing `Button("Done")` in the toolbar dismisses via `@Environment(\.dismiss)` (toolbar block `SettingsView.swift:38-45`).
- The view "owns no state" (doc comment `SettingsView.swift:1-8`): it drags a `@Bindable SettingsBindings` bag (`:136`) and a separate `@Binding var excludedLists: Set<String>` (`:134`), forwarding only the needed bindings to each sub-view.
- **Root uses `List`; all pushed sub-views use `Form`** as their root container:
  - `InterfaceSettingsView` — `Form {` at `InterfaceSettingsView.swift:37`; `.navigationTitle("Interface")` at `:72`. Uses `Picker`s + `Toggle`s.
  - `ReminderSettingsView` — `Form {` at `ReminderSettingsView.swift:22`; `.navigationTitle("Reminder")` at `:56`. Uses `Toggle`s.
  - `FilterSortSettingsView` — `Form {` at `FilterSortSettingsView.swift:36`; `.navigationTitle("Filtering & Sorting")` at `:59`. Uses `Picker` + `Toggle` + embedded `Section`.
  - `ExcludedListsView` — `Form {` at `ExcludedListsView.swift:25`; `.navigationTitle("Excluded Lists")` at `:37`. Uses a `Section` of `Toggle`s.
  - `BackgroundSettingsView` — `Form {` at `BackgroundSettingsView.swift:20`; `.navigationTitle("Background")` at `:45`. Uses `Toggle` + `Picker`.
- **ExcludedLists nesting:** inside `FilterSortSettingsView`, a labeled `Section` wraps a nested `NavigationLink { ExcludedListsView(...) } label: { Label("Excluded Lists", systemImage: "eye.slash") }` — `FilterSortSettingsView.swift:49-56`; `excludedLists` forwarded as `@Binding var excludedLists` at `:32`. `ExcludedListsView` builds per-list `Toggle`s from a computed `excludedBinding(for:)` (`ExcludedListsView.swift:39-47`) reading/writing the shared `Set<String>`.
- **Platform `#if` gating** (iOS-only vs iOS+macOS):
  - iOS-only Interface props `allowsLandscape` (`:26-28`) and `enableActionButtons` (`:33-35`) — body toggles wrapped in `#if os(iOS)` at `InterfaceSettingsView.swift:47-52` and `:57-61`; `showMicrophoneButton` (`:54-55`) is NOT gated.
  - `SettingsView.swift:52-59` uses `#if os(iOS) / #else` at the `InterfaceSettingsView` call site (macOS branch drops the two iOS-only params).
  - `SettingsBindings.swift` declares these **unconditionally** with a comment (`:10-14`) that `#if` can't appear in a parameter list; the values are "harmless" on macOS. Gating lives only at the view layer.
  - `ReminderSettingsView` wraps `.onChange` hooks in `#if os(iOS) || os(macOS)` (`:26, :36, :48`) — effectively unconditional.
- **Footer / long-text rendering** (see Q3 for detail): `ExcludedListsView` uses a single-line `Section` footer via `footer:` (`ExcludedListsView.swift:26-28`); `BackgroundSettingsView` uses an empty-content `Section {} footer:` (`BackgroundSettingsView.swift:31-41`).

## Q2: What user data is read, stored, and transmitted, and across which tiers

### Findings

- **EventKit reads/writes** are confined to `ReminderStore` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`):
  - Reads: `start()` (`:147-155`) checks `authorizationStatus`; if `.fullAccess` calls `reload()`, else `requestAccess()`. `reload()` (`:224-275`) builds a predicate and calls `eventStore.fetchReminders(matching:)`; reads `calendars(for: .reminder).title` to populate `availableLists`. `requestAccess()` (`:335-347`) is the sole caller of `requestFullAccessToReminders()`.
  - Writes (non-watchOS `#else` branch): `completeReminder` sets `isCompleted = true` then `eventStore.save(reminder, commit: true)` (`:162-185`, save at `:171`); `deleteReminder` does `eventStore.remove(reminder, commit: true)` (`:196-210`, remove at `:205`); `addReminder` uses `makeReminder` then `save(commit: true)` (`:219-238`, save at `:229`).
  - **watchOS branch is EventKit read-only**: `completeReminder`/`deleteReminder` just remove from the local `reminders` array and emit identifiers (`:166-175`, `:199-205`); `addReminder` unconditionally returns `false` (`:221`).
- **Two UserDefaults tiers**:
  - **Tier A `AppGroup.defaults`** — `UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard`, `AppGroup.suiteName` at `AppGroup.swift:8`, accessor at `:14`. Shared phone↔widget (watch has no App Group → resolves to `.standard`). Keys: `skippedReminderIdentifiers` (`ReminderSkip.swift:121-143`), `excludedListTitles` (`ExcludedListStore.swift`, key at `:6`), `sortOption` (`SortOption.swift:17-26`), and the `@AppStorage(... store: AppGroup.defaults)` toggles in `ContentView.swift:169-183` (`showUndatedReminders`, `showDate`, `showList`, `showRecurrence`, `showAlarms`).
  - **Tier B `.standard`** (phone private sandbox; non-synced cosmetics) — `contentView` `@AppStorage` at `ContentView.swift:144-165`: `appearanceMode` (`:144`), `textSize` (`:147`), `allowsLandscape` (`:151`), `showMicrophoneButton` (`:155`), `backgroundEnabled` (`:158`), `backgroundFadePercent` (`:161`), `enableActionButtons` (`:165`). The `--ui-testing` seam also writes `enableActionButtons` to `.standard` (`AppViewModel.swift:186`).
  - **Watch tier (no App Group → `.standard`)** — watch stores constructed explicitly with `defaults: .standard`: `ShowUndatedRemindersPreference(.standard)` (`WatchAppViewModel.swift:26,110`), `ShowDateState` (`ShowDateState.swift:28`), `ShowRecurrence`/`ShowAlarms`/`ShowList` states, `SortOptionStore().load()` (`WatchAppViewModel.swift:22`).
- **Background image file cache** (`BackgroundImageStore.swift`, phone-only): directory `Application Support/SingleThread/` (`:157-161`); files `background.jpg` (`imageURL`, `:133-136`) and `background.json` (metadata `BackgroundMetadata`: photographer, photographerURL, fetchedAt — `:143-146`). `refreshIfNeeded` (`:177-197`) fetches `GET https://vardy.cc/unsplash` (endpoint `:112`) returning JSON `{url, photographer, photographer_url}` (`UnsplashPayload`, `:40-52`), then the photo bytes from `payload.url`. Doc comment (`:11`, `:74`): "Phone-local cosmetic concern: never touches the App Group or sync payloads."
- **WatchConnectivity** (`SkippedReminderSyncService.swift`) is device-to-device (local `WCSession`):
  - Combined `updateApplicationContext` via `pushAll()` (`:172-191`) — always-present keys: `skippedReminderIdentifiers`, `excludedListTitles`, `showUndatedReminders`, `sortOption`; conditionally `showDate`/`showRecurrence`/`showAlarms`/`showList` (`:176-182`).
  - Interactive `sendMessage`: `requestCompleteReminder` sends `{completeReminderIdentifier:}` (`:194-202`); `requestDeleteReminder` sends `{deleteReminderIdentifier:}` (`:204-212`). Received on the other side via `didReceiveMessage` (`:247-252`); both directions are supported but complete/delete executes the EventKit write only on the phone.
  - `apply(context:)` `:266-302` persists the full set of all keys into the receiving side's store. All `PayloadKey` constants listed at `:215-225`.
- **What leaves the device:** No analytics/telemetry/CloudKit/iCloud calls (grep returned no matches). The only network egress is the phone's `BackgroundImageStore` fetch to `vardy.cc/unsplash` and the follow-up photo URL. Reminders/skip/excluded/preference data move only over the device-local WCSession.

## Q3: Patterns for explanatory text, footnotes, and external `Link`s

**Findings**

- The Unsplash photo credit is the **only** `Link(` in the codebase and lives in `BackgroundSettingsView.swift:31-37`, as an empty-content `Section {} footer:`:
  - `Section {} footer: { if let backgroundPhotographer { if let backgroundPhotographerURL { Link("Photo by \(backgroundPhotographer) on Unsplash", destination: backgroundPhotographerURL) } else { Text("Photo by \(backgroundPhotographer) on Unsplash") } } }`.
  - Props: `let backgroundPhotographer: String?` and `let backgroundPhotographerURL: URL?` (`:13-15`), threaded from `ContentView` through `SettingsView`. `Link` uses a `String` title + `URL?` destination (`:29-31`). Preview at `BackgroundSettingsView.swift:39-47` passes `URL(string: "https://unsplash.com/@neom")`.
- There are exactly **two** `Section footer:` usages in the app — `BackgroundSettingsView.swift:26` and `ExcludedListsView.swift:26` (`Text("Excluded lists are hidden from the reminder list.")`). **No multi-line footer exists**; neither applies `.font(.footnote)`, multilingual alignment, concatenated `Text`, or `\n`. Both rely on SwiftUI default `Form`/`Section` footer styling.
- **SF Symbol conventions** — hardcoded lower-case kebab-case dot-separated string literals (e.g. `"line.3.horizontal.decrease"`, `"photo.on.rectangle"`), sometimes `.fill` suffix / numbered components. Typed picker values centralize symbols in model extensions: `AppearanceMode.systemImage` (`AppearanceMode.swift:59-64`), `TextSize.systemImage` (`TextSize.swift:29-35`), `SortOption.systemImage` (`SortOption+Presentation.swift:18-24`); individual rows keep symbols inline (`SettingsView.swift:51,61,70,79`; `FilterSortSettingsView.swift:27,35`, etc.).
- **No localization infrastructure** — no `*.xcstrings`, `*.strings`, `*.stringsdict`, `*.lproj`, or `Localizable*` files anywhere in the repo. Strings are hardcoded Swift literals; `NSLocalizedString`/`String(localized:)` not used in settings views.

## Q4: Which automated tests assert on the settings screen and its sub-views

**Findings**

- `SingleThreadTests/SettingsViewTests.swift` — unit tests render views to strings and assert **substring** membership in `String(describing: body)`:
  - `settingsViewContainsNavigationLinkLabels()` (`:13`) asserts contains `"Interface"`, `"Reminder"`, `"Filtering & Sorting"`, `"Background"` (`:20-24`) and `"Done"` (`:25`).
  - `interfaceSettingsViewContainsExpectedRows()` (`:32`) asserts `"Appearance"`, `"Text Size"`, `"Show microphone"` (`:25-27`); on iOS additionally `"Allow landscape"`, `"Show action buttons"` (`:29-30`).
  - `reminderSettingsViewContainsExpectedRows()` (`:62`) asserts `"Show date"`, `"Show list"`, `"Recurrence indicator"`, `"Reminder alerts"` (`:69-70`).
  - `filterSortSettingsViewContainsExpectedRows()` (`:80`) asserts `"Sort By"`, `"Show undated reminders"`, `"Excluded Lists"` (`:87-88`), with `availableLists: ["Work"]`.
  - `backgroundSettingsViewContainsExpectedRows()` (`:97`) asserts `"Background"`, `"Background Fade"`, `"Unsplash"` (`:103-104`), photographer `"NEOM"`, `sampleURL = https://unsplash.com/@neom` (`:116`).
- `SingleThreadTests/SettingsViewModelTests.swift` — crash-only assertions: `initializesWithoutCrash()` (`:7`), `allowsLandscapeChangedDoesNotCrash()` (`:14`, iOS), `showPreferenceChangedDoesNotCrash()` (`:24`, iOS/macOS). No label assertions.
- UI `SingleThreadUITests`
  - `testSettingsOpensAndShowsControls()` (`SingleThreadUITestsFlows.swift:126`) — seeds `{"reminders":[{"title":"Buy groceries"}]}`, then looks up `staticTexts["Buy groceries"]`, `buttons["Settings"]`, `staticTexts["Interface"]`, `["Appearance"]`, `["Text Size"]`, pops back, `staticTexts["Reminder"]`, `["Show date"]`, `["Filtering & Sorting"]`, `["Sort By"]`, `["Excluded Lists"]` (`128-146`).
  - `testBackgroundToggleHidesAndPersistsAcrossRelaunch()` (`:153`) — `switches["Background"]` default `"1"` (`:163`), flips, `buttons["Done"]`, relaunch with `--ui-testing` (not `--seed`, to avoid `resetPersistedState()`), asserts `"0"` (`:177-184`).
  - `testShowListTogglePersistsAcrossRelaunch()` (`:220`) — `switches["Show list"]` default `"0"` → `"1"`, relaunch `--ui-testing`, asserts persisted (`:231-250`).
  - `flipToggle` helper (`:256`) taps nested `switches.firstMatch` up to 3 times polling `value`.
- `SingleThreadUITests/SingleThreadUITests.swift` — `testAccessibilityAudit()` (`:19`) launches `--ui-testing` (empty store → "No Reminders"), audits on iOS CI with `[.sufficientElementDescription, .trait]` (`:35-36`), locally `[.dynamicType, .hitRegion, .sufficientElementDescription, .trait]`; on macOS defaults. **It never opens the Settings sheet** — it audits the initial main-list state, so newly added Settings rows are NOT picked up by this audit.
- `SingleThreadUITests/ActionButtonsUITests.swift` — `testActionButtonsRenderAndSkipAdvancesCard()` (`:20`) uses `Complete reminder` / `Skip reminder` buttons and `"All Done"` (`:25-44`); `testActionButtonsAccessibilityAudit()` (`:47`) audits only the two buttons with the same CI carve-out (`:60-73`). Also does not enter Settings.
- `SingleThreadUITestsAppearanceLaunchTests.swift` — `testColdLaunchAppearance()` (`:22`, `--no-reminders`); `testRuntimeAppearanceToggle()` (`:54`) and `testDeviceFollowingClearsOverride()` (`:91`) navigate into `Interface` and match the appearance picker via `NSPredicate(label == "Appearance")` on `buttons.firstMatch` (`:68-70`, `:101-103`), because the picker's accessibility identifier varies with the persisted symbol (comment `:44-52`).

**Invariant implications (facts, not recommendations):**
- Root labels the tests depend on (`"Interface"`, `"Reminder"`, `"Filtering & Sorting"`, `"Background"`, `"Done"`, `"Settings"`) must keep their exact strings; the substring-based unit tests are `contains`-checks so a new row next to them would not break them, but a label *change* would.
- The appearance picker matcher `label == "Appearance"` on `buttons.firstMatch` could collide if a new Interface row renders a different button also labeled `"Appearance"`.
- `testAccessibilityAudit` is out of scope for new Settings rows (doesn't open Settings).

## Cross-Cutting Observations

- **Uniform row idiom**: Every pushed settings section follows `NavigationLink { SubView } label: { Label("Title", systemImage:) }`, whether direct in the root `List` (`SettingsView.swift:34-80`) or nested in a `Section` (`FilterSortSettingsView.swift:49-53`).
- **Root `List`, all pushed sub-views `Form`** — a `Settings` main uses `List`; every pushed destination (Interface/Reminder/Filtering & Sorting/Excluded/Background) uses `Form` as its container.
- **Two-tier UserDefaults split maps to "cosmetic vs synced data"**: cosmetic/preference cosmetics (`appearanceMode`, `textSize`, `allowsLandscape`, `showMicrophoneButton`, `backgroundEnabled`, `backgroundFadePercent`, `enableActionButtons`) live on `.standard` and are NOT synced; functional/sync data (`skippedReminderIdentifiers`, `excludedListTitles`, `sortOption`, `showUndatedReminders`, `showDate`, `showList`, `showRecurrence`, `showAlarms`) lives in `AppGroup.defaults` and is pushed/received over WatchConnectivity. The background image is a third tier (Application Support files), explicitly "never touches the App Group" (`BackgroundImageStore.swift:11`).
- **Guide-value "transparency/privacy" pattern is entirely absent** today: no privacy/data/documentation screen exists; the only `Link` is the Unsplash credit; no localization.
- Strings are hardcoded; no localization infrastructure anywhere.

## Open Areas

- Exact `SettingsView` line offsets reported by subagents vary slightly (e.g. root `List` at `:32/:33/:45` across reads); treat row/label line numbers in Q1 as indicative and confirm against the file when coding.
- Whether the phone's App Group entitlement file is present for both iOS targets and whether a paired watch might bridge context through iCloud was not verified (out of scope for the settings-question focus).
- The `BackgroundImageStore` payload URL is an arbitrary remote host returned by `vardy.cc/unsplash`; TLS/host behavior is not analyzed.
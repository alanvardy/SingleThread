# Research Findings

## Q1: How is the iOS reminder card composed, and how are its swipe actions wired?

### Card composition (`SingleThread/ReminderCardView.swift`)
- `struct ReminderCardView: View` at `:10`; init: `display: ReminderDisplay`, `showDate`, `showList` (default `false`), `showRecurrence`, `showAlarms` (default `true`) at `:14-20`.
- Body is one `VStack(alignment: .leading, spacing: 4)` at `:29`. Children in order:
  1. **Title row** — `HStack(alignment: .firstTextBaseline, spacing: 4)` `:30-38`: priority marker `Text(display.priorityMarker)` gated on `ReminderPriority.level(forMarker:) != nil` `:31-36` (`.font(.title)` `:33`, `priorityColor(level)` `:34`/`:98-103` low→green/medium→yellow/high→red, a11y label `"\(level.displayName) priority"` `:35`); then `Text(display.titleAttributed).font(.title)` `:37-38`.
  2. **Info row** — `HStack` `:40-52`: due date `Text(due, style: .date)` gated `showDate && display.dueDate != nil` `:41-44`; recurrence `HStack(spacing: 4)` (repeat icon hidden from a11y `:48` + `Text(display.recurrenceSummary ?? "Repeats")` `:50`) gated `showRecurrence && display.hasRecurrence` `:46-53`. Both `.font(.caption)` + `.foregroundStyle(.secondary)`.
  3. **List-name row** — `Text(listName)` gated `showList && !listName.isEmpty` `:55-60`, `.font(.caption)` `:59`.
  4. **Alarm row** — bell `Image` gated `showAlarms && display.hasAlarms` `:61-67`, `.font(.caption)` `:66`, a11y "Has alarm" `:65`.
  5. **Trailing notes block** — `if let notesAttr = display.notesAttributed` `:68-73`: `Text(notesAttr)`, `.font(.callout)`, `.foregroundStyle(.secondary)`, **`.lineLimit(3)`** `:73`.
- After the VStack: `.accessibilityElement(children: .combine)` `:80` (whole card = one VoiceOver unit; comment `:76-79` explains the hit-region audit rationale); plate `.padding(12)` → `.background { RoundedRectangle(cornerRadius: 10).fill(Self.plateFill(for: colorScheme)) }` → `.padding(-12)` `:86-91` — comment `:83-85`: padding pair grows for the plate then **restores original outer geometry so list metrics are unchanged**. `plateFill(for:)` `:96-100` (dark→`.black`, light→`0.96/0.95/0.94`).
- Card data comes from `ReminderDisplay` (`SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift:11-20`): maps `EKReminder` → title, notes (via `ReminderNotesFormatter`, `:73-78` applies `CodeSpanFormatter`).

### Row inside `SingleThread/ContentView.swift`
- `GeometryReader` computes `viewHeight = geometry.size.height - safeArea top/bottom` `:274-277`; row sits in `List` branch at `:309-361`.
- The card row (`:310-324`): `ReminderCardView(...)` `:311-316` with `.listRowBackground(viewModel.rowChromeBackground)` `:317` (always `.clear`, `ContentViewModel.swift:54-56`), `.padding(.horizontal, 40)` `:318`, `.padding(.vertical, 12)` `:319`, `.frame(maxWidth: .infinity, alignment: .center)` `:322`, **`.frame(minHeight: viewHeight, alignment: .center)`** `:323`, `.listRowSeparator(.hidden)` `:324`.
- List-level: `.listStyle(.plain)` `:363`, `.scrollContentBackground(.hidden)` `:367`, `.background(Color.clear)` `:370`, `.refreshable { await viewModel.reload() }` `:371-373`. `bottomBar` overlays the list in `ZStack(alignment: .bottom)` `:308`/`:374` (see Q4).

### Swipe actions (`ContentView.swift:345-360`)
- **Leading (complete)** `:345-352`: `Button { Task { await viewModel.completeCurrentReminder() } }` `:346-347`, label `Label("Complete", systemImage: "checkmark.circle.fill")` `:349`, `.tint(.green)` `:351`.
- **Trailing (skip)** `:353-360`: `Button { viewModel.skipCurrentReminder() }` `:354-355` (synchronous, no `Task`), label `Label("Skip", systemImage: "circle.slash")` `:357`, `.tint(.orange)` `:359`.
- iOS-only `.contextMenu` `:326-343`: "View in Reminders" deep link `:328-333` via `ReminderDeepLink.url(forReminderIdentifier:)`, "Delete" → `Task { await viewModel.deleteCurrentReminder() }` `.tint(.red)` `:335-341`.
- View-model chain: `ContentViewModel.completeCurrentReminder()` `ContentViewModel.swift:108-111` → `if await store.completeCurrentReminder(), showCompletionGlow.isEnabled { completionGlow.trigger() }`; `skipCurrentReminder()` `:114-115` → `store.skipCurrentReminder()` (`ReminderStore.swift:232-240`, 200 ms `eventKitSettleDelay` then `applySkipSet` persists via `SkippedReminderStore`, key `"skippedReminderIdentifiers"` `ReminderSkip.swift:126-140`).

### Row-geometry constraints for appended card content
- **No fixed row height** — only `minHeight = full viewport` (`:323`); appended content grows the row downward.
- **No `.listRowInsets` override** — only `listRowBackground`/`listRowSeparator`; default SwiftUI row insets apply.
- Horizontal cap: `.padding(.horizontal, 40)` `:318` (card width = row width − 80 pt); vertical `.padding(.vertical, 12)` `:319`.
- Plate padding self-cancels (`ReminderCardView.swift:86-91`). Notes `.lineLimit(3)` caps trailing-block height.
- Dynamic Type scaling: `.modifier(TextSizeModifier(textSize: textSize))` (`ContentView.swift:100`; `TextSizeModifier.swift:8-17`) applies `dynamicTypeSize` — card height scales with type size.
- Content is vertically centered (`alignment: .center` on the min-height frame), so appended content extends from the row's vertical center in both directions; `bottomBar` can overlap a tall row's lower edge.

## Q2: How does the Settings UI work, and how does a toggle edit persist?

### SettingsView (`SingleThread/SettingsView.swift`)
- Owns no state: `@Bindable private var bindings: SettingsBindings` `:135`, `@Binding excludedLists: Set<String>` `:132`, `viewModel: SettingsViewModel` `:137`, `backgroundImage`, `availableLists` `:138-139.` `init` `:14-28` (defaults `viewModel = SettingsViewModel()` `:22`).
- `body` `:30-107`: `NavigationStack { List }`, `.navigationTitle("Settings")` `:97`, `Done` → `dismiss()` `:100-105`, `.modifier(TextSizeModifier(textSize: bindings.textSize))` `:106`.
- Section 1 `:32-79` NavigationLink destinations (each sub-view receives `$bindings.X` projections):
  - Interface `:33-51`: `#if os(iOS)` → `InterfaceSettingsView(appearanceMode:, textSize:, allowsLandscape:, showMicrophoneButton:, enableActionButtons:, viewModel:)` `:35-41`; `#else` drops the two iOS-only bindings `:43-49`.
  - Reminder `:52-62`: `ReminderSettingsView(showDate:, showList:, showRecurrence:, showAlarms:, showCompletionGlow:, viewModel:)` `:53-60`.
  - Filtering & Sorting `:63-71`: `FilterSortSettingsView(sortOption:, showUndatedReminders:, availableLists:, excludedLists:)`.
  - Background `:72-79`: `BackgroundSettingsView(backgroundEnabled:, backgroundFadePercent:, backgroundImage:)`.
- Section 2 `:82-95`: `PrivacySettingsView()` label "Privacy Policy" `:84-86`; `AboutView()` label "About" `:88-91`.

### InterfaceSettingsView (`SingleThread/InterfaceSettingsView.swift`)
- Bindings: `appearanceMode` `:9`, `textSize` `:11`, `allowsLandscape` `:14` (`#if os(iOS)` `:13-15`), `showMicrophoneButton` `:17`, `enableActionButtons` `:20` (`#if os(iOS)` `:19-21`); `viewModel: SettingsViewModel` `:23`.
- Body (Form) `:25-57`: `Picker("Appearance", selection: $appearanceMode)` over `AppearanceMode.allCases` `:27-31`; `Picker("Text Size", ...)` `TextSize.allCases` `:33-37`; **`#if os(iOS)`** `Toggle("Allow landscape", isOn: $allowsLandscape)` `:40-42` + `.onChange` → `viewModel.allowsLandscapeChanged(newValue)` `:43-45` (the only in-sub-view side effect); `Toggle("Show microphone", isOn: $showMicrophoneButton)` `:47-49`; **`#if os(iOS)`** `Toggle("Show action buttons", isOn: $enableActionButtons)` `:51-53`.

### SettingsBindings (`SingleThread/SettingsBindings.swift`)
- `@MainActor @Observable final class` `:14-16`. Doc `:3-12`: sole bag of all `@AppStorage`-backed values; `excludedLists` deliberately excluded (store-backed, passed separately); `allowsLandscape`/`enableActionButtons` declared unconditionally (compiler forbids `#if` in param lists), never wired on macOS.
- 14 stored properties `:52-65`; init `:19-33` with defaults that mirror each `@AppStorage` default exactly (e.g. `showDate = true` `:28`, `showList = false` `:29`, `showCompletionGlow = true` `:32`, `backgroundFadePercent = 50` matching `BackgroundFade.defaultValue`).
- Sub-views never get the bag; only `$bindings.X` projections (`SettingsView.swift:35-78`).

### Write path
- Gear button opens the sheet: `settingsBag = makeSettingsBag()` then `isShowingSettings = true` `:67-68`; `@State private var settingsBag: SettingsBindings?` `:195` (doc `:189-194`: stable bag recreated each open so edits don't snap back on body re-eval).
- `.sheet(isPresented: $isShowingSettings)` `:109` renders `SettingsView(bindings: bag, ...)` `:110-137`.
- **Write-back chain** (comment `:117-119`, all `.onChange(of: bag.X) { _, new in X = new }`): `appearanceMode` `:120`, `textSize` `:121`, `allowsLandscape` `:122-123` (iOS), `enableActionButtons` `:124-125` (iOS), `showMicrophoneButton` `:126`, `backgroundEnabled` `:127`, `backgroundFadePercent` `:128`, `showUndatedReminders` `:129`, `sortOption` `:130`, `showDate` `:131`, `showList` `:132`, `showRecurrence` `:133`, `showAlarms` `:134`, `showCompletionGlow` `:135`. The `@AppStorage` property write persists to its UserDefaults suite.
- Dismiss: `.onChange(of: isShowingSettings)` `:101-107` → `settingsBag = nil` `:106` (fresh bag next open).
- `makeSettingsBag()` `:499-537` (@MainActor `:502`): iOS branch `:503-520` passes all 14 current values; `#else` `:521-535` omits the two iOS-only keys.
- Excluded lists use a separate path (not the bag): `excludedListsBinding` `:205-209` = get/set into `viewModel.store.excludedListTitles` → `ContentViewModel.setExcludedListTitles` `ContentViewModel.swift:117-119` → `ReminderStore.setExcludedListTitles` `ReminderStore.swift:325-331` (persists `"excludedListTitles"` via `ExcludedListStore`, `AppGroup.defaults`).
- ContentView-level reactions on write-back: `.task`/`.onChange(of: showUndatedReminders)` `:88-93` → `viewModel.handleShowUndatedReminders`; `sortOption` `:94-96` → `handleSortOption`; `appearanceMode` `:97-99` → `handleAppearanceMode`.

### @AppStorage suite split (`ContentView.swift`)
- **Implicit `.standard`**: `"appearanceMode"` `:144-145`, `"textSize"` `:147-148`, `"allowsLandscape"` `:150-153` (iOS), `"showMicrophoneButton"` `:155-156`, `"enableActionButtons"` `:164-167` (iOS).
- **Explicit `.standard`**: `"backgroundEnabled"` `:158-159`, `"backgroundFadePercent"` `:161-162`.
- **`store: AppGroup.defaults`**: `"showUndatedReminders"` `:169-170`, `SortOption.defaultsKey` `:172-173`, `"showDate"` `:175-176`, `"showList"` `:178-179`, `"showRecurrence"` `:181-182`, `"showAlarms"` `:183-184`, `"showCompletionGlow"` `:186-187`.
- `AppGroup.defaults` = `UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard` (`SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:8-16`).

### SettingsViewModel side-effect hooks (`SingleThread/SettingsViewModel.swift`)
- `@MainActor @Observable final class` `:7-8`; stateless.
- `allowsLandscapeChanged(_:)` `:13-14` (iOS) → `AppDelegate.applyLock(allowsLandscape:)` (`AppDelegate.swift:31-45`, orientation mask + `requestGeometryUpdate`); launch-time read in `supportedInterfaceOrientationsFor` `:52-59`.
- `showPreferenceChanged()` `:21-22` → `WidgetCenter.shared.reloadAllTimelines()`. Fired only from `ReminderSettingsView` `.onChange` for showDate `:27-29`, showRecurrence `:37-39`, showAlarms `:45-47` (all `#if os(iOS) || os(macOS)`). **Asymmetry: `showList` (`:30-32`) and `showCompletionGlow` (`:48-57`) toggles have no widget-reload hook.**

## Q3: What are the conventions for persisted preference structs in `SingleThreadCore`?

All five `Show*Preference` structs live in `SingleThreadCore/Sources/SingleThreadCore/`:

| Struct | Init default key | Read API (missing key →) | Write API |
|---|---|---|---|
| `ShowDatePreference` (`ShowDatePreference.swift:11`) | `"showDate"` | `isEnabled` `?? true` (`:19-21`) | `set(_:)` `:23-25` |
| `ShowRecurrencePreference` (`:11`) | `"showRecurrence"` | `isEnabled` `?? true` (`:19-21`) | `set(_:)` `:23` |
| `ShowAlarmsPreference` (`:11`) | `"showAlarms"` | `isEnabled` `?? true` (`:19-21`) | `set(_:)` `:23` |
| `ShowCompletionGlowPreference` (`:11`) | `"showCompletionGlow"` | `isEnabled` `?? true` (`:19-21`) | `set(_:)` `:23` |
| `ShowListPreference` (`:11`) | `"showList"` | `isEnabled` `?? false` (`:19-21`) | `set(_:)` `:23` |
| `ShowUndatedRemindersPreference` (`:11-14`) | `"showUndatedReminders"` | `func load() -> Bool` `?? false` (`:18-20`) | `save(_:)` `:22-24` |

- Common init: `public init(defaults: UserDefaults = AppGroup.defaults, key: String = "<camelCaseKey>")` (e.g. `ShowDatePreference.swift:11`, `ShowListPreference.swift:11`); private `defaults`/`key` storage (`ShowDatePreference.swift:27-28`).
- Read idiom: `defaults.object(forKey: key) as? Bool ?? <default>` — deliberately **not** `bool(forKey:)` (returns `false` for missing key); each file's doc comment states why (e.g. `ShowDatePreference.swift:4-8` "would hide dates on first launch").
- Two API families: five use computed `var isEnabled` + `set(_:)`; `ShowUndatedRemindersPreference` is the outlier with `load()`/`save(_:)` mirroring `SortOptionStore` (doc `:6`).
- `AppGroup.defaults` = `UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard` (`AppGroup.swift:8-14`), falling back to `.standard` "when the group is unavailable (watchOS, unregistered simulators, and previews)". Pinned by `AppGroupTests.swift:6-17`.

### Injection into view models/services (defaulted init params)
- **`SkippedReminderSyncService`** (`SkippedReminderSyncService.swift`) is the canonical injection site: all six preferences are defaulted init params `:31-36` (e.g. `showUndatedStore: ShowUndatedRemindersPreference = ShowUndatedRemindersPreference()`), plus `sendsShowDate/.../sendsShowCompletionGlow: Bool = true` flags `:37-41`; stored `private let` `:253-261`. Read at push time in `pushAll()` `:150-167`; written at receive time in `apply(context:)` `:288-315` (e.g. `showUndatedStore.save(...)` `:289-291`, `showDateStore.set(...)` `:297-299`). Wire keys in `PayloadKey` `:237-244`.
- **iOS `AppViewModel`** passes explicit stores but leaves defaults: `showDateStore: ShowDatePreference(), showRecurrenceStore:, showAlarmsStore:, showCompletionGlowStore:` + `sendsShowDate: true` (`AppViewModel.swift:31-35`); `showListStore`/`showUndatedStore` use AppGroup-backed defaults.
- **iOS `ContentViewModel`**: defaulted init param `showCompletionGlow: ShowCompletionGlowPreference = ShowCompletionGlowPreference()` (`ContentViewModel.swift:17`), stored `private let` `:134`, read at trigger time `:108-111`.
- **Watch**: everything `defaults: .standard` and receive-only — `WatchAppViewModel.swift:26` (`ShowUndatedRemindersPreference(defaults: .standard).load()`), sync service construction `:134-140` with all `sends*: false`; watch `Show*State` holders each own `private let preference = Show*Preference(defaults: .standard)` read in `init()`/written in `apply(_:)` (e.g. `ShowDateState.swift:17,28,31`; identical in `ShowListState`, `ShowRecurrenceState`, `ShowAlarmsState`, `ShowCompletionGlowState`).

### iOS vs watch sync
- **None of the six is iOS-only**; all sync phone→watch through `SkippedReminderSyncService` (`pushAll()` `:150-167`, `apply()` `:288-315`). On watchOS, `AppGroup.defaults` fallback makes `.standard` the same suite anyway (`AppGroup.swift:13-14`).
- Widget reads `showDate/showList/showRecurrence/showAlarms` via fresh `Show*Preference()` instances and `showUndatedReminders` raw via `AppGroup.defaults.bool(forKey:)` (`NextThingWidget.swift:64-71`).
- iOS settings toggles write the *same keys* directly through `@AppStorage(store: AppGroup.defaults)` (`ContentView.swift:169-187`), bypassing the structs; `AppViewModel.handlePreferencesChanged()` observes `UserDefaults.didChangeNotification` on the suite to push to watch (`AppViewModel.swift:177-198`).
- `UITestingSeed.persistedKeys` resets every one of these keys between UI tests (`UITestingSeed.swift:52-70`).

## Q4: What instructional, transient, or secondary-text UI patterns already exist on the main screen?

- **No instructional/onboarding/tip UI exists.** Grep for prompt/hint/onboarding/tip/coach/firstLaunch/hasSeen found only false positives: `.swipeActions` (`ContentView.swift:345,353`), a doc comment "never prompts for access" (`ReminderIntents.swift:29`), TCC-prompt comments in launch tests, and "with**Hint**ermediateDirectories" (`BackgroundImageStore.swift:202`). The swipe gesture is entirely undiscoverable in-app — no hint copy anywhere.

### Secondary/instructional-style text that does exist
- Empty/all-done states (`ContentViewModel.swift:60-74`, rendered via `ContentUnavailableView` in `ContentView.swift:279-311`): "Nothing due" + "Only today's and overdue reminders show here — pull to refresh." (`:61-63`); "No Reminders" + "You don't have any reminders yet." (`:66-68`); "All Done" + "Pull to refresh to see all your reminders again." (`:73-74`).
- Authorization states (`ContentView.swift:259-272`): `ProgressView("Requesting access…")` `:262`; denied `ContentUnavailableView("Reminders Access", "lock.shield", "Enable access in Settings to see your reminders.")` `:266-271`.

### Completion-glow overlay (closest transient auto-dismiss analogue)
- **Model** `SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift`: `@MainActor @Observable final class` `:11-13`; `public private(set) var isActive = false` `:17`; `duration = 0.50` `:27` (injectable for tests); `trigger()` `:32-43` sets active, cancels prior `dismissTask`, sleeps `duration`, resets; `private var dismissTask: Task<Void, Never>?` `:49`. **Not keyed by reminder id** — a single boolean per view-model instance (iOS: `ContentViewModel.completionGlow = CompletionGlow()` `ContentViewModel.swift:38`; watch mirror `WatchReminderViewModel.swift:36`).
- **View** `ContentView.swift:80-89` (`.overlay { completionGlowOverlay }` + `.animation(..., value: viewModel.completionGlow.isActive)` `:85-87`); overlay itself `:480-490`: `Color.green.opacity(0.1).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(!isGlowUITesting).accessibilityElement(children: .ignore).accessibilityIdentifier("completionGlowOverlay").accessibilityLabel("Completion glow").transition(.opacity)`. `isGlowUITesting` `:213-217` true only under `--ui-testing-glow`.
- Preference gate: `ContentViewModel.completeCurrentReminder()` `:108-111` — `if await store.completeCurrentReminder(), showCompletionGlow.isEnabled` (see Q3).
- Test seams: `AppViewModel.swift:102-106` sets `duration = 2.0` under `--ui-testing-glow` (comment at `:104` says "production duration is 0.25 s" — **stale**; actual default is 0.50).

### bottomBar footnotes (`ContentView.swift:380-411`)
- Dictation error text: `if let error = viewModel.dictation.dictationError { Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal) }` `:387-393` (errors from `DictationViewModel.swift:36,41,67`, cleared at `:46` on new dictation).
- Creation feedback: `creationFeedbackView(for:)` `:394-395`/`:492-497` — icon via `.controlPlate(fill: feedback.backgroundColor, glyph: .white)` + `.accessibilityLabel`; `CreationFeedback` enum (`SingleThread/CreationFeedback.swift:8-24`) `.success`/`.failure` → checkmark/xmark, green/red, "Task created"/"Task creation failed"; auto-clears after 1 s (`DictationViewModel.swift:63-64`).
- Live dictation transcript `.font(.callout).foregroundStyle(.secondary)` `:397-402`; recording indicator `:468-475` (`mic.fill`, `.controlPlate(fill: .red, ...)`, `.symbolEffect(.pulse)`).

### Styling helpers
- `controlPlate` — `SingleThread/ControlPlateModifier.swift`: 56×56 circle, shadow radius 4, scheme-adaptive plate/glyph (`:6-37`), `extension View.controlPlate(fill:glyph:)` `:39-59`. Used for gear (`ContentView.swift:67-72`), complete/skip/mic/recording/feedback (`:429-436,438-445,456-465,468-475`).
- `BackgroundFade` — `SingleThread/BackgroundFade.swift:5-34`: percent 0-90 step 10, `defaultValue = 50`, `opacity(for:)` = `1 - percent/100`; applied to `BackgroundPhotoLayer` (`ContentView.swift:57-59`).
- `.font(.caption)`/`.foregroundStyle(.secondary)` text convention (complete inventory): card due/recurrence/list/alarm rows (`ReminderCardView.swift:43-44,52-53,59-60,66-67`), notes `.font(.callout)` `:71-72`, dictation error caption+red (`:389-390`), live transcript callout+secondary (`:399-400`). No `.font(.footnote)` anywhere in app/watch sources. Dynamic Type handled globally by `TextSizeModifier` (`TextSizeModifier.swift:7-14`).
- Accessibility `.combine`: `ReminderCardView.swift:80` with explanatory comment `:76-79`.

## Q5: How do iOS UI tests drive the main screen and settings?

### Launch-arg seams
- **`--seed '<json>'`**: parsed by `UITestingSeed.fromLaunchArguments(_:)` (`SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift:24-35`); schema (`SeedPayload` `:73-90`): `reminders:[{title, notes?, priority?}]`, optional `calendars:[String]`, `excludedLists:[String]` (`:78-84`). `SeedPayload.materialize()` `:92-111` builds real `EKReminder`/`EKCalendar` fixtures. Wired in `AppViewModel.makeStore(arguments:)` (`AppViewModel.swift:113-133`): `resetPersistedState()` `:122`, `InMemoryEventStore(reminders:calendars:defaultCalendar:)` `:123-127`, wrapped `ReminderStore(eventStore:loadsReminders:true)` `:128-129`, seeded `excludedListTitles` `:130-131`, returns `usesInMemory: true` `:132` (gates off WatchConnectivity: `:27`).
- **`InMemoryEventStore`** (`SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift:13`): `@MainActor`; reports `.fullAccess` for any authorization query `:37-39`; `fetchReminders` filters `!$0.isCompleted` `:57-80` (synchronous delivery, or offline when `deliverCompletionOffMain`); `save` appends `:87-90`, `remove` deletes `:91-94`; `makeReminder` `:100-113` backs the `--ui-testing` reminder too.
- **`resetPersistedState()`** `UITestingSeed.swift:39-48`: removes every key in `persistedKeys` from **both** `AppGroup.defaults` and `UserDefaults.standard` `:42-45`. `persistedKeys` `:52-70` is a **literal 15-key list** (`skippedReminderIdentifiers`, `excludedListTitles`, `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow`, `showUndatedReminders`, `sortOption`, `enableActionButtons`, `showMicrophoneButton`, `backgroundEnabled`, `allowsLandscape`, `textSize`, `appearanceMode`). **A new persisted key must be appended here manually or it leaks across seeded launches.** Pinned by `UITestingSeedTests.resetPersistedStateClearsBackgroundEnabled` (`SingleThreadTests/UITestingSeedTests.swift:63-68`).
- **`--ui-testing`** (`AppViewModel.swift:136-166`, iOS-only): `--reset-glow-preference` removes `showCompletionGlow` from `.standard` `:143-145`; `UserDefaults.standard.set(true, forKey: "enableActionButtons")` `:146` (pre-sets action-buttons cluster ON); builds empty `InMemoryEventStore` + one deterministic reminder ("Buy groceries", "Don't forget the milk", `priority = 5`) via `makeReminder` `:151-161`; `ReminderStore(eventStore:, loadsReminders: false, reminders:, skippedIDs:, authorizationStatus: .fullAccess)` `:162-165` — `loadsReminders: false` means `start()` no-ops (`ReminderStore.swift:123-133`), no EventKit/TCC prompt. Fallback: `loads = !--ui-testing && !--no-reminders` `:168-171`.
- **`--ui-testing-glow`**: `AppViewModel.swift:98-107` sets `completionGlow.duration = 2.0` (deterministic `waitForExistence`, production 0.50); `ContentView.isGlowUITesting` `:213-217` + `completionGlowOverlay` visibility seam `:480-490` (see Q4).

### Flow patterns (`SingleThreadUITests/SingleThreadUITestsFlows.swift`)
- Helper `launchApp(seedJSON:)` sets `app.launchArguments = ["--seed", seedJSON]` `:18-24`.
- List rendering: `testListShowsSeededReminder` `:31-39` (title + notes static texts); `testEmptyListShowsNoRemindersState` `:42-47`.
- **Skip via swipe-left**: `testSkipAdvancesToNextReminder` `:53-70` — seed two reminders `priority:1`/`priority:9` (sort puts priority 1 first via `ReminderSort.areInIncreasingOrder`), `swipeUp()` `:58`, `app.staticTexts["First"].swipeLeft()` `:60`, tap `app.buttons["Skip"]` `:61-63`, assert "Second". `testSkipAllShowsAllDoneState` `:73-86` → "All Done".
- **Complete via swipe-right**: `testCompleteViaSwipeRemovesReminder` `:90-106` — `staticTexts["Buy groceries"].swipeRight()` `:96`, `app.buttons["Complete"]` `:97-99`, assert "No Reminders".
- Delete via long-press: `testDeleteViaContextMenuRemovesReminder` `:108-125` (`press(forDuration:1.0)` → `buttons["Delete"]`).
- Settings navigation: `testSettingsOpensAndShowsControls` `:126-160` — walks Interface → Reminder → Filtering & Sorting → Privacy sections via static texts, pops via `app.navigationBars.buttons.firstMatch.tap()`.
- About modal: `testAboutModalShowsAttribution` `:163-196` (copyright/version/mailto link).
- Background: `testBackgroundRefreshButtonExists` `:234-257` (`buttons["Refresh wallpaper"]`).
- Code blocks: `testCodeBlocksRenderWithoutBacktickFences` `:259-288` (aggregates `label`s since attributed text exposes no identifiers).
- **`flipToggle(_:target:)`** `:326-344`: finds `toggle.switches.firstMatch`, taps inner control (fallback outer), polls `value` against `target` ("1"/"0") up to 3 rounds with 1 s deadlines; default `target = "0"` (flip off).
- **Two-launch persistence pattern** (comment `:216-223`, `:288-289`): launch → open Settings → assert default switch `value` → `flipToggle` → back (`navigationBars.buttons.firstMatch`) → `Done` (`SettingsView.swift:101`) → `app.terminate()` → **relaunch with `--ui-testing` (NOT `--seed`, which would call `resetPersistedState()` and wipe the key under test)** → reopen sub-view → assert flipped value. Examples: `testBackgroundToggleHidesAndPersistsAcrossRelaunch` `:198-232` (both `.standard` `backgroundEnabled`), `testShowListTogglePersistsAcrossRelaunch` `:290-324` (`AppGroup.defaults` `showList`), `testCompletionGlowTogglePersistsAcrossRelaunch` `:346-372` (first launch adds `--reset-glow-preference`).
- Glow behavior: `testCompletionGlowDoesNotAppearWhenDisabled` `:374-400` (asserts `completionGlowOverlay` never exists); `testCompletionGlowFlashesWhenEnabled` `:401-416` (`waitForExistence(timeout: 3)`).

### Accessibility labels/identifiers tests rely on
- Reminder titles/notes; "No Reminders"/"All Done" (`ContentViewModel.swift:66,73`); Settings rows "Interface"/"Reminder"/"Filtering & Sorting"/"Background"/"About" (`SettingsView.swift:41,54,66,74,91`); pickers "Appearance"/"Text Size"; toggles "Show date"/"Show list"/"Recurrence indicator"/"Reminder alerts"/"Completion glow" (`ReminderSettingsView.swift:24,30,33,41,49`); "Sort By"/"Show undated reminders"/"Excluded Lists" (`FilterSortSettingsView.swift:18,24,36`); `switches["Background"]`/`switches["Show list"]`/`switches["Completion glow"]` (`value` = "1"/"0"); `buttons["Skip"]`/`buttons["Complete"]`/`buttons["Delete"]`/`buttons["Done"]`; `buttons["Complete reminder"]`/`["Skip reminder"]` (`ContentView.swift:429,441`, used by `ActionButtonsUITests.swift:33,41`); identifier `otherElements["completionGlowOverlay"]` (`ContentView.swift:487`, only in a11y tree under `--ui-testing-glow` `:485`).
- **Stale test reference**: flows still drive `staticTexts["Privacy"].tap()` (`:153`) and `navigationBars["Privacy"]` (`:156-158`), but current sources label the row "Privacy Policy" (`SettingsView.swift:86`). Both the rename and the old test string landed in commit `92da977` and the test string was never updated — that section of `testSettingsOpensAndShowsControls` cannot currently match.

### Accessibility audit
- `testAccessibilityAudit` (`SingleThreadUITests/SingleThreadUITests.swift:27-64`): launches `--ui-testing` `:29`; iOS runs `app.performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])`, reduced to `[.sufficientElementDescription, .trait]` when `CI == "true"` `:47-58`; macOS default audit `:60-61`. `runsForEachTargetApplicationUIConfiguration = false` `:14-19`.
- `ActionButtonsUITests.testActionButtonsAccessibilityAudit` (`ActionButtonsUITests.swift:46-68`): same arrangement with the action-buttons cluster present.
- CI: flows via `-only-testing:SingleThreadUITests/SingleThreadUITestsFlows`; audits via `-only-testing:SingleThreadUITests/SingleThreadUITests` + `-only-testing:SingleThreadUITests/ActionButtonsUITests` (`ci.yml:16-17`).

## Q6: What are the unit-test conventions for preferences, settings UI, and the card?

All `SingleThreadTests` use Swift Testing (`import Testing`, `@Test`, `#expect`); no XCTest asserts.

### Preference-struct tests (identical template across all five)
- Unique fixture keys: `let key = "showcompletionglow-test-\(UUID().uuidString)"` (`ShowCompletionGlowPreferenceTests.swift:8`; same in `ShowAlarmsPreferenceTests.swift:8`, `ShowDatePreferenceTests.swift:8`, `ShowListPreferenceTests.swift:8`, `ShowRecurrencePreferenceTests.swift:8`).
- `defer { UserDefaults.standard.removeObject(forKey: key) }` immediately after (`:9` in each file).
- Injected store: `ShowCompletionGlowPreference(defaults: .standard, key: key)` (e.g. `ShowCompletionGlowPreferenceTests.swift:10`) — `.standard` keeps the fixture out of the shared app-group store.
- Missing-key default (default-true: `missingKeyDefaultsToEnabled` `:6-12`; default-false: `missingKeyDefaultsToDisabled` `ShowListPreferenceTests.swift:6-12`) + `setFalseRoundTrips`/`setTrueRoundTrips` in every file; `missingKeyIsNotFalse` guards the nil→false coercion (`ShowDatePreferenceTests.swift:30-36`, `ShowCompletionGlowPreferenceTests.swift:30-36`).
- **`ShowUndatedRemindersPreference` has no dedicated test file** — exercised through `SkippedReminderSyncServiceTests.swift:84,95,132-156` and `WatchSyncPipelineTests.swift:46,66,117,157`.
- Watch-side: `ShowCompletionGlowStateTests.swift:42-46` seeds/asserts a `ShowCompletionGlowPreference(defaults: .standard)` round-trip; suite is `@Suite(.serialized)` because the holder hardcodes the real `.standard` `"showCompletionGlow"` key (`:15-22`).

### Snapshot assertions via `String(describing:)` (all `@MainActor`)
- Convention: render the concrete view, flatten `String(describing: view.body)`, `#expect(description.contains("<label>"))` for expected row labels and `!contains` for removed rows.
- `SettingsViewTests.swift` (`@MainActor struct` `:8-9`): `settingsBindingsCarriesShowCompletionGlow` `:12-18` (bag default + explicit-false round trip); `settingsViewContainsNavigationLinkLabels` `:20-33` (top-level links + Done); `interfaceSettingsViewContainsExpectedRows` `:35-58` (`#if os(iOS)` adds "Allow landscape"/"Show action buttons"); `reminderSettingsViewContainsExpectedRows` `:66-79` (expected `["Show date", "Show list", "Recurrence indicator", "Reminder alerts", "Completion glow"]` — **the row-label test a new settings row must join**); `filterSortSettingsViewContainsExpectedRows` `:81-95`; `backgroundSettingsViewContainsExpectedRows` `:97-115` (async, `makeSeededStore()` `:128-140`, private `SeededFetcher` `:143-160`); `privacySettingsViewContainsExpectedContent` `:117-129`.
- Card snapshots build `ReminderCardView` through a private `makeCard` helper:
  - `ShowDateTests.swift` (`@MainActor` `:9`): `dateRowHiddenWhenShowDateDisabled` `:11-16` proves absence via `!description.contains("FormatStyleStorage")` (how `Text(due, style: .date)` boxes); `dateRowShownWhenShowDateEnabled` `:18-21`; list row by `"Groceries"` `:23-40`; `makeCard(showDate:showList:listName:)` `:44-54`.
  - `ShowAlarmsTests.swift` `:7`: bell row proven by `NamedImageProvider` marker `:12` (rationale `:10-11` — `Image(systemName:)` never prints the symbol name).
  - `ShowRecurrenceTests.swift` `:7`: proven by rendered text `"Weekly"` `:12`.
  - `BackgroundCardTests.swift:34-37` documents why `_ConditionalContent` reflection fails (`:9-16` in `ActionButtonTests.swift`) — those suites assert model seams instead: `viewModel.showsActionButtons` (`ContentViewModel.swift:37-41`), `rowChromeBackground == Color.clear` (`BackgroundCardTests.swift:44-52`), `ReminderCardView.plateFill(for:)` `:54-63`.
- Other snapshot suites: `AboutViewTests.swift:15,31`, `MicrophoneToggleTests.swift:40,67,85,101`, root smoke tests `SingleThreadTests.swift:17,29`.

### View models with injected preferences
- `CompletionGlowTests.makeViewModel` (`CompletionGlowTests.swift:124-137`): private `@MainActor` helper building `ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false, reminders:, skippedIDs:, authorizationStatus: .fullAccess)` + `ContentViewModel(store:, backgroundImage:, speechTranscriber: GlowFakeTranscriber(), showCompletionGlow:)`.
- Pre-set preference fixtures: `glowStaysInactiveWhenPreferenceDisabled` `:47-56` (constructs `ShowCompletionGlowPreference(defaults: .standard, key: "glow-disabled-\(UUID().uuidString)")`, `set(false)`); `glowTriggersWhenPreferenceEnabled` `:59-68` (same with `set(true)`).
- Injection contract: `ContentViewModel.init` defaulted param `ContentViewModel.swift:17`, stored `private let` `:134`, read at trigger `:108-111`.
- Alternative non-injected pattern (live `UserDefaults` reads, no init param): `ActionButtonTests.swift:19-22,30-33,42-45,55-58` (sets `UserDefaults.standard.set(true, forKey: "enableActionButtons")` + `defer removeObject`); same for `"showMicrophoneButton"` (`MicrophoneToggleTests.swift:54-57` etc.) and `"backgroundEnabled"` (`BackgroundCardTests.swift:95-99`). Backing read: `ContentViewModel.swift:37-41`.
- Per-file fake transcribers (each file declares its own `SpeechTranscribing` stub — not shared): `GlowFakeTranscriber` (`CompletionGlowTests.swift:147`), `ActionButtonFakeTranscriber` (`ActionButtonTests.swift:101-123`), `MicToggleFakeTranscriber` (`MicrophoneToggleTests.swift:8-27`).

### Annotations/serialization conventions
- `@Suite(.serialized)` for timing-sensitive/shared-global suites: `ReminderStoreTests.swift:6`, `ResumptionGateTests.swift:12`, `BackgroundImageStoreTests.swift:8`, `EventKitStoringTests.swift:148,278,425`, `UITestingSeedTests.swift:9`, `BackgroundCardTests.swift:43`, `CompletionGlowTests.swift:13,59` (comment `:12`).
- View/view-model suites `@MainActor`: `SettingsViewTests.swift:8`, `ShowDateTests.swift:9`, `ShowAlarmsTests.swift:7`, `ShowRecurrenceTests.swift:7`, `AboutViewTests.swift:11`, `MicrophoneToggleTests.swift:43`, `CompletionGlowTests.swift:13,59`, `BackgroundCardTests.swift:42`, `SingleThreadTests.swift:10`.
- Preference-struct tests deliberately NOT `@MainActor`/serialized — unique fixture keys make parallel `UserDefaults.standard` use safe.
- Timing tests poll for invariants rather than sleeping fixed deadlines: `CompletionGlowTests.swift:28-43` (20 ms sleeps up to 100×).

### Where tests must be added for a new persisted key / `SettingsBindings` property
1. `SettingsBindings` init defaults + property (`SettingsBindings.swift:19-33,52-65`) — asserted via `settingsBindingsCarriesShowCompletionGlow`-style test (`SettingsViewTests.swift:12-18`).
2. Row label: `SettingsViewTests.reminderSettingsViewContainsExpectedRows`' label array (`SettingsViewTests.swift:78-79`) or the applicable sub-view list.
3. Preference struct: a new `Show*PreferenceTests` file mirroring the template (unique key + `defer` cleanup + `.standard` injection + missing-key default ± `missingKeyIsNotFalse` + set round trips).
4. Card row: a `makeCard` snapshot test with a reflection-visible marker (`FormatStyleStorage`/`NamedImageProvider`/rendered text).
5. View-model gating: `makeViewModel`-style defaulted init param + pre-set preference fixture.
6. UI-test reset: append the key to `UITestingSeed.persistedKeys` (`UITestingSeed.swift:52-70`) or it leaks across seeded launches; pattern test `UITestingSeedTests.resetPersistedStateClearsBackgroundEnabled` (`:46-51`). No unit test guards list completeness.
7. `@AppStorage` mirror + `makeSettingsBag()` branch + `.onChange(of: bag.X)` write-back (`ContentView.swift:120-135,499-537`) — currently covered only indirectly via smoke tests (`SettingsViewModelTests.swift:6-26`) and UI flows.

## Cross-Cutting Observations

- **One key per preference, three writers**: every preference value is written by three separate paths that must stay in sync — (a) `@AppStorage(..., store: AppGroup.defaults)` in `ContentView` for settings UI write-backs, (b) `Show*Preference.set(_:)`/`save(_:)` in `SingleThreadCore` for the watch-sync receive path and watch view models, (c) `UITestingSeed.persistedKeys` for test reset. Struct defaults mirror `@AppStorage` defaults mirror bag defaults (verified identical in all 14 cases, Q2).
- **`isEnabled` semantics split by feature**: missing key → `true` for show-date/recurrence/alarms/glow (features that predate the toggle or should default on) vs. `false` for show-list/undated (newer, opt-in) — each choice justified in the struct's doc comment.
- **IOS-only vs synced**: none of the six `Show*Preference`s is iOS-only; all reach the watch via `SkippedReminderSyncService`. iOS-only app preferences live in `.standard` (`allowsLandscape`, `enableActionButtons`, appearance/textSize/microphone/background) and are *not* `Show*Preference` structs.
- **The bag pattern**: `SettingsBindings` is a transient in-memory staging bag (not a store); persistence happens only via the `.onChange` write-backs on the presented `SettingsView`. The bag is rebuilt on every sheet open.
- **Accessibility-first seams**: both the card (`.accessibilityElement(children: .combine)`) and the glow overlay (`accessibilityHidden(!isGlowUITesting)`) treat the a11y tree as the test interface; `--ui-testing-glow` extends the glow duration so the transient overlay is observable.
- **Test dual-track**: unit tests assert logic through injected stores/preferences and `String(describing:)` body snapshots; UI tests assert the same surface through accessibility labels/identifiers with `--seed`/`--ui-testing` seams. Both tracks must be updated in lockstep with any new toggle/row.

## Open Areas

- The stale "Privacy"/"Privacy Policy" UI-test reference (`SingleThreadUITestsFlows.swift:153-158` vs `SettingsView.swift:86`) is documented but not confirmed failing — it depends on XCUITest exact-match subscripting behavior for `NavigationLink` rows.
- The stale duration comment `AppViewModel.swift:104` ("0.25 s") conflicts with `CompletionGlow.swift:27` (0.50 s) — cosmetic only.
- `ShowUndatedRemindersPreference`'s `load()`/`save(_:)` API diverges from the `isEnabled`/`set(_:)` family; no dedicated unit-test file exists for it (coverage via sync-service tests only).
- Whether swipe actions can be triggered with `XCUIElement.press(forDuration:)`-style gestures other than `swipeLeft()`/`swipeRight()` is untested; existing tests only use the two swipe directions plus long-press context menu.
- Row-height growth behavior with `bottomBar` overlap for very tall cards (large Dynamic Type + long notes) is not covered by any test.
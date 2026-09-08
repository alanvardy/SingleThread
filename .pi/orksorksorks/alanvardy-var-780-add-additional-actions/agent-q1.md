# Q1 — Toggle-style settings: end-to-end wiring (SingleThread repo)

Every claim below was verified by reading the cited lines.

## 1. The two storage tiers

### 1a. `AppGroup.defaults` — the shared App Group suite
- `SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:8` — `public enum AppGroup`, suite name `"group.app.alanvardy.SingleThread"` (`:11`).
- `AppGroup.defaults` is a computed property: `UserDefaults(suiteName: suiteName) ?? .standard` (`:15-19`). So on watchOS / unregistered simulators / previews it transparently falls back to `.standard`.
- Doc comment (`:3-7`) lists the shared keys: `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow`, `showUndatedReminders`, `sortOption` plus store payloads.

### 1b. `@AppStorage` declarations split by store
All in `SingleThread/ContentView.swift` (verified lines):

- `appearanceMode` — default (`.standard`) — `ContentView.swift:72-73`
- `textSize` — default (`.standard`) — `ContentView.swift:75-76`
- `allowsLandscape` (iOS) — default (`.standard`) — `ContentView.swift:79-80`
- `showMicrophoneButton` — default (`.standard`) — `ContentView.swift:83-84`
- `backgroundEnabled` — **explicit `.standard`** — `ContentView.swift:86-87`
- `backgroundFadePercent` — **explicit `.standard`** — `ContentView.swift:89-90`
- `backgroundPinned` — **explicit `.standard`** — `ContentView.swift:92-93`
- `enableActionButtons` (iOS) — default (`.standard`) — `ContentView.swift:96-97`
- `showSwipePrompt` (iOS) — default (`.standard`) — `ContentView.swift:101-102`
- `showUndoButton` (iOS) — default (`.standard`) — `ContentView.swift:106-107`
- `notificationsEnabled` (iOS) — default (`.standard`) — `ContentView.swift:109-110` (key = `AppViewModel.NotificationKeys.enabled`, defined `SingleThread/AppViewModel.swift:98-101`)
- `notificationIntervalHours` (iOS) — default (`.standard`) — `ContentView.swift:112-113` (key = `NotificationKeys.intervalHours`, `AppViewModel.swift:102`)
- `showUndatedReminders` — **`AppGroup.defaults`** — `ContentView.swift:115-116`
- `sortOption` — **`AppGroup.defaults`** — `ContentView.swift:118-119` (key = `SortOption.defaultsKey`, `SingleThreadCore/Sources/SingleThreadCore/SortOption.swift:18`)
- `showDate` — **`AppGroup.defaults`** — `ContentView.swift:121-122`
- `showList` — **`AppGroup.defaults`** — `ContentView.swift:124-125`
- `showRecurrence` — **`AppGroup.defaults`** — `ContentView.swift:127-128`
- `showAlarms` — **`AppGroup.defaults`** — `ContentView.swift:129-130`
- `showCompletionGlow` — **`AppGroup.defaults`** — `ContentView.swift:132-133`

Note: `@AppStorage("x")` without a `store:` parameter uses `UserDefaults.standard`; the Interface set (`allowsLandscape`, `showMicrophoneButton`, `enableActionButtons`, `showSwipePrompt`, `showUndoButton`), the notifications pair, and the background trio live in `.standard`, while the widget-sharing preference set lives in `AppGroup.defaults`.

## 2. The typed preference structs (SingleThreadCore)

Six structs, all in `SingleThreadCore/Sources/SingleThreadCore/`, all defaulting to `AppGroup.defaults` with the key literal matching the `@AppStorage` key:

- `ShowDatePreference.swift:8` — `public struct ShowDatePreference`, init `defaults: UserDefaults = AppGroup.defaults, key: String = "showDate"` (`:11-12`). `isEnabled` = `defaults.object(forKey: key) as? Bool ?? true` (`:16-19`); `set(_:)` (`:21-23`). Missing key resolves to `true` (doc `:4-6`).
- `ShowCompletionGlowPreference.swift:8` — same shape, key `"showCompletionGlow"`, missing key → `true` (`:11-19`).
- `ShowListPreference.swift:8` — key `"showList"`, missing key → `false` (doc `:6`).
- `ShowRecurrencePreference.swift:8` — missing key → `true` (doc `:5`).
- `ShowAlarmsPreference.swift:8`.
- `ShowUndatedRemindersPreference.swift:6` — the load/save pair (`load()`, `save(_:)`); consumed as `ShowUndatedRemindersPreference(defaults: .standard).load()` on watch (`SingleThreadWatch/WatchAppViewModel.swift:34`).

Default-arg context: `SkippedReminderSyncService.swift:32-37` declares all six as `= XPreference()` (i.e. `AppGroup.defaults`), and `AppViewModel.swift:33-36` passes `ShowDatePreference()` / `ShowRecurrencePreference()` / `ShowAlarmsPreference()` / `ShowCompletionGlowPreference()` explicitly.

The typed structs and the `@AppStorage` properties are **two readers of the same underlying keys**: e.g. `ContentView.swift:121-122` (`@AppStorage("showDate", store: AppGroup.defaults)`) and `ShowDatePreference` defaulting to `AppGroup.defaults` point at the same storage cell.

## 3. The snapshot bag: `SettingsBindings`

`SingleThread/SettingsBindings.swift`:
- `@MainActor @Observable final class SettingsBindings` (`:18-19`), owned by `SettingsView` (init `SettingsView.swift:11-20`), passed down as `@Bindable` (`SettingsView.swift:35`).
- 19 stored properties, plain Swift values mirroring the `@AppStorage` defaults (`:64-83`; init defaults `:21-40`).
- Not in the bag: `excludedLists` — store-backed, passed separately as `Binding<Set<String>>` (doc `:6-8`, also `SettingsView.swift:24, 33`).
- Compiler-`#if` note: iOS-only preferences are declared unconditionally with ContentView defaults; unused on macOS (doc `:10-15`).

## 4. The Interface section: SettingsView → InterfaceSettingsView

`SingleThread/SettingsView.swift`:
- "Interface" `NavigationLink` builds `InterfaceSettingsView` with **seven** bindings on iOS (`:37-45`: `appearanceMode`, `textSize`, `allowsLandscape`, `showMicrophoneButton`, `enableActionButtons`, `showSwipePrompt`, `showUndoButton`) plus `viewModel:`; on macOS only **three** (`:47-51`: `appearanceMode`, `textSize`, `showMicrophoneButton`).
- "Reminder" `NavigationLink` builds `ReminderSettingsView` with the five display toggles (`:74-80`: `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow`) plus `viewModel:`.
- The bag is applied at the root: `.modifier(TextSizeModifier(textSize: bindings.textSize))` (`SettingsView.swift:164`).

`SingleThread/InterfaceSettingsView.swift` (verified lines):
- `Picker` Appearance, `$appearanceMode`, id `appearancePicker` (`:35-46`).
- `Picker` Text Size, `$textSize`, id `textSizePicker` (`:47-58`).
- Toggle "Allow landscape" (iOS), `$allowsLandscape` (`:60-69`), id `allowLandscapeToggle` (`:70`), **only direct `.onChange` in the Interface screen** → `viewModel.allowsLandscapeChanged(newValue)` (`:71-73`).
- Toggle "Show microphone", `$showMicrophoneButton` (`:75-84`), id `showMicrophoneToggle` (`:85`), no `.onChange`.
- Toggle "Show action buttons" (iOS), `$enableActionButtons` (`:87-96`), id `showActionButtonsToggle` (`:97`), no `.onChange`.
- Toggle "Show swipe prompt" (iOS), `$showSwipePrompt` (`:98-107`), id `showSwipePromptToggle` (`:108`), no `.onChange`.
- Toggle "Show undo button" (iOS), `$showUndoButton` (`:110-119`), id `showUndoButtonToggle` (`:120`), no `.onChange`.

Observed pattern — Interface toggles are **pure bindings** (sole exception: landscape). Side effects and reads happen elsewhere:
- `enableActionButtons` is re-read from `UserDefaults.standard.bool(forKey: "enableActionButtons")` on demand by `ContentViewModel.showsActionButtons` (`SingleThread/ContentViewModel.swift:57-60`; iOS-only `:52`), gated additionally on `store.visibleReminders.first != nil`, and drives action-cluster vs mic (`ContentView.swift:686`).
- `showMicrophoneButton` gates the mic in the bottom bar (`ContentView.swift:680`, `:696`).
- `showUndoButton` gates the undo overlay (`ContentView.swift:202`).
- `showSwipePrompt` feeds `ReminderCardView` via `swipePromptBinding` (`ContentView.swift:320-326`); the prompt Dismiss button writes `false` back through the binding (`ReminderCardView.swift:186`).

`SingleThread/ReminderSettingsView.swift` (verified):
- Toggle `showDate` (`:23-33`), `.onChange(of: showDate)` → `viewModel.showPreferenceChanged()` (`:35-37`, gated `#if os(iOS) || os(macOS)` `:34`).
- Toggle `showList` (`:39-49`), **no `.onChange`**.
- Toggle `showRecurrence` (`:50-60`), `.onChange` → `viewModel.showPreferenceChanged()` (`:62-64`).
- Toggle `showAlarms` (`:66-76`), `.onChange` → `viewModel.showPreferenceChanged()` (`:78-80`).
- Toggle `showCompletionGlow` (`:82-92`), **no `.onChange`**.

## 5. The writeback chain: ContentView+Settings.swift

`SingleThread/ContentView+Settings.swift`:
- `settingsSheetWritebacks(_ bag:)` (`:9-46`) wraps `SettingsView` and adds `.onChange(of: bag.<prop>) { _, new in <prop> = new }` for every bag value:
  - always: `appearanceMode`, `textSize` (`:19-20`);
  - iOS-only block: `allowsLandscape`, `enableActionButtons`, `showSwipePrompt`, `showUndoButton`, `notificationsEnabled`, `notificationIntervalHours` (`:23-28`); macOS gets an empty `withIOSPreferences` alias (`:29`);
  - common tail: `showMicrophoneButton`, `backgroundEnabled`, `backgroundFadePercent`, `backgroundPinned`, `showUndatedReminders`, `sortOption`, `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow` (`:31-41`).
- Because the `@AppStorage` properties themselves persist to `.standard`/`AppGroup.defaults`, persistence happens on writeback; the chain also re-renders ContentView reactively.
- Doc comment (`:3-6`): chain split into staged locals to stay within the type-check budget.
- `makeSettingsBag()` (`:49-85`) snapshots current `@AppStorage` values into a fresh `SettingsBindings` (iOS branch `:51-76`, macOS branch `:77-84`).
- Note `ContentView+Settings.swift:14` passes `viewModel: SettingsViewModel()` (a fresh instance per sheet open; `SettingsView.swift:20` has its own `viewModel: SettingsViewModel()` default).

## 6. Sheet lifecycle (when the chain runs)

`SingleThread/ContentView.swift`:
- Gear button action: `settingsBag = makeSettingsBag(); isShowingSettings = true` (`:186-187`).
- `.sheet(isPresented: $isShowingSettings) { settingsSheetContent }` (`:267-268`); `settingsSheetContent` guards `if let bag = settingsBag` then wraps `settingsSheetWritebacks(bag)` (`:597-599`; macOS min frame `:602-603`).
- Bag nilled on dismiss via `.onChange(of: isShowingSettings)` (`:259-266`) so a fresh snapshot is taken on each open. Bag is `@State private var settingsBag: SettingsBindings?` (`:304`).

## 7. Side effects: SettingsViewModel and widget reload

`SingleThread/SettingsViewModel.swift` (verified):
- `allowsLandscapeChanged(_:)` — iOS-only (`:12-16`), calls `AppDelegate.applyLock(allowsLandscape:)` (`:14`).
- `showPreferenceChanged()` — iOS+macOS (`:18-23`), calls `WidgetCenter.shared.reloadAllTimelines()` (`:22`). `import WidgetKit` gated (`:2-4`).
- Fired only from `ReminderSettingsView` `.onChange` on `showDate` (`:35-37`), `showRecurrence` (`:62-64`), `showAlarms` (`:78-80`). **`showList` and `showCompletionGlow` have no widget-reload hook** (verified: no `.onChange` clauses on those toggles).

## 8. The AppGroup → watch sync side effect (does not touch the sheet)

Because the shared keys live in `AppGroup.defaults`, a settings change also feeds watch sync without a sheet-side hook:
- `AppViewModel.swift:88` — `#if os(iOS) setupSyncObservation()` inside init.
- `setupSyncObservation()` (`:418-431`) registers a `NotificationCenter` observer on `UserDefaults.didChangeNotification` scoped to `object: AppGroup.defaults`, calling `handlePreferencesChanged()` (`:419-425`).
- `handlePreferencesChanged()` (`:432-450`) reads `ShowDatePreference().isEnabled`, `ShowRecurrencePreference()`, `ShowAlarmsPreference()`, `ShowListPreference()`, `ShowCompletionGlowPreference()` (`:433-437`), diffs against last-seen values (`:438-442`), updates the cache (`:443-447`), and calls `syncService?.pushAll()` (`:448`). Last-seen properties at `:453-457`.
- Phone-side `SkippedReminderSyncService` is constructed with the AppGroup-defaulted preference stores (`AppViewModel.swift:31-37`); store-mutation hooks also call `pushAll()` (`:60-62` for `onSkipSetChanged`/`onShowUndatedRemindersChanged`/`onExcludedListsChanged`, `:71-73` for `onSortOptionChanged`; `syncService = service` at `:59`).
- Watch side reads the same structs pinned to `.standard`: `WatchAppViewModel.swift:166-171`; standalone `@Observable` state holders `ShowDateState.swift:28`, `ShowListState.swift:28`, `ShowRecurrenceState.swift:28`, `ShowAlarmsState.swift:28`, `ShowCompletionGlowState.swift:27` all hold `XPreference(defaults: .standard)` with `isEnabled` + `apply(_:)`. Watch-side glow consumed via `WatchAppViewModel.swift:40` and triggered in `WatchReminderViewModel.swift:89`.

## 9. Consumers of the display preferences

- `showDate` / `showList` / `showRecurrence` / `showAlarms` flow to the card: `ContentView.swift:432-435` → `ReminderCardView` (`ReminderCardView.swift:15-18`, rendered `:90` showDate, `:96` showRecurrence, `:108` showList, `:115` showAlarms).
- `showCompletionGlow` gates the green flash at mutation time: `ContentViewModel.swift:136-139` (`if await store.completeCurrentReminder(), showCompletionGlow.isEnabled { completionGlow.trigger() }`); live preference read (doc `:216-217`); overlay `CompletionGlow()` at `ContentViewModel.swift:50`, rendered `ContentView.swift:221`, definition `:581-591`, a11y exposure under `--ui-testing-glow` (`:314-316`, seed/reset in `AppViewModel.swift:286-291`).
- Widget reads same AppGroup-defaulted structs: `NextThingWidget.swift:57-60` (`ShowDatePreference().isEnabled`, `ShowListPreference()`, `ShowRecurrencePreference()`, `ShowAlarmsPreference()`); undated direct `AppGroup.defaults.bool(forKey: "showUndatedReminders")` (`:62`). **Widget does not read `showCompletionGlow` (verified: no match in `SingleThreadWidget/`)**.

## 10. Closest exemplar toggles

- Existing toggle with complete chain (binding → bag → writeback → live re-read): **`enableActionButtons`** — `@AppStorage` (`ContentView.swift:96-97`); bag property (`SettingsBindings.swift:67`, default `false` `:25`); toggle (`InterfaceSettingsView.swift:87-97`, wired `SettingsView.swift:42`); write-back `.onChange` (`ContentView+Settings.swift:24`); live re-read (`ContentViewModel.swift:57-60`).
- Pure-binding toggles, no `.onChange`: `showMicrophoneButton`, `showSwipePrompt`, `showUndoButton` (prompt Dismiss writes through binding, `ReminderCardView.swift:186`).
- Toggle with widget-reload `.onChange` (only in `ReminderSettingsView`, not Interface): `showDate`.

## 11. Verified absences

- No `ShowCompletionGlowPreference` / `showCompletionGlow` usage inside `SingleThreadWidget/` (no match).
- No `.onChange` side effect on `showMicrophoneButton`, `enableActionButtons`, `showSwipePrompt`, `showUndoButton` in `InterfaceSettingsView.swift` (only `allowsLandscape`, `:71-73`).

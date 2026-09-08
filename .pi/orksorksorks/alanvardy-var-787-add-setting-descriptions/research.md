# Research Findings

All paths relative to repo root. Line numbers verified against the working tree.

## Q1: How the settings screens structure their `List`/`Section`/`Form` rows, platform gates, and section header/footer text

### Navigation shape
- `SettingsView` is a `NavigationStack > List > 2 Sections` (`SingleThread/SettingsView.swift:32-34`, second `Section` at :112) presented as a sheet: gear button sets `isShowingSettings = true` (`ContentView.swift:163-165`), sheet at `ContentView.swift:243-244`; sheet content = `settingsSheetWritebacks(SettingsView(...))` (`ContentView+Settings.swift:11-13`).
- 8 root rows, each `NavigationLink { destination } label: { Label("…", systemImage:) }`: Interface :35, Notifications :58, Reminder :67, Filtering & Sorting :79, Background :89, Purchase :99, Privacy Policy :113, About :119. Nested push: `FilterSortSettingsView.swift:30` → `ExcludedListsView`. Separate sheet: `PurchaseSheet` (NavigationStack-wrapped, `PurchaseSettingsView.swift:203-213`) from `ContentView.swift:246-249`.

### Containers per screen (all `Form` except two `List`s)
| Screen | Container | Rows |
|---|---|---|
| SettingsView | List (:32-34) | 8 NavigationLinks + Done toolbar button :132 |
| InterfaceSettingsView | Form (:34) | Picker("Appearance") :35, Picker("Text Size") :42, Toggles :50/:58/:63/:67/:71 |
| NotificationsSettingsView | Form (:12) | Toggle :13, Picker (24/48/72h) :17 |
| ReminderSettingsView | Form (:22) | 5 Toggles :23/:32/:36/:45/:54 |
| FilterSortSettingsView | Form (:19) | Picker :20, Toggle :26, NavigationLink :30 |
| ExcludedListsView | Form (:19) | Toggle per list :22 |
| BackgroundSettingsView | Form (:19) | Toggle :20, Picker :24, Toggle :31, Button :37 |
| PurchaseSettingsView | List (:18) | conditional content :19-37, Button :41/:84/:102 |
| PrivacySettingsView | Form (:10) | Text per PrivacyGuideContent.sections :13 |
| AboutView | Form (:22) | Label :24, Text :27-29, Link/Text :33/:35 |

### `#if os(...)` gating
- **SettingsView**: Notifications row only — `#if os(iOS)` :57-66. Interface destination splits constructor arg lists: `#if os(iOS)` :36 / `#elseif os(macOS)` :48 / `#endif` :53.
- **InterfaceSettingsView**: `allowsLandscape` binding decl :13-15, `enableActionButtons` :19-21, `showSwipePrompt` :23-25, `showUndoButton` :27-29; body gates :49-57 (landscape + onChange :54-56) and :62-75 (3 toggles); `#Preview` :85 / `#else` :101.
- **ReminderSettingsView**: `#if os(iOS) || os(macOS)` onChange reloads :27-31, :40-44, :49-53.
- **ContentView+Settings.swift**: iOS-only writebacks :21 / `#elseif os(macOS)` :29; `makeSettingsBag` iOS 19 props :50-73 vs macOS 13 props :75-99.
- **NotificationsSettingsView / FilterSortSettingsView / BackgroundSettingsView / PurchaseSettingsView / PrivacySettingsView / ExcludedListsView**: no gates in-file (Notifications reachability gated only at the root row; doc comment `NotificationsSettingsView.swift:4`).

### Section headers/footers (current state)
- **Root SettingsView sections are headerless today** — `Section {` at :34 and :112 with no `header:`/`footer:` closures; only `.navigationTitle("Settings")` :129. A per-section caption would be placed as a new `header:` (or `footer:`) argument on either `Section`.
- **Headerless elsewhere**: `FilterSortSettingsView.swift:29`; `BackgroundSettingsView.swift:30, 36`; `AboutView.swift:23, 26`; `ExcludedListsView.swift:20`.
- **With headers**: `PurchaseSettingsView.swift:26-27` `Section { … } header: { Text("Unlock SingleThread") }`; `PrivacySettingsView.swift:12` `Section(section.title)` (titles from `PrivacySettingsContent.swift:61-82`).
- **With footers**: ExcludedListsView :26-27 `"Excluded lists are hidden from the reminder list."`; BackgroundSettingsView :55-66 photo credit `"Photo by \(photographer) on Unsplash"` as `Link`/`Text`; PurchaseSettingsView :28-38 (3-branch conditional) + :50-51 restore hint; PrivacySettingsView :16-17 `closingLine` "SingleThread has no analytics, no tracking, and no advertising." (`PrivacySettingsContent.swift:55`); AboutView :31-36 mail `Link`.
- **Styling: none on section chrome.** No `.textCase`, `.headerProminence`, or `.font` on any header/footer; the only footer-adjacent modifier in the settings UI is `.foregroundStyle(.red)` on the Purchase load-error footer (`PurchaseSettingsView.swift:33`).

## Q2: Exact inventory of every setting row → control → binding → `@AppStorage` key

### Wiring pattern (all screens share it)
- `SettingsBindings` (`SettingsBindings.swift:29-83`) is an in-memory `@MainActor @Observable` bag of 19 properties; defaults mirror ContentView's `@AppStorage` defaults exactly (doc :20-26 — iOS-only props declared unconditionally, harmless on macOS). No `@AppStorage` on the bag.
- Write-back: `.onChange(...)` chains in `settingsSheetWritebacks()` (`ContentView+Settings.swift:14-44`) assign each bag property to the matching `@AppStorage` property on `ContentView`. Bag built fresh on sheet open via `makeSettingsBag()` (`ContentView+Settings.swift:46-99`).
- `excludedLists` is **not** in the bag — store-backed `Binding<Set<String>>` (`SettingsBindings.swift:6-9`, `SettingsView.swift:18-19`, `ContentView.swift:137-142`).
- All 19 backing `@AppStorage` keys live on `ContentView` at `ContentView.swift:72-133`. Suites: `.standard` (no `store:` or `store: .standard`); App Group = `UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard` (`SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:8, 13-15`).

### `@AppStorage` key table (backing every row)
| key | suite | gating | line |
|---|---|---|---|
| `"appearanceMode"` | standard | — | ContentView.swift:72-73 |
| `"textSize"` | standard | — | :75-76 |
| `"allowsLandscape"` | standard | iOS | :79-80 |
| `"showMicrophoneButton"` | standard | — | :83-84 |
| `"backgroundEnabled"` | standard | — | :86-87 |
| `"backgroundFadePercent"` | standard | — | :89-90 |
| `"backgroundPinned"` | standard | — | :92-93 |
| `"enableActionButtons"` | standard | iOS | :96-97 |
| `"showSwipePrompt"` | standard | iOS | :101-102 |
| `"showUndoButton"` | standard | iOS | :106-107 |
| `"notificationsEnabled"` | standard | iOS | :109-110 |
| `"notificationIntervalHours"` | standard | iOS | :112-113 |
| `"showUndatedReminders"` | **App Group** | — | :115-116 |
| `"sortOption"` (`SortOption.defaultsKey`, `SortOption.swift:18`) | **App Group** | — | :118-119 |
| `"showDate"` | **App Group** | — | :121-122 |
| `"showList"` | **App Group** | — | :124-125 |
| `"showRecurrence"` | **App Group** | — | :127-128 |
| `"showAlarms"` | **App Group** | — | :129-130 |
| `"showCompletionGlow"` | **App Group** | — | :132-133 |

Key literals: `AppViewModel.NotificationKeys` (`AppViewModel.swift:96-100`), `SortOption.defaultsKey` (`SortOption.swift:18`), `BackgroundFade.defaultValue` (`ContentView.swift:90`).

### Row inventory by screen
**Root — SettingsView (List)**: row label → a11y id → control → binding.
| label | a11y id | control→destination | binding | gating |
|---|---|---|---|---|
| "Interface" :54 | `settingsInterfaceRow` :56 | NavLink→InterfaceSettingsView :35-53 | 7 iOS / 3 macOS bindings | dest splits per-OS |
| "Notifications" :63 | `settingsNotificationsRow` :65 | NavLink→NotificationsSettingsView :58-65 | notificationsEnabled, notificationIntervalHours | row `#if os(iOS)` :57-66 |
| "Reminder" :76 | `settingsReminderRow` :78 | NavLink→ReminderSettingsView :67-77 | 5 show-* props | — |
| "Filtering & Sorting" :86 | `settingsFilterSortRow` :88 | NavLink→FilterSortSettingsView :79-87 | sortOption, showUndatedReminders, excludedLists | — |
| "Background" :96 | `settingsBackgroundRow` :98 | NavLink→BackgroundSettingsView :89-97 | 3 background props | — |
| "Manage Purchase"/"Unlock" :102-104 | `settingsPurchaseRow` :108 | NavLink→PurchaseSettingsView :99-108 | none (entitlementStore) | — |
| "Privacy Policy" :116 | `settingsPrivacyRow` :118 | NavLink→PrivacySettingsView :113-118 | none | — |
| "About" :122 | `settingsAboutRow` :125 | NavLink→AboutView :119-126 | none | — |
| "Done" :132 | `settingsDoneButton` :135 | Button→dismiss | — | — |

**InterfaceSettingsView (Form)**: "Appearance" :35 `appearancePicker` :41 Picker→appearanceMode; "Text Size" :42 `textSizePicker` :48 Picker→textSize; "Allow landscape" :51 `allowLandscapeToggle` :53 Toggle→allowsLandscape (+`SettingsViewModel.allowsLandscapeChanged`, `SettingsViewModel.swift:13-15`) iOS :49-56; "Show microphone" :59 `showMicrophoneToggle` :61 Toggle→showMicrophoneButton; "Show action buttons" :64 `showActionButtonsToggle` :66 Toggle→enableActionButtons iOS :62-75; "Show swipe prompt" :68 `showSwipePromptToggle` :70 Toggle→showSwipePrompt iOS; "Show undo button" :72 `showUndoButtonToggle` :74 Toggle→showUndoButton iOS.

**NotificationsSettingsView (Form, iOS-only reachable)**: "Enable reminder notifications" :13 `notificationsEnabledToggle` :16 Toggle→notificationsEnabled; "Remind after" :17 `notificationIntervalPicker` :23 Picker(.menu) tags 24/48/72 :19-21→notificationIntervalHours.

**ReminderSettingsView (Form)**: "Show date" :23 `showDateToggle` :26→showDate (+WidgetCenter reload :27-30); "Show list" :32 `showListToggle` :35→showList; "Recurrence indicator" :36 `showRecurrenceToggle` :39→showRecurrence (+reload :41-44); "Reminder alerts" :45 `showAlarmsToggle` :48→showAlarms (+reload :50-53); "Completion glow" :54 `showCompletionGlowToggle` :57→showCompletionGlow (label from `SharedStrings.completionGlow`, `LocalizedString+Shared.swift:36-38`).

**FilterSortSettingsView (Form)**: "Sort By" :20 Picker→sortOption (no id); "Show undated reminders" :26-27 Toggle→showUndatedReminders (no id); "Excluded Lists" :35 NavLink→ExcludedListsView :30-36 (no id).

**ExcludedListsView (Form)**: one Toggle per list `Text(list)` :23, no ids; binding via `excludedBinding(for:)` :37-43 on the store-backed `excludedLists` `Binding` (NOT @AppStorage, sourced from `viewModel.store.excludedListTitles`, `ContentView.swift:137-142`).

**BackgroundSettingsView (Form)**: "Background" :21 `backgroundToggle` :23→backgroundEnabled; "Background Fade" :24 `backgroundFadePicker` :29 Picker→backgroundFadePercent (`BackgroundFade.allValues`); "Pin wallpaper" :32 `pinWallpaperToggle` :34→backgroundPinned (own Section :30-35); "Refresh wallpaper" :41 `refreshWallpaperButton` :53→`backgroundImage.forceRefresh()` :37-51, disabled while refreshing :46, a11yValue "Refreshing" :49-51; Unsplash credit footer :58-67.

**PurchaseSettingsView (List)**: "You're all set! 🎉" :21 (entitled); product row :94-118 with "Try Again" :84, name :95, desc :97, price Button :99-112, ProgressView :107; "Loading…" :127; "Restore Purchases" :45 `restorePurchasesButton` :49→`entitlementStore.sync()` :43-49 (unentitled only :42).

**PrivacySettingsView (Form)** — stateless; sections from `PrivacyGuideContent.sections` :12-16, closing footer :17-19; zero bindings/ids. **AboutView (Form)** — app name Label :24; "Copyright 2026 Alan Vardy" :27; "Made with love by a lone developer" :28; version :29-30; footer mail Link :34-37; zero bindings/ids.

Pattern: every persisted row binds to exactly one of the 19 keys via bag + `.onChange`; only `excludedLists` escapes the bag. Platform flow: iOS bag 19 props, macOS 13 (`ContentView+Settings.swift:50-73` / :75-99).

## Q3: Time-based constants and number-into-localized-string formatters

### Background rotation period
- **No user-facing rotation constant exists.** Internal only: `private static let defaultMaxAge: TimeInterval = 86400` — `SingleThread/BackgroundImageStore.swift:177`. TimeInterval (Double), **seconds** (86400 = 24h; doc :110-111), `private`. Sole use: default arg of `refreshIfNeeded(maxAge:)` :98; staleness in `isFresh(maxAge:)` :228-233.
- Rotation controls are only: Pin `@AppStorage("backgroundPinned")` default false (`ContentView.swift:92-93`) → "Pin wallpaper" toggle (`BackgroundSettingsView.swift:31`); manual refresh button :37-38. **No interval picker.** `defaultMaxAge` is not referenced by any view.
- Fade is a separate `Int` percent pref `BackgroundFade` (`BackgroundFade.swift:15-22`, `defaultValue = 50`, picker `BackgroundSettingsView.swift:24-29`), not a time value.

### Notification-interval hours
- Stored pref: `@AppStorage(AppViewModel.NotificationKeys.intervalHours)` `private var notificationIntervalHours = 48` — `ContentView.swift:112-113` (inside `#if os(iOS)` :95). Type `Int`, units **hours**, default **48**.
- Key constant: `enum NotificationKeys` `internal` (no modifier), `static let intervalHours = "notificationIntervalHours"` — `AppViewModel.swift:96-99`, `#if os(iOS)` guarded.
- Bag mirror: `SettingsBindings.swift:29` init default `48`, stored prop :71; writeback `.onChange(of: bag.notificationIntervalHours)` `ContentView+Settings.swift:28`.
- Picker uses **fixed literals, not derived from a constant**: `Text("24 hours").tag(24)` / `48` / `72` — `NotificationsSettingsView.swift:17-21`.
- Hours→seconds conversion lives in the scheduler: `intervalHours > 0 ? intervalHours : 48` then `Double(effectiveHours * 3600)` — `AppViewModel.swift:138-144` (inline `48` fallback duplicates the @AppStorage default).

### Number-into-localized-string pattern
**Established pattern: `String(localized:table:bundle:)` with Swift string interpolation; `String(format:` has zero matches in the repo.** Interpolations compile to `String.LocalizationValue`; catalogs store them as `%lld`/`%@` keys with plural variations.
- `ReminderRecurrenceFormatter` — `SingleThreadCore/Sources/SingleThreadCore/ReminderRecurrenceFormatter.swift:10-34`; `public nonisolated enum`, `format(_ rules: [EKRecurrenceRule]?) -> String?`. Pattern :16-19:
  ```swift
  case .daily:
      return interval > 1
          ? String(localized: "Every \(interval) days", table: "Localizable", bundle: .module)
          : String(localized: "Daily", table: "Localizable", bundle: .module)
  ```
  Weeks/months/years same shape :21-32. Plural keys in Core catalog: `"Every %lld days"` :373, `"Every %lld weeks"` :575, `"Every %lld months"` :474, `"Every %lld years"` — `one`/`other` variants.
- `SharedStrings.priorityAccessibilityLabel(_ levelName: String)` — `LocalizedString+Shared.swift:72-74` — `String(localized: "\(levelName) priority", table: "Localizable", bundle: .module)`.
- `AppInfo.versionDescription` — `AppInfo.swift:44-52` — `String(localized: "Version \(marketing) (\(build))", …)`.
- Notification body with Int count — `AppViewModel.swift:131-135`: `String(localized: "You have \(count) reminders waiting — open SingleThread!", table: "Localizable", bundle: .main)`; plural `one`/`other` at App catalog `Localizable.xcstrings:3120`.
- SwiftUI `Text` interpolation (same catalog mechanism, no explicit lookup): `Text("\(percent)%").tag(percent)` `BackgroundSettingsView.swift:26` → key `"%lld%%"` (`Localizable.xcstrings:4`).
- Other app-target Style B: `SortOption+Presentation.swift:12-14`, `TextSize.swift:41-46`, `AppearanceMode.swift:69-72`, `ReminderCardView.swift:104`, `CreationFeedback.swift:29-30`.
- Test-side confirmation: `SingleThreadTests/ReminderRecurrenceFormatterTests.swift:19-20` asserts `== String.en("Every 2 days", bundle: .core)` (locale-pinned helper `LocalizationTestHelpers.swift:4-11`).

## Q4: String declaration, styling, and localization across the settings UI

### Two coexisting styles
- **Style A (dominant)**: SwiftUI literals `Text("…")` / `Label("…", systemImage:)` — auto-localized via `LocalizedStringKey` against the host target's main-bundle catalog. Nearly all settings rows: SettingsView :54/:63/:76/:86/:96/:116/:122, nav title :129, Done :132; InterfaceSettingsView :35/:42/:51/:59/:64/:68/:72; ReminderSettingsView :24/:33/:37/:46; NotificationsSettingsView; FilterSortSettingsView :20/:27/:35/:39; BackgroundSettingsView :21/:24/:33/:40; PurchaseSettingsView :20/:27/:45/:58/:94/:136; AboutView :27/:28/:38.
- **Style B**: explicit `String(localized:table:bundle:)` when a `String` value is needed (a11y values, interpolation, prose helpers) — always pinned `table: "Localizable"` + `bundle: .main` (app/watch/widget) or `.module` (Core). Settings examples: BackgroundSettingsView :48-51 ("Refreshing" a11yValue) and :52-58 ("Photo by \(photographer) on Unsplash" → key `"Photo by %@ on Unsplash"`, App catalog :1398); PrivacySettingsView via helper `localized(_:)` = `String(localized: String.LocalizationValue(stringLiteral: key), table: "Localizable", bundle: .main)` (`PrivacySettingsContent.swift:64-71`), invoked :26-55.
- **Not localized at all**: Purchase runtime error strings stored in `@State`, not catalog lookups: `loadError = "Product not available."` `PurchaseSettingsView.swift:163-165`, displayed via `Label(error, …)` :90. StoreKit `product.displayName/description/displayPrice` are framework-localized data :106-107/:114.
- Watch/widget (context): all Core keys go through `SharedStrings.*` accessors (`LocalizedString+Shared.swift:9-73`, `bundle: .module`); widget uses `LocalizedStringResource("Next Thing", table: "Localizable", bundle: .main)` `NextThingWidget.swift:122-127`.

### Footer rendering/styling (exact)
- All rely on default `Form`/`List` footer styling (footnote, secondary); **no explicit `.font(.footnote)` anywhere**.
- ExcludedListsView :20-28: `Section { ForEach … Toggle … } footer: { Text("Excluded lists are hidden from the reminder list.") }` — plain Text.
- BackgroundSettingsView :55-61: footer `if let photographer … { let credit = String(localized: "Photo by \(photographer) on Unsplash", …); Link(credit, destination: url) else Text(credit) }`.
- PurchaseSettingsView :26-38: `Section { … } header: { Text("Unlock SingleThread") } footer: { if isEntitled { Text("Thank you for your support! All features are unlocked.") } else if loadError != nil { Text("Could not load product. Check your internet connection and try again.").foregroundStyle(.red) } else { Text("A one-time purchase unlocks unlimited completions, skips, and deletes forever.") } }`; second footer :50-52 restore hint, no modifiers.
- AboutView :31-36: footer `Link(feedbackEmail, destination: mailto URL) else Text(feedbackEmail)`.
- PrivacySettingsView :12-17: `ForEach(sections) { Section(section.title) { Text(section.body) } }` + `Section {} footer: { Text(PrivacyGuideContent.closingLine) }`.

### `.xcstrings` catalogs (all four)
| Catalog | Keys | extraction | Plural keys | Languages |
|---|---|---|---|---|
| App `SingleThread/Resources/Localizable.xcstrings` | 96 | 96 manual / 0 extracted | 1 | en, zh-Hans, es, ja, de, fr |
| Core `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings` | 29 | 29 manual | 4 | en, zh-Hans, es, ja, de, fr |
| Watch `SingleThreadWatch/Resources/Localizable.xcstrings` | 4 | 4 manual | 0 | en, zh-Hans, es, ja, de, fr |
| Widget `SingleThreadWidget/Resources/Localizable.xcstrings` | 5 | 5 manual | 0 | en, zh-Hans, es, ja, de, fr |

- Every catalog: `sourceLanguage = "en"`, `version = "1.0"`; every key `extractionState = "manual"`, every value `state = "translated"` in all six languages. **Device variants: none.**
- Plural: App `"You have %lld reminders waiting — open SingleThread!"` (App catalog :3120) and Core `"Every %lld days/weeks/months/years"` (:373/:575/:474 + years) carry `variations.plural` — `one`+`other` for en/es/de/fr, `other`-only for zh-Hans/ja.
- Wiring: synchronized folder groups — `project.pbxproj` has 16 `PBXFileSystemSynchronizedRootGroup`s, zero explicit xcstrings entries; `developmentRegion = en`; `knownRegions = (en, Base, "zh-Hans", es, ja, de, fr)` (`project.pbxproj:445-454`).

### LocalizationTests (`SingleThreadTests/LocalizationTests.swift`)
- `catalogsParseAndHaveNonEmptyEnglish` :20-61 — parses all four catalogs (paths :166-172), asserts non-empty English values.
- `catalogsHaveAllSixLanguages` :63-85 — every key in every catalog has a non-empty localization for `["en", "zh-Hans", "es", "ja", "de", "fr"]` (:164).
- `pluralKeysCarryPluralVariationsInAllLanguages` :87-122 — plural keys list :150-158; every locale needs `variations.plural.other`, plus `one` in `pluralLocales = ["en", "es", "de", "fr"]` (:147); zh-Hans/ja may be `other`-only.
- `infoPlistStringsHaveRequiredKeysPerLanguage` :124-144 — per-target required InfoPlist.strings keys :174-180 (App: NSMicrophoneUsageDescription, NSRemindersUsageDescription, NSSpeechRecognitionUsageDescription, CFBundleDisplayName; Watch/Widget: NSRemindersFullAccessUsageDescription, CFBundleDisplayName).
- Helper: `String.en(_:bundle:table:)` pins `Locale(identifier: "en")` (`LocalizationTestHelpers.swift:4-11`); `Bundle.core` :14-24.

## Q5: Automated tests exercising the settings screens — exact asserted strings/ids

### Target split
- `SingleThreadTests` = Swift Testing (`import Testing`, `@Test`, `#expect`; target `bundle.unit-test` `project.pbxproj:268-290`; `@MainActor` structs). `SingleThreadUITests` = XCTest (`import XCTest`, subclass `SingleThreadUITestCase: XCTestCase` `SingleThreadUITests/SingleThreadUITestCase.swift:6`; target `bundle.ui-testing` `project.pbxproj:292-314`).
- Gating: `interfaceSettingsViewContainsExpectedRows` `#if os(iOS)` (`SettingsViewTests.swift:58-75`); `NotificationsUITests.swift:1` and `NotificationSchedulingUITests.swift:1` wrapped in `#if os(iOS)`; `SettingsViewModelTests.swift:17,21` gate mutation calls.

### Unit tests — `String(describing: view.body)` substring assertions (`SingleThreadTests/SettingsViewTests.swift`)
- :13 `settingsBindingsCarriesShowCompletionGlow`, :21 `…ShowSwipePrompt`, :29 `…ShowUndoButton` — `SettingsBindings()` defaults true + explicit-false round-trip.
- :37 `settingsViewContainsNavigationLinkLabels` — :47 asserts body contains `"Interface", "Reminder", "Filtering & Sorting", "Background", "Unlock", "Privacy", "About"`; :52 asserts `"Done"`. **Note: asserts "Unlock" (unentitled) — the dynamic Purchase label.**
- :56 `interfaceSettingsViewContainsExpectedRows` — :77 `"Appearance", "Text Size", "Show microphone"`; :80 (iOS) `+"Allow landscape", "Show action buttons", "Show swipe prompt", "Show undo button"`.
- :88 `reminderSettingsViewContainsExpectedRows` — :99 `"Show date", "Show list", "Recurrence indicator", "Reminder alerts", "Completion glow"`.
- :107 `filterSortSettingsViewContainsExpectedRows` — :116 `"Sort By", "Show undated reminders", "Excluded Lists"`.
- :124 `backgroundSettingsViewContainsExpectedRows` — :133 `"Background", "Background Fade", "Pin wallpaper", "Unsplash"` (seeded via `makeSeededStore()`/`SeededFetcher` :173-219).
- :140 `backgroundSettingsViewContainsPinToggle` / :155 `pinToggleVisibleWhenBackgroundDisabled` — `"Pin wallpaper"` present (:150, :165).
- :170 `privacySettingsViewContainsExpectedContent` — :175-181 `"Privacy", "Reminders", "Display & Sync Preferences", "Skipped & Excluded Lists", "Background Image", "vardy.cc", "no analytics"`.

### Per-preference persistence tests (each `@Test func` at file:7, UUID-key `isEnabled` + `set` round-trip, `removeObject` defer)
- `ShowAlarmsPreferenceTests.swift:7` `defaultAndRoundTrips` — missing key ⇒ enabled.
- `ShowDatePreferenceTests.swift:7` — enabled default, "must never read as false".
- `ShowListPreferenceTests.swift:7` `defaultAndRoundTripsWithDisabledDefault` — absent key ⇒ **disabled** (only one defaulting off).
- `ShowRecurrencePreferenceTests.swift:7` — enabled default.
- `ShowCompletionGlowPreferenceTests.swift:7` — enabled default.
- Sibling card-layer (same prefs, body-description, not settings screens): `ShowAlarmsTests.swift:11` asserts `"NamedImageProvider"` present/absent; ShowDateTests / ShowListTests / ShowRecurrenceTests exist.
- `SettingsViewModelTests.swift:11` `initializationAndMutationsDoNotCrash` — smoke only.

### UI tests (XCTest) — settings-flows
`SingleThreadUITestsFlows.swift` (helpers in `SingleThreadUITestCase.swift`: `launchSeeded(_:extra:)` = `--seed <json>`; `launchApp(arguments:)` :18-26; `flipToggle` :28-41; `assertTogglePersists` :45-54):
- :185 `testSettingsOpensAndShowsControls` — taps `settingsButton`; rows `settingsInterfaceRow`/`settingsReminderRow`/`settingsFilterSortRow`/`settingsPrivacyRow`; staticTexts `"Appearance"`, `"Text Size"`, `"Show date"`, `"Sort By"`, `"Excluded Lists"`, `"Skipped & Excluded Lists"`; navBar `"Privacy Policy"`.
- :222 `testAboutModalShowsAttribution` — `settingsAboutRow`; asserts `"Copyright 2026 Alan Vardy"`, `"Made with love by a lone developer"`, `"Version 1.0 (1)"`, `alan@vardy.cc`.
- :262 `testBackgroundAndPinTogglesPersistAcrossRelaunch` — `--seed` launch 1: `backgroundToggle` default `"1"`, `pinWallpaperToggle` `"0"`; flips; `--ui-testing` relaunch asserts persisted `"0"`/`"1"`; launch 3 pin-off persists.
- :327 `testBackgroundRefreshButtonExists` — `refreshWallpaperButton` exists/isHittable.
- :386 `testReminderTogglesPersistAcrossRelaunch` — `--ui-testing --reset-glow-preference`; `showListToggle` `"0"`, `showCompletionGlowToggle` `"1"`; relaunch asserts `"1"`/`"0"`.
- :429 `testCompletionGlowDoesNotAppearWhenDisabled` / :456 `…FlashesWhenEnabled` — `--seed … --ui-testing-glow`; `otherElements["completionGlowOverlay"]` absent/present.
- :478 `testSwipePromptAppearsUnderUITesting` / :490 `…PersistsAcrossRelaunch` — `--ui-testing --reset-swipe-preference`; button `"Dismiss swipe prompt"`.
- :517 `testSwipePromptToggleRoundTripsViaSettings` — `app.switches["Show swipe prompt"]` matched **by label** (source `InterfaceSettingsView.swift:68`, id `showSwipePromptToggle` :70); asserts value `"1"`→`"0"`→re-open→`"1"`.
- :594 `testUndoButtonHiddenWhenToggleOff` — `settingsInterfaceRow` + `showUndoButtonToggle`→`"0"`; `undoButton` gone.
- :689 `testSettingsHasPurchaseRow` — `settingsPurchaseRow` exists. :704 `testPurchaseSheetHasRestoreButton` — `restorePurchasesButton` exists.

`NotificationsSettingsUITests.swift` (no `#if`): :6 `testNotificationsToggleExists` — `settingsNotificationsRow`, `notificationsEnabledToggle` default `"0"`; :25 `testIntervalPickerOptions` — `notificationIntervalPicker`, buttons `"24 hours"`, `"48 hours"`, `"72 hours"`.

`NotificationsUITests.swift` (`#if os(iOS)`): `configureNotifications` :18-47 (toggle default `"0"`, picker label `"48 hours"`, `"Allow"` prompt, selects `"24 hours"`); :50 `testFullNotificationFlow` — relaunch persistence: toggle `"1"`, picker `"24 hours"`; seam labels `lastScheduleStatus`/`pendingStatus` contain `count=1`/`count=0`, `body=You have 2 reminders waiting — open SingleThread!`, `interval=86400`; :96 `testAccessibilityAudit` — `performAccessibilityAudit(for: [.sufficientElementDescription, .trait])`.

`NotificationSchedulingUITests.swift` (`#if os(iOS)`): `enableNotifications` :9-29; :37 `testSchedulingOnBackground` (`interval=172800`, 48h default); :58 `testCancelOnForeground`; :80 `testNoScheduleWhenDisabled`; :99 `testNoScheduleWhenNoReminders`.

`SingleThreadUITestsAppearanceLaunchTests.swift` (`--no-reminders`): :60 `testRuntimeAppearanceToggle` — `settingsButton`→`settingsInterfaceRow`→`appearancePicker`; :90 `testDeviceFollowingClearsOverride`.

### Identifier inventory (source-confirmed)
- Rows: `settingsButton` (`ContentView.swift:171`); `settingsInterfaceRow`/`settingsNotificationsRow`/`settingsReminderRow`/`settingsFilterSortRow`/`settingsBackgroundRow`/`settingsPurchaseRow`/`settingsPrivacyRow`/`settingsAboutRow`/`settingsDoneButton` (`SettingsView.swift:56,65,78,88,98,108,118,125,135`).
- Toggles/pickers: `backgroundToggle` (`BackgroundSettingsView.swift:23`), `pinWallpaperToggle` :34, `refreshWallpaperButton` :53, `backgroundFadePicker` :29; `showDateToggle`/`showListToggle`/`showRecurrenceToggle`/`showAlarmsToggle`/`showCompletionGlowToggle` (`ReminderSettingsView.swift:26,35,39,48,57`); `appearancePicker`/`showMicrophoneToggle`/`showActionButtonsToggle`/`showSwipePromptToggle`/`showUndoButtonToggle` (`InterfaceSettingsView.swift:41,61,66,70,74`); `notificationsEnabledToggle`/`notificationIntervalPicker` (`NotificationsSettingsView.swift:16,23`); `restorePurchasesButton`, `completionGlowOverlay`.
- Matched by label (no id): `"Show swipe prompt"` switch, `"Settings"`/`"Done"` bar buttons, row staticTexts `"Interface"`/`"Reminder"`, `"Appearance"`, `"Text Size"`, `"Show date"`, `"Sort By"`, `"Excluded Lists"`, picker options `"24 hours"`/`"48 hours"`/`"72 hours"`, `"Privacy Policy"`, `"Dismiss swipe prompt"`, `"Allow"` (SpringBoard).
- Launch seams: `--seed <json>`, `--ui-testing`, `--ui-testing-glow`, `--ui-testing-notifications`, `--reset-glow-preference`, `--reset-swipe-preference`, `--no-reminders`. Persistence asserted only via `--ui-testing` relaunches (seeding resets persisted keys).

## Cross-Cutting Observations
- **Bag + `.onChange` write-back is the single settings-state mechanism** (`ContentView+Settings.swift:14-44`): no direct `@AppStorage` binding reaches a settings row; everything flows through `SettingsBindings` → `ContentView`'s `@AppStorage`. Any new setting must be added to `SettingsBindings` (init + stored prop + `@Observable`), `makeSettingsBag`, and the `.onChange` chain.
- **Two defaults suites split by audience**: standard-suite keys (`appearanceMode`, `textSize`, background, microphone, iOS-only toggles, notification keys) are phone-local UI; App-Group keys (`showUndatedReminders`, `sortOption`, `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow`) are exactly the ones the widget reads and the watch syncs (documented in `AppGroup.swift:5-7`). Caption text changes don't affect keys, but any new persisted setting must pick the right suite.
- **Body-description unit tests are the first casualty of any text change**: `SettingsViewTests` asserts the exact literal strings above appear in `String(describing: view.body)`; UI tests re-assert the same strings via static texts/switches and the full `.accessibilityIdentifier` set. Adding a caption that reuses/renames a label, or wrapping a row in a Section with a header, is invisible to these tests (they don't assert Section structure), but **removing/renaming** any asserted string breaks them.
- **All catalog keys are `manual`** with all six languages `translated`: any new caption string must be added to the correct per-target catalog with translations for all six languages or `LocalizationTests.catalogsHaveAllSixLanguages` (:63-85) fails; plural-capable strings must carry `variations.plural` per `pluralKeysCarryPluralVariationsInAllLanguages` (:87-122).
- **Structured captions have no precedent to copy** — existing headers/footers are plain `Text`/`Link` with default styling; the richest examples are the 3-branch conditional footer (`PurchaseSettingsView.swift:28-38`) and the interpolated credit footer (`BackgroundSettingsView.swift:55-61`).
- **Time values are not user-displayed today**: the only numbers surfaced in settings UI are the 24/48/72 hour picker tags and `Text("\(percent)%")`; runtime wording derived from `defaultMaxAge` (86400s) or `notificationIntervalHours` would need a formatter in the established `String(localized:table:bundle:)` interpolation style (`%lld` plural keys in catalogs).
- Supported languages: exactly en, zh-Hans, es, ja, de, fr — enforced across all four catalogs and InfoPlist.strings.

## Open Areas
- **CI UI coverage gap**: `.github/workflows/ci.yml` UI jobs run disjoint class-level `-only-testing:` groups (Group A = Launch+AppearanceLaunch :11-12, Group B = Flows :13, Group C = `SingleThreadUITests`+`ActionButtonsUITests` :14). The three notification classes (`NotificationsUITests`, `NotificationsSettingsUITests`, `NotificationSchedulingUITests`) do **not** appear in any group and therefore never run in CI; they run only in the local `./scripts/test.sh` whole-target UI pass. The comment at `ci.yml:9-14` claims the groups "cover all 5 iOS UI classes … exactly once" — whether this exclusion is intentional is unresolved.
- **`testPurchaseSheetHasRestoreButton`** (`Flows:704`) body beyond :713 was not fully read; identifier `restorePurchasesButton` cited from the grep at Flows:713.
- `SettingsViewTests` asserts `"Unlock"` for the Purchase row — that assertion depends on `EntitlementStore()` defaulting to unentitled in tests; verified by the passing suite but not re-derived here.
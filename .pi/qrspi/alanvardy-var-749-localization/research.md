# Research Findings

Questions from `.pi/qrspi/alanvardy-var-749-localization/questions.md`. All sources
`SingleThread/`, `SingleThreadCore/`, `SingleThreadWatch/`, `SingleThreadWidget/` relative to
repo root; pbxproj lines reference `SingleThread.xcodeproj/project.pbxproj` (1235 lines,
`objectVersion = 77`, synchronized-folder layout).

## Q1: String inventory across targets

### Findings

- **No localization files exist anywhere** — zero `.xcstrings`, `.strings`, `.stringsdict`,
  `.lproj` (verified by find + `git ls-files`). All copy is hardcoded Swift literals, plus a
  few strings in pbxproj build settings and one `.storekit` file.
- **SingleThread app (iOS+macOS): ≈105–110 distinct literals**, concentrated in:
  - Settings screens: `SettingsView.swift:54-124` (row labels + `"Done"`), `InterfaceSettingsView.swift:35-70`,
    `NotificationsSettingsView.swift:14-23`, `ReminderSettingsView.swift:22-53`, `FilterSortSettingsView.swift:20-39`,
    `BackgroundSettingsView.swift:21-60`, `PurchaseSettingsView.swift:21-207`, `PrivacySettingsView.swift:20`,
    `AboutView.swift:27-39`, `ExcludedListsView.swift:27-30`
  - Enum picker titles: `AppearanceMode.swift:70-72` (`System/Light/Dark`), `TextSize.swift:42-46` (`System/Small/Medium/Large/Extra Large`), `SortOption+Presentation.swift:12-14` (`Priority/Due Date/Title`)
  - Empty states (centralized app-side): `ContentViewModel.swift:61-75` (`"Nothing due"`, `"No Reminders"`,
    `"All Done"` + descriptions), rendered `ContentView.swift:355-378`; auth state `ContentView.swift:336,340-343`
  - Reminder card: `ReminderCardView.swift:92-185` (priority a11y `"\(level.displayName) priority"`, `"Repeats"`,
    bell a11y `"Has alarm"`, swipe-prompt copy `"Swipe left to skip"`/`"Swipe right to complete"`/`"Dismiss"`)
  - Actions & a11y labels: `ContentView.swift:92,108,297-326,409-432,502-570` (`"Complete"`/`"Skip"`/`"Delete"`,
    `"Complete reminder"`/`"Skip reminder"`/`"Delete reminder"`, `"Undo completion"`, `"Dictate reminder"`, `"Completion glow"`)
  - Dictation errors: `DictationViewModel.swift:36,41`, `ReminderDictation.swift:212-215`; feedback bubble `CreationFeedback.swift:29-30`
  - Local notification: `AppViewModel.swift:134-135` (`title = "SingleThread"`, `body = "You have \(count) reminders waiting — open SingleThread!"`)
- **SingleThreadWatch: 18 distinct** — all in `WatchReminderView.swift:49-248`
  (`"Requesting access…"`, `"Enable Reminders access in Settings"`, `"Complete"`/`"Skip"` + a11y,
  `"Upgrade on\nyour iPhone"` :138, empty states `:148,156,158`, `"Refresh"`, `"Delete"` :202-206,
  priority a11y :227, `"Repeats"` :243, `"Alert"` :248, glow a11y :178). No strings in
  `WatchReminderViewModel.swift` or the app files.
- **SingleThreadWidget: 16 distinct** — `NextThingWidget.swift:` gallery copy :121-122
  (`configurationDisplayName("Next Thing")`, `.description("Your next reminder, with Complete and Skip.")`),
  placeholder/snapshot :33,44, empty states :138-148, action labels + a11y :161-174, `"Repeats"` :220, `"Alert"` :225.
- **SingleThreadCore: 17 distinct** — intent titles `ReminderIntents.swift:14,37` (`"Complete Reminder"`/`"Skip Reminder"`,
  `LocalizedStringResource`, `isDiscoverable = false`), recurrence `ReminderRecurrenceFormatter.swift:16-22`,
  priority names `ReminderSkip.swift:42-44`, version/name/email `AppInfo.swift:16,29-41`.
- **Cross-target duplicates** (15 rows): `"Complete"`/`"Skip"`, a11y `"Complete reminder"`/`"Skip reminder"`,
  `"All Done"`, `"No Reminders"`, `"Nothing due right now"`/`"No reminders yet"` (watch+widget, separate literals
  from app's `ContentViewModel`), `"Reminders Access"`, `"Requesting access…"`, `"Completion glow"`,
  `"\(level.displayName) priority"`, `"Repeats"`, `"Delete"`, plus near-dup intent titles `"Complete/Skip Reminder"`
  vs widget-button a11y `"Complete/Skip reminder"`. Watch and widget re-hardcode their own empty-state copy
  independently of the app (`WatchReminderView.swift:148,156` vs `NextThingWidget.swift:143-148` vs `ContentViewModel.swift:61-75`).
- Not user-facing (excluded): `print`/logger lines (`AppDelegate.swift:41,46`), UI-test seam overlay
  (`ContentView.swift:702-706`, `AppViewModel.swift:319`), preview/seed fixtures (`"Buy groceries"`, `"Work"`, `"Personal"`),
  dictation parser vocab (`ReminderDictationParser.swift:106-112`), sync payload keys (`SkippedReminderSyncService.swift:269-281`).

## Q2: Localization plumbing in the Xcode project

### Findings

- `developmentRegion = en` (pbxproj:442); `knownRegions = (en, Base)` (pbxproj:444-447) — only two, no other `.lproj` entries.
- `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` in both project-level configs (pbxproj:662 Debug, :719 Release).
- `STRING_CATALOG_GENERATE_SYMBOLS` + `SWIFT_EMIT_LOC_STRINGS` paired, YES for the 3 product targets,
  NO for the 4 test targets, in Debug and Release each:
  - App YES :766/:770 (Debug), :816/:820 (Release); Watch YES :950/:954, :978/:982; Widget YES :1010/:1013, :1041/:1044
  - Tests NO: SingleThreadTests :841/:844, :870/:873; UITests :898/:901, :922/:925; WatchUITests :1062/:1065, :1084/:1087; WatchTests :1107/:1110, :1131/:1134
- **All 7 `PBXResourcesBuildPhase` sections have empty `files = ( );`** (pbxproj:471,478,485,492,499,506,513);
  likewise Sources (:406-429) and Frameworks (:150-180). Resource wiring is entirely implicit.
- **No `PBXVariantGroup`** — grep for `PBXVariantGroup|VariantGroup|\.strings|\.lproj|Localizable` in pbxproj = zero.
- 7 `PBXFileSystemSynchronizedRootGroup` objects (1:1 to targets, roots at pbxproj:111,116,121,126,131,139,144;
  wired at :255,279,303,325,348,372,395). One exception set `51AA3F4E` (pbxproj:99-108) excludes
  `SingleThreadWidget/Info.plist` from the widget's synchronized folder (referenced via `INFOPLIST_FILE = SingleThreadWidget/Info.plist`, :1001/:1032).
  Implication: any resource dropped into a synchronized folder is auto-included — no pbxproj entry needed.
- **No localization file type exists**: zero `*.xcstrings`, `*.strings`, `*.stringsdict`, `.lproj` dirs repo-wide,
  none referenced in pbxproj or both xcschemes.
- Only localization-API use in production: `LocalizedStringResource` in `ReminderIntents.swift:15,36`; test-only
  `String(localized:)` at `SingleThreadTests/ReminderIntentsTests.swift:23,41`.

## Q3: Dynamic and locale-sensitive formatting

### Findings

- **Recurrence summaries** — `SingleThreadCore/Sources/SingleThreadCore/ReminderRecurrenceFormatter.swift:15-23`:
  `interval > 1 ? "Every \(interval) days" : "Daily"` (same for weeks/months/years). Hardcoded English, no pluralization
  (only the `interval > 1` ternary); interval 1 reads the singular word. `format` reads only the **first** recurrence rule (:4-7).
  Wired in `ReminderDisplay.swift:18`; rendered at `ReminderCardView.swift:105`, `NextThingWidget.swift:220`, `WatchReminderView.swift:243` (all with `?? "Repeats"` fallback).
- **Notification body with count** — `AppViewModel.swift:135`: `"You have \(count) reminders waiting — open SingleThread!"`
  (`count = store.visibleReminders.count` :126; `UNTimeIntervalNotificationTrigger` :139-144). No singular/plural handling.
  UI-test seam interpolates again at `AppViewModel.swift:319`, rendered `ContentView.swift:704-707`.
- **Version strings** — `AppInfo.swift:35-41`: `"Version \(marketing) (\(build))"` / `"Version \(marketing)"`
  (from `CFBundleShortVersionString`/`CFBundleVersion` :19-25). Rendered `AboutView.swift:29`.
- **Priority display names** — `ReminderSkip.swift:38-50`: `"High"/"Medium"/"Low"` (`displayName`) and `"!!!"/`"!!"/`"!"` (`marker`).
  Interpolated into a11y labels `"\(level.displayName) priority"` at `ReminderCardView.swift:95`, `WatchReminderView.swift:227`;
  widget renders only the marker (`NextThingWidget.swift:201-204`). Numeric mapping `level(for:)` :60-67 (1...4 high, 5 medium, 6...9 low).
- **Percent / photo credit** — `BackgroundSettingsView.swift:25` `"\(percent)%"` (0–90 by 10, `BackgroundFade.swift:16`);
  :52/:55 `"Photo by \(photographer) on Unsplash"` (`BackgroundImageStore.swift:71,74`).
- **Locale-aware output — only one path**: SwiftUI `Text(date, style: .date)` at `ReminderCardView.swift:97`,
  `WatchReminderView.swift:233`, `NextThingWidget.swift:210` (date from `EKReminder.dueDateComponents?.date`,
  `ReminderDisplay.swift:16`). No explicit locale/calendar/region passed; formatting is SwiftUI-environment driven.
- **Locale-aware APIs**: `Locale.current` only for speech-**input** (`ReminderDictation.swift:28,89` → `SFSpeechRecognizer`);
  `Calendar = .current` defaults in `ReminderDictationParser.swift:62` and `ReminderDateFilter.swift:29,43,56`
  (calculation, not display); `NSDataDetector` at `ReminderDictationParser.swift:147-148` (system-locale date parsing).
  Recurrence phrase detection in dictation is **hardcoded English regexes** `ReminderDictationParser.swift:110-144` with
  English weekday dictionary :84-92 and connector words :146.
- **Absent**: zero production `DateFormatter`, `Date.FormatStyle`, `.formatted(`, `NumberFormatter`, `Measurement`,
  `Text(verbatim:)`, `LocalizedStringKey`, or pluralization anywhere. `AttributedString` only via
  `CodeSpanFormatter.swift:22` (backtick-code styling, no value formatting).
- StoreKit `product.displayPrice` (`PurchaseSettingsView.swift:108`) is system-localized by StoreKit itself.

## Q4: Info.plist user-facing values

### Findings

- **App (iOS+macOS) — fully generated, no physical plist**: `GENERATE_INFOPLIST_FILE = YES` (pbxproj:743/:793);
  no `INFOPLIST_FILE`. User-facing usage strings (Debug/Release identical):
  - pbxproj:744/794 `INFOPLIST_KEY_NSMicrophoneUsageDescription = "SingleThread needs microphone access to capture your voice for reminders."`
  - pbxproj:745/795 `INFOPLIST_KEY_NSRemindersUsageDescription = "SingleThread needs access to show your reminders."` (**legacy key**; no `NSRemindersFullAccessUsageDescription` here)
  - pbxproj:746/796 `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "SingleThread uses speech recognition to create reminders from your voice."`
  - **No `CFBundleDisplayName`** on the app target — name synthesized from `PRODUCT_NAME = "$(TARGET_NAME)"` (pbxproj:763/813) = "SingleThread". No `NSHumanReadableCopyright`.
- **Watch — fully generated**: `GENERATE_INFOPLIST_FILE = YES` (pbxproj:940/968). User copy:
  `INFOPLIST_KEY_CFBundleDisplayName = SingleThread` (:941/969), `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` (:942/970, **full-access** key),
  `WKCompanionAppBundleIdentifier = app.alanvardy.SingleThread` (:943/971), `WKWatchOnly = NO` (:944/972).
  `INFOPLIST_KEY_WKApplication = YES` is toolchain-injected (not in pbxproj). No mic/speech strings.
- **Widget — generated + the repo's only physical plist**: `GENERATE_INFOPLIST_FILE = YES` (pbxproj:996/1027)
  **and** `INFOPLIST_FILE = SingleThreadWidget/Info.plist` (:997/1028). The physical plist contains only
  `NSExtension → NSExtensionPointIdentifier = com.apple.widgetkit-extension` (no copy). Build settings:
  `INFOPLIST_KEY_CFBundleDisplayName = SingleThread` (:998/1029), `INFOPLIST_KEY_NSHumanReadableCopyright = ""` (:999/1030,
  the **only** occurrence in the project, explicit empty), `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` (:1000/1031).
- **Test targets**: all 4 set `GENERATE_INFOPLIST_FILE = YES` with no user-facing copy (pbxproj:834,863,891,915,1057,1079,1102,1126).
- **Localization status: none of this copy is localized.** Single English literals baked into generated plists for every
  language; no `InfoPlist.strings` exists. Widget gallery name/description are hardcoded Swift literals
  (`NextThingWidget.swift:121-122`), not localizable forms.
- Generated plists land in gitignored `build/`/`DerivedData*` (`.gitignore`); none currently on disk.
  `SingleThreadWidget/Info.plist` is tracked (added in commit `00f30c4`).

## Q5: Tests' dependence on string literals

### Findings

- **No central string/constants helper exists** in app, Core, or any test target — every definition is inline
  at the render site, every assertion is an inline copy. Sources of truth the tests quote:
  `ContentViewModel.swift:56-77` (empty states), `WatchReminderView.swift:148,156`, `AppViewModel.swift:102,129,135,315-320`,
  `ReminderCardView.swift:95,151,159,170,185`, `SettingsView.swift` + sub-screens, `AboutView.swift`/`AppInfo.swift:22,44-49`,
  `ReminderSkip.swift:40-44`, `ContentView.swift:92-570`.
- **UI tests (XCTest) — 230 subscript call sites** (`staticTexts["…"]`, `buttons["…"]`, `switches["…"]`,
  `navigationBars["…"]`, `otherElements["…"]`): 191 in `SingleThreadUITests/` (143 in `SingleThreadUITestsFlows.swift`
  alone; `ActionButtonsUITests.swift:28,32,51,55`; `NotificationsUITests.swift`; `NotificationsSettingsUITests.swift`;
  `NotificationSchedulingUITests.swift`; `AppearanceLaunchTests.swift:65-104`) + 39 in `SingleThreadWatchUITests/`
  (`SingleThreadWatchUITestsFlows.swift`, `SingleThreadWatchUITests.swift`). Exact strings pinned include
  `"No Reminders"`, `"All Done"`, `"Skip"`/`"Complete"`/`"Delete"`, settings rows, `"Version 1.0 (1)"` (Flows:200;
  AboutViewTests:20), `"Copyright 2026 Alan Vardy"` (Flows:194), a11y labels `"High priority"` (Flows:84),
  `"Dismiss swipe prompt"`, `"Complete reminder"`, `"Undo completion"`, `"Upgrade to unlock unlimited completions"`.
- **Relative/contains matches**: `label BEGINSWITH "Remind after"` (`NotificationsUITests.swift:48`, `NotificationsSettingsUITests.swift:45-48`);
  `label == "Appearance"` (`AppearanceLaunchTests.swift:70,104`); picker `contains("48 hours")` (NotificationsUITests:82,152);
  notification-seam status `contains("body=You have 2 reminders waiting — open SingleThread!")` etc. (NotificationsUITests:121-137,
  NotificationSchedulingUITests:94-166); aggregated-label `contains("map")` for code-block rendering (Flows:341-356).
- **True accessibility *identifiers* are rare**: only `completionGlowOverlay` (`ContentView.swift:569`; Flows:471,489;
  WatchFlows:179,197,224), `pendingStatus`/`lastScheduleStatus` (`ContentView.swift:703,705`; NotificationsUITests:57-62; NotificationSchedulingUITests:46-51).
- **Accessibility audits (assert no copy directly)**: `SingleThreadUITests.swift:27` (performs audit :54-61/64),
  `ActionButtonsUITests.swift:46` (pre-asserts `buttons["Complete reminder"]`/`"Skip reminder"` :51,55), `NotificationsUITests.swift:157`,
  `SingleThreadWatchUITests.swift:27` (pre-asserts `staticTexts["Buy groceries"]` :32) — indirectly sensitive to every a11y label listed above.
- **Unit tests (Swift Testing): ~101 copy-literal sites across 15 files** — exact equality (e.g. `AppInfoTests.swift:19`
  `versionDescription == "Version 1.0 (1)"`, `ReminderRecurrenceFormatterTests.swift:19-49`, `ReminderIntentsTests.swift:23,41`
  via `String(localized:)`) and `String(describing: view.body).contains("…")` reflection checks (`SettingsViewTests.swift:47-184`,
  `AboutViewTests.swift:18-36`, `SwipePromptTests.swift:13-26`, `MicrophoneToggleTests.swift:48`, `PrivacySettingsContentTests.swift:21-33`).
- Watch unit tests assert fixture data only, no app copy. Seed fixtures (`"Buy groceries"`, `"milk"`) lock the seed/rendering contract but are not translation-relevant copy.
- **Affected call sites if literals moved**: ~230 UI-test subscripts + ~35 UI-test relative/contains sites + ~101 unit-test
  literals, plus every render-site literal in 3–4 targets. Empty-state copy alone is duplicated in app
  (`ContentViewModel.swift:56-77`), watch (`WatchReminderView.swift:148,156`), widget (`NextThingWidget.swift:143-148`), and tests.

## Q6: External and system-owned copy

### Findings

- **StoreKit product metadata** — purchased UI renders StoreKit `Product` fields verbatim:
  `PurchaseSettingsView.swift:94` `Text(product.displayName)`, :96 `Text(product.description)`, :108 `Text(product.displayPrice)`,
  loaded at :138 `Product.products(for: [Self.unlockProductID])` (ID `EntitlementStore.swift:42`).
  Origin: production = App Store Connect metadata for `app.alanvardy.SingleThread.unlimited`;
  local dev/test = `SingleThread/Products.storekit` (`displayName "Unlock"`, USD 2.99, **no description** field; :6-24;
  consumed via `SKTestSession(configurationFileNamed: "Products")` `EntitlementStoreTests.swift:28,48`).
  The app never defines name/description/price in Swift. `error.localizedDescription` (:144,:164) is system-provided.
- **AppIntent titles** — `ReminderIntents.swift:14` `"Complete Reminder"`, :37 `"Skip Reminder"`, both
  `LocalizedStringResource` with `isDiscoverable = false` (:15,:38) — so they don't surface in Shortcuts/Siri;
  they feed widget `Button(intent:)` (`NextThingWidget.swift:160,168`). Origin: hardcoded app-source strings.
  No `description` defined; no `AppShortcut`, `@AssistantIntent`, `EntityQuery`, or `IntentConfiguration` anywhere.
- **Widget gallery copy** — `.configurationDisplayName("Next Thing")` / `.description("Your next reminder, with Complete and Skip.")`
  (`NextThingWidget.swift:121-122`), consumed by WidgetKit. Hardcoded app-source literals. Widget uses `StaticConfiguration`
  (not `AppIntentConfiguration`); single widget only (`SingleThreadWidgetBundle.swift:6-9`).
- **WatchConnectivity** — `SkippedReminderSyncService.swift:268-281` payload keys are data (`skippedReminderIdentifiers`,
  `excludedListTitles`, ...), no user-facing copy; values are user data. `WCSession` errors only hit the unified log
  (:204,214,224,253). Watch-side user-facing results are hardcoded app copy (e.g. `WatchReminderView.swift:138`).
- **Other OS surfaces — mostly absent**: no `AppShortcut`, `NSUserActivity`, `CSSearchable`, SiriKit anywhere.
  Notifications carry app copy (`AppViewModel.swift:134-135`); home-screen name derives from build settings
  (`PRODUCT_NAME`/`INFOPLIST_KEY_CFBundleDisplayName`, read via `AppInfo.swift:29-33` into `AboutView.swift:24`);
  "View in Reminders" deep link `x-apple-reminderkit://REMCDReminder/<id>` (`ReminderDeepLink.swift:16`).
  Reminder titles/notes/lists/dates are **user data via EventKit** (`ReminderDisplay.swift:15-28`), not app copy.

## Q7: App Store / storefront copy

### Findings

- **No repo evidence of the live App Store listing** (name/subtitle/description/keywords/screenshots).
  The only in-tree reference to the listing itself is this task's own research question (`.pi/qrspi/alanvardy-var-749-localization/questions.md:62-67`)
  and a grep-matched line in task.md:8 (not read).
- **TestFlight appears only in prior crash-report task docs** (`.pi/qrspi/alanvardy-var-643-crash-report/task.md:3`,
  `.pi/qrspi/alanvardy-var-644-qrspi-design-crash-report/task.md:3`; grep evidence only) — confirms the app is distributed via TestFlight.
- **Fastlane: ignore entries only** (`.gitignore:34-37`: `fastlane/report.xml`, `fastlane/Preview.html`,
  `fastlane/screenshots`). No `fastlane/` dir, Fastfile, Gemfile, or lane config; no altool/notarytool/transporter/ASC-API tooling.
- **App identity metadata in-repo** (not listing copy): bundle id `app.alanvardy.SingleThread` (pbxproj:762/812,
  watch `…watchkitapp` :946/974, widget `…widget` :1007/1038), `MARKETING_VERSION = 1.0` (pbxproj:761/811/837/894/945/1006...),
  `CURRENT_PROJECT_VERSION = 1` (:737/787/...), display name "SingleThread", `DEVELOPMENT_TEAM = 6NWX2DHB9Q` (:644/707...),
  `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. IAP product metadata in `SingleThread/Products.storekit` ("Unlock", USD 2.99).
- **Closest marketing adjacent copy**: `AboutView.swift` ("Copyright 2026 Alan Vardy", "Made with love by a lone developer",
  `alan@vardy.cc`), `PurchaseSettingsView.swift` ("Unlock SingleThread", "A one-time purchase unlocks unlimited completions, skips, and deletes forever."),
  `PrivacySettingsContent.swift` (privacy copy: EventKit/Apple Reminders, device-local Watch sync, `vardy.cc/unsplash`, "no analytics, no tracking, no advertising").
- **No README, no marketing docs**: top-level markdown is `AGENTS.md` (dev conventions), `linear-project.md`,
  `docs/SimulatorManualVerification.md` (technical, `make simverify`, screenshots only as test artifacts).
  `Makefile` has no archive/upload targets; `scripts/` has only `test.sh` and `simverify.sh`;
  `.github/workflows/ci.yml` builds/tests/lints only (nulls `DEVELOPMENT_TEAM`) — no release automation.
- In-repo screenshots are UI-test attachments and `scripts/simverify.sh:39` `simctl` captures, not listing assets.

## Cross-Cutting Observations

- **Zero localization infrastructure is the headline**: no catalogs, no strings files, no variant groups,
  no `.lproj`; `knownRegions = (en, Base)`, `developmentRegion = en`; yet product targets are configured as if
  catalog generation were expected (`SWIFT_EMIT_LOC_STRINGS`/`STRING_CATALOG_GENERATE_SYMBOLS` YES +
  `LOCALIZATION_PREFERS_STRING_CATALOGS` YES) — settings that currently produce nothing.
- **Every target re-hardcodes shared copy**: app (`ContentViewModel`), watch (`WatchReminderView`), and widget
  (`NextThingWidget`) each define their own `"All Done"`/`"No Reminders"` empty states; action labels
  (`"Complete"`/`"Skip"`/`"Delete"`) and a11y labels are duplicated in all three UI targets, with
  near-identical intent titles in Core. Core supplies the only shared cross-target strings (recurrence, priority, version).
- **No central string collection exists anywhere** — app, Core, and tests all hold inline copies; tests mirror
  app copy a third time (up to 3–4 copies of one literal across app/watch/widget/tests).
- **Locale-awareness is nearly absent**: the only locale-aware output is SwiftUI `Text(date, style: .date)`;
  locale/calendar use is otherwise input-side (speech recognizer, dictation parsing, date-window filtering).
  Plurals never appear — `interval > 1` ternaries and plain `\(count)` interpolation instead.
- **Info.plist copy lives in build settings** (3 product targets), except the single tiny widget plist.
  `NSHumanReadableCopyright` is set (empty) only on the widget; display name is explicit on watch/widget,
  synthesized on the app. Usage-description keys differ between app (legacy `NSReminders…`) and watch/widget (full-access).
- **Storefront context is minimal**: TestFlight distribution evidenced only in prior task docs, fastlane only as
  gitignore ghosts, and no listing metadata or release tooling in-tree.

## Open Areas

- **Q7 cannot be fully answered from the repo**: the live App Store Connect listing (name/subtitle/description/
  keywords/screenshots) and its primary language are not recorded anywhere in the repository; the store-language
  question and the "what do listing localization options consist of" sub-question require external/web knowledge,
  which is out of scope for codebase research (existing repo docs only mention TestFlight as a channel).
- **Q3 date rendering**: exact rendered date strings depend on SwiftUI environment formatting (no explicit locale),
  so precise localized output behavior is OS- and environment-dependent and was not empirically verified by a build.
- **Q2 implied-but-absent**: with the current settings Xcode would conventionally emit catalog artifacts; none
  exist, and no build was run to confirm what `xcodebuild` currently produces (inference is from objectVersion 77
  synchronized-folder semantics).
- **Counts are grep-derived**: distinct-string and call-site totals (≈105–110 / 18 / 16 / 17; 230 UI + ~101 unit)
  treat interpolated templates as single literals and exclude fixtures/seams/logs; exact tallies can shift slightly
  under a different counting rule.
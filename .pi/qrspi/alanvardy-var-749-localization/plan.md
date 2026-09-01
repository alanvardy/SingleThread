# Implementation Plan

## Overview

Route every user-facing string in all four targets (iOS/macOS app, watchOS app, widget, `SingleThreadCore`) through string catalogs and `InfoPlist.strings`, shipping English + zh-Hans, es, ja, de, fr — verified by en-locale-pinned unit tests, identifier-based UI tests, and a new `LocalizationTests` suite that validates catalog integrity across all six languages.

---

## Phase 1: String Catalog Infrastructure

Create the four `.xcstrings` catalogs and the per-target per-language `InfoPlist.strings` files. This stage is resource-only: no production code reads the catalogs yet, so every existing test must stay green.

### Changes

#### 1. Core shared catalog
**File**: `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`
**Action**: create (new directory `Resources/`)

A JSON string catalog, `"sourceLanguage": "en"`, `"version": "1.0"`, every entry `"extractionState": "manual"`. Populate with **English source values plus translations for all six languages** (`en`, `zh-Hans`, `es`, `ja`, `de`, `fr`).

**Shared keys** (the single source of truth for strings used by ≥2 targets or owned by Core):

| Key | Used by |
|---|---|
| `High`, `Medium`, `Low` | priority display names (Core → app/watch) |
| `%@ priority` | priority a11y suffix, app + watch (`"\(level.displayName) priority"`) |
| `Repeats` | recurrence fallback, app + watch + widget |
| `Alert` | alarm row label, watch + widget |
| `Complete`, `Skip`, `Delete` | action button labels, app + watch (+ widget for Complete/Skip) |
| `Complete reminder`, `Skip reminder`, `Delete reminder` | action a11y labels, app + watch + widget |
| `Completion glow` | glow overlay a11y, app + watch (also reused by the app settings row) |
| `All Done`, `No Reminders` | empty-state titles, app + watch + widget |
| `Nothing due right now`, `No reminders yet` | empty-state sub-copy, watch + widget |
| `Reminders Access` | no-access title, app + widget |
| `Requesting access…` | loading label, app + watch |
| `Version %@ (%@)`, `Version %@` | AppInfo version strings |
| `Complete Reminder`, `Skip Reminder` | AppIntent titles |
| `Daily`, `Weekly`, `Monthly`, `Yearly` | recurrence singular (interval 1) |
| `Every %lld days`, `Every %lld weeks`, `Every %lld months`, `Every %lld years` | recurrence plurals (interval ≥ 2) |

Example entry (plain):

```json
{
  "sourceLanguage" : "en",
  "version" : "1.0",
  "strings" : {
    "High" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "High" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "高" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Alta" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "高" } },
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Hoch" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Haute" } }
      }
    },
    "Every %lld days" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : { "state" : "translated", "value" : "Every %lld days" },
          "variations" : {
            "plural" : {
              "one" : { "stringUnit" : { "state" : "translated", "value" : "Every %lld day" } },
              "other" : { "stringUnit" : { "state" : "translated", "value" : "Every %lld days" } }
            }
          }
        },
        "zh-Hans" : {
          "stringUnit" : { "state" : "translated", "value" : "每 %lld 天" },
          "variations" : {
            "plural" : {
              "other" : { "stringUnit" : { "state" : "translated", "value" : "每 %lld 天" } }
            }
          }
        }
      }
    }
  }
}
```

Same plural pattern for `Every %lld weeks/months/years`. `%@ priority` and the `Version %@` keys are format strings — translators may reorder `%1$@` placeholders; keep the English value identical to the key.

**Translations**: obtain zh-Hans/es/ja/de/fr via machine translation (DeepL) with human review of gesture metaphors (`Swipe left…`, `Swipe right…`) and plurals — see Phase 6 manual verification.

#### 2. Core package resources wiring
**File**: `SingleThreadCore/Package.swift`
**Action**: modify

```swift
.target(
    name: "SingleThreadCore",
    resources: [.process("Resources")]
)
```

Required so `Bundle.module` resolves the catalog in the app, watch, and widget processes.

#### 3. App catalog
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: create (new directory `Resources/`)

Same JSON shape. Holds every **app-only** literal (English + 5 translations). Extract from (research Q1 line refs):

- `SettingsView.swift` — `"Settings"`, `"Done"`, `"Interface"`, `"Notifications"`, `"Reminder"`, `"Filtering & Sorting"`, `"Background"`, `"Unlock"`/`"Manage Purchase"`, `"Privacy Policy"`, `"About"`
- `InterfaceSettingsView.swift` — `"Appearance"`, `"Text Size"`, `"Allow landscape"`, `"Show microphone"`, `"Show action buttons"`, `"Show swipe prompt"`, `"Show undo button"`, `"Interface"`
- `NotificationsSettingsView.swift` — `"Enable reminder notifications"`, `"Remind after"`, `"24 hours"`, `"48 hours"`, `"72 hours"`, `"Notifications"`
- `ReminderSettingsView.swift` — `"Show date"`, `"Show list"`, `"Recurrence indicator"`, `"Reminder alerts"` (the `"Completion glow"` row reuses the shared key), `"Reminder"`
- `FilterSortSettingsView.swift` — `"Sort By"`, `"Show undated reminders"`, `"Excluded Lists"`, `"Filtering & Sorting"`
- `BackgroundSettingsView.swift` — `"Background"` (toggle + nav), `"Background Fade"`, `"Pin wallpaper"`, `"Refresh wallpaper"`, `"Refreshing"` (a11y value), `"Photo by %@ on Unsplash"` (footer), `"%lld%%"` (fade picker values)
- `ExcludedListsView.swift` — `"Excluded Lists"` (nav), `"Excluded lists are hidden from the reminder list."`
- `PurchaseSettingsView.swift` — `"Unlock SingleThread"`, `"You're all set! 🎉"`, `"Thank you for your support! All features are unlocked."`, `"Could not load product. Check your internet connection and try again."`, `"A one-time purchase unlocks unlimited completions, skips, and deletes forever."`, `"Restore Purchases"`, `"If you've already purchased Unlock on another device, restore it here."`, `"Unlock"` (nav), `"Try Again"`, `"Loading…"`, `"Product not available."`, `"Upgrade to unlimited"`, `"Upgrade to unlock unlimited completions"`
- `PrivacySettingsView.swift` / `PrivacySettingsContent.swift` — `"Privacy Policy"` (nav) + the 4 section titles/bodies + `closingLine`
- `AboutView.swift` — `"Copyright 2026 Alan Vardy"`, `"Made with love by a lone developer"`, `"About"`
- `AppearanceMode.swift` — `"System"`, `"Light"`, `"Dark"`
- `TextSize.swift` — `"System"`, `"Small"`, `"Medium"`, `"Large"`, `"Extra Large"`
- `SortOption+Presentation.swift` — `"Priority"`, `"Due Date"`, `"Title"`
- `ContentView.swift` — `"Nothing due"`, `"Only today's and overdue reminders show here — pull to refresh."`, `"You don't have any reminders yet."`, `"Pull to refresh to see all your reminders again."`, `"Enable access in Settings to see your reminders."`, `"Undo completion"`, `"Dictate reminder"`, `"Recording"`, `"View in Reminders"`, `"Swipe left to skip"`, `"Swipe right to complete"`, `"Dismiss"`, `"Dismiss swipe prompt"`, `"Has alarm"`
- `DictationViewModel.swift` — `"Speech recognition access is required."`, `"Speech recognition access was denied."`
- `CreationFeedback.swift` — `"Task created"`, `"Task creation failed"`
- `AppViewModel.swift` — `"SingleThread"` (notification title), `"You have %lld reminders waiting — open SingleThread!"` (notification body, with `variations.plural.one/other` per language)

Shared keys (`No Reminders`, `All Done`, `Reminders Access`, `Requesting access…`, `Completion glow`, `Complete`/`Skip`/`Delete` + a11y) are **not** duplicated here — they live only in the Core catalog.

#### 4. Watch catalog
**File**: `SingleThreadWatch/Resources/Localizable.xcstrings`
**Action**: create

Watch-only keys: `"Enable Reminders access in Settings"`, `"Upgrade on\nyour iPhone"`, `"Refresh"`, `"Reminder"` (confirmation-dialog title). Everything else in `WatchReminderView.swift` comes from the shared catalog.

#### 5. Widget catalog
**File**: `SingleThreadWidget/Resources/Localizable.xcstrings`
**Action**: create

Widget-only keys: `"Next Thing"` (gallery display name), `"Your next reminder, with Complete and Skip."` (gallery description), `"Open SingleThread to enable access."` (no-access message). Action labels / `Repeats` / `Alert` / empty states come from the shared catalog.

#### 6. `InfoPlist.strings` — app target
**Files**: `SingleThread/en.lproj/InfoPlist.strings`, `SingleThread/zh-Hans.lproj/InfoPlist.strings`, `SingleThread/es.lproj/InfoPlist.strings`, `SingleThread/ja.lproj/InfoPlist.strings`, `SingleThread/de.lproj/InfoPlist.strings`, `SingleThread/fr.lproj/InfoPlist.strings`
**Action**: create (six files)

English:

```
"NSMicrophoneUsageDescription" = "SingleThread needs microphone access to capture your voice for reminders.";
"NSRemindersUsageDescription" = "SingleThread needs access to show your reminders.";
"NSSpeechRecognitionUsageDescription" = "SingleThread uses speech recognition to create reminders from your voice.";
"CFBundleDisplayName" = "SingleThread";
```

The other five languages translate only the usage-description values (keep `CFBundleDisplayName` = `"SingleThread"` in all languages).

#### 7. `InfoPlist.strings` — watch target
**Files**: `SingleThreadWatch/{en,zh-Hans,es,ja,de,fr}.lproj/InfoPlist.strings`
**Action**: create

```
"NSRemindersFullAccessUsageDescription" = "SingleThread needs access to show your reminders.";
"CFBundleDisplayName" = "SingleThread";
```

#### 8. `InfoPlist.strings` — widget target
**Files**: `SingleThreadWidget/{en,zh-Hans,es,ja,de,fr}.lproj/InfoPlist.strings`
**Action**: create

```
"NSRemindersFullAccessUsageDescription" = "SingleThread needs access to show your reminders.";
"CFBundleDisplayName" = "SingleThread";
```

(The widget's physical `SingleThreadWidget/Info.plist` is unchanged; `NSHumanReadableCopyright` stays empty in build settings.)

#### 9. Project `knownRegions`
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

At pbxproj:444-447, extend `knownRegions` so the `.lproj` variant groups are recognized as localizations:

```
knownRegions = (
    en,
    Base,
    "zh-Hans",
    es,
    ja,
    de,
    fr,
);
```

Leave `developmentRegion = en` (pbxproj:442) untouched. No other pbxproj edits — synchronized folder groups auto-include the new `Resources/` and `.lproj/` files.

#### 10. `LocalizationTests` (Stage 1 version)
**File**: `SingleThreadTests/LocalizationTests.swift`
**Action**: create

Locates the four `.xcstrings` files and the `InfoPlist.strings` files on disk via `#filePath` (tests compile from the checkout, so `#filePath` of this file is the absolute source path):

```swift
import Foundation
import Testing

struct LocalizationTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SingleThreadTests/
        .deletingLastPathComponent()   // repo root

    private static let languages = ["en", "zh-Hans", "es", "ja", "de", "fr"]

    private static let catalogs: [(name: String, url: URL)] = [
        ("Core", repoRoot.appendingPathComponent("SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings")),
        ("App", repoRoot.appendingPathComponent("SingleThread/Resources/Localizable.xcstrings")),
        ("Watch", repoRoot.appendingPathComponent("SingleThreadWatch/Resources/Localizable.xcstrings")),
        ("Widget", repoRoot.appendingPathComponent("SingleThreadWidget/Resources/Localizable.xcstrings"))
    ]

    private static let infoPlistTargets: [(name: String, keys: [String])] = [
        ("App", ["NSMicrophoneUsageDescription", "NSRemindersUsageDescription",
                 "NSSpeechRecognitionUsageDescription", "CFBundleDisplayName"]),
        ("Watch", ["NSRemindersFullAccessUsageDescription", "CFBundleDisplayName"]),
        ("Widget", ["NSRemindersFullAccessUsageDescription", "CFBundleDisplayName"])
    ]

    @Test
    func catalogsParseAndHaveNonEmptyEnglish() throws {
        for (name, url) in Self.catalogs {
            let data = try Data(contentsOf: url)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = try #require(root["strings"] as? [String: Any])
            #expect(!strings.isEmpty, "\(name) catalog has no keys")
            for (key, value) in strings {
                let entry = try #require(value as? [String: Any], "\(name)/\(key) malformed")
                let localizations = try #require(entry["localizations"] as? [String: Any])
                let en = try #require(localizations["en"] as? [String: Any], "\(name)/\(key) missing en")
                let unit = en["stringUnit"] as? [String: Any]
                let enValue = unit?["value"] as? String
                #expect(enValue?.isEmpty == false, "\(name)/\(key) has empty en value")
            }
        }
    }

    @Test
    func infoPlistStringsHaveRequiredKeysPerLanguage() throws {
        for (target, keys) in Self.infoPlistTargets {
            for language in Self.languages {
                let path = repoRoot
                    .appendingPathComponent(pluralizedTargetPath(target))
                    .appendingPathComponent("\(language).lproj/InfoPlist.strings")
                let data = try Data(contentsOf: path)
                let plist = try #require(
                    try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
                for key in keys {
                    let value = try #require(plist[key], "\(target)/\(language) missing \(key)")
                    #expect(!value.isEmpty, "\(target)/\(language) \(key) is empty")
                }
            }
        }
    }
}
```

(`pluralizedTargetPath` maps `"App"`→`SingleThread/`, `"Watch"`→`SingleThreadWatch/`, `"Widget"`→`SingleThreadWidget/` — implement as a private helper.)

### Verification

#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug -derivedDataPath DerivedData test -only-testing:SingleThreadTests/LocalizationTests` passes (all catalogs parse; all `InfoPlist.strings` complete). If the name-only destination hangs (4 runtimes), pin `,id=3F6CFD49-B62B-43C2-B93F-50B0D9F87E4D`.
- [x] `make build` succeeds — empty/wired catalogs do not break compilation of any target.
- [x] `make watch-build` succeeds.

#### Manual
- [ ] Open the project in Xcode: each target's `Resources/Localizable.xcstrings` opens in the string-catalog editor with en + 5 languages; `InfoPlist.strings` appear as localizations (not plain groups) after the `knownRegions` edit.
- [ ] Confirm the generated app/watch `Info.plist` in `DerivedData/…/SingleThread.app/Info.plist` still contains the English usage strings (build-setting fallback), and the app bundle contains `zh-Hans.lproj/InfoPlist.strings` etc. — verifies the open `GENERATE_INFOPLIST_FILE=YES` + `InfoPlist.strings` risk at build time.

---

## Phase 2: Accessibility Identifiers

Add `.accessibilityIdentifier(_:)` to every interactive, navigable, and test-asserted element. **No test assertions change yet** — existing UI tests keep exact-string matching and must stay green.

### Changes

#### 1. `SingleThread/ContentView.swift`
**Action**: modify

Add identifiers (don't touch existing `.accessibilityLabel`/`.accessibilityHint`):

- Settings gear button → `"settingsButton"`
- Undo button → `"undoButton"`
- Mic button → `"dictateButton"`
- Complete button → `"completeButton"`; Skip → `"skipButton"`; Delete (macOS `actionButtons` + iOS context menu) → `"deleteButton"`
- Empty-state `ContentUnavailableView` title → `"emptyStateTitle"`; description → `"emptyStateDescription"`
- Upgrade prompt button → `"upgradeButton"`
- Recording indicator → `"recordingIndicator"`
- Keep existing identifiers: `completionGlowOverlay`, `pendingStatus`, `lastScheduleStatus`

```swift
Button { Task { await viewModel.completeCurrentReminder() } } label: {
    Label("Complete", systemImage: "checkmark.circle.fill")
        .labelStyle(.iconOnly)
        .controlPlate()
}
.accessibilityLabel("Complete reminder")
.accessibilityIdentifier("completeButton")
.accessibilityAddTraits(.isButton)
```

#### 2. `SingleThread/SettingsView.swift` + sub-screens
**Action**: modify

- `"settingsDoneButton"` (Done), row links: `"settingsInterfaceRow"`, `"settingsNotificationsRow"`, `"settingsReminderRow"`, `"settingsFilterSortRow"`, `"settingsBackgroundRow"`, `"settingsPurchaseRow"`, `"settingsPrivacyRow"`, `"settingsAboutRow"`
- `InterfaceSettingsView.swift`: `"appearancePicker"`, `"textSizePicker"`, `"allowLandscapeToggle"`, `"showMicrophoneToggle"`, `"showActionButtonsToggle"`, `"showSwipePromptToggle"`, `"showUndoButtonToggle"`
- `NotificationsSettingsView.swift`: `"notificationsEnabledToggle"`, `"notificationIntervalPicker"`
- `ReminderSettingsView.swift`: `"showDateToggle"`, `"showListToggle"`, `"showRecurrenceToggle"`, `"showAlarmsToggle"`, `"showCompletionGlowToggle"`
- `FilterSortSettingsView.swift`: `"sortByPicker"`, `"showUndatedRemindersToggle"`, `"excludedListsRow"`
- `BackgroundSettingsView.swift`: `"backgroundToggle"`, `"backgroundFadePicker"`, `"pinWallpaperToggle"`, `"refreshWallpaperButton"`
- `PurchaseSettingsView.swift`: `"restorePurchasesButton"`

#### 3. `SingleThread/ReminderCardView.swift`
**Action**: modify

- Priority marker → `"priorityMarker"`; due date → `"dueDateText"`; recurrence row → `"recurrenceLabel"`; alarm bell → `"alarmLabel"`; list name → `"listNameText"`; notes → `"notesText"`; swipe-prompt Dismiss → `"swipePromptDismissButton"`

#### 4. `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

- Complete → `"completeButton"`; Skip → `"skipButton"`; Refresh (button + dialog) → `"refreshButton"`; Delete (dialog) → `"deleteButton"`; empty-state title → `"emptyStateTitle"`; upgrade prompt → `"upgradePrompt"`; priority marker → `"priorityMarker"`; keep `"completionGlowOverlay"`

#### 5. `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

- Complete → `"completeButton"`; Skip → `"skipButton"`; empty-state title → `"emptyStateTitle"`; priority marker → `"priorityMarker"`; recurrence → `"recurrenceLabel"`; alarm → `"alertLabel"` (no widget UI-test target exists today; identifiers are future-proofing and harmless).

### Verification

#### Automated
- [x] `make ui-test` passes — zero changes to existing assertions (identifiers don't affect `staticTexts["…"]`/`buttons["…"]` lookups or `performAccessibilityAudit`).
- [x] `make watch-ui-test` passes unchanged.
- [x] `make test` passes unchanged (unit tests unaffected).

#### Manual
- [ ] In the iOS simulator (`make simverify`), run the app with VoiceOver: every button/row still reads its English a11y label; no element lost its label to the identifier.

---

## Phase 3: Core Shared Strings Migration

Wire `SingleThreadCore` code to the shared catalog, collapsing cross-target duplicates into one source of truth. After this phase, `String(localized: "Complete", table: "Localizable", bundle: .module)` resolves from anywhere.

### Changes

#### 1. `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift`
**Action**: modify

```swift
public var displayName: String {
    switch self {
    case .high: String(localized: "High", table: "Localizable", bundle: .module)
    case .medium: String(localized: "Medium", table: "Localizable", bundle: .module)
    case .low: String(localized: "Low", table: "Localizable", bundle: .module)
    }
}
```

(`marker` — `"!!!"`/`"!!"`/`"!"` — stays hardcoded; it's a symbol, not prose.)

#### 2. `SingleThreadCore/Sources/SingleThreadCore/ReminderRecurrenceFormatter.swift`
**Action**: modify

```swift
public static func format(_ rules: [EKRecurrenceRule]?) -> String? {
    guard let first = rules?.first else { return nil }
    let interval = first.interval
    switch first.frequency {
    case .daily:
        return interval > 1
            ? String(localized: "Every \(interval) days", table: "Localizable", bundle: .module)
            : String(localized: "Daily", table: "Localizable", bundle: .module)
    case .weekly:
        return interval > 1
            ? String(localized: "Every \(interval) weeks", table: "Localizable", bundle: .module)
            : String(localized: "Weekly", table: "Localizable", bundle: .module)
    case .monthly:
        return interval > 1
            ? String(localized: "Every \(interval) months", table: "Localizable", bundle: .module)
            : String(localized: "Monthly", table: "Localizable", bundle: .module)
    case .yearly:
        return interval > 1
            ? String(localized: "Every \(interval) years", table: "Localizable", bundle: .module)
            : String(localized: "Yearly", table: "Localizable", bundle: .module)
    @unknown default:
        return nil
    }
}
```

The `%lld` keys carry `variations.plural` (Phase 1) so interval ≥ 2 renders correctly in languages with more plural categories (en: `one`/`other`; zh-Hans/ja: `other` only).

#### 3. `SingleThreadCore/Sources/SingleThreadCore/AppInfo.swift`
**Action**: modify

```swift
public var versionDescription: String {
    guard let marketing = marketingVersion else { return "" }
    if let build = buildNumber {
        return String(localized: "Version \(marketing) (\(build))",
                      table: "Localizable", bundle: .module)
    }
    return String(localized: "Version \(marketing)",
                  table: "Localizable", bundle: .module)
}
```

`displayName`'s `"SingleThread"` fallback stays hardcoded (it's a bundle-key fallback, not user-facing copy).

#### 4. `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift`
**Action**: modify

Point both titles at the shared catalog (they run inside the widget/app process, so `Bundle.module` is the Core resource bundle):

```swift
public static let title: LocalizedStringResource = LocalizedStringResource(
    "Complete Reminder",
    table: "Localizable",
    bundle: .atURL(Bundle.module.bundleURL))
```

(same for `"Skip Reminder"` in `SkipReminderIntent`).

#### 5. `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`
**Action**: create

Typed accessors so app/watch/widget callers don't repeat `table:`/`bundle:`:

```swift
import Foundation

/// Typed accessors for the shared string catalog in this package.
public enum SharedStrings {
    public static var completeAction: String {
        String(localized: "Complete", table: "Localizable", bundle: .module)
    }
    public static var skipAction: String {
        String(localized: "Skip", table: "Localizable", bundle: .module)
    }
    public static var deleteAction: String {
        String(localized: "Delete", table: "Localizable", bundle: .module)
    }
    public static var completeReminderAccessibility: String {
        String(localized: "Complete reminder", table: "Localizable", bundle: .module)
    }
    public static var skipReminderAccessibility: String {
        String(localized: "Skip reminder", table: "Localizable", bundle: .module)
    }
    public static var deleteReminderAccessibility: String {
        String(localized: "Delete reminder", table: "Localizable", bundle: .module)
    }
    public static var completionGlow: String {
        String(localized: "Completion glow", table: "Localizable", bundle: .module)
    }
    public static var allDone: String {
        String(localized: "All Done", table: "Localizable", bundle: .module)
    }
    public static var noReminders: String {
        String(localized: "No Reminders", table: "Localizable", bundle: .module)
    }
    public static var repeats: String {
        String(localized: "Repeats", table: "Localizable", bundle: .module)
    }
    public static var alert: String {
        String(localized: "Alert", table: "Localizable", bundle: .module)
    }
    public static func priorityAccessibilityLabel(_ levelName: String) -> String {
        String(localized: "\(levelName) priority", table: "Localizable", bundle: .module)
    }
}
```

Add the remaining shared keys (`Reminders Access`, `Requesting access…`, `Nothing due right now`, `No reminders yet`) as needed by Phases 4–5.

#### 6. Tests
**File**: `SingleThreadTests/ReminderSkipTests.swift`
**Action**: modify

Add `displayName` coverage that pins locale (see Phase 6 for the shared helper):

```swift
@Test
func displayNameLocalizes() {
    #expect(ReminderPriority.Level.high.displayName == "High")
    #expect(ReminderPriority.Level.medium.displayName == "Medium")
    #expect(ReminderPriority.Level.low.displayName == "Low")
}
```

**File**: `SingleThreadTests/ReminderRecurrenceFormatterTests.swift`
**Action**: modify

Existing en assertions (`"Daily"`, `"Every 2 days"`, …) stay valid. Add:

```swift
@Test
func recurrenceUsesPluralAwareLookup() {
    let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil)
    #expect(ReminderRecurrenceFormatter.format([rule]) == "Every 2 days")
}
```

**File**: `SingleThreadTests/AppInfoTests.swift`
**Action**: modify

Existing `"Version 1.0 (1)"` / `"Version 1.0"` assertions stay valid (en locale); keep as-is.

**File**: `SingleThreadTests/ReminderIntentsTests.swift`
**Action**: no change

Existing `String(localized: …title)` assertions already exercise the new bundle/table resolution.

### Verification

#### Automated
- [x] `make test` passes — Core unit suites (ReminderSkip, ReminderRecurrenceFormatter, AppInfo, ReminderIntents) green under the default en locale.
- [x] `make build` succeeds — catalog wired through `Bundle.module`.
- [x] `make watch-build` succeeds — proves `Bundle.module` resolves inside the watch extension process (the design's open risk).

#### Manual
- [ ] Temporarily run one Core test with a `Locale(identifier: "zh-Hans")` override and confirm `displayName`/recurrence output changes (then revert) — sanity-checks that the catalog, not the fallback, is serving.

---

## Phase 4: App Target Localization

Move every hardcoded English literal in `SingleThread/` to the app catalog, using shared keys from Phase 3 where applicable. Two rules keep this mechanical:

1. **App-only SwiftUI literals** (`Text("…")`, `Label("…", systemImage:)`, `Button("…")`, `Picker("…")`, `Toggle` labels, `.navigationTitle("…")`, `ContentUnavailableView` title/description) need **no code change** — they resolve through `LocalizedStringKey` against the app catalog. Just ensure the key exists (Phase 1).
2. **Shared strings** switch to `SharedStrings.*` (a pre-localized `String`).
3. **Computed `String` values** (view-model properties, notification content, `accessibilityLabel` computed vars) switch to `String(localized:table:"Localizable",bundle:.main)`.

### Changes

#### 1. `SingleThread/ContentViewModel.swift`
**Action**: modify

`EmptyStateCopy` keeps its `String` fields but sources them from the catalogs:

```swift
static func emptyStateCopy(hasHidden: Bool) -> EmptyStateCopy {
    if hasHidden {
        return EmptyStateCopy(
            title: String(localized: "Nothing due", table: "Localizable", bundle: .main),
            systemImage: "calendar",
            description: String(localized: "Only today's and overdue reminders show here — pull to refresh.",
                                    table: "Localizable", bundle: .main))
    }
    return EmptyStateCopy(
        title: SharedStrings.noReminders,
        systemImage: "checklist",
        description: String(localized: "You don't have any reminders yet.",
                                    table: "Localizable", bundle: .main))
}

static func allDoneStateCopy() -> EmptyStateCopy {
    EmptyStateCopy(
        title: SharedStrings.allDone,
        systemImage: "checkmark.circle",
        description: String(localized: "Pull to refresh to see all your reminders again.",
                                table: "Localizable", bundle: .main))
}
```

#### 2. `SingleThread/AppViewModel.swift`
**Action**: modify

```swift
content.title = String(localized: "SingleThread", table: "Localizable", bundle: .main)
content.body = String(localized: "You have \(count) reminders waiting — open SingleThread!",
                      table: "Localizable", bundle: .main)
```

The `%lld` body key has plural variations in the app catalog. The UI-test seam `summary(requests:)` interpolates `first.content.body`, so under the en locale its output is byte-identical to today (`body=You have 2 reminders waiting — open SingleThread!`) and the notification UI tests keep passing.

#### 3. `SingleThread/DictationViewModel.swift`
**Action**: modify

```swift
dictationError = String(localized: "Speech recognition access is required.",
                        table: "Localizable", bundle: .main)
// …
dictationError = String(localized: "Speech recognition access was denied.",
                        table: "Localizable", bundle: .main)
```

#### 4. `SingleThread/CreationFeedback.swift`
**Action**: modify

```swift
var accessibilityLabel: String {
    switch self {
    case .success: String(localized: "Task created", table: "Localizable", bundle: .main)
    case .failure: String(localized: "Task creation failed", table: "Localizable", bundle: .main)
    }
}
```

#### 5. `SingleThread/ContentView.swift`
**Action**: modify

Swap shared strings to the `SharedStrings` namespace (pre-localized `String`, so the `StringProtocol` view overloads render the already-localized value):

```swift
// macOS actionButtons + iOS completeButton/skipButton:
Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
    .labelStyle(.iconOnly)
// …
.accessibilityLabel(SharedStrings.completeReminderAccessibility)
```

- `"Delete"` context menu / macOS button → `SharedStrings.deleteAction`; `"Delete reminder"` a11y → `SharedStrings.deleteReminderAccessibility`
- `"Completion glow"` (glow overlay + its a11y) → `SharedStrings.completionGlow`
- `authGatedContent`: `ProgressView("Requesting access…")` → shared `"Requesting access…"`; `ContentUnavailableView("Reminders Access", …)` → shared `"Reminders Access"`; its `description` stays app-only
- `"Dictate reminder"`, `"Undo completion"`, `"Recording"`, `"View in Reminders"`, `"Settings"` (gear a11y) stay app-only → ensure keys exist; no code change beyond what's already there
- Dictation error `Text(error)` / recording indicator render view-model-provided strings (already localized at source)

#### 6. `SingleThread/ReminderCardView.swift`
**Action**: modify

```swift
.accessibilityLabel(SharedStrings.priorityAccessibilityLabel(level.displayName))
// …
Text(display.recurrenceSummary ?? SharedStrings.repeats)
// …
Image(systemName: "bell")
    .accessibilityLabel(String(localized: "Has alarm", table: "Localizable", bundle: .main))
```

Swipe-prompt `Text("Swipe left to skip")` / `"Swipe right to complete"` / `"Dismiss"` and `"Dismiss swipe prompt"` stay app-only literals (keys already added in Phase 1).

#### 7. `SingleThread/AboutView.swift`, `SingleThread/PrivacySettingsContent.swift`
**Action**: no code change (view literals resolve via LocalizedStringKey); the `versionDescription` flows through `AppInfo` (Phase 3). Ensure keys exist in the app catalog.

#### 8. `SingleThread/AppearanceMode.swift`, `TextSize.swift`, `SortOption+Presentation.swift`
**Action**: modify

`title` computed vars are rendered as `Label(mode.title, systemImage:)` with a `String` argument (verbatim), so localize at source:

```swift
var title: String {
    switch self {
    case .system: String(localized: "System", table: "Localizable", bundle: .main)
    case .light: String(localized: "Light", table: "Localizable", bundle: .main)
    case .dark: String(localized: "Dark", table: "Localizable", bundle: .main)
    }
}
```

Same pattern for `TextSize.title` (`System/Small/Medium/Large/Extra Large`) and `SortOption.title` (`Priority/Due Date/Title`).

#### 9. Settings sub-screens (`InterfaceSettingsView`, `NotificationsSettingsView`, `ReminderSettingsView`, `FilterSortSettingsView`, `BackgroundSettingsView`, `PurchaseSettingsView`, `ExcludedListsView`, `SettingsView`)
**Action**: no code change for row/picker/toggle literals (LocalizedStringKey resolves them). One exception — `BackgroundSettingsView` footer is dynamic:

```swift
Link(
    String(localized: "Photo by \(photographer) on Unsplash", table: "Localizable", bundle: .main),
    destination: url)
```

and the `accessibilityValue` `"Refreshing"` becomes `String(localized: "Refreshing", table: "Localizable", bundle: .main)`. `ReminderSettingsView`'s `"Completion glow"` toggle → `SharedStrings.completionGlow`.

#### 10. Tests (string-literal assertions)
**Files**: `SingleThreadTests/SingleThreadTests.swift`, `SettingsViewTests.swift`, `AboutViewTests.swift`, `SwipePromptTests.swift`, `MicrophoneToggleTests.swift`, `PrivacySettingsContentTests.swift`, `ActionButtonTests.swift`
**Action**: modify

- `SingleThreadTests.swift` `contentViewEmptyStatesShowDistinctCopy` / `contentViewAllDoneShowsAllDoneCopy`: replace hardcoded literals with `String(localized:table:bundle:.main)` or the `ContentViewModel` values themselves (compare title/description against the now-localized properties).
- `SettingsViewTests.swift`, `AboutViewTests.swift`, `SwipePromptTests.swift`, `MicrophoneToggleTests.swift`, `PrivacySettingsContentTests.swift`: these assert `String(describing: view.body).contains("literal")`. Because SwiftUI `Text`/`Label` serialize the key (not the resolved value) and computed vars now hold localized strings, update the expected literals to the catalog keys where a view literal is reflected, or drop the text assertion where it now depends on runtime localization. For `PrivacySettingsContentTests`, switch assertions to the raw `PrivacyGuideContent` values (they remain en under the default locale).
- `ActionButtonTests.swift`: unaffected (gate logic only).

### Verification

#### Automated
- [x] `make test` passes — updated unit suites green under en locale.
- [x] `make build` succeeds.
- [x] `make ui-test` passes — notification body seam and all flows still match en output.
- [x] `make lint` passes (`swiftformat --lint` + `swiftlint lint --strict`).

#### Manual
- [ ] Launch the app in the simulator and click through Settings → every sub-screen, the About screen, the swipe prompt, the dictation error path, and the upgrade prompt — all still read natural English (no raw keys, no missing strings).

---

## Phase 5: Watch + Widget Localization

Wire the watch app and widget extension to their catalogs plus the shared Core catalog.

### Changes

#### 1. `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

- `Text("All Done")` → `Text(SharedStrings.allDone)`; `Text("No Reminders")` → `Text(SharedStrings.noReminders)`; `"Nothing due right now"`/`"No reminders yet"` → `SharedStrings` counterparts
- Action `Label("Complete"/"Skip", systemImage:)` + a11y → `SharedStrings.completeAction`/`skipAction`/`completeReminderAccessibility`/`skipReminderAccessibility`
- Priority a11y → `SharedStrings.priorityAccessibilityLabel(level.displayName)`
- `"Repeats"` fallback → `SharedStrings.repeats`; `"Alert"` → `SharedStrings.alert`; glow a11y → `SharedStrings.completionGlow`
- Watch-only literals stay in place and resolve against the watch catalog: `ProgressView("Requesting access…")` (shared), `Text("Enable Reminders access in Settings")`, `Text("Upgrade on\nyour iPhone")`, `Button("Refresh")`, `confirmationDialog("Reminder", …)`, `Button("Delete", role: .destructive)` → `SharedStrings.deleteAction`

#### 2. `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

```swift
.configurationDisplayName(
    LocalizedStringResource("Next Thing", table: "Localizable", bundle: .main))
.description(
    LocalizedStringResource("Your next reminder, with Complete and Skip.",
                            table: "Localizable", bundle: .main))
```

- No-access title `"Reminders Access"` → `SharedStrings.remindersAccess`; message `"Open SingleThread to enable access."` → widget catalog
- Empty states → `SharedStrings.allDone`/`noReminders` + shared `"Nothing due right now"`/`"No reminders yet"`
- Action `Label("Complete"/"Skip", …)` + a11y → `SharedStrings.completeAction`/`skipAction`/`completeReminderAccessibility`/`skipReminderAccessibility`
- `"Repeats"` → `SharedStrings.repeats`; `"Alert"` → `SharedStrings.alert`

#### 3. `SingleThreadWidget/NextThingWidgetView.swift`
**Action**: modify (same shared-namespace swaps for any remaining view-body literals; `ReminderDisplay` user data untouched).

#### 4. `SingleThreadWatchTests/`
**Action**: modify

Watch unit tests assert fixture data only (no app copy) — verify none break; add a watch-side catalog smoke test if `WatchReminderViewRegressionTests` asserts any literal.

### Verification

#### Automated
- [ ] `make watch-build` succeeds.
- [ ] `make build` succeeds (widget + app + embed).
- [ ] `make watch-test` passes.
- [ ] `make watch-ui-test` passes under en locale.

#### Manual
- [ ] Add the widget to the simulator home screen: gallery name/description, empty state, and a seeded reminder render correctly.
- [ ] Launch the watch app in the watch simulator: empty states, action buttons, confirmation dialog, and upgrade prompt render without raw keys.

> **Deviation**: structure.md lists "Widget snapshot tests" in this phase, but the repo has no widget test target (`SingleThreadWidget` is an app-extension only; schemes expose only `SingleThreadTests`, `SingleThreadUITests`, `SingleThreadWatchTests`, `SingleThreadWatchUITests`). Widget rendering is verified via `make build` + the manual simulator check above; widget catalog integrity is covered by `LocalizationTests`.

---

## Phase 6: Test Migration & Final Verification

Switch UI tests from exact-string matching to accessibility identifiers, hard-pin unit tests to `Locale(identifier: "en")`, and expand `LocalizationTests` to full six-language integrity.

### Changes

#### 1. `SingleThreadUITests/` — all 8 files
**Action**: modify

Replace app-copy element lookups with identifier lookups; keep **user-data** matches (seed fixture titles/notes) as text:

```swift
// Before
XCTAssertTrue(app.staticTexts["All Done"].waitForExistence(timeout: 5))
app.buttons["Complete reminder"].tap()
let toggle = app.switches["Enable reminder notifications"]

// After
XCTAssertTrue(app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5))
app.buttons["completeButton"].tap()
let toggle = app.switches["notificationsEnabledToggle"]
```

File-by-file:
- `ActionButtonsUITests.swift` — `buttons["Complete reminder"]`→`["completeButton"]`, `["Skip reminder"]`→`["skipButton"]`, `staticTexts["All Done"]`→`["emptyStateTitle"]`
- `SingleThreadUITestsFlows.swift` — settings rows → row identifiers, action buttons → `completeButton`/`skipButton`/`deleteButton`, empty states → `emptyStateTitle`, `"High priority"` → `staticTexts["priorityMarker"]`, `"Copyright 2026 Alan Vardy"`/`"Made with love by a lone developer"`/`"Version 1.0 (1)"` → About identifiers or drop (About assertions are cosmetic; keep `staticTexts["Version 1.0 (1)"]` as an en-pinned check or switch to an `aboutVersionText` identifier). Seed titles `"Buy groceries"`/`"First"`/`"Second"` stay text-matched.
- `NotificationsUITests.swift` / `NotificationSchedulingUITests.swift` / `NotificationsSettingsUITests.swift` — `"Settings"`→`settingsButton`, `"Notifications"` row → `settingsNotificationsRow`, `"Enable reminder notifications"`→`notificationsEnabledToggle`, `"Done"`→`settingsDoneButton`, `BEGINSWITH "Remind after"` → `buttons["notificationIntervalPicker"]`; `contains("48 hours")` value check stays (en-pinned), `contains("body=You have 2 reminders waiting — open SingleThread!")` seam assertions stay (en-pinned body). Keep `pendingStatus`/`lastScheduleStatus` identifiers.
- `SingleThreadUITestsAppearanceLaunchTests.swift` — `"Appearance"` lookups → `appearancePicker` identifier.
- `SingleThreadUITests.swift` / `SingleThreadUITestsLaunchTests.swift` — audit/launch smoke tests; audit already asserts no copy directly (no change), launch test asserts launch only.

#### 2. `SingleThreadWatchUITests/` — `SingleThreadWatchUITests.swift` + `SingleThreadWatchUITestsFlows.swift`
**Action**: modify

- `buttons["Complete reminder"]`→`["completeButton"]`, `["Skip reminder"]`→`["skipButton"]`, `["Delete"]`→`["deleteButton"]`, `["Refresh"]`→`["refreshButton"]`
- `staticTexts["All Done"]`/`["No Reminders"]`→`["emptyStateTitle"]`; `"Low priority"`→`["priorityMarker"]`; `"Upgrade on\nyour iPhone"`→`["upgradePrompt"]`
- Seed titles `"Buy groceries"`/`"Don't forget the milk"` stay text-matched.

#### 3. `SingleThreadTests/` — en-locale pinning
**Action**: modify

Add a shared test helper (new file `SingleThreadTests/LocalizationTestHelpers.swift`):

```swift
import Foundation

extension String {
    /// Localizes a key from the given bundle with the test suite's pinned locale,
    /// so unit tests assert deterministic English output regardless of host locale.
    static func en(_ key: String.LocalizationValue, table: String = "Localizable",
                   bundle: Bundle) -> String {
        String(localized: key, table: table, bundle: bundle, locale: Locale(identifier: "en"))
    }
}
```

Update the ~101 literal sites that now flow through `String(localized:)` (AppInfo, ReminderSkip, ReminderRecurrenceFormatter, EmptyStateCopy, SettingsView/AboutView/SwipePrompt reflection checks) to use `String.en(...)` with the correct bundle (`.module` for Core keys, `.main` for app keys) — or simply re-assert the localized value under the pinned locale. Exact-English assertions continue to pass because the locale is pinned to `en`.

#### 4. `SingleThreadTests/LocalizationTests.swift` — expand
**Action**: modify

Add tests:
- Every key in every catalog has a **non-empty `en`** value (Phase 1 test, kept).
- Every key has a `localizations` entry for **all six languages** with non-empty `stringUnit.value` (or non-empty plural variation values).
- **No orphaned keys**: for each catalog, assert every key is referenced somewhere in the matching target(s) via a `grep` of the source (run as a script step rather than inside XCTest — see verification below).
- **Plural variants** exist for `Every %lld …`, `You have %lld …`, and `%@ priority`/`Version %@` in each locale where the CLDR plural rules demand more than `other`.

### Verification

#### Automated
- [ ] `make format` then `make lint` clean.
- [ ] `make test` — all unit suites green under pinned `en`.
- [ ] `make ui-test` — all 8 iOS UI files green on identifiers.
- [ ] `make watch-ui-test` — both watch UI files green.
- [ ] `make periphery` — zero dead code (catalogs/resources don't register as dead; `SharedStrings` members are all referenced).
- [ ] `./scripts/test.sh` — full CI-identical gate (format, lint, build, Periphery, unit + UI + watch UI, macOS build/test) passes.

#### Manual
- [ ] Set the simulator language to `Deutsch` (Settings → General → Language & Region → German), relaunch, and spot-check: settings rows, empty state, action buttons, About, and the widget all render German; usage-description strings appear in German when triggering Reminders/mic permission.
- [ ] Repeat for `zh-Hans` and `es` (quick spot-check; the full six languages are validated structurally by `LocalizationTests`).
- [ ] Review the machine-translated strings for gesture metaphors (`Swipe left/right`) and plural forms; correct any that are culturally wrong in the catalogs.
- [ ] Create the App Store listing localization follow-up ticket in Linear (VAR-xxx) — out of scope for this change but documented in the design.

---

## Testing Checkpoints

| After Phase | Must be green |
|---|---|
| 1 | `LocalizationTests` (targeted xcodebuild) + `make build` + `make watch-build` |
| 2 | `make ui-test` + `make watch-ui-test` + `make test` (assertions unchanged) |
| 3 | `make test` + `make build` + `make watch-build` |
| 4 | `make test` + `make ui-test` + `make build` + `make lint` |
| 5 | `make build` + `make watch-build` + `make watch-test` + `make watch-ui-test` |
| 6 | `./scripts/test.sh` (full gate) + manual non-English simulator check |

## Deviations from `structure.md`

1. **Stage 1 ships six-language content, not English-only.** The structure says catalogs are "populated with English entries" but also mandates six-language `InfoPlist.strings` in the same stage; a complete resource layer requires all six languages for both catalogs and `.strings` files. Translations are machine-translated (DeepL) with human review of gesture/plural metaphors in Phase 6.
2. **`swift test --filter LocalizationTests` → targeted `xcodebuild -only-testing:SingleThreadTests/LocalizationTests`.** `SingleThreadCore` has no SPM test target; unit tests run in the Xcode `SingleThreadTests` bundle (Swift Testing via xcodebuild).
3. **`ContentViewModelTests` doesn't exist** — structure.md names it, but the real files are `SingleThreadTests.swift` (empty-state assertions), `ActionButtonTests.swift`, `SwipePromptTests.swift`, `MicrophoneToggleTests.swift`, `AboutViewTests.swift`, `PrivacySettingsContentTests.swift`. The plan maps to those.
4. **No widget snapshot-test target exists** — widget rendering is verified via `make build` + manual simulator check; catalog integrity via `LocalizationTests`.
5. **`knownRegions` pbxproj edit added** (structure implied but didn't state it) — required for `.lproj` localizations to be recognized under the synchronized-folder layout.
6. **Shared-catalog key list refined** — structure's `"Nothing due"` is actually app-only; the shared watch+widget sub-copy is `"Nothing due right now"`. `"Reminders Access"` and `"Requesting access…"` are also cross-target duplicates moved into the shared catalog.

Next: run `/6_implement` to implement.

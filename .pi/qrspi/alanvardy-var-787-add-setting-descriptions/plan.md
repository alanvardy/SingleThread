# Implementation Plan — Add setting descriptions

## Overview

Add a static caption under every root navigation row (8) and every control row
(21) in the iOS/macOS Settings UI, for 29 captions total. Captions are
`Text("…")` literals auto-localized against the App catalog in all six
languages, rendered with `.font(.caption)` + `.foregroundStyle(.secondary)`.
No new state, persistence, or catalog edits outside the App target.

---

## Deviation from `structure.md`

**`.accessibilityElement(children: .combine)` is dropped** (Resolution A).
With `.combine`, SwiftUI merges title and caption into a single accessibility
element, which deletes the standalone `staticTexts["…"]` / `switches["…"]`
queries that existing UI tests use to find rows by label (e.g.
`app.switches["Show swipe prompt"]`, `app.staticTexts["Interface"]`). Dropping
it keeps every existing UI-test locator byte-identical. On the one switch
matched by label (`"Show swipe prompt"`), we add an explicit
`.accessibilityLabel("Show swipe prompt")` to the toggle itself so the
switch remains findable without `.combine`. VoiceOver announces title then
caption as distinct elements on every row — identical behavior to today.

---

## Caption Copy (canonical, 29 keys)

All keys are added to `SingleThread/Resources/Localizable.xcstrings` with
`extractionState = "manual"`, `state = "translated"` in all six languages.
No plurals. No plural variations needed — all captions are static sentences.

### Root rows (8)

| Row | Key (English literal) |
|---|---|
| Interface | `"Customize the appearance, text size, and controls."` |
| Notifications | `"Get reminded when you have due reminders."` |
| Reminder | `"Choose what information is shown with each reminder."` |
| Filtering & Sorting | `"Control the order, visibility, and excluded lists."` |
| Background | `"Manage the wallpaper and its appearance."` |
| Purchase | `"View and manage your purchase status."` |
| Privacy Policy | `"How SingleThread handles your data."` |
| About | `"App version, credits, and contact."` |

### Interface (7; 3 iOS-only)

| Row | Key |
|---|---|
| Appearance | `"Choose between system, light, and dark mode."` |
| Text Size | `"Adjust the size of text throughout the app."` |
| Allow landscape | `"Let the app rotate on iPhone."` **(iOS only)** |
| Show microphone | `"Add a microphone button for voice input."` |
| Show action buttons | `"Show complete, skip, and delete buttons."` **(iOS only)** |
| Show swipe prompt | `"Show a hint when there are swipeable reminders."` **(iOS only)** |
| Show undo button | `"Show an undo button after completing a reminder."` **(iOS only)** |

### Notifications (2; iOS-only reachable)

| Row | Key |
|---|---|
| Enable reminder notifications | `"Send a notification when you have due reminders."` |
| Remind after | `"How long to wait before sending another reminder."` |

### Reminder (5)

| Row | Key |
|---|---|
| Show date | `"Show the due date next to each reminder."` |
| Show list | `"Show which list each reminder belongs to."` |
| Recurrence indicator | `"Show if a reminder repeats."` |
| Reminder alerts | `"Show if a reminder has a time alert."` |
| Completion glow | `"Show a sparkle animation when a reminder is completed."` |

### Filtering & Sorting (3)

| Row | Key |
|---|---|
| Sort By | `"Choose the order reminders appear in."` |
| Show undated reminders | `"Include reminders that have no due date."` |
| Excluded Lists (link row) | `"Hide specific lists from the reminder view."` |

### Background (4)

| Row | Key |
|---|---|
| Background | `"Show a wallpaper behind the reminder list."` |
| Background Fade | `"How much the wallpaper fades for readability."` |
| Pin wallpaper | `"Prevents the background from refreshing automatically."` |
| Refresh wallpaper | `"Fetch a new wallpaper now."` |

---

## Phase 1: Catalog & copy

### Changes

#### 1. Add 29 caption keys to App catalog
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify (insert 29 new keys before closing `}` of `"strings"`)

Each new key follows the existing pattern exactly (one key shown; repeat for all 29):

```json
"Customize the appearance, text size, and controls.": {
  "extractionState": "manual",
  "localizations": {
    "en": {
      "stringUnit": {
        "state": "translated",
        "value": "Customize the appearance, text size, and controls."
      }
    },
    "zh-Hans": {
      "stringUnit": {
        "state": "translated",
        "value": "自定义外观，文本大小和控件。"
      }
    },
    "es": {
      "stringUnit": {
        "state": "translated",
        "value": "Personaliza la apariencia, el tamaño del texto y los controles."
      }
    },
    "ja": {
      "stringUnit": {
        "state": "translated",
        "value": "外観、テキストサイズ、コントロールをカスタマイズします。"
      }
    },
    "de": {
      "stringUnit": {
        "state": "translated",
        "value": "Passe Erscheinungsbild, Textgröße und Steuerelemente an."
      }
    },
    "fr": {
      "stringUnit": {
        "state": "translated",
        "value": "Personnalisez l'apparence, la taille du texte et les contrôles."
      }
    }
  }
}
```

Repeat for all 29 keys. All six languages get non-empty `"translated"` values.
Non-English translations are placeholder-quality; skim before merge (Open Risk
from design.md).

### Verification

#### Automated
- [x] `make build && make lint` passes (catalog parses, no unused-key warnings)
- [x] `xcodebuild -only-testing:SingleThreadTests/LocalizationTests -destination "$SIM"`:
  `catalogsParseAndHaveNonEmptyEnglish` + `catalogsHaveAllSixLanguages` both green
  — proves every new key is non-empty in all six languages

#### Manual
- [ ] Open `.xcstrings` in Xcode — no key is marked "Needs Review" (all `"translated"`)

---

## Phase 2: Caption primitive

### Changes

#### 1. New file — `SettingsCaption.swift`
**File**: `SingleThread/SettingsCaption.swift`
**Action**: create

```swift
import SwiftUI

// MARK: - SettingsCaption

/// Shared caption styling used under every settings row title.
/// Call sites pass a `LocalizedStringKey` literal so Style A
/// auto-localization is preserved.
struct SettingsCaption: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - SettingsLinkLabel

/// NavigationLink label with a title, system image, and caption subtitle.
/// Used for the eight root settings rows.
struct SettingsLinkLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let caption: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(title)
                SettingsCaption(text: caption)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}
```

No `.accessibilityElement(children: .combine)` — see Deviation note at top.

#### 2. New unit test file
**File**: `SingleThreadTests/SettingsCaptionTests.swift`
**Action**: create

```swift
@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct SettingsCaptionTests {
    @Test
    func captionRendersText() {
        let view = SettingsCaption(text: "Show the due date next to each reminder.")
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("Show the due date next to each reminder."))
    }

    @Test
    func captionTextDoesNotMatchExistingLabels() {
        // Caption strings are full sentences; no label collision.
        let captions: [LocalizedStringKey] = [
            "Show the due date next to each reminder.",
            "Show which list each reminder belongs to.",
            "Show if a reminder has a time alert."
        ]
        let labels: Set<String> = [
            "Show date", "Show list", "Reminder alerts", "Interface",
            "Reminder", "Background", "Appearance", "Text Size",
            "Sort By", "Privacy Policy", "About", "Done", "Unlock",
            "Completion glow"
        ]
        for caption in captions {
            let desc = String(describing: caption)
            for label in labels {
                #expect(!desc.contains(label),
                        "Caption must not embed an existing row label: \(desc) contains \(label)")
            }
        }
    }

    @Test
    func linkLabelContainsTitleAndCaption() {
        let view = SettingsLinkLabel(
            title: "Reminder",
            systemImage: "bell.badge",
            caption: "Choose what information is shown with each reminder.")
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("Reminder"))
        #expect(bodyDescription.contains("Choose what information is shown with each reminder."))
    }
}
```

### Verification

#### Automated
- [ ] `make build && make lint` — both new files compile, SwiftLint clean
- [ ] `xcodebuild -only-testing:SingleThreadTests/SettingsCaptionTests -destination "$SIM"` — three `@Test`s green
- [ ] `make periphery` — no dead code (SettingsCaption used in Phase 3)

---

## Phase 3: Apply captions to every screen

### Changes

#### 1. SettingsView — 8 root rows
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Replace each root-row `NavigationLink` label with `SettingsLinkLabel`. The
Purchase row is dynamic ("Manage Purchase" / "Unlock") and uses a wrapped
`LocalizedStringKey`.

```swift
// Interface row
} label: {
    SettingsLinkLabel(
        title: "Interface",
        systemImage: "paintpalette",
        caption: "Customize the appearance, text size, and controls.")
}

// Notifications row (inside #if os(iOS))
} label: {
    SettingsLinkLabel(
        title: "Notifications",
        systemImage: "bell.badge",
        caption: "Get reminded when you have due reminders.")
}

// Reminder row
} label: {
    SettingsLinkLabel(
        title: "Reminder",
        systemImage: "bell.badge",
        caption: "Choose what information is shown with each reminder.")
}

// Filtering & Sorting row
} label: {
    SettingsLinkLabel(
        title: "Filtering & Sorting",
        systemImage: "line.3.horizontal.decrease",
        caption: "Control the order, visibility, and excluded lists.")
}

// Background row
} label: {
    SettingsLinkLabel(
        title: "Background",
        systemImage: "photo.on.rectangle",
        caption: "Manage the wallpaper and its appearance.")
}

// Purchase row — dynamic title
let purchaseTitle = LocalizedStringKey(
    entitlementStore.isEntitled ? "Manage Purchase" : "Unlock")
let purchaseIcon = entitlementStore.isEntitled ? "checkmark.seal" : "lock.open"
} label: {
    SettingsLinkLabel(
        title: purchaseTitle,
        systemImage: purchaseIcon,
        caption: "View and manage your purchase status.")
}

// Privacy Policy row
} label: {
    SettingsLinkLabel(
        title: "Privacy Policy",
        systemImage: "hand.raised",
        caption: "How SingleThread handles your data.")
}

// About row
} label: {
    SettingsLinkLabel(
        title: "About",
        systemImage: "info.circle",
        caption: "App version, credits, and contact.")
}
```

Pre-existing `.accessibilityLabel` / `.accessibilityAddTraits` on the Purchase
and About rows remain **after** the label closure — no change to identifiers.

#### 2. InterfaceSettingsView — 7 control captions
**File**: `SingleThread/InterfaceSettingsView.swift`
**Action**: modify

Every Toggle and Picker label changes from bare `Label("…", systemImage:)` or
`"…"` literal to a `Label { VStack { title; caption } } icon: { Image }` or
`label: { VStack { title; caption } }` pattern. iOS-only toggles stay inside
existing `#if os(iOS)` gates. The "Show swipe prompt" toggle gets
`.accessibilityLabel("Show swipe prompt")` per Resolution A.

```swift
// Appearance — Picker with caption (label: closure, no icon)
Picker(selection: $appearanceMode) {
    ForEach(AppearanceMode.allCases, id: \.self) { mode in
        Label(mode.title, systemImage: mode.systemImage).tag(mode)
    }
} label: {
    VStack(alignment: .leading) {
        Text("Appearance")
        SettingsCaption(text: "Choose between system, light, and dark mode.")
    }
}
.accessibilityIdentifier("appearancePicker")

// Text Size — same shape
Picker(selection: $textSize) {
    ForEach(TextSize.allCases, id: \.self) { size in
        Label(size.title, systemImage: size.systemImage).tag(size)
    }
} label: {
    VStack(alignment: .leading) {
        Text("Text Size")
        SettingsCaption(text: "Adjust the size of text throughout the app.")
    }
}
.accessibilityIdentifier("textSizePicker")

#if os(iOS)
// Allow landscape — Toggle with Label + icon + caption
Toggle(isOn: $allowsLandscape) {
    Label {
        VStack(alignment: .leading) {
            Text("Allow landscape")
            SettingsCaption(text: "Let the app rotate on iPhone.")
        }
    } icon: {
        Image(systemName: "rectangle.landscape.rotate")
    }
}
.accessibilityIdentifier("allowLandscapeToggle")
.onChange(of: allowsLandscape) { _, newValue in
    viewModel.allowsLandscapeChanged(newValue)
}
#endif

// Show microphone — Toggle
Toggle(isOn: $showMicrophoneButton) {
    Label {
        VStack(alignment: .leading) {
            Text("Show microphone")
            SettingsCaption(text: "Add a microphone button for voice input.")
        }
    } icon: {
        Image(systemName: "microphone")
    }
}
.accessibilityIdentifier("showMicrophoneToggle")

#if os(iOS)
// Show action buttons — Toggle
Toggle(isOn: $enableActionButtons) {
    Label {
        VStack(alignment: .leading) {
            Text("Show action buttons")
            SettingsCaption(text: "Show complete, skip, and delete buttons.")
        }
    } icon: {
        Image(systemName: "hand.tap")
    }
}
.accessibilityIdentifier("showActionButtonsToggle")

// Show swipe prompt — Toggle + explicit a11y label (Resolution A)
Toggle(isOn: $showSwipePrompt) {
    Label {
        VStack(alignment: .leading) {
            Text("Show swipe prompt")
            SettingsCaption(text: "Show a hint when there are swipeable reminders.")
        }
    } icon: {
        Image(systemName: "arrow.left.arrow.right")
    }
}
.accessibilityIdentifier("showSwipePromptToggle")
.accessibilityLabel("Show swipe prompt")

// Show undo button — Toggle
Toggle(isOn: $showUndoButton) {
    Label {
        VStack(alignment: .leading) {
            Text("Show undo button")
            SettingsCaption(text: "Show an undo button after completing a reminder.")
        }
    } icon: {
        Image(systemName: "arrow.uturn.backward")
    }
}
.accessibilityIdentifier("showUndoButtonToggle")
#endif
```

**Pattern**: every Toggle that had `Label("text", systemImage:)` now uses
`Label { VStack(alignment: .leading) { Text(…); SettingsCaption(…) } } icon: { Image(…) }`.
Pickers use `label: { VStack { Text; Caption } }` (no icon — their label
has no icon today).

#### 3. NotificationsSettingsView — 2 control captions
**File**: `SingleThread/NotificationsSettingsView.swift`
**Action**: modify

```swift
Toggle(isOn: $notificationsEnabled) {
    Label {
        VStack(alignment: .leading) {
            Text("Enable reminder notifications")
            SettingsCaption(text: "Send a notification when you have due reminders.")
        }
    } icon: {
        Image(systemName: "bell.badge")
    }
}
.accessibilityIdentifier("notificationsEnabledToggle")

Picker(selection: $notificationIntervalHours) {
    Text("24 hours").tag(24)
    Text("48 hours").tag(48)
    Text("72 hours").tag(72)
} label: {
    VStack(alignment: .leading) {
        Text("Remind after")
        SettingsCaption(text: "How long to wait before sending another reminder.")
    }
}
.pickerStyle(.menu)
.accessibilityIdentifier("notificationIntervalPicker")
```

#### 4. ReminderSettingsView — 5 control captions
**File**: `SingleThread/ReminderSettingsView.swift`
**Action**: modify

Replace each `Toggle(isOn:) { Label("…", systemImage:) }` with the
`Label { VStack { title; caption } } icon:` pattern. Existing
`.accessibilityIdentifier`, `.onChange`, and `#if os(iOS) || os(macOS)`
gates stay untouched.

```swift
Toggle(isOn: $showDate) {
    Label {
        VStack(alignment: .leading) {
            Text("Show date")
            SettingsCaption(text: "Show the due date next to each reminder.")
        }
    } icon: {
        Image(systemName: "calendar")
    }
}
.accessibilityIdentifier("showDateToggle")
#if os(iOS) || os(macOS)
    .onChange(of: showDate) { _, _ in
        viewModel.showPreferenceChanged()
    }
#endif

Toggle(isOn: $showList) {
    Label {
        VStack(alignment: .leading) {
            Text("Show list")
            SettingsCaption(text: "Show which list each reminder belongs to.")
        }
    } icon: {
        Image(systemName: "list.bullet")
    }
}
.accessibilityIdentifier("showListToggle")

Toggle(isOn: $showRecurrence) {
    Label {
        VStack(alignment: .leading) {
            Text("Recurrence indicator")
            SettingsCaption(text: "Show if a reminder repeats.")
        }
    } icon: {
        Image(systemName: "repeat")
    }
}
.accessibilityIdentifier("showRecurrenceToggle")
#if os(iOS) || os(macOS)
    .onChange(of: showRecurrence) { _, _ in
        viewModel.showPreferenceChanged()
    }
#endif

Toggle(isOn: $showAlarms) {
    Label {
        VStack(alignment: .leading) {
            Text("Reminder alerts")
            SettingsCaption(text: "Show if a reminder has a time alert.")
        }
    } icon: {
        Image(systemName: "bell")
    }
}
.accessibilityIdentifier("showAlarmsToggle")
#if os(iOS) || os(macOS)
    .onChange(of: showAlarms) { _, _ in
        viewModel.showPreferenceChanged()
    }
#endif

Toggle(isOn: $showCompletionGlow) {
    Label {
        VStack(alignment: .leading) {
            Text(SharedStrings.completionGlow)
            SettingsCaption(text: "Show a sparkle animation when a reminder is completed.")
        }
    } icon: {
        Image(systemName: "sparkles")
    }
}
.accessibilityIdentifier("showCompletionGlowToggle")
```

**Note**: `Completion glow` row title uses `SharedStrings.completionGlow`
(a Core-catalog `String`), which is fine — it's the title Text, not the caption.

#### 5. FilterSortSettingsView — 3 control captions
**File**: `SingleThread/FilterSortSettingsView.swift`
**Action**: modify

```swift
// Sort By — Picker
Picker(selection: $sortOption) {
    ForEach(SortOption.allCases, id: \.self) { option in
        Label(option.title, systemImage: option.systemImage)
            .tag(option)
    }
} label: {
    VStack(alignment: .leading) {
        Text("Sort By")
        SettingsCaption(text: "Choose the order reminders appear in.")
    }
}

// Show undated reminders — Toggle
Toggle(isOn: $showUndatedReminders) {
    Label {
        VStack(alignment: .leading) {
            Text("Show undated reminders")
            SettingsCaption(text: "Include reminders that have no due date.")
        }
    } icon: {
        Image(systemName: "calendar.badge.minus")
    }
}

// Excluded Lists — NavigationLink
Section {
    NavigationLink {
        ExcludedListsView(
            excludedLists: $excludedLists,
            availableLists: availableLists)
    } label: {
        Label {
            VStack(alignment: .leading) {
                Text("Excluded Lists")
                SettingsCaption(text: "Hide specific lists from the reminder view.")
            }
        } icon: {
            Image(systemName: "eye.slash")
        }
    }
}
```

#### 6. BackgroundSettingsView — 4 control captions
**File**: `SingleThread/BackgroundSettingsView.swift`
**Action**: modify

```swift
// Background — Toggle
Toggle(isOn: $backgroundEnabled) {
    Label {
        VStack(alignment: .leading) {
            Text("Background")
            SettingsCaption(text: "Show a wallpaper behind the reminder list.")
        }
    } icon: {
        Image(systemName: "photo")
    }
}
.accessibilityIdentifier("backgroundToggle")

// Background Fade — Picker
Picker(selection: $backgroundFadePercent) {
    ForEach(BackgroundFade.allValues, id: \.self) { percent in
        Text("\(percent)%").tag(percent)
    }
} label: {
    VStack(alignment: .leading) {
        Text("Background Fade")
        SettingsCaption(text: "How much the wallpaper fades for readability.")
    }
}
.accessibilityIdentifier("backgroundFadePicker")

// Pin wallpaper — Toggle (in own Section)
Section {
    Toggle(isOn: $backgroundPinned) {
        Label {
            VStack(alignment: .leading) {
                Text("Pin wallpaper")
                SettingsCaption(text: "Prevents the background from refreshing automatically.")
            }
        } icon: {
            Image(systemName: "pin")
        }
    }
    .accessibilityIdentifier("pinWallpaperToggle")
}

// Refresh wallpaper — Button (add caption under the HStack)
Section {
    Button {
        Task { await backgroundImage.forceRefresh() }
    } label: {
        VStack(alignment: .leading) {
            HStack {
                Label("Refresh wallpaper", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                if backgroundImage.isRefreshing {
                    ProgressView()
                }
            }
            SettingsCaption(text: "Fetch a new wallpaper now.")
        }
    }
    .disabled(backgroundImage.isRefreshing)
    .accessibilityValue(
        backgroundImage.isRefreshing
            ? String(localized: "Refreshing", table: "Localizable", bundle: .main)
            : "")
    .accessibilityIdentifier("refreshWallpaperButton")
}
```

### Tests

#### 7. Extend unit tests
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Each existing test gets additional `#expect(bodyDescription.contains("…"))`
assertions for the new captions.

In `settingsViewContainsNavigationLinkLabels` — add 8 root-row subtitle assertions:
```swift
#expect(bodyDescription.contains("Customize the appearance, text size, and controls."))
#expect(bodyDescription.contains("Get reminded when you have due reminders."))
#expect(bodyDescription.contains("Choose what information is shown with each reminder."))
#expect(bodyDescription.contains("Control the order, visibility, and excluded lists."))
#expect(bodyDescription.contains("Manage the wallpaper and its appearance."))
#expect(bodyDescription.contains("View and manage your purchase status."))
#expect(bodyDescription.contains("How SingleThread handles your data."))
#expect(bodyDescription.contains("App version, credits, and contact."))
```

In `interfaceSettingsViewContainsExpectedRows` — add 7 captions (4 iOS-gated):
```swift
var expectedCaptions = [
    "Choose between system, light, and dark mode.",
    "Adjust the size of text throughout the app.",
    "Add a microphone button for voice input."
]
#if os(iOS)
    expectedCaptions += [
        "Let the app rotate on iPhone.",
        "Show complete, skip, and delete buttons.",
        "Show a hint when there are swipeable reminders.",
        "Show an undo button after completing a reminder."
    ]
#endif
for caption in expectedCaptions {
    #expect(bodyDescription.contains(caption))
}
```

In `reminderSettingsViewContainsExpectedRows` — add 5 captions:
```swift
let expectedCaptions = [
    "Show the due date next to each reminder.",
    "Show which list each reminder belongs to.",
    "Show if a reminder repeats.",
    "Show if a reminder has a time alert.",
    "Show a sparkle animation when a reminder is completed."
]
for caption in expectedCaptions {
    #expect(bodyDescription.contains(caption))
}
```

In `filterSortSettingsViewContainsExpectedRows` — add 3 captions:
```swift
let expectedCaptions = [
    "Choose the order reminders appear in.",
    "Include reminders that have no due date.",
    "Hide specific lists from the reminder view."
]
for caption in expectedCaptions {
    #expect(bodyDescription.contains(caption))
}
```

In `backgroundSettingsViewContainsExpectedRows` — add 4 captions:
```swift
let expectedCaptions = [
    "Show a wallpaper behind the reminder list.",
    "How much the wallpaper fades for readability.",
    "Prevents the background from refreshing automatically.",
    "Fetch a new wallpaper now."
]
for caption in expectedCaptions {
    #expect(bodyDescription.contains(caption))
}
```

#### 8. New test — notifications screen
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify (add new `@Test` function after existing tests)

```swift
@Test
func notificationsSettingsViewContainsExpectedRows() {
    let view = NotificationsSettingsView(
        notificationsEnabled: .constant(false),
        notificationIntervalHours: .constant(48))
    let bodyDescription = String(describing: view.body)

    // Existing row titles
    let expectedLabels = [
        "Enable reminder notifications", "Remind after"
    ]
    for label in expectedLabels {
        #expect(bodyDescription.contains(label))
    }

    // Captions
    let expectedCaptions = [
        "Send a notification when you have due reminders.",
        "How long to wait before sending another reminder."
    ]
    for caption in expectedCaptions {
        #expect(bodyDescription.contains(caption))
    }
}
```

### Verification — Phase 3

#### Automated
- [ ] `make build && make lint` — compiles, SwiftLint clean
- [ ] `xcodebuild -only-testing:SingleThreadTests/SettingsViewTests -destination "$SIM"` —
  all 7 tests green (including new `notificationsSettingsViewContainsExpectedRows`)
- [ ] `xcodebuild -only-testing:SingleThreadTests -destination "$SIM"` — complete unit suite green
- [ ] `xcodebuild -only-testing:SingleThreadUITests -destination "$SIM"` —
  existing UI tests pass unchanged (all settings staticText/switch matches intact)
- [ ] `make periphery` — `SettingsCaption` + `SettingsLinkLabel` both referenced

#### Manual
- [ ] `make mac-build && make mac-run` — captions render on macOS without clipping
- [ ] VoiceOver on iOS simulator: each row announces title then caption as two elements

---

## Phase 4: Full gate + visual/a11y/translation review

### Verification

#### Automated
- [ ] `./scripts/test.sh` (full CI-identical gate) — single run, everything green:
  - `make format` (writes) → `make lint` (strict)
  - iOS build-for-testing + watchOS build
  - Periphery (updated index)
  - iOS unit tests (including new SettingsCaptionTests + extended SettingsViewTests)
  - iOS UI tests (Group A/B/C + ungrouped notification suites)
  - watch unit tests + watch UI tests
  - macOS unit tests

#### Manual
- [ ] `make mac-build && make mac-run` — verify no clipping at `.dynamicType` on macOS List/Form two-line rows
- [ ] Skim non-English catalog translations in Xcode: zh-Hans, es, ja, de, fr for all 29 new keys

---

## Testing Checkpoints Summary

| Stage | Proof |
|---|---|
| After Stage 1 | `LocalizationTests` — all 29 new keys non-empty in 6 languages |
| After Stage 2 | `SettingsCaptionTests` (3 tests) + lint/build green |
| After Stage 3 | `SettingsViewTests` (7 tests, including new notifications) green; all existing UI tests unchanged |
| After Stage 4 | `./scripts/test.sh` green once; `make mac-build` renders without clipping |

## Non-horizontal notes

- **Toggle/Picker label shape**: every Toggle that previously used
  `Toggle(isOn:) { Label("…", systemImage:) }` now uses
  `Label { VStack(alignment: .leading) { Text(…); SettingsCaption(…) } } icon: { Image(…) }`.
  This preserves the existing icon and wraps the title+caption in a leading-aligned
  stack. Picker rows use `label: { VStack { Text; Caption } }` (no icon — Picker's
  `label:` closure is text-only today).
- **Purchase row** is the only dynamic root-row caption; its title is evaluated
  inline with `LocalizedStringKey(entitlementStore.isEntitled ? … : …)`.
- **"Show swipe prompt"** gets `.accessibilityLabel("Show swipe prompt")` explicitly
  to preserve the UI test's switch-label match (`Flows.swift:523`).
- **NO existing accessibility identifier, `.onChange` chain, or `#if` gate is
  removed or reordered** — every diff is additive within the existing structure.

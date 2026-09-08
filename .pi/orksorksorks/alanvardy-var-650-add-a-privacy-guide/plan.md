# Implementation Plan

## Overview

Add a read-only, long-form "Privacy" screen pushed from the root Settings `List` as a fifth
`NavigationLink { PrivacySettingsView() } label: { Label("Privacy", systemImage: "hand.raised") }`
row, explaining in plain language what the app reads, stores, and syncs — and what leaves the
device. It is documentation-only: no data-flow, persistence, or sync changes.

**Files touched** (no schema migrations, no codegen, no pbxproj edits — Xcode auto-discovers
new `.swift` files under `SingleThread/` and `SingleThreadTests/`):

| # | File | Action |
|---|------|--------|
| 1 | `SingleThread/PrivacySettingsContent.swift` | create |
| 2 | `SingleThreadTests/PrivacySettingsContentTests.swift` | create |
| 3 | `SingleThread/PrivacySettingsView.swift` | create |
| 4 | `SingleThreadTests/SettingsViewTests.swift` | modify |
| 5 | `SingleThread/SettingsView.swift` | modify |
| 6 | `SingleThreadUITests/SingleThreadUITestsFlows.swift` | modify |

**Periphery ordering constraint (important):** `periphery scan --strict` runs only in the
**full** `./scripts/test.sh` pipeline. During Stages 1–3, `PrivacyGuideContent` and
`PrivacySettingsView` are referenced only from the test target, so Periphery would flag them as
unused. **Use `make test` (`./scripts/test.sh --unit-only`) for Stages 1–3**, and run the full
`./scripts/test.sh` only after Stage 3 (once `SettingsView` references `PrivacySettingsView`
which references `PrivacyGuideContent`, nothing is unused).

---

## Phase 1: Disclosure Content (bottom layer)

### Changes

#### 1. Privacy content type
**File**: `SingleThread/PrivacySettingsContent.swift`
**Action**: create

Pure Swift value types — no `SwiftUI` import needed (only `Swift` stdlib types).

```swift
// MARK: - PrivacySection

/// A single section of the privacy guide: a headline plus explanatory prose.
struct PrivacySection: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
}

// MARK: - PrivacyGuideContent

/// Static disclosure copy — the single source of truth for what SingleThread
/// claims about its data handling.
///
/// IMPORTANT: this copy hardcodes facts about the app's data flow (Apple
/// Reminders via EventKit, local Watch sync over WCSession, and the
/// `vardy.cc/unsplash` background-image fetch). If any of those data flows
/// change, update this copy in the same change or it becomes misleading.
enum PrivacyGuideContent {
    static let sections: [PrivacySection] = [
        PrivacySection(
            id: "reminders",
            title: "Reminders",
            body: "Reminders are read and written through Apple Reminders. "
                + "They stay on your device or in your own iCloud account, "
                + "and are never sent to SingleThread or any third party."),
        PrivacySection(
            id: "preferences",
            title: "Display & Sync Preferences",
            body: "Your display and sync preferences — such as sort order, "
                + "text size, and which lists are hidden — are stored on your "
                + "device in shared app storage and synced to your own Apple "
                + "Watch over a direct local connection, never over the "
                + "internet."),
        PrivacySection(
            id: "skipped",
            title: "Skipped & Excluded Lists",
            body: "Skipped reminders and excluded lists are stored on your "
                + "device and synced to your Apple Watch over the same direct "
                + "local connection. They never leave your devices."),
        PrivacySection(
            id: "background",
            title: "Background Image",
            body: "When the background is enabled, the image is downloaded "
                + "from vardy.cc/unsplash and cached on your device. This is "
                + "the app's only network request, and it never includes any "
                + "reminder, preference, or list data."),
    ]

    static let closingLine =
        "SingleThread has no analytics, no tracking, and no advertising."
}
```

Notes:
- The four `sections` map to design decisions (a)–(d); `closingLine` is decision (e).
- The copy is deliberately split across adjacent string literals (`+`) to keep every line under
  the SwiftLint `line_length` warning threshold of 120 chars.
- Run `make format` after writing — SwiftFormat will normalize operator placement/wrapping.

#### 2. Content unit tests
**File**: `SingleThreadTests/PrivacySettingsContentTests.swift`
**Action**: create

```swift
@testable import SingleThread
import Testing

struct PrivacySettingsContentTests {
    @Test
    func privacyGuideContentCoversAllDisclosures() {
        let sections = PrivacyGuideContent.sections

        #expect(sections.count == 4)
        #expect(!PrivacyGuideContent.closingLine.isEmpty)

        for section in sections {
            #expect(!section.title.isEmpty)
            #expect(!section.body.isEmpty)
        }

        let allText = (sections.map(\.body) + [PrivacyGuideContent.closingLine])
            .joined(separator: " ")

        #expect(allText.contains("vardy.cc/unsplash"))
        #expect(allText.contains("Apple Watch"))
        #expect(allText.contains("never sent"))
        #expect(allText.contains("iCloud"))
    }

    @Test
    func privacyGuideContentHasNoAnalyticsClaim() {
        let closing = PrivacyGuideContent.closingLine

        #expect(closing.contains("no analytics"))
        #expect(closing.contains("no tracking"))
        #expect(closing.contains("no advertising"))
    }
}
```

Note: no `@MainActor` — the content types are plain value types; the test target does not
enable `SWIFT_DEFAULT_ACTOR_ISOLATION`. No `SwiftUI` import.

### Verification

#### Automated
- [x] `make test` passes (runs `./scripts/test.sh --unit-only`: build-for-testing + all `SingleThreadTests`)
- [x] Faster iteration: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/PrivacySettingsContentTests`

#### Manual
- [ ] Read the copy in `PrivacySettingsContent.swift` and confirm every claim is true against the
      research findings (Q2): reminders via EventKit → on-device/iCloud; preferences + skipped/excluded
      lists → on-device + local Watch sync; background → `vardy.cc/unsplash` fetch, no other network use;
      no analytics/tracking/advertising.

---

## Phase 2: Presentational View

### Changes

#### 1. Privacy screen view
**File**: `SingleThread/PrivacySettingsView.swift`
**Action**: create

```swift
import SwiftUI

// MARK: - PrivacySettingsView

/// Read-only, long-form disclosure of what SingleThread reads, stores, and
/// syncs. Stateless: no bindings, no view model, no init parameters — it
/// renders `PrivacyGuideContent` directly.
struct PrivacySettingsView: View {
    var body: some View {
        Form {
            ForEach(PrivacyGuideContent.sections) { section in
                Section(section.title) {
                    Text(section.body)
                }
            }
            Section {} footer: {
                Text(PrivacyGuideContent.closingLine)
            }
        }
        .navigationTitle("Privacy")
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        PrivacySettingsView()
    }
}
```

Notes:
- `Form` container + `Section(title) { Text(body) }` prose pattern + `Section {} footer:` for the
  single closing line — matches `FilterSortSettingsView.swift:36,59` and
  `BackgroundSettingsView.swift:31-37` / `ExcludedListsView.swift:26-28`.
- No `ScrollView`, no `#if os(iOS)` (pure `Text` builds on iOS + macOS unchanged).
- `import SwiftUI` only — no `SingleThreadCore` (would trip the `unused_import` analyzer rule).

#### 2. View render test
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify — add one test inside the `@MainActor struct SettingsViewTests`

```swift
    @Test
    func privacySettingsViewContainsExpectedContent() {
        let view = PrivacySettingsView()
        let bodyDescription = String(describing: view.body)

        let expected = [
            "Privacy",
            "Reminders",
            "Display & Sync Preferences",
            "Skipped & Excluded Lists",
            "Background Image",
            "vardy.cc/unsplash",
            "no analytics",
        ]
        for label in expected {
            #expect(bodyDescription.contains(label), "Expected privacy content to contain \(label)")
        }
    }
```

Notes:
- Mirrors the existing render-to-string pattern (`SettingsViewTests.swift:13-25`).
- Asserts the `.navigationTitle("Privacy")`, all four section headlines, one body substring
  (`vardy.cc/unsplash`), and the closing line (`no analytics`).

### Verification

#### Automated
- [x] `make test` passes
- [x] `swiftlint lint --strict` passes (no `line_length` violations from the view; the copy lives in `PrivacySettingsContent.swift`)

#### Manual
- [ ] Open the `#Preview("Default")` in Xcode; bump to the largest Dynamic Type size and confirm
      section headers and body prose wrap cleanly without truncation/clipping.

---

## Phase 3: Entry Point

### Changes

#### 1. Root Settings row
**File**: `SingleThread/SettingsView.swift`
**Action**: modify — add a `NavigationLink` after the `Background` row (after `SettingsView.swift:80`),
before the closing `}` of the `List`

```swift
                NavigationLink {
                    PrivacySettingsView()
                } label: {
                    Label("Privacy", systemImage: "hand.raised")
                }
```

Notes:
- `PrivacySettingsView()` takes no parameters, so `SettingsView`'s `init` and the
  `SettingsBindings`/`excludedLists` plumbing are untouched.
- `"hand.raised"` is a lower-case dot-separated SF Symbol literal, matching convention; available
  on iOS 13+ and macOS 11+ (project floors are iOS 18.7 / macOS 26.5).

#### 2. Extend label-invariant test
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify — add `"Privacy"` to the `expectedLabels` array in
`settingsViewContainsNavigationLinkLabels()` (`SettingsViewTests.swift:20-24`)

```swift
        let expectedLabels = [
            "Interface", "Reminder", "Filtering & Sorting", "Background", "Privacy"
        ]
```

### Verification

#### Automated
- [x] `make test` passes — confirms the new row renders and the existing labels remain unchanged
- [x] `swiftlint lint --strict` passes

#### Manual
- [ ] Run the app on the iOS simulator; open Settings and confirm a fifth "Privacy" row appears
      (hand-raised glyph) after "Background".

---

## Phase 4: End-to-End Navigation

### Changes

#### 1. Extend settings flow UI test
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify — append to `testSettingsOpensAndShowsControls()` (after the
`Filtering & Sorting` assertions ending at `SingleThreadUITestsFlows.swift:146`)

```swift
        // Back to root, then into Privacy.
        app.navigationBars.buttons.firstMatch.tap()
        app.staticTexts["Privacy"].tap()
        XCTAssertTrue(
            app.navigationBars["Privacy"].waitForExistence(timeout: 2),
            "Privacy screen should be pushed with its own navigation title")
        XCTAssertTrue(
            app.staticTexts["Skipped & Excluded Lists"].waitForExistence(timeout: 2),
            "Privacy should show its disclosure sections")
```

Notes:
- Asserts the **scoped** navigation-bar title `navigationBars["Privacy"]` *and* the unique section
  header `staticTexts["Skipped & Excluded Lists"]` (not the bare word "Privacy", which would also
  match the root row).
- `"Skipped & Excluded Lists"` is the most distinctive section title — the only substring
  overlap is with `"Excluded Lists"` (the FilterSort nested `NavigationLink` label), and
  `staticTexts[...]` matches by exact identifier, so no collision.

### Verification

#### Automated
- [x] `./scripts/test.sh --ui-only` passes (build-for-testing + `SingleThreadUITests` only)
- [x] `./scripts/test.sh` (full) passes — format, lint, build, Periphery, unit tests, UI tests
      (including the accessibility audit, which is unaffected because it never enters Settings)
- [x] `make lint` passes (`swiftformat --lint` + `swiftlint lint --strict`)

#### Manual
- [ ] Run on the iOS simulator: Settings → Privacy → confirm the screen pushes with title
      "Privacy" and shows all four sections plus the "no analytics / no tracking / no advertising"
      closing footer.
- [ ] `make mac-test` (macOS destination) passes — confirms the shared screen builds/renders on
      macOS without `#if` gating.

---

## Testing Checkpoints

- After Phase 1: `make test` green (copy is complete and honest) before any view exists.
- After Phase 2: `make test` green (view renders) before the screen is wired into Settings.
- After Phase 3: `make test` green — `settingsViewContainsNavigationLinkLabels` has the new label
  and the old labels intact; this is the first point the full `./scripts/test.sh` (with Periphery)
  can pass.
- After Phase 4: `./scripts/test.sh` (full) green — `testSettingsOpensAndShowsControls` navigates
  into Privacy and asserts the headline.

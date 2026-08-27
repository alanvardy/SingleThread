# Implementation Plan

## Overview

Push a read-only **About** screen onto Settings' existing `NavigationStack`,
presenting bundle-derived identity (display name, marketing version, build
number) via a new injectable `AppInfo` value type in `SingleThreadCore`, plus
author attribution and a `mailto:` feedback link. Coverage stacks bottom-up:
unit → view → integration → UI/a11y. No migration, store, service, or transport
layer.

All commands run from the repo root. Default simulator is `iPhone 17`.

---

## Phase 1: Core identity read — `AppInfo`

### Changes

#### 1. New `AppInfo` value type
**File**: `SingleThreadCore/Sources/SingleThreadCore/AppInfo.swift`
**Action**: create

```swift
import Foundation

/// Bundle-derived app identity — display name, marketing version, and build
/// number — formatted for the About screen. The first runtime `Bundle` read in
/// the codebase, kept injectable so it is unit-testable.
public struct AppInfo: Sendable {
    // MARK: Lifecycle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    // MARK: Public

    /// Single source of truth for the feedback email address.
    public static let feedbackEmail = "alan@vardy.cc"

    /// `CFBundleShortVersionString` (e.g. "1.0"), nil if absent.
    public var marketingVersion: String? {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// `CFBundleVersion` (e.g. "1"), nil if absent.
    public var buildNumber: String? {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// `CFBundleDisplayName` ?? `CFBundleName` ?? "SingleThread".
    public var displayName: String {
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "SingleThread"
    }

    /// "Version 1.0 (1)"; "Version 1.0" when build is nil; "" when marketing is nil.
    public var versionDescription: String {
        guard let marketing = marketingVersion else { return "" }
        if let build = buildNumber {
            return "Version \(marketing) (\(build))"
        }
        return "Version \(marketing)"
    }

    // MARK: Private

    private let bundle: Bundle
}
```

#### 2. Test fixture — `StubBundle`
**File**: `SingleThreadTests/StubBundle.swift`
**Action**: create

> **Why a shared file**: `AppInfoTests` (Phase 1) and `AboutViewTests` (Phase 2)
> both need a `Bundle` with known identity keys. A single fixture file avoids
> duplicating the subclass in two test files.

```swift
import Foundation

/// Test fixture: a `Bundle` subclass returning a fixed info dictionary so
/// `AppInfo` can be exercised without the real bundle's Info.plist.
///
/// Must restate `@unchecked Sendable`: `Bundle` is `@unchecked Sendable`, and
/// Swift 6 + warnings-as-errors rejects subclasses that don't restate it.
final class StubBundle: Bundle, @unchecked Sendable {
    private let stubbedInfo: [String: Any]

    init(info: [String: Any]) {
        self.stubbedInfo = info
        super.init()
    }

    override var infoDictionary: [String: Any]? { stubbedInfo }

    override func object(forInfoDictionaryKey key: String) -> Any? { stubbedInfo[key] }
}
```

#### 3. Unit tests
**File**: `SingleThreadTests/AppInfoTests.swift`
**Action**: create

```swift
import Foundation
import SingleThreadCore
import Testing

// MARK: - AppInfo Tests

struct AppInfoTests {
    // MARK: Internal

    @Test
    func readsMarketingVersionBuildNumberAndDisplayName() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleDisplayName": "SingleThread",
        ]))

        #expect(info.marketingVersion == "1.0")
        #expect(info.buildNumber == "1")
        #expect(info.displayName == "SingleThread")
        #expect(info.versionDescription == "Version 1.0 (1)")
    }

    @Test
    func fallsBackWhenIdentityKeysAreAbsent() {
        let info = AppInfo(bundle: StubBundle(info: [:]))

        #expect(info.marketingVersion == nil)
        #expect(info.buildNumber == nil)
        #expect(info.displayName == "SingleThread")
        #expect(info.versionDescription == "")
    }

    @Test
    func omitsBuildParentheticalWhenBuildIsAbsent() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleShortVersionString": "1.0",
        ]))

        #expect(info.marketingVersion == "1.0")
        #expect(info.buildNumber == nil)
        #expect(info.versionDescription == "Version 1.0")
    }

    @Test
    func emptyVersionWhenMarketingAbsentButBuildPresent() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleVersion": "1",
        ]))

        #expect(info.marketingVersion == nil)
        #expect(info.buildNumber == "1")
        #expect(info.versionDescription == "")
    }

    @Test
    func fallsBackToBundleNameWhenDisplayNameAbsent() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleName": "SingleThread",
        ]))

        #expect(info.displayName == "SingleThread")
    }
}
```

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/AppInfoTests` passes

#### Manual
- [ ] No manual step — this is pure Core logic, fully covered by unit tests.

---

## Phase 2: `AboutView` — presentational layer

### Changes

#### 1. New view
**File**: `SingleThread/AboutView.swift`
**Action**: create (auto-discovered by the synchronized file group — no pbxproj edit)

```swift
import SingleThreadCore
import SwiftUI

// MARK: - AboutView

/// Read-only About screen presenting app identity, author attribution, and a
/// feedback mail link. Pushed from Settings' `NavigationStack`, so it owns its
/// own `.navigationTitle` and never re-presents a sheet.
struct AboutView: View {
    // MARK: Lifecycle

    init(
        appInfo: AppInfo = AppInfo(),
        feedbackEmail: String = AppInfo.feedbackEmail) {
        self.appInfo = appInfo
        self.feedbackEmail = feedbackEmail
    }

    // MARK: Internal

    var body: some View {
        Form {
            Section {
                Label(appInfo.displayName, systemImage: "checklist")
            }
            Section {
                Text("Copyright 2026 Alan Vardy")
                Text("Made with love by a lone developer")
                Text(appInfo.versionDescription)
            }
            Section {} footer: {
                if let feedbackURL = URL(string: "mailto:\(feedbackEmail)") {
                    Link(feedbackEmail, destination: feedbackURL)
                } else {
                    Text(feedbackEmail)
                }
            }
        }
        .navigationTitle("About")
    }

    // MARK: Private

    private let appInfo: AppInfo
    private let feedbackEmail: String
}

// MARK: - Previews

#if os(iOS)
    #Preview("About") {
        AboutView()
    }
#endif
```

> The header icon uses the `checklist` SF Symbol — the app's existing identity
> metaphor (`ContentViewModel.swift` empty-state). The `mailto:` link mirrors
> the `Link`-with-`Text`-fallback pattern at `SettingsView.swift:241-245`.

#### 2. View tests
**File**: `SingleThreadTests/AboutViewTests.swift`
**Action**: create

```swift
@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - AboutView Tests

@MainActor
struct AboutViewTests {
    // MARK: Internal

    @Test
    func aboutViewRendersAttributionAndIdentity() {
        let view = AboutView(appInfo: stubAppInfo())
        let bodyDescription = String(describing: view.body)

        for expected in [
            "Copyright 2026 Alan Vardy",
            "Made with love by a lone developer",
            "Version 1.0 (1)",
            "SingleThread",
            "alan@vardy.cc",
        ] {
            #expect(bodyDescription.contains(expected))
        }
    }

    @Test
    func aboutViewRendersWithoutCrashingWhenVersionIsNil() {
        let view = AboutView(appInfo: AppInfo(bundle: StubBundle(info: [:])))
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("Copyright 2026 Alan Vardy"))
        #expect(bodyDescription.contains("Made with love by a lone developer"))
        // Display name falls back to the "SingleThread" literal.
        #expect(bodyDescription.contains("SingleThread"))
    }

    // MARK: Private

    private func stubAppInfo() -> AppInfo {
        AppInfo(bundle: StubBundle(info: [
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleDisplayName": "SingleThread",
        ]))
    }
}
```

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/AboutViewTests` passes

#### Manual
- [ ] In Xcode, open `AboutView.swift`'s `#Preview` and confirm: header shows the `checklist` icon + "SingleThread", then the copyright, "Made with love…", "Version 1.0 (1)" rows, and the "alan@vardy.cc" footer link.

---

## Phase 3: Settings entry — navigation integration

### Changes

#### 1. Add the About row
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Insert a new `Section` immediately **after** the "Excluded Lists" `Section`
(`SettingsView.swift:229-237`) and **before** the empty footer `Section`:

```swift
                Section {
                    NavigationLink {
                        ExcludedListsView(
                            excludedLists: $excludedLists,
                            availableLists: availableLists)
                    } label: {
                        Label("Excluded Lists", systemImage: "eye.slash")
                    }
                }
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    .accessibilityLabel("About")
                    .accessibilityAddTraits(.isButton)
                }
                Section {} footer: {
```

No new init parameters, no new `@State`, no second `.sheet` — `AboutView()`
uses its defaults (`AppInfo()` + `AppInfo.feedbackEmail`).

#### 2. Extend the settings-row test
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add `"About"` to `commonLabels` (shared by both the `#if os(iOS)` and `#else`
branches — no per-platform change needed):

```swift
        let commonLabels = [
            "Appearance", "Text Size", "Sort By", "Show microphone", "Background",
            "Background Fade", "Unsplash", "Show undated reminders", "Show date",
            "Show list", "Recurrence indicator", "Reminder alerts", "Excluded Lists",
            "About", "Done"
        ]
```

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SettingsViewTests` passes

#### Manual
- [ ] In Xcode, run the app, tap the gear, confirm an "About" row (info.circle icon) appears below "Excluded Lists", and that tapping it pushes `AboutView` with the "About" navigation title and a working back button.

---

## Phase 4: End-to-end UI test + accessibility

### Changes

#### 1. New UI flow test
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

Add a new `@MainActor` test (e.g. after `testSettingsOpensAndShowsControls`):

```swift
    // MARK: - About

    @MainActor
    func testAboutModalShowsAttribution() {
        let app = launchApp(seedJSON: #"{"reminders":[]}"#)

        XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()

        // The About row sits near the bottom of the Form; scroll if needed.
        let about = app.buttons["About"]
        if !about.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(about.waitForExistence(timeout: 3), "Settings should show an About row")
        about.tap()

        XCTAssertTrue(
            app.staticTexts["Copyright 2026 Alan Vardy"].waitForExistence(timeout: 3),
            "About should show the copyright line")
        XCTAssertTrue(
            app.staticTexts["Made with love by a lone developer"].waitForExistence(timeout: 2),
            "About should show the made-with-love line")
        XCTAssertTrue(
            app.staticTexts["Version 1.0 (1)"].waitForExistence(timeout: 2),
            "About should show the version + build")

        // The `mailto:` link is a tappable `Link`, not a plain `Text`; assert it
        // is present but NEVER tap it (simulator/CI Mail behavior is out of scope).
        XCTAssertTrue(
            app.buttons["alan@vardy.cc"].waitForExistence(timeout: 2),
            "About should show the feedback email link")
    }
```

> **Fallback if the email link surfaces as `staticTexts` instead of `buttons`:**
> `Link` inside a `Section` footer is normally exposed as a button, but if the
> assertion fails on the element type, swap the last assertion for
> `app.staticTexts["alan@vardy.cc"]` (or a `descendants(matching: .any)`
> predicate on the label). Do **not** tap the link.

The existing `testAccessibilityAudit()` launches `--ui-testing` and audits the
main screen only (it never opens Settings), so the new row does not affect it;
the About row's `.accessibilityLabel` + `.isButton` trait keep it conformant if
it were ever traversed.

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests` passes (includes the new flow test and `testAccessibilityAudit`)
- [ ] `./scripts/test.sh` passes — the full format + lint + build + Periphery + unit + UI gate

#### Manual
- [ ] Run the app in the simulator, seed empty → gear → About, and visually confirm the copyright and "Made with love…" lines, the "Version 1.0 (1)" line, and the "alan@vardy.cc" link are all visible. Verify VoiceOver reads the About row as a button labeled "About".

---

## Notes & Deviations

- **`StubBundle.swift` (extra test fixture file)** — the structure listed only
  `AppInfoTests.swift` and `AboutViewTests.swift`, but both need the `Bundle`
  subclass. A single shared fixture file is cleaner than duplicating the stub;
  it lives in the same `SingleThreadTests` module and is `internal` by default.
- **Fourth `AppInfo` case (build present, marketing absent)** — the structure's
  test bullet said "build present, marketing absent → omits the parenthetical",
  which is ambiguous (there is no marketing version to parenthesize). Resolved
  per the documented `versionDescription` contract: marketing drives the string,
  so marketing-absent ⇒ `""`. Covered explicitly by
  `emptyVersionWhenMarketingAbsentButBuildPresent`.
- **`@unchecked Sendable` on `StubBundle`** — required to avoid a
  warnings-as-errors failure under Swift 6 (verified against the simulator SDK).
- **`#Preview` placement** — the structure's Layer 3 mentioned adding a preview
  "alongside the existing two"; interpreted as giving `AboutView` its own
  `#Preview` in `AboutView.swift` (gated `#if os(iOS)`, matching
  `SettingsView.swift`'s preview convention), not a third `SettingsView` preview
  (which would add no coverage).
- **Version string in the UI test is hard-coded** — `"Version 1.0 (1)"` is
  coupled to `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 1` in
  `project.pbxproj`. If either bumps, update this assertion.

# Structure Outline

## Approach

A read-only iOS/macOS surface: push an `AboutView` onto Settings' existing
`NavigationStack` (no new `.sheet`), sourcing display name / version / build from
an injectable `Bundle` read in Core (`AppInfo`), with author + `mailto:` feedback
content, covered bottom-up by unit → view → integration → UI/a11y tests.

This is a UI feature with **no migration, store, service, or transport layer** —
the horizontal layers are: **Core data access → presentational view → navigation
integration → end-to-end/a11y verification**. Each layer is green before the next
is started.

---

## Layer 1: Core identity read — `AppInfo` (bottom-most)

The single source of truth for bundle-derived identity. A `Sendable`, injectable
value type that reads `CFBundleShortVersionString` / `CFBundleVersion` /
`CFBundleDisplayName` (falling back to `CFBundleName` → `"SingleThread"`) and
formats `"Version 1.0 (1)"`. Its green tests prove the *data* is correct before
any view consumes it.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/AppInfo.swift` (new),
`SingleThreadTests/AppInfoTests.swift` (new)

**Key changes**:
```swift
public struct AppInfo: Sendable {
    public init(bundle: Bundle = .main)

    /// CFBundleShortVersionString (e.g. "1.0"), nil if absent.
    public var marketingVersion: String? { get }
    /// CFBundleVersion (e.g. "1"), nil if absent.
    public var buildNumber: String? { get }
    /// CFBundleDisplayName ?? CFBundleName ?? "SingleThread".
    public var displayName: String { get }
    /// "Version 1.0 (1)"; "Version 1.0" when build nil; empty when both nil.
    public var versionDescription: String { get }

    /// Single source of truth for the feedback address.
    public static let feedbackEmail = "alan@vardy.cc"
}
```

**Tests**: `AppInfoTests.swift` injects a `Bundle` subclass stub (test fixture;
`SingleThreadTests/.swiftlint.yml` relaxes force-unwrap) returning a fixed
`[String: Any]` info dictionary:
- happy: marketing + build + display name present → `versionDescription == "Version 1.0 (1)"`, `displayName` matches.
- sad: all keys absent → `marketingVersion == nil`, `buildNumber == nil`, `displayName == "SingleThread"`.
- sad: build present, marketing absent → `versionDescription` omits the parenthetical.

**Verify**:
`xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/AppInfoTests`

---

## Layer 2: `AboutView` — presentational layer

Renders the About screen as a standalone `Form` from injected `AppInfo` (never
reads `Bundle.main` directly). Its green tests prove the *presentation* renders
the proven data correctly, in the same `String(describing: body)` style as
`SettingsViewTests`.

**Files**: `SingleThread/AboutView.swift` (new, auto-discovered — no pbxproj edit),
`SingleThreadTests/AboutViewTests.swift` (new)

**Key changes**:
```swift
struct AboutView: View {
    init(
        appInfo: AppInfo = AppInfo(),
        feedbackEmail: String = AppInfo.feedbackEmail
    )
    var body: some View
    // Form {
    //   Section { Image(systemName:) + Text(appInfo.displayName) }       // header
    //   Section { "Copyright 2026 Alan Vardy", "Made with love by a lone developer",
    //             appInfo.versionDescription }
    //   Section {} footer: { Link(feedbackEmail, destination: mailto) w/ Text fallback }
    // }
    // .navigationTitle("About")
}
```

Consumes `appInfo.displayName` + `appInfo.versionDescription`; the `mailto:` URL
is built from `feedbackEmail` with the codebase's `Link`-with-`Text`-fallback
pattern (mirroring `SettingsView.swift:241-245`). Must be testable as a
standalone `Form`, **not** wrapped in a sheet (body-dump substring assertions
only see `Form` content).

**Tests**: `AboutViewTests.swift` (`@MainActor`, Swift Testing) builds
`AboutView(appInfo: stub)` and asserts `String(describing: body)` contains
`"Copyright 2026 Alan Vardy"`, `"Made with love by a lone developer"`,
`"Version 1.0 (1)"`, the display name, and `"alan@vardy.cc"`; sad path with
nil-version `AppInfo` renders without crashing and shows the fallback version.

**Verify**:
`xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/AboutViewTests`

---

## Layer 3: Settings entry — navigation integration

Add the "About" row as a sibling `Section` + `NavigationLink` next to
"Excluded Lists" inside the existing `NavigationStack`. Green test proves the
entry point is reachable from the proven Settings surface.

**Files**: `SingleThread/SettingsView.swift` (modified),
`SingleThreadTests/SettingsViewTests.swift` (modified)

**Key changes**:
```swift
// new Section in SettingsView's Form, sibling of the Excluded Lists Section:
Section {
    NavigationLink { AboutView() } label: {
        Label("About", systemImage: "info.circle")
    }
}
// pair per a11y convention: .accessibilityLabel("About") +
// .accessibilityAddTraits(.isButton) (matches ContentView.swift:71-72)
```

No new init params, no new `@State`, no second `.sheet` — `AboutView()` uses its
defaults. (Add a `#Preview` entry alongside the existing two, per convention.)

**Tests**: extend `SettingsViewTests.settingsViewContainsAllPreferenceRows`
`expectedLabels` (both `#if os(iOS)` and `#else` branches) with `"About"`.

**Verify**:
`xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SettingsViewTests`

---

## Layer 4: End-to-end UI test + accessibility (top)

Prove the user flow (seed → gear → About → attribution visible) and that the new
surface passes the existing accessibility audit. Completes the three verification
layers required by repo conventions.

**Files**: `SingleThreadUITests/SingleThreadUITestsFlows.swift` (modified)

**Key changes**:
```swift
@MainActor func testAboutModalShowsAttribution() {
    // launchApp(seedJSON: #"{"reminders":[]}"#) → app.buttons["Settings"].tap()
    // → app.buttons["About"].tap()
    // assert app.staticTexts["Copyright 2026 Alan Vardy"] and
    //       app.staticTexts["Made with love by a lone developer"] exist
    // assert "Version 1.0 (1)" and "alan@vardy.cc" exist — do NOT tap the email link
}
```

The `mailto:` link is asserted *present*, never tapped (simulator/CI Mail behavior
is out of scope — the link pattern itself is already covered). The About row's
label/trait additions must keep `testAccessibilityAudit()` passing.

**Tests**: `testAboutModalShowsAttribution` (new); existing
`testAccessibilityAudit` must remain green.

**Verify**:
`xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests`, then the full gate `./scripts/test.sh`.

---

## Testing Checkpoints

Resume points — after each incremental gate, the following must be green before
advancing (later layers mock/seed against the already-proven ones):

1. `AppInfoTests` green → Core identity read is correct (data layer stable).
2. `AboutViewTests` green → presentation renders proven data (view layer stable).
3. `SettingsViewTests` green → entry point reachable (integration stable).
4. `testAboutModalShowsAttribution` + `testAccessibilityAudit` green → full
   user flow verified; run `./scripts/test.sh` for the complete format + lint +
   build + Periphery + unit + UI gate.

## Notes

- **No horizontal blockers**: the feature is naturally layered (no
  cross-cutting change that only becomes testable at the top). The one
  testability wrinkle — `Bundle` is stubbed via a subclass in Layer 1's test
  fixture — is isolated to the bottom layer and reused by Layers 2-3 as an
  injected `AppInfo`.
- **macOS `#else` path**: `AboutView` touches only the shared `Form`; the
  macOS init path is not build-tested in CI (research "Open Areas") and remains
  low risk — flagged, not blocking.

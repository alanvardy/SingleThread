# Design Discussion — About Modal (VAR-651)

## Current State

**Presentation.** The main app has exactly one presented surface: the Settings
`.sheet` bound to `@State isShowingSettings` (`ContentView.swift:100`), opened
from the top-trailing gear button (`ContentView.swift:62`, `:66-67`). Inside
that sheet, `SettingsView` owns its own `NavigationStack` (`SettingsView.swift:155`)
and already pushes one sub-screen — `ExcludedListsView` — via a
`Section { NavigationLink { … } label: { Label("Excluded Lists", systemImage: "eye.slash") } }`
(`SettingsView.swift:229-237`). That pushed view declares its own
`.navigationTitle("Excluded Lists")` (`SettingsView.swift:34`). Settings rows are
siblings directly in the `Form`; only "Excluded Lists" and the empty attribution
footer are wrapped in `Section`s (`SettingsView.swift:238-247`).

**Attribution.** The only author-credit content today is the Unsplash footer:
a text-form `Link("Photo by \(photographer) on Unsplash", destination:)` with a
`Text` fallback when the URL is nil (`SettingsView.swift:241-245`). The credit is
*injected* data owned by `BackgroundImageStore` (`photographer: String?` /
`photographerURL: URL?`, `BackgroundImageStore.swift:71,73`), not hardcoded in the
view. It is the codebase's **only** `Link(` call.

**Outbound links.** `@Environment(\.openURL)` is declared once
(`ContentView.swift:189-190`) and called once for "View in Reminders" inside an
iOS long-press `.contextMenu` (`ContentView.swift:312-322`).

**App identity.** Version/build metadata is build-time only: the iOS app target
uses `GENERATE_INFOPLIST_FILE = YES` with `MARKETING_VERSION = 1.0` and
`CURRENT_PROJECT_VERSION = 1` (`project.pbxproj:737,761` Debug; `:787,811`
Release). There are **zero** runtime `Bundle`/Info.plist reads anywhere in
`SingleThread/`, `SingleThreadCore/`, `SingleThreadWatch/`, or
`SingleThreadWidget/`. No "About"/version surface exists.

**watchOS.** No settings surface — a single `WindowGroup` card
(`SingleThreadWatchApp.swift:17-22`) whose only modal is a `.confirmationDialog`
(`WatchReminderView.swift:165`). Out of scope for this task.

## Desired End State

A new **About** entry in the Settings screen that pushes an `AboutView`
screenshot presenting, in order:

1. App icon + display name (from the bundle) — header section.
2. `Copyright 2026 Alan Vardy`
3. `Made with love by a lone developer`
4. `Version 1.0 (1)` (marketing version + build number, read from the bundle)
5. A tappable `mailto:alan@vardy.cc` feedback link.

**Verification** (all three layers per repo conventions):
- **Unit** (`SingleThreadTests`): a `BundleInfo`/`AppInfo` test asserting version
  and build are read correctly from an injected `Bundle`, plus a
  `String(describing: AboutView.body)` substring check for the three static
  strings (mirroring `SettingsViewTests.swift:13-33`).
- **UI** (`SingleThreadUITests`): seed → tap gear → tap "About" → assert the
  copyright and "Made with love" lines are visible. (The `mailto:` and version
  lines can be asserted too but the email must not be tapped in CI.)
- **Accessibility**: the About row carries a label, and the view passes the
  existing `performAccessibilityAudit()`.

## Patterns to Follow

- **Push, don't re-present.** Settings already owns a `NavigationStack`
  (`SettingsView.swift:155`); add `About` as a sibling `Section` +
  `NavigationLink` + `Label` next to "Excluded Lists" (`SettingsView.swift:229-237`).
  Do **not** add a second `.sheet`.
- **`NavigationLink` to a dedicated view file** with its own `.navigationTitle`,
  exactly like `ExcludedListsView` (`SettingsView.swift:34`). `AboutView` gets a
  new file `SingleThread/AboutView.swift` (auto-discovered, no pbxproj edit).
- **`Link` for outbound**, with a nil-destination `Text` fallback — match
  `SettingsView.swift:241-245`. `Link` already routes through `openURL`, so no
  explicit `@Environment(\.openURL)` call is needed.
- **Core owns logic, views render it.** The version read lives in
  `SingleThreadCore` (testable, injectable `Bundle`), following how
  `SettingsViewModel` and `ReminderStore` are structured and tested. The view
  only formats what Core returns.
- **Attribution as injected data.** Do not hardcode the email/version in
  `AboutView`; read version from `Bundle` and pass the email as a constant so it
  remains the single source of truth.
- **Accessibility convention.** Interactive controls pair `.accessibilityLabel` +
  `.accessibilityAddTraits(.isButton)` (e.g. `ContentView.swift:71-72`); static
  informational text needs no label beyond its visible text. Match this on the
  About `NavigationLink`.
- **`#if os` discipline.** `AboutView` needs no platform divergence (iOS and macOS
  both have the Settings sheet; watchOS has no entry). If macOS init paths need
  it, mirror the existing `#if os(iOS)` / `#else` split used in
  `SettingsView.swift:76-150`.

### Patterns NOT to follow

- **Do not** add `.presentationDetents`, `.interactiveDismissDisabled`, or a
  second `.sheet` — no precedent exists and it complicates the single-sheet flow.
- **Do not** hardcode the version string in the view or in a plist-backed
  constant — `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` already exist in
  `project.pbxproj` and must stay the single source of truth.
- **Do not** read `Bundle.main` directly inside the view — it's untestable and
  breaks the Core-owns-logic split.

## Design Decisions

1. **Presentation: push inside Settings' `NavigationStack`.** Add
   `Section { NavigationLink { AboutView() } label: { Label("About", systemImage: "info.circle") } }`
   as a sibling of the "Excluded Lists" `Section` (`SettingsView.swift:229-237`).
   Rationale: reuses the existing single-sheet + push pattern, needs no new state
   or presentation primitive, and works identically on iOS/macOS.

2. **Author email: include as a `mailto:` link.** `Link("alan@vardy.cc",
   destination: URL(string: "mailto:alan@vardy.cc"))`, rendered with the existing
   `Link` pattern (`SettingsView.swift:241-243`). Author decision: feedback email
   is permitted and desirable; `mailto:` avoids any App Store link policy
   exposure and needs no server.

3. **Version read: new `AppInfo` helper in `SingleThreadCore`.** A small,
   `@MainActor`-free, `Sendable` value type that takes an injectable
   `Bundle = .main` and exposes `marketingVersion: String?` and
   `buildNumber: String?` via `object(forInfoDictionaryKey:)` for
   `CFBundleShortVersionString` and `CFBundleVersion`. Formatting
   (`"Version \(marketing) (\(build))"`) lives here so it is unit-tested.
   Rationale: first runtime `Bundle` read in the codebase; it must be testable,
   and Core is where the domain logic and its tests already live.

4. **Content & layout: a `Form` matching Settings' aesthetic.** `AboutView` is a
   `Form` with a header `Section` (app icon via `Image(systemName:)` + display
   name) and an info `Section` listing copyright, "Made with love…", and version.
   The email `Link` sits in a `Section {} footer:` — the same slot the Unsplash
   credit already uses (`SettingsView.swift:238-247`).

5. **Display name source: `PRODUCT_NAME = $(TARGET_NAME)` → "SingleThread".**
   The app target declares no `INFOPLIST_KEY_CFBundleDisplayName`
   (`project.pbxproj` app target `:737-763`), so `CFBundleDisplayName` is
   synthesized from `PRODUCT_NAME`. `AboutView` reads `CFBundleDisplayName`
   (or `CFBundleName`) via `AppInfo` rather than hardcoding "SingleThread".

## What We're NOT Doing

- **No watchOS About surface.** The watch has no settings/menu precedent
  (`SingleThreadWatchApp.swift:17-22`); the task is iOS/macOS-only.
- **No third-party attribution** (Unsplash-style) beyond the author line — the
  background credit already lives in the Settings footer and is unchanged.
- **No new settings toggle or `@AppStorage` key.** About is read-only; nothing
  is persisted, so `UITestingSeed.resetPersistedState()` and the sync service
  need no changes.
- **No navigation-title changes** to the Settings `Form` itself (it has none
  today, `SettingsView.swift:155-256`); only the pushed `AboutView` gets a title.
- **No custom version-display formatting beyond "Version 1.0 (1)".** No build
  date, Git SHA, or analytics.

## Open Risks

- **`CFBundleDisplayName` synthesis is inferred, not compiled-verified**
  (research "Open Areas"). `AppInfo` must fall back to `CFBundleName` /
  a `"SingleThread"` literal if the dictionary key is absent, and the unit test
  must cover the nil/fallback path.
- **`mailto:` link behavior in simulator/CI.** `Link` with `mailto:` may open
  Mail or do nothing in the simulator. UI tests should assert the label is
  *present*, not tap it; the link's behavior itself is covered by the existing
  `Link` pattern (no new surface to test).
- **`Form` body-dump substring assertions are brittle** (`SettingsViewTests.swift:18-20`
  notes `.sheet` content is not dumped, but `Form` rows are). `AboutView` must be
  testable as a standalone `Form` (not wrapped in a sheet) for the
  `String(describing: body)` approach to work.
- **macOS `#else` build path** for `ContentView`/`SettingsView` is verified in
  source but not build-tested in CI (research "Open Areas"). Adding `AboutView`
  touches only the shared `Form`, so macOS risk is low but nonzero.

# Design Discussion

## Current State

The settings screen is a `.sheet` presented from `ContentView`'s gear button
(`ContentView.swift:162-173`). The sheet content is `SettingsView` — a
`NavigationStack { List { Section { rows } } }` with a "Done" toolbar button
(`SettingsView.swift:30-137`). The app is a single multiplatform target
(iOS + macOS, `project.pbxproj:772,822`), and the settings screen is shared
code with platform variance at four `#if os(iOS)` sites.

**On macOS, opening the settings sheet shows only the "Done" toolbar
button — none of the settings rows/content render.** On iOS the same sheet
renders all rows correctly.

Key facts from research and diagnostic:

- The SwiftUI body is **correct at the code level on macOS**: all
  `SettingsViewTests` pass on `platform=macOS`, including
  `settingsViewContainsNavigationLinkLabels` which asserts the body string
  contains "Interface", "Reminder", "Filtering & Sorting", "Background",
  "Unlock", "Privacy", "About", and "Done" (`SettingsViewTests.swift:37-52`).
- The sheet has **no explicit sizing anywhere** — zero `presentationDetents`,
  `preferredContentSize`, or `.frame` calls on the sheet or its root
  (repo-wide grep confirmed). On macOS, sheets inside `WindowGroup` without
  explicit sizing commonly default to a minimal height that shows only the
  toolbar.
- Platform variance is **concentrated at exactly four `#if os(iOS)` sites**
  in the settings path (`ContentView+Settings.swift:21,50`,
  `SettingsView.swift:36,57`), with macOS behavior expressed exclusively
  through `#else` — no `#if os(macOS)` guards exist anywhere in settings code.
- macOS settings rows are a **strict subset of iOS**: the Notifications
  NavigationLink is iOS-only (`SettingsView.swift:57-64`), and the Interface
  sub-view passes 3 bindings on macOS vs 7 on iOS
  (`SettingsView.swift:46-53`). All other 8 rows are unconditional.
- Two **comment drifts** exist: `ContentView+Settings.swift:6-7` says
  "17-modifier chain" but actual counts are 19 (iOS) / 13 (non-iOS);
  `SettingsBindings.swift:8-10` enumerates 3 iOS-only fields but
  `showSwipePrompt` is also iOS-only and not listed.
- **No macOS UI test coverage** exists (`scripts/test.sh:288-292` runs macOS
  unit tests only; no macOS UI test target).

## Desired End State

The settings sheet on macOS renders all rows: Interface, Reminder, Filtering
& Sorting, Background, Unlock/Purchase, Privacy, About — plus the Done
toolbar button. iOS behavior is unchanged. Platform conditionals in settings
code use explicit `#if os(macOS)` instead of bare `#else`. Comments are
accurate.

Verification: manual build-and-run on macOS shows all settings rows; all
existing unit tests (iOS + macOS) and UI tests (iOS) continue to pass.

## Patterns to Follow

- **Platform guards**: `#if os(iOS)` / `#if os(macOS)` / `#if os(iOS) || os(macOS)` —
  explicit, never bare `#else` for macOS-only paths
  (`AppDelegate.swift:27-34`, `Color+CrossPlatform.swift:3,16`,
  `BackgroundImageStore.swift:5,244`).
- **Single bag pattern**: `SettingsBindings` holds all preference values;
  iOS-only fields declared unconditionally with defaults because `#if` can't
  appear in parameter lists (`SettingsBindings.swift:8-10`). Bag is built
  fresh in `makeSettingsBag()` before the sheet opens
  (`ContentView.swift:164-165`).
- **Write-back chain**: `.onChange(of: bag.X)` observers copy bag values back
  to `@AppStorage` (`ContentView+Settings.swift:17-43`). Platform-gated
  observers use `#if os(iOS)` for iOS-only fields.
- **Test patterns**: `String(describing: view.body).contains(...)` for
  settings row labels (`SettingsViewTests.swift:37-52`); `--seed` launch
  argument for deterministic UI test state
  (`UITestingSeed.swift:31-46`).

**Patterns NOT to follow**: bare `#else` for macOS behavior — it's ambiguous
and makes reasoning about macOS behavior require reading the `#if` block to
infer what's excluded.

## Design Decisions

1. **Diagnostic-first approach**: Before committing to a fix, build and run
   the macOS app to observe the actual sheet rendering. The unit tests
   confirm the body is correct, but the runtime rendering failure needs
   visual confirmation. The most likely root cause is missing sheet sizing
   (no `presentationDetents` or `.frame`), but this is inferred, not
   observed.

2. **Sheet sizing fix pending diagnostic**: If the diagnostic confirms the
   sheet is collapsed to toolbar-only, add `.frame(minWidth: 400,
   minHeight: 500)` or `.presentationDetents([.medium, .large])` on the
   settings sheet content, gated `#if os(macOS)`. If the diagnostic reveals
   a different root cause, adjust the fix accordingly. **No sizing change
   until the diagnostic confirms it's needed.**

3. **Convert `#else` to `#if os(macOS)`**: In the three `#else` blocks that
   represent macOS-specific behavior:
   - `ContentView+Settings.swift:29-31` — write-back passthrough
   - `ContentView+Settings.swift:71-83` — bag construction
   - `SettingsView.swift:47-53` — InterfaceSettingsView macOS path
   
   Change `#else` to `#elseif os(macOS)` so the macOS intent is explicit and
   grep-able. This is low-risk, self-documenting, and matches the existing
   pattern in `AppDelegate.swift:31-34`.

4. **Fix stale comments**:
   - `ContentView+Settings.swift:6-7`: "17-modifier chain" → "13-modifier
     chain (19 on iOS)" (the shared tail is 13, iOS adds 6 more).
   - `SettingsBindings.swift:8-10`: add `showSwipePrompt` to the enumerated
     iOS-only fields: "allowsLandscape, enableActionButtons, showSwipePrompt,
     and showUndoButton".

5. **No macOS UI test target**: Adding `SingleThreadMacUITests` requires
   pbxproj object IDs, scheme TestAction wiring, `-only-testing` entries in
   `scripts/test.sh`, and CI matrix entries — a significant project-structure
   change. Defer to a follow-up ticket. The fix is verified through existing
   macOS unit tests + manual build verification.

## What We're NOT Doing

- **No macOS UI test target** — deferred to a follow-up ticket.
- **No restructuring of the settings architecture** — the single-bag
  pattern, sheet presentation, and write-back chain are working correctly;
  the bug is a rendering issue, not an architecture problem.
- **No new pbxproj entries** — no new targets, build phases, or scheme
  changes.
- **No `#if os(macOS)` guards on individual settings rows** — the `#elseif`
  conversion is about the three `#else` blocks in the sheet construction
  path, not about adding guards to views that are already unconditional.
- **No Notification or Widget changes on macOS** — those are intentionally
  iOS-only and correctly gated.

## Open Risks

- **Root cause uncertainty**: The exact cause of the blank rendering is
  inferred (sheet sizing) but not observed. If the diagnostic reveals a
  different root cause (e.g., SwiftUI `NavigationStack`+`List` rendering bug
  on macOS, or an `@Bindable` lifecycle issue), the fix scope may change.
- **macOS version sensitivity**: Sheet sizing behavior in macOS `WindowGroup`
  may differ between macOS 26 (Sequoia) and earlier versions. The deployment
  target is `MACOSX_DEPLOYMENT_TARGET = 26.5` (`project.pbxproj:765,815`),
  so this should be consistent, but it's worth verifying on the actual
  target.
- **`NavigationStack` inside `.sheet`**: On macOS, `NavigationStack` inside a
  sheet may have different layout behavior than on iOS. If `.frame` alone
  doesn't fix the issue, the `NavigationStack` may need to be extracted or
  the sheet may need to be converted to a `Window` scene on macOS.
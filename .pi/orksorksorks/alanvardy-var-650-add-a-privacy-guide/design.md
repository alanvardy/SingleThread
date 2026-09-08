# Design Discussion — Privacy Guide

## Current State

The Settings screen is a modal `NavigationStack { List { … } }` (`SettingsView.swift:32-33`)
that pushes four themed sub-views via a uniform
`NavigationLink { SubView } label: { Label("Title", systemImage:) }` row idiom:

- Interface (`SettingsView.swift:34,51`) → `InterfaceSettingsView`
- Reminder (`SettingsView.swift:53,61`) → `ReminderSettingsView`
- Filtering & Sorting (`SettingsView.swift:63,70`) → `FilterSortSettingsView`
- Background (`SettingsView.swift:72,79`) → `BackgroundSettingsView`

The root uses `List`; every pushed destination uses `Form` as its container
(Interface `InterfaceSettingsView.swift:37`, Reminder `ReminderSettingsView.swift:22`,
FilterSort `FilterSortSettingsView.swift:36`, Excluded `ExcludedListsView.swift:25`,
Background `BackgroundSettingsView.swift:20`). `SettingsView` owns no state — it forwards
a `@Bindable SettingsBindings` bag plus a separate `@Binding excludedLists`
(`SettingsView.swift:1-8,134-136`).

There is **no user-facing transparency/privacy content anywhere** today. The app's data
footprint, per research Q2:

- **EventKit** reads/writes confined to `ReminderStore` (`ReminderStore.swift:147-238`);
  the watchOS branch is read-only for reminders (`ReminderStore.swift:166-175,199-205`).
- **Two `UserDefaults` tiers**: `AppGroup.defaults` (shared phone↔widget, synced to watch)
  holding `skippedReminderIdentifiers` (`ReminderSkip.swift:121-143`), `excludedListTitles`
  (`ExcludedListStore.swift:6`), `sortOption` (`SortOption.swift:17-26`), and the
  `@AppStorage(store: AppGroup.defaults)` toggles (`ContentView.swift:169-183`); vs
  `.standard` (phone-private cosmetics — `appearanceMode`, `textSize`, `backgroundEnabled`,
  etc., `ContentView.swift:144-165`).
- **Background image cache** on disk under Application Support
  (`BackgroundImageStore.swift:157-161`), fetched over the network from
  `https://vardy.cc/unsplash` (`BackgroundImageStore.swift:112`) plus a follow-up photo URL.
- **WatchConnectivity** (`SkippedReminderSyncService.swift:172-302`) moves the skip/excluded/
  preference payload device-to-device over local `WCSession` only.

The **only** network egress is the background-image fetch. No analytics/telemetry/iCloud
calls exist (research Q2 grep). The **only** `Link(` in the codebase is the Unsplash credit
(`BackgroundSettingsView.swift:31-37`). No localization infrastructure exists anywhere —
all strings are hardcoded Swift literals.

## Desired End State

A new "Privacy" screen, pushed from the root Settings `List` as a fifth
`NavigationLink { … } label: { Label("Privacy", systemImage: "hand.raised") }` row,
explaining in plain language what the app reads, stores, and syncs, and — critically —
what leaves the device. It is a read-only, long-form screen (no bindings, no view model).

Verification:

- New unit test `privacySettingsViewContainsExpectedContent` in
  `SingleThreadTests/SettingsViewTests.swift` asserting the expected headline/body
  substrings render.
- Extend `testSettingsOpensAndShowsControls` (`SingleThreadUITestsFlows.swift:126`) to tap
  into "Privacy" and assert a headline, matching the existing sub-view navigation asserts.
- Existing root labels (`"Interface"`, `"Reminder"`, `"Filtering & Sorting"`,
  `"Background"`, `"Done"`) are **unchanged**; a new row adjacent to them does not break
  the substring/`contains` assertions or the UI flow (research Q4 invariant note).

## Patterns to Follow

- **Row idiom** — the new entry follows the exact `NavigationLink { … } label:
  { Label("Privacy", systemImage:) }` shape as the existing four rows
  (`SettingsView.swift:34-80`). SF Symbol is a lower-case dot-separated literal, matching
  convention (e.g. `"line.3.horizontal.decrease"` at `SettingsView.swift:70`).
- **`Form` container** — like every pushed sub-view (research Q1). The privacy screen is a
  `Form` with `Section`s, `.navigationTitle("Privacy")`, following
  `FilterSortSettingsView.swift:36,59`.
- **Prose rendering** — body paragraphs live as `Text` in `Section` *content* (normal-size
  type) rather than stacked footers. Use `Section {} footer:` only where a single
  disclaimer line fits, mirroring `ExcludedListsView.swift:26-28`.
- **`Link` pattern** — if we link out (e.g. to a data source), reuse the
  `Link("Title", destination:)` form proven in `BackgroundSettingsView.swift:31-37`.
- **Honest disclosure** — the copy must state that reminders/preferences stay on-device or
  in the user's own iCloud, *and* that the background image is fetched from
  `vardy.cc/unsplash`. No claims contradicted by the actual data flow.
- **No view model / no bindings** — a pure read-only view, consistent with `SettingsView`
  owning no state (`SettingsView.swift:1-8`).

### Patterns NOT to follow

- Do **not** add localization (`String(localized:)`/`.xcstrings`) — the codebase is
  hardcoded-literals only (research Q3); introducing it here would be a one-off
  inconsistency.
- Do **not** use `ScrollView` + `VStack` for the body — that breaks the "pushed = `Form`"
  convention, even though it reads better for prose. (Decision Q2-C.)
- Do **not** gate with `#if os(iOS)` — pure `Text`/`Link` content builds on both iOS and
  macOS unchanged (Decision Q5-A). `#if` gating in Settings exists only where a *control*
  is iOS-only (`InterfaceSettingsView.swift:47-52`).

## Design Decisions

1. **Entry point**: new top-level row in the root `SettingsView` `List` — consistent with
   the four existing sub-views; a privacy guide deserves first-class placement (Q1-A).
2. **Row label**: `"Privacy"` with symbol `"hand.raised"` — matches the noun + SF Symbol
   convention; `hand.raised` is the conventional privacy symbol (Q1 default).
3. **Prose structure**: `Form` with per-topic `Section`s carrying body `Text` in section
   content; `footer:` reserved for a single optional disclaimer line (Q2-C). Avoids the
   small-type footer problem and stays in the `Form` idiom.
4. **Content scope**: fully honest disclosure — no table (Q3-A). Sections:
   (a) *Reminders* — read/written via Apple Reminders (EventKit); stay on-device or in your
   own iCloud; never sent to SingleThread or any third party.
   (b) *Display & sync preferences* — stored on-device in shared app storage, synced to
   your own Apple Watch over a direct local connection (not the internet).
   (c) *Skipped & excluded lists* — on-device, same local watch sync.
   (d) *Background image* — downloaded from `vardy.cc/unsplash` when the background is
   enabled; the request is the app's only network use, and no reminder or preference data
   is included in it.
   (e) A closing line: no analytics, no tracking, no advertising.
5. **Test coverage**: unit test (substring pattern) **plus** extend the existing UI flow
   test to navigate into Privacy and assert a headline (Q4-B). No new dedicated
   accessibility audit — the existing audit never enters Settings
   (`SingleThreadUITests.swift:19`), and adding one risks the known GitHub-runner audit
   flakiness.
6. **Platform**: iOS + macOS only (Q5-A). No watch/widget changes — the watch app has no
   Settings surface.

## What We're NOT Doing

- **No localization** — no `.xcstrings`/`.strings`, no `String(localized:)`.
- **No privacy entry on watchOS or the widget** — those targets have no Settings UI.
- **No data-flow changes** — this is documentation only; we are not adding analytics,
  changing the fetch endpoint, or altering any `UserDefaults` tier.
- **No accessibility audit of the Privacy screen** — out of scope per the existing audit's
  main-list-only behavior.
- **No data-retention/export controls** — no "delete my data" or "export" actions; the
  screen is informational.
- **No table/grid of data** — prose sections only (Q3-A), keeping the copy short enough to
  remain truthful without exhaustive enumeration.

## Open Risks

- **Copy accuracy drift** — the disclosure hardcodes facts (e.g. `vardy.cc/unsplash`, local
  WCSession sync). If the data flow changes later, the copy must be updated in the same
  change or it becomes misleading. Consider a code comment near the copy flagging this
  coupling.
- **Prose length vs. `Form` rendering** — long `Text` in section content can wrap oddly on
  narrow/small text sizes; verify at Dynamic Type sizes manually (the existing audit won't
  cover this screen).
- **UI test stability** — extending `testSettingsOpensAndShowsControls` adds a tap + assert
  to an existing green test; low risk, but the headline string must be unique enough not to
  collide with other `staticTexts` (e.g. avoid asserting the word "Privacy" only via a
  substring that might match elsewhere).
- **macOS parity** — the screen is shared; confirm `Text`/`Link` render acceptably in the
  macOS `Form` (the app builds both targets from one file tree). No `#if` is expected, but
  macOS `Form` styling differs from iOS and may need a manual check.
- **Symbol availability** — `hand.raised` must exist on the minimum supported OS for both
  targets; verify against the deployment target before committing.

# Design Discussion

## Current State

The reminder due date is rendered identically on three surfaces, each reading it
independently as `Text(due, style: .date)` + `.font(.caption)` +
`.foregroundStyle(.secondary)`, gated by an `if let`:

- **iPhone/Mac card** — `if let due = reminder.dueDateComponents?.date`
  (`SingleThread/ContentView.swift:242-245`), below the title row (:232) and
  above notes (:247).
- **Watch card** — `if let due = reminder.dueDateComponents?.date`
  (`SingleThreadWatch/WatchReminderView.swift:155-159`), inside `reminderDetails`
  (`:143`).
- **Widget** — `if let dueDate = display.dueDate`
  (`SingleThreadWidget/NextThingWidget.swift:169-172`), inside `reminderView`
  (`:157`).

The date is always shown; there is no way to hide it.

Persistence is split across two domains:

- **App preferences** via `@AppStorage` → `UserDefaults.standard`
  (`SingleThread/ContentView.swift:115-127`): `appearanceMode`, `textSize`,
  `allowsLandscape`, `showMicrophoneButton`. The latter two are plain `Bool`
  toggles defaulting to `true`, presented as `Toggle`/`Label` rows in
  `SettingsView` (`SingleThread/SettingsView.swift:57-59`), which owns no state —
  every control is a `Binding` (`SettingsView.swift:8-29`).
- **Cross-process skipped-reminder IDs** via `SkippedReminderStore` →
  `AppGroup.defaults` (`SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift:111-126`,
  `AppGroup.swift:13-14`). The widget reads these through `ReminderStore`'s
  default `SkippedReminderStore`; the watch has no App Group entitlement and no
  `UserDefaults` usage at all — it syncs skipped IDs over WatchConnectivity via
  `SkippedReminderSyncService` (`SkippedReminderSyncService.swift:56-91`).

The widget target already carries the App Group entitlement
(`project.pbxproj:844,872`), so it can read `AppGroup.defaults` directly. The
watch target does not.

## Desired End State

A "Show Date" toggle appears in `SettingsView` on iOS and macOS, defaulting to
**on** (today's behavior). When turned off, the due-date row disappears from all
three surfaces: iPhone/Mac card, watch card, and widget. When on, nothing
changes. Sorting, the overdue fetch window, and the priority/title layout are
untouched.

Verification: the date row's `if let due` gate becomes
`if showDate, let due = …` on all three surfaces; shipped tests confirm the
toggle row, the preference round-trip, and that setting the key `false` removes
the row. The reading surfaces stay in sync: phone writes one shared key, widget
reads it directly, watch receives it over WatchConnectivity.

## Patterns to Follow

- **Injectable store struct** — mirror `SkippedReminderStore`
  (`ReminderSkip.swift:111-126`): `init(defaults:key:)`, small `load`/`set`
  methods, `AppGroup.defaults` as the default store. The new
  `ShowDatePreference` lives in `SingleThreadCore` so phone, widget, and watch
  share one key + default with zero drift.
- **`@AppStorage` toggle with `store:`** — like `showMicrophoneButton`
  (`ContentView.swift:126-127`), but with an explicit store:
  `@AppStorage("showDate", store: AppGroup.defaults) private var showDate = true`.
- **`Toggle` + `Label(title, systemImage:)` row** — match `Show Microphone`
  (`SettingsView.swift:57-59`); add the row to **both** `SettingsView` inits
  (iOS and macOS variants, `SettingsView.swift:10-29`), alongside
  `showMicrophoneButton`.
- **`.onChange` side-effect pattern** — `allowsLandscape` fires
  `AppDelegate.applyLock` from `.onChange` (`SettingsView.swift:53-55`); wire the
  new toggle the same way to trigger the widget reload + watch push (see
  decisions).
- **WatchConnectivity payload keys** — extend the private `PayloadKey` enum with
  `showDate = "showDate"` (`SkippedReminderSyncService.swift:118-120`).
- **Widget timeline reload** — reuse the existing
  `WidgetCenter.shared.reloadAllTimelines()` hook (`SingleThreadApp.swift:39-42`).
- **`if let` optional gating** — keep the existing card skeleton; only prepend
  `showDate &&` to the date condition on each surface.

### Patterns NOT to follow

- **Do not centralize the date `Text` itself.** The `dueDateComponents?.date`
  mapping is already duplicated across three views (`ContentView.swift:242`,
  `WatchReminderView.swift:155`, `ReminderDisplay.swift:14`) — a pre-existing
  smell. Don't expand it; just gate locally.
- **Do not key off `bool(forKey:)` alone in the widget.** An absent key returns
  `false`, which would hide dates by default. `ShowDatePreference` must treat a
  missing key as `true` (nil-check), and the app's `@AppStorage` default must be
  `true`.
- **Do not put `showDate` in `UserDefaults.standard` on the phone** — the widget
  cannot read the app's standard defaults; that's the trap Q4/standard-defaults
  avoided.

## Design Decisions

1. **Toggle shape**: plain `Bool`, key `showDate`, label "Show Date" (system
   image `calendar`), default `true`. Mirrors `showMicrophoneButton`
   (`ContentView.swift:126-127`, `SettingsView.swift:57-59`); opt-out, not
   opt-in.

2. **Storage = App Group**: the preference lives in
   `group.app.alanvardy.SingleThread` (`AppGroup.swift:8`). The app binds with
   `@AppStorage("showDate", store: AppGroup.defaults)`; the widget reads the same
   key. Single source of truth shared app↔widget, like skipped IDs
   (`ReminderSkip.swift:114`).

3. **Core type owns key + default**: add `ShowDatePreference` to
   `SingleThreadCore`, a struct mirroring `SkippedReminderStore`
   (`ReminderSkip.swift:111-126`) with `init(defaults: AppGroup.defaults,
   key: "showDate")`, `isEnabled` (nil → `true`), and `set(_:)`. Phone, widget,
   and watch all reference it — no key-string drift.

4. **Widget reads via entry**: `NextThingProvider.makeEntry`
   (`NextThingWidget.swift:50`) reads `ShowDatePreference().isEnabled` and
   carries it on `NextThingEntry` (new `let showsDate: Bool`); `reminderView`
   gates `if entry.showsDate, let dueDate = display.dueDate`
   (`NextThingWidget.swift:169`). Deterministic per-timeline read, no
   `@AppStorage` in the widget view.

5. **Watch via existing WatchConnectivity service**: extend
   `SkippedReminderSyncService` to carry `showDate` in the same
   `updateApplicationContext` push (`:58`), so it's latest-wins and auto-delivers
   on (re)connect (`:21`). `didReceiveApplicationContext` (`:79`) writes the
   received value to the watch's `UserDefaults.standard` via
   `ShowDatePreference(defaults: .standard).set(...)`. `WatchReminderView` adds
   `@AppStorage("showDate") private var showDate = true` (watch sandbox) and
   gates `if showDate, let due = …` (`WatchReminderView.swift:155`). No new
   entitlement, no watch settings UI.

6. **Prompt widget refresh on toggle change**: the toggle's `.onChange` (new,
   mirroring `allowsLandscape` at `SettingsView.swift:53-55`) triggers
   `WidgetCenter.shared.reloadAllTimelines()` — reusing the hook already present
   in `SingleThreadApp.swift:39-42` — so the widget doesn't wait out its 15-min
   refresh (`NextThingWidget.swift:43`).

7. **Both payload keys always travel together**: `updateApplicationContext` is a
   whole-context replace (`:58`), so the phone's push must always send
   `skippedReminderIdentifiers` **and** `showDate` in one call, or one clobbers
   the other.

## What We're NOT Doing

- **No change to sorting or the fetch window.** `ReminderSort`
  (`ReminderSort.swift:7-34`) and `ReminderDateFilter`/`overdueCutoff`
  (`ReminderDateFilter.swift:26-50`) keep using due dates even when hidden —
  hiding only affects display.
- **No watch settings surface.** The watch has no preferences UI today
  (research Q5); it simply mirrors the phone's value.
- **No date-format options** (relative dates, time, countdown). Plain
  `Text(…, style: .date)` stays.
- **No sharing of other prefs across surfaces.** `showDate` is the only
  cross-process preference; `appearanceMode`/`textSize` stay app-local.
- **No refactor of the duplicated date rendering** — pre-existing duplication is
  out of scope.

## Open Risks

- **Watch first-launch staleness**: before the first WatchConnectivity context
  arrives, the watch shows dates even if hidden. Accepted; `updateApplicationContext`
  auto-delivers on connect, so it self-heals within the first sync.
- **`@AppStorage` fallback**: `AppGroup.defaults` falls back to `.standard` on
  watchOS/unregistered simulators/previews (`AppGroup.swift:10-12`); tests and
  previews must inject `UserDefaults` or rely on the nil→`true` default.
- **Whole-context clobbering**: if a future change pushes only one of the two
  keys, the other is dropped. Decision 7 is the guard; a follow-up payload struct
  would make this compile-time safe.
- **`SkippedReminderSyncService` is under active cleanup** (its own "removal
  plan" comment, `SkippedReminderSyncService.swift:32-36`); keep the `showDate`
  addition additive (one `PayloadKey` + one save) to avoid widening the API the
  team plans to refactor.
- **CI strictness**: warnings-as-errors, SwiftLint `--strict`, and Periphery are
  all enforced; `ShowDatePreference` must be referenced by app, widget, and watch
  (or Periphery flags it), and new tests go inside `SingleThreadTests/`
  (auto-discovered, no Makefile/`-only-testing` change needed).
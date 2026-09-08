# Design Discussion — Add iPhone Complete/Skip action buttons (VAR-641)

## Current State

The iPhone bottom bar is a `VStack(spacing: 8){...}.padding(.bottom,16)`
(`ContentView.swift:369-399`) rendered in the two non-all-skipped branches of
`reminderList`, pinned to the bottom edge of the safe area inside
`ZStack(alignment: .bottom)` (`ContentView.swift:297-363`).

Children of `bottomBar`, in order:
1. `#if os(macOS) if store.visibleReminders.first != nil { actionButtons }`
   (`ContentView.swift:373`) — macOS-only full action row (Complete/Skip/Delete).
2. Optional dictation error text (`:376`).
3. `creationFeedback` → `creationFeedbackView`; else `isDictating` →
   recording indicator; else `canDictate, showMicrophoneButton` → `micButton`
   (`ContentView.swift:385-395`).

`micButton` (`ContentView.swift:403-417`) is a 56×56 blue circle
(`Image("mic.fill").font(.title2)`) with `.background(.blue, in: Circle())`,
`.accessibilityLabel("Dictate reminder")`, `.accessibilityAddTraits(.isButton)`.

The only existing fixed Complete/Skip surface on iOS lives on the reminder
`List` as `.swipeActions(.leading)=Complete` / `.swipeActions(.trailing)=Skip`,
plus a `.contextMenu` with View-in-Reminders / Delete (`ContentView.swift:320-360`).

WatchOS styling source (`WatchReminderView.swift:85-101`): an `HStack` of
Complete (async `await store.completeCurrentReminder()`,
`label: Label("Complete", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly)`,
`.tint(.green)`, `.accessibilityLabel("Complete reminder")`) + Skip
(sync `store.skipCurrentReminder()`, `"circle.slash"`, `.tint(.orange)`,
`.accessibilityLabel("Skip reminder")`), both `.accessibilityAddTraits(.isButton)`.

Settings (`SettingsView.swift:174-187`) owns no state — every preference is a
`@Binding` passed from `ContentView` (`ContentView.swift:98-117`). Toggle rows
(Show Microphone / Show Undated / Show Date) at `SettingsView.swift:121-126`.
Persistence splits: `showMicrophoneButton` is plain
`@AppStorage("showMicrophoneButton")` → `.standard`
(`ContentView.swift:184-185`); shared prefs use
`@AppStorage(_, store: AppGroup.defaults)` (`:186-191`).

## Desired End State

When the new Settings toggle **"Enable action buttons"** is on AND there is a
visible reminder, the iPhone bottom bar renders **Complete on the left and
Skip on the right of the mic button** — Complete replacing the mic's left gap
and Skip its right. The buttons use the watch action-button styling.
Hidden (off) by default; toggled in Settings; only present on iOS.

**Verification**
- Unit tests assert the buttons appear in the iOS bottom bar only when the
  toggle is on and a visible reminder exists (see Test Plan).
- `SettingsViewTests` asserts the new row "Enable action buttons".
- Accessibility audit passes with the two new buttons (same label/traits as
  the existing watch buttons).
- Complete persists to EventKit; Skip writes the shared skipped list — both
  reuse existing store calls (no new persistence logic).

## Patterns to Follow

- **Shared cross-platform action idiom.** Every existing surface uses the same
  symbols, tints, and labels: Complete = `checkmark.circle.fill`/`.green`, Skip
  = `circle.slash`/`.orange`, `.iconOnly` labels, `.accessibilityLabel(...reminder)`,
  `.accessibilityAddTraits(.isButton)`. Match the watch exactly
  (`WatchReminderView.swift:86-101`) and the macOS row
  (`ContentView.swift:223-240`).
- **Sync/async split per button.** Complete wraps `Task { await store.completeCurrentReminder() }`
  (async); Skip calls `store.skipCurrentReminder()` synchronously — matching
  the watch/macOS/swipe call sites. Do NOT use `skipCurrentReminderImmediately()`
  (that variant exists for the widget process only).
- **Settings `@Binding` wiring.** Add the toggle as an iOS-only `@Binding` in
  `SettingsView.swift` and pass it in from `ContentView.swift` (both the `#if
  os(iOS)` `.sheet` call and the iOS `init`), mirroring how `allowsLandscape`
  is threaded (`ContentView.swift:98-117`, `SettingsView.swift:174-187`).
- **`.standard` persistence for a device-local chrome toggle** (mirrors
  `showMicrophoneButton`, `ContentView.swift:184-185`), NOT `AppGroup.defaults`.
- **Gating mirrors the macOS `actionButtons` condition**
  (`ContentView.swift:373`): only when `store.visibleReminders.first != nil`.
- **Icon-only flanking buttons share the `micButton` presence.** The two
  buttons ride the same `else if canDictate, showMicrophoneButton` branch as
  the mic, so they naturally disappear while error-feedback / dictation / when
  the mic toggle is off or speech is denied (`ContentView.swift:385-395`).

Do NOT follow: the widget `Button(intent:)` pattern (`NextThingWidget.swift:82-106`),
`skipCurrentReminderImmediately()` (`ReminderStore.swift:239-247`), or the
`.contextMenu` deep-link deletion path — irrelevant to a plain bottom-bar button.

## Design Decisions

1. **Toggle gating** — Add `@AppStorage("enableActionButtons")` default `false`,
   persisted to `.standard` (device-local). The flanking buttons render only when
   this is on AND `store.visibleReminders.first != nil` (mirrors macOS). Off-by-
   default satisfies "hidden by default".
2. **Placement & layout** — Wrap the mic in an `HStack(spacing:16,
   alignment:.center) { complete; micButton; skip }` inside the existing
   mic branch. Both flanking buttons use an identical `.frame(...44)` so the
   mic text `width:56` stays visually centered. Complete left, mic center,
   Skip right.
3. **Store calls** — Complete: `Task { await store.completeCurrentReminder() }`.
   Skip: `store.skipCurrentReminder()` (sync, settle-delayed apply). No new
   store API. Skip's delayed apply is fine on iPhone because the writer is always
   this device.
4. **Settings surface** — Add the toggle row `Toggle(isOn: $enableActionButtons) {
   Label("Enable action buttons", systemImage: "..." ) }` to `SettingsView`
   under iOS-only (like `allowsLandscape`), threading the `@Binding` only in the
   iOS init/call site. Do NOT add it to macOS — the macOS action buttons are not
   gated by it, so it would be a dead toggle there.
5. **Platform scoping** — The new bottom-bar cluster is iOS-only (`#if os(iOS)`).
   macOS keeps its existing `actionButtons` row unchanged. Android not applicable.
6. **Keep existing interactions** — swipeActions and contextMenu remain. The
   new buttons are an alternative, not-saturated, sourced discoverability path.

## What We're NOT Doing

- NOT adding a Delete button to the iPhone bottom row (task specifies Complete
  + Skip only; Delete stays in − contextMenu and macOS row).
- NOT adding keyboard shortcuts (`iOS `c`/`s`/`d`) — the iPhone row is touch.
- NOT using `skipCurrentReminderImmediately()`.
- NOT changing the watch, widget, or macOS action surfaces.
- NOT persisting the toggle via `AppGroup.defaults` (device-local only).
- NOT gating or altering the existing swipe/context actions.

## Test Plan

- `SettingsViewTests.swift`: add the `enableActionButtons...` iOS-only binding
  (`.constant(true)`) to the iOS constructor and a
  `#expect(bodyDescription.contains("Enable action buttons"))`.
- New/extended unit tests mirroring `MicrophoneToggleTests.swift`: inject a
  `ContentView` with a pre-populated `ReminderStore` (a real reminder +
  `.authorized` fake transcriber) and `UserDefaults.standard.set(true,
  "enableActionButtons")`; assert the body description contains "Complete" and
  "Skip", and that they are absent when the toggle is off or no reminder is
  visible.
- UI test: because `--ui-testing` on iOS creates an **empty** store
  (`SingleThreadApp.swift:18-20`), add a deterministic pre-populated store seam
  (like the watch's `Self.uiTestingStore()`, `SingleThreadWatchApp.swift:22-35`)
  OR a test that launches with the toggle on + a seeded reminder, then assert the
  action buttons appear; run the accessibility audit.

## Open Risks

- **iOS UI-test seam.** The current `--ui-testing` store is empty, so the new
  buttons won't render in the default iOS audit path. The Test lead may need the
  deterministic-store seam like the watch.
- **Mic centering.** A symmetric 44pt frame keeps the mic centered; verify
  visually in the iOS preview, especially with the `.padding(.bottom,16)`.
- **Settle-delayed skip.** `store.skipCurrentReminder()` applies after a
  200ms settle sleep; the UI updates via `onSkipSetChanged`. Confirm the row
  reflects the skip without an explicit reload (expected: yes).
- **Toggle default migration.** Off-by-default is new; a previously-installed
  devices with no key will get `false`. Confirm no preview/test currently sets
  it.
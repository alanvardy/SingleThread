# Structure Outline

## Approach

Add a "Show Date" toggle (default **on**) that hides the due-date row — already
rendered identically as `Text(due, style: .date)` + `.font(.caption)` +
`.foregroundStyle(.secondary)` on three surfaces — by prepending `showDate &&`
to each surface's existing `if let due` gate. One shared key
(`"showDate"`, stored in the App Group) is written by the phone, read directly
by the widget, and pushed to the watch over the existing WatchConnectivity
service. Sorting, the fetch window, and layout are untouched.

Each phase below is a **vertical slice**: it touches persistence → service → UI
for one surface, is independently valuable, and has a verification checkpoint.

---

## Phase 1: Phone/Mac — toggle + card gate + shared preference

Delivers the core feature end-to-end on iPhone and macOS: a settings row that
writes one shared key, and the card hiding/showing its date row. This also
publishes the `ShowDatePreference` core type + App Group key that Phases 2–3
build on.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/ShowDatePreference.swift` *(new)*
- `SingleThread/ContentView.swift`
- `SingleThread/SettingsView.swift`
- `SingleThreadTests/ShowDatePreferenceTests.swift` *(new)*
- `SingleThreadTests/ShowDateTests.swift` *(new)*
- `SingleThreadTests/SettingsViewTests.swift`

**Key changes**:
- `struct ShowDatePreference` *(new)* — mirrors `SkippedReminderStore`:
  `init(defaults: UserDefaults = AppGroup.defaults, key: String = "showDate")`,
  `var isEnabled: Bool` (nil → **`true`**, so a missing key keeps today's behavior;
  *not* `bool(forKey:)`), and `func set(_ enabled: Bool)`.
- `@AppStorage("showDate", store: AppGroup.defaults) private var showDate = true`
  in `ContentView.swift` (the only new `@AppStorage`, lives beside
  `showMicrophoneButton`).
- `SettingsView.init` gains `showDate: Binding<Bool>` in **both** the iOS and
  `#else` (macOS) variants; new `@Binding private var showDate: Bool`; new row
  `Toggle(isOn: $showDate) { Label("Show Date", systemImage: "calendar") }`.
- `ContentView.swift:242` gate becomes
  `if showDate, let due = reminder.dueDateComponents?.date`.
- `ContentView`'s `.sheet` passes `showDate: $showDate` to `SettingsView`
  (iOS + macOS branches); previews updated.

**Verify**: `make test` (new unit tests below), `make build`, `make mac-build`.
Manual: open Settings → turn "Show Date" off → date row vanishes from the card on
the iPhone and Mac; toggle back on → row returns.
- `ShowDatePreferenceTests`: default `isEnabled == true` with no key;
  `set(false)` round-trips; missing key ≠ `false`.
- `ShowDateTests` (string-snapshot of `ContentView.body`, mirroring
  `MicrophoneToggleTests`): with `loadsReminders: false` + a dated reminder,
  `AppGroup.defaults.set(false, forKey: "showDate")` removes the date text;
  `true` restores it (with `defer` cleanup).
- `SettingsViewTests.settingsViewContainsAllPreferenceRows()`: add `"Show Date"`.

---

## Phase 2: Widget — read the shared key, gate the date row

The widget reads the same App Group key and hides the date. The phone toggle now
also prompts an immediate timeline reload so the widget doesn't wait out its
15-minute refresh.

**Files**:
- `SingleThreadWidget/NextThingWidget.swift`
- `SingleThread/SettingsView.swift`

**Key changes**:
- `struct NextThingEntry` gains `let showsDate: Bool` (alongside `date`, `state`).
- `NextThingProvider.makeEntry()` reads `ShowDatePreference().isEnabled` and sets
  `showsDate:` on every `NextThingEntry` (placeholder/snapshot entries hardcode
  `true`).
- `reminderView(_:)` gate becomes
  `if entry.showsDate, let dueDate = display.dueDate` (`NextThingWidget.swift:169`).
- `SettingsView`: `.onChange(of: showDate) { _, _ in WidgetCenter.shared.reloadAllTimelines() }`
  (with `import WidgetKit` under `#if os(iOS) || os(macOS)`), mirroring the
  existing `allowsLandscape` `.onChange`.

**Verify**: `make build` (builds the app **and** the widget extension) and
`make mac-build`; unit tests still green. Manual: toggle on the phone → the widget
refreshes immediately (not after 15 min) and drops/restores the date row.
*Note*: the widget is a separate extension target and isn't unit-testable from
`SingleThreadTests`; verification here is compile + manual.

---

## Phase 3: Watch — WatchConnectivity push + watch card gate

The watch mirrors the phone's choice: the existing sync service now carries
`showDate` alongside the skip IDs, the watch writes it to its own
`UserDefaults.standard`, and `WatchReminderView` gates its date row.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
- `SingleThread/SingleThreadApp.swift`
- `SingleThreadWatch/SingleThreadWatchApp.swift`
- `SingleThreadWatch/WatchReminderView.swift`
- `SingleThreadTests/SkippedReminderSyncServiceTests.swift`

**Key changes**:
- `PayloadKey.showDate = "showDate"` *(new)*.
- `SkippedReminderSyncService` init gains two defaulted params (keeps existing call
  sites compiling):
  `init(session: any SkipSyncSession, skipStore: SkippedReminderStore, showDateStore: ShowDatePreference = ShowDatePreference(), sendsShowDate: Bool = true)`.
- `pushSkipIDs(_ ids: [String])` now sends **both** keys when `sendsShowDate`:
  `[skippedReminderIdentifiers: ids, showDate: showDateStore.isEnabled]`
  (guards decision 7's whole-context clobber).
- `pushShowDate(_ enabled: Bool)` *(new)*: sends
  `[skippedReminderIdentifiers: skipStore.load(), showDate: enabled]`.
- `didReceiveApplicationContext` additionally does
  `if let showDate = context[PayloadKey.showDate] as? Bool { showDateStore.set(showDate) }`
  (absent key → no-op, so a skip-only push never clobbers `showDate`).
- **Phone** (`SingleThreadApp.swift`): retain the service; add
  `@AppStorage("showDate", store: AppGroup.defaults) private var showDate = true`;
  wire `.onChange(of: showDate) → service.pushShowDate(newValue)`. Uses
  `sendsShowDate: true`.
- **Watch** (`SingleThreadWatchApp.swift`): construct the service with
  `showDateStore: ShowDatePreference(defaults: .standard)` and `sendsShowDate: false`
  — the watch *receives* `showDate` but never echoes it back.
- `WatchReminderView.swift`: add `@AppStorage("showDate") private var showDate = true`
  (watch sandbox, `.standard`); gate becomes `if showDate, let due = …` at `:155`.

**Verify**: `make test` (new sync tests), `make watch-build`,
`./scripts/test.sh` (full pipeline). Manual: pair a watch, toggle on the phone;
the watch drops/restores the date row within the first sync.
- `SkippedReminderSyncServiceTests`: `pushSkipIDsIncludesShowDate`,
  `pushShowDateSendsBothKeys`, `receiveContextWritesShowDate` (to `.standard`),
  `receiveContextMissingShowDateLeavesLocalUnchanged`,
  `sendsShowDateFalseOmitsKey` (the watch-never-echoes guard).

---

## Testing Checkpoints

- **After Phase 1**: `ShowDatePreference` round-trips; `"Show Date"` row present;
  phone/mac card hides the date on `showDate == false`. `make test`, `make build`,
  `make mac-build` green. (`ShowDatePreference` stays Periphery-clean: public,
  referenced from `SingleThreadTests`, which imports `SingleThreadCore`
  non-`@testable`.)
- **After Phase 2**: `NextThingEntry.showDate` flows into the widget's date gate;
  toggling on the phone reloads widget timelines. `make build` (app + widget) green.
- **After Phase 3**: both payload keys travel phone→watch in one context; watch
  writes to `.standard` and gates its card; watch never echoes `showDate` back.
  `make watch-build` + full `./scripts/test.sh` green.
- **Final**: run `./scripts/test.sh` once more end-to-end; confirm the design's
  tri-surface invariant — key `"showDate"` `false` removes the date row on phone,
  widget, and watch.

## Noted gaps in design.md

- **Watch→phone echo (decision 7 is one-directional).** `updateApplicationContext`
  is whole-context replace, and the watch *also* pushes skip IDs
  (`SingleThreadWatchApp.swift:19`). If the watch included `showDate` in that push,
  a stale watch value could overwrite the phone's fresh toggle. Phase 3 resolves
  this with `sendsShowDate: false` (phone is authoritative for `showDate`);
  `didReceiveApplicationContext` adopts `showDate` only when the key is present.
  If the team would rather make this compile-time-safe *now*, the follow-up
  "payload struct" mentioned in design.md's risks could replace the two booleans —
  but that widens the API the sync-service "removal plan" comment asks us to keep
  additive.
- **First-launch staleness** (accepted in design.md): the watch shows dates until
  the first context arrives; self-heals on connect. Unchanged by this outline.
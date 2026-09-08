# Structure Outline

## Approach

Extend `ReminderDisplay` with `listName` and route the iOS card through it (starting the
documented `EKReminder` removal plan), add a default-off `ShowListPreference` in the App
Group so iOS and the widget share one key, then normalize Settings labels. Four vertical
slices, each independently testable.

---

## Phase 1: List name on the iOS card (via `ReminderDisplay`)

Delivers the list name rendering end-to-end on the iOS card, with the card's input swapped
from raw `EKReminder` to `ReminderDisplay` — the foundation later phases read from.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`,
`SingleThread/ReminderCardView.swift`, `SingleThread/ContentView.swift`,
`SingleThreadTests/ReminderDisplayTests.swift`, `SingleThreadTests/ShowDateTests.swift`

**Key changes**:
- `ReminderDisplay.listName: String?` — new field; `init(reminder:)` populates from
  `reminder.calendar?.title`; direct init gains `listName: String? = nil`
- `ReminderCardView.init(display: ReminderDisplay, showDate: Bool, showList: Bool = false,
  showsOverPhoto: Bool = false)` — input swap; body reads `display.title/.priorityMarker/
  .notes/.dueDate/.listName`; list-name row gated on BOTH pref and data
  (`if showList, let listName = display.listName`), secondary style under the date row
- `ContentView.reminderList`: wraps `ReminderDisplay(reminder:)` and passes
  `showList:` (temporary literal `true` until Phase 2 wires the pref)
- Test factories updated to build `ReminderDisplay` instead of `EKReminder`

**Verify**: unit tests pass (`make test SIM=... -only-testing:SingleThreadTests`);
snapshot tests assert list name present with a calendar title, absent when nil.
Manual: run app — card shows list name beneath the date for a reminder in a named calendar.

---

## Phase 2: "Show list" preference end-to-end

Delivers the toggle, persistence, and gating — the user-facing control that turns Phase 1's
row off (default state).

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ShowListPreference.swift` (new),
`SingleThread/ContentView.swift`, `SingleThread/SettingsView.swift`,
`SingleThreadApp.swift`, `SingleThreadTests/ShowListPreferenceTests.swift` (new),
`SingleThreadUITests/SingleThreadUITestsFlows.swift`

**Key changes**:
- `struct ShowListPreference { init(defaults: UserDefaults = AppGroup.defaults,
  key: String = "showList"); var isEnabled: Bool; func set(_: Bool) }` — missing key ⇒
  `false` (mirror of `ShowDatePreference`, inverted default)
- `@AppStorage("showList", store: AppGroup.defaults) private var showList = false`
  in `ContentView`; passed into `SettingsView` binding and `ReminderCardView`
- `Toggle(isOn: $showList) { Label("Show list", systemImage: "list.bullet") }` — new row
- `"showList"` added to `--seed` reset key list (`SingleThreadApp.resetPersistedState`)
- UI test: flip toggle → relaunch with `--ui-testing` → still flipped

**Verify**: preference round-trip + missing-key unit tests pass; relaunch-persistence UI
test passes. Manual: Settings → toggle off → row disappears from card.

---

## Phase 3: Widget honors the same preference

Delivers list-name display in the widget, gated by the shared `showList` key — no extra
refresh wiring needed since the widget re-reads defaults at timeline build time.

**Files**: `SingleThreadWidget/NextThingWidget.swift`,
`SingleThreadTests` (snapshot test for widget render if pattern permits — else manual)

**Key changes**:
- `NextThingEntry.showsList: Bool` — new field, populated via `ShowListPreference().isEnabled`
  alongside `showsDate` in all five construction sites
- `reminderView(_ display: ReminderDisplay)` gains:
  `if showsList, let listName = display.listName { Text(listName)...secondary }`
  near the date line
- Preview entries updated

**Verify**: widget extension builds; unit tests pass. Manual: add widget to home screen /
gallery preview — list name appears only when the iOS toggle is on.

---

## Phase 4: Sentence-case label normalization

Renames existing Settings labels per design decision 4. Independent of Phases 1–3 but last
because it breaks text-matched XCUI queries across already-green tests.

**Files**: `SingleThread/SettingsView.swift`,
`SingleThreadTests/SettingsViewTests.swift`, `SingleThreadUITests/*.swift`

**Key changes**:
- Labels → "Allow landscape", "Show microphone", "Show date", "Show undated reminders",
  "Enable action buttons" → "Show action buttons" (storage keys unchanged)
- Updated assertions in `SettingsViewTests` (`contains("Show Undated")` etc.) and every
  XCUI query matching renamed text (grep `app.switches["Show Date"]` and friends)

**Verify**: `./scripts/test.sh` full gate passes (unit + UI + lint). Manual: Settings rows
read sentence-cased on iPhone and macOS branches.

---

## Testing Checkpoints

- **After Phase 1**: `ReminderDisplayTests` covers `listName` mapping; card snapshot tests
  show/hide the list-name row by data. Card compiles against `ReminderDisplay` everywhere
  (no remaining `EKReminder` inputs).
- **After Phase 2**: `showList` round-trips, defaults `false` on missing key, resets under
  `--seed`, persists across relaunch in a UI test, and gates the card row.
- **After Phase 3**: Widget renders list name iff shared pref is on and data exists;
  both surfaces read the single App Group key.
- **After Phase 4**: Full CI-equivalent gate green; no test references old label strings.

Note: nothing in this design is horizontally-sliced-only; each phase touches Core + app UI
(+ widget where relevant) and has its own checkpoint.

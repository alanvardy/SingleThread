# Research Findings

All paths are relative to the repo root (`/Users/vardy/dev/alanvardy-var-698-show-code-blocks`). Line numbers verified against the current sources.

## Q1: How `title` and `notes` flow from `EKReminder` → `ReminderDisplay`/`ReminderNotesFormatter` → `Text`

### Findings
- **Single bridge struct.** `ReminderDisplay` (`SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`) is the one display-ready struct mapped from `EKReminder`, reused by iOS, watch, widget, and tests. `public init(reminder:)` (line 9) maps `title = reminder.title` (line 12), `notes = ReminderNotesFormatter.format(reminder.notes)` (line 13), plus `dueDate`, `priorityMarker`, `listName`, `hasRecurrence`, `recurrenceSummary`, `hasAlarms` (lines 14–18).
- **Type split.** `title` is declared **non-optional `String`** (`ReminderDisplay.swift:31`); `notes` is declared **optional `String?`** (`ReminderDisplay.swift:32`).
- **Title nil nuance.** `EKReminder.title` lives on `EKCalendarItem` as `null_unspecified NSString`, so it imports as implicitly-unwrapped `String!`; assigning it to the non-optional `String` at `ReminderDisplay.swift:12` compiles, but a runtime-nil title would trap (no guard/default).
- **`ReminderNotesFormatter.format`** (`ReminderSkip.swift:93` enum, `format` at `:103`) → `String?`:
  - nil input → `nil` (`:104`);
  - trims whitespace/newlines, empty-after-trim → `nil` (`:105–106`);
  - strips a leading `"t"` artifact (`"tBuy milk"` → `"Buy milk"`) only when the `t` is followed by whitespace/uppercase/end-of-string, then re-trims; if cleaned to empty → `nil` (`:107–114`); otherwise trimmed text (`:116`).
- **Consumers all receive a plain `String` to `Text`.** A repo-wide grep for `AttributedString|NSAttributedString|AttributeContainer` returned **zero matches** in sources.
  - **iOS card** `SingleThread/ReminderCardView.swift`: `Text(display.title)` unconditional at `:39` (`.font(.title)` `:40`); `if let noteText = display.notes { Text(noteText) ... }` at `:71–75` — emitted only when `display.notes` is non-nil.
  - **ContentView** builds/owns the display: `ReminderDisplay(reminder: reminder)` passed into `ReminderCardView` at `SingleThread/ContentView.swift:298`; `ContentView` itself never touches title/notes.
  - **Watch** `SingleThreadWatch/WatchReminderView.swift`: `let display = ReminderDisplay(reminder: reminder)` at `:158`; `Text(display.title)` at `:189`; `if let noteText = display.notes { Text(noteText) ... }` at `:213`.
  - **Widget** `SingleThreadWidget/NextThingWidget.swift`: `ReminderDisplay(reminder: current)` in `makeEntry` at `:94`; `Text(display.title)` at `:205`; `if let notes = display.notes { Text(notes) ... }` at `:230`.
- **Absent/present handling.** Title is always rendered unconditionally (non-optional `String`, all three surfaces). Notes are rendered only when the formatter returns non-nil (absent = nil, whitespace-only, or `t`-artifact-to-empty); absent notes produce no `Text` view on any surface.
- **Placeholder/preview path.** The direct constructor `ReminderDisplay(title:notes:...)` (`ReminderDisplay.swift:22–40`, `notes` defaults to `nil`) is used by widget placeholders/snapshots/previews (e.g. `NextThingWidget.swift:94` `state` variations), exercising the "absent notes" branch.

---

## Q2: How `Text`/SwiftUI styles title, notes, and multi-line content per surface

### Findings
**iOS — `SingleThread/ReminderCardView.swift`**
- Title row `HStack(alignment: .firstTextBaseline, spacing: 4)` at `:29`; priority marker `Text(.title)` with `priorityColor` foreground at `:35–36` (only rendered when `priorityMarker` maps to a known level); title `Text(display.title).font(.title)` at `:39–40`. **No line limit** on iOS title and no explicit foreground (inherits primary).
- Notes block `if let noteText = display.notes { Text(noteText).font(.callout).foregroundStyle(.secondary).lineLimit(3) }` at `:71–75` (`Text(noteText)` `:72`, `.font(.callout)` `:73`, `.lineLimit(3)` `:75`). **Only surface combining `.callout` + `.lineLimit(3)`.**
- Backing `VStack(alignment: .leading, spacing: 4)` at `:26`; the card is a `List` row in `ContentView.swift` (seeded `List` around `:296`).
- Whole card `.accessibilityElement(children: .combine)` at `:82`; optional `showsOverPhoto` plate at `:98–109`.
- Global font scaling: `ContentView.swift:99` applies `TextSizeModifier` (mapped to a `dynamicTypeSize` override in `SingleThread/TextSizeModifier.swift:12–15`, selections in `TextSize.swift:32–45`). No `.minScaleFactor`/`.allowsTightening` per view.

**iOS tests do not assert styling.** `SingleThreadTests/ReminderDisplayTests.swift` asserts only data mapping (`mapsTitle` :10, `formatsNotes` :16, `mapsNilNotes` :24), never font/lineLimit.

**watchOS — `SingleThreadWatch/WatchReminderView.swift`**
- Reminder body wrapped in a `ScrollView` at `:157`, so title/notes are **never truncated**.
- Title `Text(display.title).font(.headline)` at `:189–190`; no lineLimit.
- Notes `Text(noteText).font(.caption2).foregroundStyle(.secondary)` at `:213–215`; **no lineLimit** (scroll extends unbounded).
- Supporting rows use `.caption`/`.caption2` + `.secondary` (lines `:194–210`); card `VStack(spacing: 6)` at `:156`, title `HStack` at `:182`.

**Widget — `SingleThreadWidget/NextThingWidget.swift`**
- `VStack(alignment: .leading, spacing: 4)` at `:198`; title row `HStack` at `:199`.
- Priority marker `.font(.subheadline)` + `.foregroundStyle(.secondary)` at `:201–203` (secondary, not colored).
- Title `Text(displayText).font(.headline).lineLimit(2)` at `:205–207` (hard-capped 2).
- Notes `Text(notes).font(.caption2).foregroundStyle(.secondary).lineLimit(2)` at `:230–233`.
- dueDate `.font(.caption)`/`.secondary` at `:211–212`; listName `:216–217`; recurrence/alarm rows `:221–227`.

### Cross-surface styling comparison
| Surface | Title font | Title lineLimit | Notes font | Notes lineLimit | Scroll |
|---|---|---|---|---|---|
| iOS (`ReminderCardView.swift`) | `.title` (`:40`) | none | `.callout`+`.secondary` (`:73–74`) | `3` (`:75`) | no |
| watch (`WatchReminderView.swift`) | `.headline` (`:190`) | none | `.caption2`+`.secondary` (`:214–215`) | none (unbounded) | yes — `ScrollView` (`:157`) |
| widget (`NextThingWidget.swift`) | `.headline` (`:206`) | `2` (`:207`) | `.caption2`+`.secondary` (`:231–232`) | `2` (`:233`) | no |

Notes are the only element using `.foregroundStyle(.secondary)` **and** a line-limit on all three surfaces. iOS is the only surface with `.title` font but no scroll container. Only the widget caps both title and notes. Only iOS applies `dynamicTypeSize` scaling (via `ContentView.swift:99`); all fonts fall back to default system text styles.

---

## Q3: Existing text-processing/formatting in `SingleThreadCore`, and any `AttributedString`/Markdown/monospaced/escaping

### Findings
- **The Core formatters all output plain `String`/`String?`/enums — none build attributed text.**
  - `ReminderNotesFormatter` — `ReminderSkip.swift:93–117`. `String?` → `String?` (trim + `t`-artifact strip, nil for empty). Tests `ReminderSkipTests.swift:147–234`.
  - `ReminderPriority` — `ReminderSkip.swift:31`. Int/`String` marker → `Level` enum (with `displayName`), bigger `marker(for:)` at `:71`, reverse `level(forMarker:)` at `:60`. Consumed by `ReminderDisplay.swift:15`, `ReminderSort.swift:47–48`.
  - `ReminderRecurrenceFormatter` — `SingleThreadCore/.../ReminderRecurrenceFormatter.swift` (`Daily`/`Every 2 days`/`Weekly`/`Monthly`/`Yearly`); formats only the **first** `EKRecurrenceRule`; nil for empty/unhandled.
  - `ReminderDisplay` — `ReminderDisplay.swift` composes the above into display fields (see Q1).
- **Adjacent (not simple formatters):** `ReminderDictationParser` (`ReminderDictationParser.swift`; SLT natural-language parse → title + dueDate + recurrence; strips phrases, collapses `\s{2,}`), `TranscriptionAccumulator.swift` (joins chunked dictation text), `ReminderSort.swift` (ordering via priority + `title.localizedCaseInsensitiveCompare`).
- **`AttributedString`, Markdown, monospaced fonts, and string escaping/sanitization: none exist.** A repo-wide grep across all `.swift`/`.md` for `AttributedString|AttributeContainer|NSAttributedString|Markdown|monospaced|mono|addingPercentEncoding|removingPercentEncoding|escaped|html|sanitiz` returned **no genuine hits** — every match was the Swift `@escaping` closure keyword (e.g. `SingleThread/ReminderDictation.swift:15,59`, `EventKitStoring.swift:24`, `SingleThreadWidget/NextThingWidget.swift:40,51`), not string escaping.
- No Markdown parsing, no `monospaced` font, no percent-encoding/HTML/sanitization helpers anywhere in the sources.

---

## Q4: How title/notes rendering is asserted in `SingleThreadTests`

### Findings
- **Snapshot approach (three suites).** `ShowDateTests.swift`, `ShowRecurrenceTests.swift`, `ShowAlarmsTests.swift` render `ReminderCardView.body` and capture it with `String(describing:)` — but **none asserts the rendered title or notes text**. They assert structural markers as proxies:
  - `ShowDateTests.swift:12–15` — `!description.contains("FormatStyleStorage")`; comment `:14` explicitly: "Title/notes are LocalizedTextStorage." `:20–21` for the date row; `:26–27`/`:32–33`/`:38–41` assert list name strings (`"Groceries"`/`"Errands"`), not title.
  - `ShowRecurrenceTests.swift:12–16`/`:21–22`/`:26–28` — assert `description.contains("Weekly")` (the recurrence summary).
  - `ShowAlarmsTests.swift:12–16`/`:21–22`/`:26–28` — assert `description.contains("NamedImageProvider")` (the `Image(systemName:)` bell). Comment `:13–15` notes symbol names never print.
  - `makeCard` helpers: `ShowDateTests.swift:46` (title `"Buy groceries"` at `:51`), `ShowRecurrenceTests.swift:33`/`:36`, `ShowAlarmsTests.swift:33`/`:35`. **None passes `notes`**, so the `if let noteText` notes branch never executes in these snapshots.
- **Formatter-only tests of `ReminderNotesFormatter` exist** — `struct ReminderNotesFormatterTests` at `ReminderSkipTests.swift:147–234`: `#expect(ReminderNotesFormatter.format(...) == ...)` cases for nil (`:150`), whitespace (`:155`), empty (`:160`), multiline keep (`:214`), `t`-artifact stripping (`:188`, `:194`, `:220`), and legit lowercase-`t` preserved (`:208`‑`209`).
- **Raw-string mapping tests** — `ReminderDisplayTests.swift`: `mapsTitle` `:10`, `formatsNotes` `:16` (sets raw `"tTwo percent"`, expects display `"Two percent"`), `mapsNilNotes` `:24`. `ReminderDictationParserTests.swift` parses raw dictation strings into title/recurrence. `ReminderStore.swift:515–544` (`MakeReminderTests`) and `EventKitStoringTests.swift:126,201` write/assert raw note strings through store seams.
- **Key gap:** no unit test asserts the rendered title text glyph string, and none renders a non-nil `notes` value through `ReminderCardView`. Title/notes rendering changes would not be caught by `ShowDateTests/ShowRecurrenceTests/ShowAlarmsTests`.

---

## Q5: UI tests + accessibility audit observation of title/notes, and constraints

### Findings
- **Launch-argument seams decide what renders** (`SingleThread/AppViewModel.swift`, `makeStore`):
  - `--seed '<json>'` → builds `{InMemoryEventStore}` from seed, `loadsReminders: true` (`:107–127`).
  - `--ui-testing` (iOS) → sets `UserDefaults "enableActionButtons"` flag, builds `InMemoryEventStore` with one reminder — `title: "Buy groceries"`, `notes: "Don't forget the milk"`, `priority: 5` (`:135–148`) — and returns `ReminderStore(loadsReminders: false, reminders: [reminder], ...)` (`:152`). Because `loadsReminders: false`, `ContentView.swift:59–62` renders `reminderList` directly.
  - `--no-reminders` → empty store (`:159`).
- **Where UI tests query the rendered title/notes** — `SingleThreadUITests/SingleThreadUITestsFlows.swift:28–40` `testListShowsSeededReminder` launches with `--seed '{"reminders":[{"title":"Buy groceries","notes":"milk"}]}'` (`:33–38`) and asserts `app.staticTexts["Buy groceries"]` (`:34`) and `app.staticTexts["milk"].waitForExistence` (`:37`). The same per-string `staticTexts[...]` pattern is used for titles across the suite (`:58,76,93,111,129,147`).
- **Accessibility surfacing of the card.** `ReminderCardView.swift:82` `.accessibilityElement(children: .combine)` merges the whole card (marker, title, all info rows, notes) into a single Speak-area element. Comment `:77–81` explains this was done so the iOS hit-region audit no longer size-checks each small child row (marker/notes fall below 44pt). Child details that are individually labeled before being merged: priority marker `.accessibilityLabel`, recurrence `Image(.accessibilityHidden(true))` (`:59`), alarm bell `.accessibilityLabel("Has alarm")` (`:67`). The card sits in a full `List` row with `.frame(minHeight:...)` (`ContentView.swift:315`) and `.padding` `:310–311`.
- **Accessibility audits.**
  - `SingleThreadUITests.swift` (`testAccessibilityAudit`): waits for `app.staticTexts.firstMatch`, then on iOS runs only `[.sufficientElementDescription, .trait]` on CI (`:47–50`); locally runs `[.dynamicType, .hitRegion, .sufficientElementDescription, .trait]` (`:51–57`); macOS runs defaults (`:61`). Contrast/textClipped deliberately omitted.
  - `SingleThreadUITests/ActionButtonsUITests.swift` `testActionButtonsAccessibilityAudit`: waits for the two action buttons, runs `[.dynamicType, .hitRegion, .sufficientElementDescription, .trait]` on iOS (`:67` gate), full-render against the card on every run.
  - Watch audit `SingleThreadUITests...`/`SingleThreadWatchUITests` uses the same four categories.
- **Constraints affected by title/notes rendering changes:** (described as current behavior, not recommendations)
  1. **VoiceOver combine** (`.combine`, `ReminderCardView.swift:82`) — removing/skipping it re-exposes each child as its own element; then the flows-test per-string `staticTexts["Buy groceries"]`/`["milk"]` queries and hit-region behavior both change.
  2. **Hit-region (44pt)** — with `.combine` the merged card passes `.hitRegion`; a separately-combined or uncombined notes/title row would be individually size-checked and could fail (notes rows are small).
  3. **lineLimit** — iOS notes `.lineLimit(3)` (`ReminderCardView.swift:75`), widget notes/title `.lineLimit(2)` (`NextThingWidget.swift:207,230`). Truncation affects rendered snippet height (matters for hit-region if combined), not the accessibility value (which is the full string).
  4. **Formatter gateway** — text surfaced is `ReminderNotesFormatter` and is `ReminderSkip.swift:93–117`; any change must preserve trimming/`t`-strip, or the seeded UI-test strings (`"milk"`, `"Buy groceries"`) and VoiceOver value drift.
  5. **Dynamic type** — `.dynamicType` audit in `ActionButtonsUITests` and local `SingleThreadUITests` scales fonts; a standalone small row could fail hit-region after scaling.
  6. **Stale comment** — `SingleThreadUITests/SingleThreadUITests.swift:23–27` says `--ui-testing` yields an "empty store / No Reminders", but `AppViewModel.swift:135–152` seeds a single card; the audit's real tree differs from its prose commentary (locally the card is present).

---

## Cross-Cutting Observations
- **One shared read-model, three thin renderers.** `ReminderDisplay` is the sole `EKReminder → UI` bridge consumed by iOS (`ContentView.swift:298`), watch (`WatchReminderView.swift:158`), widget (`NextThingWidget.swift:94`), and tests. No view reads `EKReminder` directly.
- **`Notes` are the only conditional `format`-gated field.** `title` flows through untouched (`ReminderDisplay.swift:12`, no formatter); `notes` flow through `ReminderNotesFormatter.format` (`:13`), which can return `nil`. Every consumer gates the notes `Text` on `if let`.
- **The pipeline is wholly plain-`String`.** No `AttributedString`, Markdown, or monospaced rendering exists anywhere in sources (Q3), so notes/title styling is font+color+lineLimit only.
- **Test seams are string-snapshot + UI-staticText.** Value mapping is asserted in `ReminderDisplayTests`/`ReminderNotesFormatterTests`; card presence is asserted by `String(describing:)` structural markers (not title/notes content); end-to-end is asserted by XCUI `staticTexts[...]` string queries seeded via `--seed` / `--ui-testing`.
- **Accessibility is coupled to rendering.** The whole card is one accessible element via `.combine`, so hit-region passes; per-string UI-test queries and the audit categories both depend on that single-element behavior and the exact formatter-cleaned strings.

## Open Areas
- **nil-title trap** (`ReminderDisplay.swift:12`): not exercised by any test/preview; what actual `EKReminder` can have a nil title isn't evidenced.
- **`ReminderRecurrenceFormatter`** summarizes only the first recurrence rule; k multi-rule reminders under-report (not part of title/notes flow but adjacent).
- **`--ui-testing` vs. comment mismatch** (`SingleThreadUITests.swift:23–27` vs `AppViewModel.swift:135–148`): not resolved here—both are features; the doc-based note is recorded as state, not judged.
- **Watch/widget rendered output** was inferred from sources, not observed at runtime this session.
# Design Discussion — Show Code Blocks (VAR-698)

## Current State

Today, a reminder’s `title` and `notes` flow as plain `String` from `EKReminder`
through a single bridge struct (`ReminderDisplay`) to `Text` views on three
surfaces: iOS (`ReminderCardView.swift:39,72`), watch
(`WatchReminderView.swift:189,214`), and widget (`NextThingWidget.swift:205,231`).

- **No `AttributedString`, Markdown parsing, or `monospaced` fonts exist
  anywhere in the codebase** (`research.md` Q3). The pipeline is exclusively
  plain-`String` + font/color/lineLimit modifiers.
- **`ReminderDisplay`** (`ReminderDisplay.swift:9–48`) is the sole `EKReminder →
  UI` read-model for all surfaces. `title` is stored as non-optional `String`
  (`:31`); `notes` is stored as optional `String?` (`:32`), gated through
  `ReminderNotesFormatter.format` (`:13`) which trims, strips a `"t"` artifact,
  and returns `nil` for empty (`ReminderSkip.swift:103–116`).
- **`ReminderDisplay` must remain `Codable`** — it is stored as an associated
  value in the widget’s `NextThingEntry` enum (`NextThingWidget.swift:14`),
  which conforms to `TimelineEntry` (requires `Codable`).
- **Backtick-delimited text renders literally.** `` `code` `` and ```` ```fenced``` ````
  appear as raw backticks in all three surfaces, indistinguishable from
  surrounding prose.
- **Accessibility** merges the entire card into one element via
  `.accessibilityElement(children: .combine)` (`ReminderCardView.swift:82`),
  so VoiceOver reads the whole card as a single unit. UI tests query per-string
  `staticTexts["Buy groceries"]` / `staticTexts["milk"]` (`SingleThreadUITestsFlows.swift:34,37`).
- **Test coverage gap**: no unit test renders a non-nil `notes` through
  `ReminderCardView`, and the `String(describing:)` snapshot tests
  (`ShowDateTests.swift`, etc.) only assert structural markers — not rendered
  title/notes text. `ReminderNotesFormatterTests` (`ReminderSkipTests.swift:147–234`)
  tests the formatter in isolation; `ReminderDisplayTests` (`ReminderDisplayTests.swift`)
  tests value mapping but not rendering.

## Desired End State

`Reminder.title` and `Reminder.notes` containing backtick-delimited code are
rendered with distinct, readable code styling:

- **Inline** `` `code` `` → monospaced font + subtle rounded background, backticks
  stripped from visible text
- **Fenced blocks** ```` ```code``` ```` → monospaced font + subtle rounded
  background spanning the full block, backtick fences stripped from visible
  text

This applies on **all three surfaces** (iOS, watch, widget) and to **both title
and notes**. Parsing is centralized in `SingleThreadCore`. The widget timeline
remains `Codable`-compatible.

### Validation

- **Unit tests**: `CodeSpanFormatterTests` (new) — parse empty, inline, fenced,
  unmatched backticks, multiple spans per string, code-only strings, backtick
  at boundaries
- **Unit tests**: `ReminderDisplayTests` — extend to verify
  `titleAttributed`/`notesAttributed` for titles/notes containing backtick
  sequences
- **UI tests**: existing `staticTexts["Buy groceries"]` / `staticTexts["milk"]`
  queries must still pass (seeded data has no backticks); add a seeded
  backtick-bearing reminder and assert the visible text excludes backtick fences
- **Accessibility audit**: `.dynamicType`, `.hitRegion`,
  `.sufficientElementDescription`, `.trait` categories must still pass
- **Manual verification**: verify a real `EKReminder` with code blocks renders
  correctly on all three surfaces

## Patterns to Follow

1. **Static `format` on an enum** — `ReminderNotesFormatter` (`ReminderSkip.swift:93–117`)
   is a caseless enum with a single `static func format(_:) -> String?`. The new
   `CodeSpanFormatter` should follow this pattern: enum + `static func
   format(_:) -> AttributedString`.

2. **Single read-model for all surfaces** — `ReminderDisplay` is the sole bridge
   from `EKReminder` to UI (`ReminderDisplay.swift:9`), consumed by iOS
   (`ContentView.swift:298`), watch (`WatchReminderView.swift:158`), widget
   (`NextThingWidget.swift:94`), and tests. Any new display fields must live here
   or be derived from existing fields here.

3. **Optional-notes gating** — Every surface gates notes rendering on `if let`
   (`ReminderCardView.swift:71`, `WatchReminderView.swift:213`,
   `NextThingWidget.swift:230`). The attributed-notes computed property should
   return `nil` when raw notes is `nil`, preserving this gate.

4. **Test isolation** — Formatter tests live alongside the formatter
   (`ReminderSkipTests.swift:147–234` tests `ReminderNotesFormatter`; new
   `CodeSpanFormatterTests` should live in `SingleThreadTests` next to the
   existing formatter tests). Display-mapping tests live in
   `ReminderDisplayTests.swift`.

5. **`.accessibilityElement(children: .combine)`** — `ReminderCardView.swift:82`
   keeps the card as a single VoiceOver element. Code spans contribute their
   plain text content (backticks stripped) to the combined label.

### Patterns to Avoid

- **No per-surface parsing** — Don't duplicate backtick parsing in each view.
  Parse once in `SingleThreadCore`; views just display the result.
- **No `NSAttributedString`** — The codebase is `AttributedString`-native
  (SwiftUI era). Use `AttributedString`, not `NSAttributedString`.

## Design Decisions

1. **Parse in a new `CodeSpanFormatter` enum in `SingleThreadCore`, output
   `AttributedString`** — Follows the `ReminderNotesFormatter` pattern
   (`ReminderSkip.swift:93`). The formatter takes a plain `String` and returns
   `AttributedString` with `.font` (monospaced) and `.backgroundColor` (subtle
   secondary system background) attributes on code spans. All three surfaces
   pass the result directly to `Text`.

2. **`ReminderDisplay` stores raw `String`/`String?`; exposes computed
   `AttributedString` properties** — Raw fields (`title`, `notes`) stay as-is
   for `Codable` compatibility with the widget timeline. New computed
   properties `titleAttributed: AttributedString` and `notesAttributed:
   AttributedString?` call `CodeSpanFormatter.format` on the raw values. The
   widget uses the attributed properties at render time just like iOS/watch;
   timeline serialization only touches the raw `String` fields. No Codable
   changes needed.

3. **Simple backtick parsing: single-backtick inline, triple-backtick fenced**
   — `` `code` `` parses as inline code; ```` ```code``` ```` parses as a fenced
   block. No variable-length fences, no escaping, no tilde fences, no nesting.
   Unmatched backticks (odd number, mismatched delimiters) render as literal
   text. This is predictable, testable, and covers the common use case.

4. **Monospaced font + subtle background on all code spans** — Both inline and
   fenced code get `.font(.system(.body, design: .monospaced))` (scaled
   relative to the surrounding text style per surface) and a rounded background
   using a platform-adaptive secondary system background color. This provides
   the distinct, readable styling the task calls for. Inline and fenced use the
   same styling; fenced blocks additionally span the full content width.

5. **Backticks stripped from visible text** — Parsed code spans contribute only
   their content to the `AttributedString`; backtick fences are removed. This
   matches standard Markdown rendering behavior and keeps the displayed text
   clean. VoiceOver reads the code content without backtick artifacts.

6. **Both title and notes get code formatting** — The formatter runs on `title`
   (`non-optional String`) and `notes` (`String?`). A code-styled title renders
   with monospaced spans inside the existing `.title`/`.headline` font context.
   Fenced blocks in a single-line title are valid input (they render as styled
   inline text since no line break exists to separate the fence from the title
   flow).

7. **No special accessibility treatment for code spans** — Code spans
   contribute plain text (backticks stripped) to the combined
   `.accessibilityElement(children: .combine)` label. No
   `.accessibilityTextContentType(.sourceCode)`, no "Code:" prefix. This
   preserves the existing hit-region behavior and avoids splitting the combined
   element. VoiceOver users hear the code content naturally in context.

8. **Formatter runs after `ReminderNotesFormatter`** — The notes pipeline is
   `EKReminder.notes` → `ReminderNotesFormatter.format` → `String?` →
   `CodeSpanFormatter.format` → `AttributedString?`. The code-span formatter
   operates on the already-trimmed, `t`-artifact-stripped output. Titles go
   directly: `EKReminder.title` → `String` → `CodeSpanFormatter.format` →
   `AttributedString`.

## What We're NOT Doing

- **NOT supporting GFM variable-length fences** (`` `` code with ` inside `` ``)
  or tilde-fenced blocks (`~~~`). Simple backtick-only parsing.
- **NOT adding syntax highlighting.** Monospaced + background only.
- **NOT changing `ReminderNotesFormatter` behavior.** The `t`-artifact strip
  and trim logic is untouched.
- **NOT introducing `AttributedString` stored fields on `ReminderDisplay`.**
  Raw `String` fields remain; attributed are computed-only.
- **NOT changing accessibility structure.** `.accessibilityElement(children:
  .combine)` stays. No new accessible sub-elements for code spans.
- **NOT adding code-styling to `ReminderDictationParser` or dictation flow.**
  Code styling is display-only; the raw reminder text stored in EventKit is
  unchanged.

## Open Risks

- **Cross-platform background color**: `Color(.secondarySystemBackground)` may
  not resolve identically on watchOS 26.5. Fallback: use a fixed hex color with
  dark/light variants if `secondarySystemBackground` is unavailable on watch.
- **Dynamic Type + background padding**: Code span backgrounds add intrinsic
  height. At largest dynamic type sizes, combined with the iOS
  `TextSizeModifier` (`ContentView.swift:99`), a notes row could push past the
  `.lineLimit(3)` boundary in unexpected ways — background-attributed text may
  truncate differently than plain text. Verify with `.dynamicType` audit.
- **Widget truncation**: Widget notes are `.lineLimit(2)`
  (`NextThingWidget.swift:233`). Code spans with background padding consume
  more horizontal space, potentially worsening truncation. The widget view may
  need a `.minScaleFactor` or `scaledToFit` adjustment if this proves
  problematic.
- **nil-title trap**: `ReminderDisplay.swift:12` assigns the implicitly-unwrapped
  `EKReminder.title` directly to a non-optional `String`. A nil title would
  trap. While unexercised today, the new formatter code path for
  `titleAttributed` should guard against this (and a nil title will trap before
  reaching the formatter anyway — existing behavior, not a regression).
- **Unmatched-backtick edge cases**: A reminder note containing ```` ``` ```` with
  no closing fence renders the rest of the note as "code" until end-of-string.
  This is acceptable per the simple parsing rules but may surprise users who
  expect GFM-style recovery.
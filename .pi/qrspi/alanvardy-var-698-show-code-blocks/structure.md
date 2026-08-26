# Structure Outline — Show Code Blocks (VAR-698)

## Approach

Add a centralized `CodeSpanFormatter` in `SingleThreadCore` that parses
backtick-delimited text into `AttributedString` with monospaced font + subtle
background, expose computed `titleAttributed`/`notesAttributed` on
`ReminderDisplay`, and update all three rendering surfaces (iOS, watch, widget)
to use them. Backtick fences are stripped from visible text and VoiceOver.
Raw `String` fields and `Codable` conformance are untouched.

---

## Phase 1: Core formatter + display model

**Delivers**: `CodeSpanFormatter` that parses `` `inline` `` and ```` ```fenced``` ````
into `AttributedString`, plus computed `AttributedString` properties on
`ReminderDisplay` — all testable in isolation with no UI changes.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/CodeSpanFormatter.swift` — new
- `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift` — add two computed properties
- `SingleThreadTests/CodeSpanFormatterTests.swift` — new
- `SingleThreadTests/ReminderDisplayTests.swift` — extend

**Key changes**:

```swift
// CodeSpanFormatter.swift (new)
public enum CodeSpanFormatter {
    /// Returns `AttributedString` with monospaced font + subtle background
    /// on backtick-delimited spans; backtick fences are stripped.
    /// Unmatched backticks render as literal text.
    public static func format(_ text: String) -> AttributedString
}

// ReminderDisplay.swift — add computed properties
extension ReminderDisplay {
    public var titleAttributed: AttributedString {
        CodeSpanFormatter.format(title)
    }

    /// nil when raw notes is nil, preserving existing `if let` gates.
    /// Runs CodeSpanFormatter after ReminderNotesFormatter (already applied in init).
    public var notesAttributed: AttributedString? {
        guard let notes else { return nil }
        return CodeSpanFormatter.format(notes)
    }
}
```

**Unit tests — `CodeSpanFormatterTests`** (new file, follows `ReminderNotesFormatterTests` pattern):
- Empty string → single empty AttributedString run
- No backticks → returns plain AttributedString (no code attributes)
- Single inline `` `code` `` → monospaced + background run, backticks stripped
- Triple-fenced ```` ```block``` ```` → same styling, fences stripped
- Multiple spans in one string → adjacent plain + code + plain runs
- Unmatched single backtick → renders as literal text
- Unmatched triple-fence (no closer) → rest of string rendered as code (by design)
- Code-only string (no surrounding text) → single code run
- Backtick at start/end boundaries
- Nested inline-in-fenced behavior (by design: inner backticks inside a fenced block are treated literally; no nesting recursion)

**Unit tests — `ReminderDisplayTests`** extend:
- `titleAttributed` for plain title → plain AttributedString, same visible text
- `titleAttributed` for title with `` `code` `` → AttributedString with backticks stripped
- `notesAttributed` for nil notes → nil
- `notesAttributed` for backtick-bearing notes → AttributedString with backticks stripped

**Verify**:
```fish
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests/CodeSpanFormatterTests \
  -only-testing:SingleThreadTests/ReminderDisplayTests
```
All new + existing tests pass. Existing `ReminderNotesFormatterTests` unchanged.

---

## Phase 2: iOS card view

**Delivers**: `ReminderCardView` renders code spans in both title and notes
with monospaced styling. Existing UI tests with seeded plain-text reminders
still pass. New UI test with a backtick-bearing seed verifies visible text
has no backtick fences.

**Files**:
- `SingleThread/ReminderCardView.swift` — title and notes `Text` lines
- `SingleThreadUITests/SingleThreadUITestsFlows.swift` — new test method

**Key changes**:

```swift
// ReminderCardView.swift
// Line ~39:  Text(display.title)               → Text(display.titleAttributed)
// Lines ~71-75: if let noteText = display.notes → if let notesAttr = display.notesAttributed
//               Text(noteText)                   → Text(notesAttr)
// Remaining modifiers (.font(.*), .foregroundStyle(.secondary), .lineLimit(3)) removed
// because styling is now in the AttributedString.
```

Note: removing existing `.font()` and `.foregroundStyle()` overrides from
the `Text` lines for title and notes — the `AttributedString` carries its
own styling, and the non-code portions embed the surface-appropriate font via
the formatter (which uses `.body`-relative monospaced for code, leaving plain
text as-is). Title and notes already have their surface-appropriate fonts
applied at the `Text` level; plain-text runs in the `AttributedString` carry
no font attribute, so the view-level modifiers still apply to the plain-text
runs.

Correction: the existing `.font(.title)` on `Text(display.title)` and
`.font(.callout)` + `.foregroundStyle(.secondary)` + `.lineLimit(3)` on
`Text(noteText)` stay as-is for the plain-text runs. Only code-span runs get
`.font(.system(.body, design: .monospaced))` scoped relative to the
containing text style.

**UI test** (new, in `SingleThreadUITestsFlows`):
```swift
func testCodeBlocksRenderWithoutBacktickFences() {
    let seed = #"{"reminders":[{"title":"Use `map`","notes":"```\nlet x = 1\n```"}]}"#
    let app = launchApp(seedJSON: seed)
    // Visible text has backtick fences stripped
    XCTAssertTrue(app.staticTexts["Use map"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["let x = 1"].waitForExistence(timeout: 2))
    // Backtick fences themselves NOT present
    XCTAssertFalse(app.staticTexts["`map`"].exists)
}
```

**Verify**:
```fish
# Unit tests still pass (Phase 1)
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests

# UI flows — existing seeded tests + new code-block test
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadUITests/SingleThreadUITestsFlows

# Accessibility audit still passes
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadUITests/SingleThreadUITests/testAccessibilityAudit
```

Manual: build to iPhone 17 simulator; verify a real `EKReminder` with
`` `code` `` in title and ```` ```fenced``` ```` in notes renders styled.

---

## Phase 3: Watch app

**Delivers**: `WatchReminderView` renders code spans identically. No new UI
tests (watch UI tests use `--ui-testing` seam which doesn't seed multi-line
notes easily), but manual verification covers it.

**Files**:
- `SingleThreadWatch/WatchReminderView.swift` — title and notes `Text` lines

**Key changes**:

```swift
// WatchReminderView.swift
// Line ~189: Text(display.title)    → Text(display.titleAttributed)
// Line ~213: if let noteText = display.notes → if let notesAttr = display.notesAttributed
//            Text(noteText)                    → Text(notesAttr)
```

Same modifier-preservation logic as Phase 2: `.font(.headline)` on title,
`.font(.caption2)` + `.foregroundStyle(.secondary)` on notes stay for
plain-text runs. Watch uses `ScrollView` so no truncation concerns.

**Open risk addressed here**: If `Color(.secondarySystemBackground)` doesn't
resolve on watchOS 26.5, fall back to a fixed hex with dark/light variants.
Validation in this phase confirms the fallback works or isn't needed.

**Verify**:
```fish
# Build watch target
xcodebuild -scheme SingleThread \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
  build
```
Manual: run on watch simulator with a real `EKReminder` containing code spans.

---

## Phase 4: Widget

**Delivers**: `NextThingWidget` renders code spans. Truncation concern from
the design's open risks is validated here — code-span backgrounds consume
extra horizontal space with `.lineLimit(2)`.

**Files**:
- `SingleThreadWidget/NextThingWidget.swift` — title and notes `Text` lines

**Key changes**:

```swift
// NextThingWidget.swift
// Line ~205: Text(display.title)     → Text(display.titleAttributed)
// Line ~230: if let notes = display.notes → if let notesAttr = display.notesAttributed
//            Text(notes)                     → Text(notesAttr)
```

Same modifier-preservation: `.font(.headline)` + `.lineLimit(2)` on title,
`.font(.caption2)` + `.foregroundStyle(.secondary)` + `.lineLimit(2)` on
notes. If truncation becomes severe (code spans are wider due to monospaced
font + background padding), add `.minimumScaleFactor(0.8)` as a mitigation —
tested at this phase since only the widget has tight line-limit constraints.

**Verify**:
```fish
# Build widget target
xcodebuild -scheme SingleThreadWidget \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```
Manual: run widget in simulator with a reminder containing
`` `var x = "long identifier string"` `` in notes; verify it doesn't push
critical content past the 2-line limit.

---

## Testing Checkpoints

| After | What must be true |
|---|---|
| Phase 1 | `CodeSpanFormatterTests` all pass; `ReminderDisplayTests` new cases pass; all existing tests still pass. No visual changes yet — the app renders identically (attributed properties exist but nothing consumes them). |
| Phase 2 | iOS card shows styled code spans; `SingleThreadUITestsFlows` existing + new tests pass; accessibility audit passes. Watch and widget still render unchanged. |
| Phase 3 | Watch renders styled code spans. `make build` passes for all targets. |
| Phase 4 | Widget renders styled code spans; truncation validated (mitigation applied if needed). Full `./scripts/test.sh` passes. |
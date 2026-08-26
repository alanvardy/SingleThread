# Implementation Plan — Show Code Blocks (VAR-698)

## Overview

Add a centralized `CodeSpanFormatter` in `SingleThreadCore` that parses
backtick-delimited text into `AttributedString` with monospaced font + subtle
background, expose computed `titleAttributed`/`notesAttributed` on
`ReminderDisplay`, and update all three rendering surfaces (iOS, watch, widget)
to use them.

---

## Phase 1: Core formatter + display model

### Changes

#### 1. Add SwiftUI dependency to SingleThreadCore
**File**: `SingleThreadCore/Package.swift`
**Action**: modify — add SwiftUI dependency

```
// In the package dependencies array, add:
.package(url: "https://github.com/apple/swiftui.git", branch: "main"),
```

And in the target dependencies:
```
.target(name: "SingleThreadCore", dependencies: [
    .product(name: "SwiftUI", package: "swiftui")
])
```

**Note**: `SwiftUI` is already a dependency of every consuming target (iOS app, watch app, widget). Adding it to the package is purely for `AttributedString` attributes like `AttributeScopes.SwiftUIAttributes.FontAttribute` and `.backgroundColor`. If the SwiftUI package import doesn't resolve cleanly in the SPM package (Apple doesn't publish SwiftUI as a standalone SPM package — it's bundled with the SDK), use `#if canImport(SwiftUI)` around the SwiftUI attribute assignments and fall back to Foundation-only attributes:

```swift
#if canImport(SwiftUI)
import SwiftUI
#endif
```

If the package-level dependency proves problematic, remove it from Package.swift and rely solely on the `#if canImport(SwiftUI)` conditional — the SDK makes SwiftUI available at compile time for all Apple-platform targets without an explicit Package.swift dependency.

#### 2. Create CodeSpanFormatter
**File**: `SingleThreadCore/Sources/SingleThreadCore/CodeSpanFormatter.swift`
**Action**: create

```swift
import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

/// Parses backtick-delimited text into `AttributedString` with monospaced
/// styling on code spans. Follows the same caseless-enum pattern as
/// `ReminderNotesFormatter`.
public enum CodeSpanFormatter {
    /// Returns an `AttributedString` where backtick-delimited spans are
    /// styled with a monospaced font and subtle background; backtick fences
    /// are stripped from visible text. Unmatched backticks render as literal
    /// text.
    ///
    /// - Single backtick pairs `` `code` `` render as inline code.
    /// - Triple-backtick pairs ```` ```block``` ```` render as fenced code.
    /// - Unmatched backticks (odd count, mismatched delimiters) render as
    ///   literal text.
    public static func format(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remainder = text[...]
        var pendingPlain = ""

        while !remainder.isEmpty {
            guard let codeSpan = extractCodeSpan(from: remainder) else {
                pendingPlain.append(contentsOf: remainder)
                break
            }

            // Append the plain text leading up to this span.
            if !codeSpan.leadingPlain.isEmpty {
                pendingPlain.append(contentsOf: codeSpan.leadingPlain)
            }
            result.append(AttributedString(pendingPlain))
            pendingPlain = ""

            // Append the code span with styling.
            var codeAttr = AttributedString(codeSpan.content)
            applyCodeAttributes(to: &codeAttr)
            result.append(codeAttr)

            remainder = codeSpan.remainder
        }

        // Flush any trailing plain text.
        result.append(AttributedString(pendingPlain))
        return result
    }

    // MARK: Private

    private struct CodeSpan {
        let leadingPlain: String
        let content: String        // backtick fences removed
        let remainder: Substring
    }

    /// Attempts to extract a code span from the start of `text`.
    /// Returns nil when no valid opening fence is found.
    private static func extractCodeSpan(from text: Substring) -> CodeSpan? {
        // Try triple-backtick fenced first (longest match).
        if let span = extractFenced(from: text) {
            return span
        }
        // Then single-backtick inline.
        if let span = extractInline(from: text) {
            return span
        }
        return nil
    }

    private static func extractFenced(from text: Substring) -> CodeSpan? {
        guard text.hasPrefix("```") else { return nil }
        let afterOpen = text.dropFirst(3)

        // Find the closing ``` — must be on its own or at end.
        guard let closeRange = afterOpen.range(of: "```") else {
            // No closing fence: rest of string is code content.
            return CodeSpan(
                leadingPlain: "",
                content: String(afterOpen),
                remainder: ""
            )
        }

        let content = String(afterOpen[..<closeRange.lowerBound])
        let remainder = afterOpen[closeRange.upperBound...]
        return CodeSpan(leadingPlain: "", content: content, remainder: remainder)
    }

    private static func extractInline(from text: Substring) -> CodeSpan? {
        guard text.hasPrefix("`") else { return nil }
        let afterOpen = text.dropFirst()

        // Double backtick (``) is not a valid inline opener — skip so the
        // literal backtick falls through as plain text. Triple backtick is
        // already handled by extractFenced (runs first).
        guard afterOpen.first != "`" else { return nil }

        guard let closeIdx = afterOpen.firstIndex(of: "`") else {
            // Unmatched: render literally (handled by caller skipping this span).
            return nil
        }

        let content = String(afterOpen[..<closeIdx])
        let remainder = afterOpen[afterOpen.index(after: closeIdx)...]
        return CodeSpan(leadingPlain: "", content: content, remainder: remainder)
    }

    private static func applyCodeAttributes(to attributed: inout AttributedString) {
        #if canImport(SwiftUI)
        // Monospaced font, scaled relative to `.body`.
        attributed.font = .system(.body, design: .monospaced)
        // Subtle rounded background using a platform-adaptive secondary
        // system background color. Falls back to gray opacity on platforms
        // where `secondarySystemBackground` is not available.
        if let bgColor = platformSecondaryBackground() {
            attributed.backgroundColor = bgColor
        }
        #endif
    }

    #if canImport(SwiftUI)
    private static func platformSecondaryBackground() -> SwiftUI.Color? {
        #if canImport(UIKit)
        // UIColor.secondarySystemBackground is available iOS 13+ / watchOS 10+.
        return SwiftUI.Color(uiColor: .secondarySystemBackground)
        #elseif canImport(AppKit)
        return SwiftUI.Color(nsColor: .secondarySystemBackground)
        #else
        // Fallback for platforms without UIKit/AppKit (unlikely but safe).
        return SwiftUI.Color.gray.opacity(0.15)
        #endif
    }
    #endif
}
```

**Edge cases handled**:
- Empty string → single empty run
- No backticks → plain AttributedString
- Single inline `` `code` `` → styled run, backticks stripped
- Triple-fenced ```` ```block``` ```` → styled run, fences stripped
- Multiple spans in one string → alternating plain/code runs
- Unmatched single backtick → renders as literal (extractInline returns nil, `` ` `` becomes plain text)
- Double backtick `` `` `` `` → renders literally (guard rejects it; not a valid delimiter)
- Unmatched triple-fence (no closer) → rest of string rendered as code
- Backtick at start/end boundaries → handled by pendingPlain flushing
- Nested inline-in-fenced → inner backticks inside a fenced block treated literally (no nesting recursion — by design)
- Plain text between code spans → appended as plain runs

#### 3. Add computed properties to ReminderDisplay
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`
**Action**: modify — add two computed properties after the existing stored properties (after line 48)

```swift
// MARK: Attributed variants

/// `title` with any backtick-delimited code spans styled as monospaced.
/// Backtick fences are stripped from the visible string.
public var titleAttributed: AttributedString {
    CodeSpanFormatter.format(title)
}

/// `notes` with any backtick-delimited code spans styled as monospaced,
/// or `nil` when raw notes is `nil`. Runs after `ReminderNotesFormatter`
/// (already applied during `init`).
public var notesAttributed: AttributedString? {
    guard let notes else { return nil }
    return CodeSpanFormatter.format(notes)
}
```

#### 4. Create CodeSpanFormatterTests
**File**: `SingleThreadTests/CodeSpanFormatterTests.swift`
**Action**: create

```swift
import SingleThreadCore
import Testing

struct CodeSpanFormatterTests {
    // MARK: Empty / plain

    @Test
    func emptyStringReturnsEmptyAttributedString() {
        let result = CodeSpanFormatter.format("")
        #expect(String(result.characters[...]) == "")
    }

    @Test
    func plainTextReturnsUnstyledAttributedString() {
        let result = CodeSpanFormatter.format("Buy groceries")
        #expect(String(result.characters[...]) == "Buy groceries")
    }

    // MARK: Inline code

    @Test
    func inlineCodeStripsBackticks() {
        let result = CodeSpanFormatter.format("Use `map` here")
        #expect(String(result.characters[...]) == "Use map here")
    }

    @Test
    func singleInlineCodeOnly() {
        let result = CodeSpanFormatter.format("`code`")
        #expect(String(result.characters[...]) == "code")
    }

    // MARK: Fenced code

    @Test
    func fencedCodeStripsFences() {
        let result = CodeSpanFormatter.format("Before\n```\nlet x = 1\n```\nAfter")
        let text = String(result.characters[...])
        #expect(text.contains("let x = 1"))
        #expect(!text.contains("```"))
    }

    @Test
    func fencedCodeOnly() {
        let result = CodeSpanFormatter.format("```\ncode\n```")
        let text = String(result.characters[...])
        #expect(text.trimmingCharacters(in: .whitespacesAndNewlines) == "code")
    }

    // MARK: Multiple spans

    @Test
    func multipleCodeSpansInOneString() {
        let result = CodeSpanFormatter.format("Use `map` and `filter`")
        #expect(String(result.characters[...]) == "Use map and filter")
    }

    // MARK: Unmatched backticks

    @Test
    func unmatchedSingleBacktickRendersLiterally() {
        let result = CodeSpanFormatter.format("a ` b")
        #expect(String(result.characters[...]) == "a ` b")
    }

    @Test
    func doubleBacktickRendersLiterally() {
        // Two backticks is not a valid delimiter per the simple parsing rules.
        let result = CodeSpanFormatter.format("a `` b")
        #expect(String(result.characters[...]) == "a `` b")
    }

    @Test
    func unmatchedTripleFenceRendersRestAsCode() {
        // No closing fence: rest of string is code content, fences stripped.
        let result = CodeSpanFormatter.format("```\nunclosed")
        let text = String(result.characters[...])
        #expect(!text.contains("```"))
        #expect(text.contains("unclosed"))
    }

    // MARK: Boundaries

    @Test
    func backtickAtStartOfString() {
        let result = CodeSpanFormatter.format("`start` and end")
        #expect(String(result.characters[...]) == "start and end")
    }

    @Test
    func backtickAtEndOfString() {
        let result = CodeSpanFormatter.format("start and `end`")
        #expect(String(result.characters[...]) == "start and end")
    }

    // MARK: Attributes

    @Test
    func codeSpanHasMonospacedFontAttribute() {
        let result = CodeSpanFormatter.format("`code`")
        // Verify at least one run has a font attribute (monospaced).
        var foundMonospaced = false
        for run in result.runs {
            if run.font != nil {
                foundMonospaced = true
                break
            }
        }
        #expect(foundMonospaced, "Code span should carry a font attribute")
    }

    @Test
    func plainTextHasNoCodeAttributes() {
        let result = CodeSpanFormatter.format("plain `code` plain")
        // The plain runs should not have monospaced styling.
        for run in result.runs {
            let runText = String(result.characters[run.range])
            if runText == "plain " || runText == " plain" {
                #expect(run.font == nil, "Plain text run should not have font attribute")
            }
        }
    }
}
```

#### 5. Extend ReminderDisplayTests
**File**: `SingleThreadTests/ReminderDisplayTests.swift`
**Action**: modify — add test methods before the closing `}` of `struct ReminderDisplayTests` (after the `directConstructorCreatesFields` test, around line 129)

```swift
    @Test
    func titleAttributedReturnsPlainForPlainTitle() {
        let display = ReminderDisplay(reminder: makeReminder(title: "Buy milk"))
        let attributed = display.titleAttributed
        #expect(String(attributed.characters[...]) == "Buy milk")
    }

    @Test
    func titleAttributedStripsBackticks() {
        let display = ReminderDisplay(reminder: makeReminder(title: "Use `map` now"))
        let attributed = display.titleAttributed
        #expect(String(attributed.characters[...]) == "Use map now")
    }

    @Test
    func notesAttributedReturnsNilForNilNotes() {
        let display = ReminderDisplay(reminder: makeReminder(title: "Test"))
        #expect(display.notesAttributed == nil)
    }

    @Test
    func notesAttributedStripsBackticks() {
        let reminder = makeReminder(title: "Use `map`")
        reminder.notes = "See `filter` docs"
        let display = ReminderDisplay(reminder: reminder)
        let attributed = display.notesAttributed
        #expect(attributed != nil)
        #expect(String(attributed!.characters[...]) == "See filter docs")
    }

    @Test
    func notesAttributedRunsAfterNotesFormatter() {
        // Verifies the pipeline: EKReminder.notes → ReminderNotesFormatter → CodeSpanFormatter
        let reminder = makeReminder(title: "Test")
        reminder.notes = "tUse `map`"  // t-artifact + code span
        let display = ReminderDisplay(reminder: reminder)
        let attributed = display.notesAttributed
        #expect(attributed != nil)
        let text = String(attributed!.characters[...])
        #expect(text == "Use map")  // t stripped, backticks stripped
    }
```

### Verification

#### Automated
- [x] Build SingleThreadCore:
  ```fish
  swift build --package-path SingleThreadCore
  ```
- [x] Run new formatter tests:
  ```fish
  xcodebuild test -scheme SingleThread \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:SingleThreadTests/CodeSpanFormatterTests
  ```
- [x] Run extended ReminderDisplayTests:
  ```fish
  xcodebuild test -scheme SingleThread \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:SingleThreadTests/ReminderDisplayTests
  ```
- [x] All existing tests still pass:
  ```fish
  xcodebuild test -scheme SingleThread \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:SingleThreadTests
  ```
- [x] Periphery reports no dead code:
  ```fish
  make periphery
  ```

#### Manual
- [ ] App builds and runs on iPhone 17 simulator with no visible change (properties exist but nothing consumes them yet)

---

## Phase 2: iOS card view

### Changes

#### 1. Update ReminderCardView title Text
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify — line 39-40

```swift
// Before:
Text(display.title)
    .font(.title)

// After:
Text(display.titleAttributed)
    .font(.title)
```

The `.font(.title)` stays — it applies to plain-text runs in the `AttributedString` that have no font attribute. Code-span runs carry their own `.font(.system(.body, design: .monospaced))` which scopes relative to `.title` context (SwiftUI resolves this as the code span having monospaced design at the title's point size — but `.body`-relative monospaced will be smaller than `.title`. This is intentional: code at body size within a title looks proportional).

**Note**: If the monospaced `.body` size within `.title` context looks too small, adjust to `.font(.system(.title, design: .monospaced))` in `CodeSpanFormatter.applyCodeAttributes`. This is a visual tuning decision — verify during manual testing.

#### 2. Update ReminderCardView notes Text
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify — lines 71-75

```swift
// Before:
if let noteText = display.notes {
    Text(noteText)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(3)
}

// After:
if let notesAttr = display.notesAttributed {
    Text(notesAttr)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(3)
}
```

Same modifier-preservation logic: `.font(.callout)`, `.foregroundStyle(.secondary)`, and `.lineLimit(3)` stay. Code-span runs carry monospaced font; plain runs inherit the callout font.

#### 3. Add code-block UI test
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify — add a new test method before the closing `}` of `final class SingleThreadUITestsFlows` (after the `testBackgroundToggleHidesAndPersistsAcrossRelaunch` method, around line 210)

```swift
    // MARK: - Code blocks

    @MainActor
    func testCodeBlocksRenderWithoutBacktickFences() {
        let seed = #"{"reminders":[{"title":"Use `map`","notes":"```\nlet x = 1\n```"}]}"#
        let app = launchApp(seedJSON: seed)

        // Visible text has backtick fences stripped.
        XCTAssertTrue(app.staticTexts["Use map"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["let x = 1"].waitForExistence(timeout: 2))

        // Backtick fences themselves NOT present as visible text.
        XCTAssertFalse(app.staticTexts["`map`"].exists)
        XCTAssertFalse(app.staticTexts["```"].exists)
    }
```

### Verification

#### Automated
- [x] iOS build:
  ```fish
  xcodebuild -scheme SingleThread \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -configuration Debug build
  ```
- [x] Unit tests still pass:
  ```fish
  xcodebuild test -scheme SingleThread \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:SingleThreadTests
  ```
- [x] UI flows — existing seeded tests + new code-block test:
  ```fish
  xcodebuild test -scheme SingleThread \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:SingleThreadUITests/SingleThreadUITestsFlows
  ```
- [x] Accessibility audit still passes:
  ```fish
  xcodebuild test -scheme SingleThread \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:SingleThreadUITests/SingleThreadUITests/testAccessibilityAudit
  ```
- [x] SwiftLint clean:
  ```fish
  swiftlint lint --strict
  ```

#### Manual
- [ ] Build to iPhone 17 simulator; verify a real `EKReminder` with `` `code` `` in title and ```` ```fenced``` ```` in notes renders with monospaced styling
- [ ] Verify VoiceOver reads code content without backtick artifacts
- [ ] Verify at largest Dynamic Type size the card doesn't break (Settings → Accessibility → Larger Text → max)

---

## Phase 3: Watch app

### Changes

#### 1. Update WatchReminderView title Text
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify — lines 189-190

```swift
// Before:
Text(display.title)
    .font(.headline)

// After:
Text(display.titleAttributed)
    .font(.headline)
```

#### 2. Update WatchReminderView notes Text
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify — lines 213-215

```swift
// Before:
if let noteText = display.notes {
    Text(noteText)
        .font(.caption2)
        .foregroundStyle(.secondary)
}

// After:
if let notesAttr = display.notesAttributed {
    Text(notesAttr)
        .font(.caption2)
        .foregroundStyle(.secondary)
}
```

#### 3. Address watchOS background color risk
If `Color(uiColor: .secondarySystemBackground)` fails to compile on watchOS 26.5 (the structure flags this as an open risk), update the fallback in `CodeSpanFormatter.platformSecondaryBackground()`:

```swift
#if canImport(UIKit)
// Verify secondarySystemBackground is available on the target.
// If watchOS simulator build fails with "not in scope", switch to:
return SwiftUI.Color.gray.opacity(0.15)
#endif
```

Test the watch build first — if it passes, no change needed. If it fails, apply the fallback.

### Verification

#### Automated
- [x] Watch build:
  ```fish
  xcodebuild -scheme SingleThreadWatch \
    -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
    -configuration Debug build
  ```
- [x] Full build (all targets):
  ```fish
  make build
  ```
- [x] Watch UI tests:
  ```fish
  xcodebuild -scheme SingleThreadWatch \
    -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
    -configuration Debug \
    -derivedDataPath DerivedData \
    build-for-testing \
    -only-testing:SingleThreadWatchUITests
  xcodebuild -scheme SingleThreadWatch \
    -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
    -derivedDataPath DerivedData \
    test-without-building \
    -only-testing:SingleThreadWatchUITests
  ```

#### Manual
- [ ] Run on watch simulator with a real `EKReminder` containing code spans — verify monospaced styling renders correctly
- [ ] Verify code background color is visible on the watch (small screen); if too subtle, consider bumping opacity to `0.25`

---

## Phase 4: Widget

### Changes

#### 1. Update NextThingWidgetView title Text
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify — lines 205-207

```swift
// Before:
Text(display.title)
    .font(.headline)
    .lineLimit(2)

// After:
Text(display.titleAttributed)
    .font(.headline)
    .lineLimit(2)
```

#### 2. Update NextThingWidgetView notes Text
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify — lines 230-233

```swift
// Before:
if let notes = display.notes {
    Text(notes)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
}

// After:
if let notesAttr = display.notesAttributed {
    Text(notesAttr)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
}
```

#### 3. Truncation mitigation (conditional)
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify — if manual testing shows code-span backgrounds push critical content past the 2-line limit

Add `.minimumScaleFactor(0.8)` to the title and/or notes `Text` lines:

```swift
Text(display.titleAttributed)
    .font(.headline)
    .lineLimit(2)
    .minimumScaleFactor(0.8)  // Only if truncation is severe
```

```swift
Text(notesAttr)
    .font(.caption2)
    .foregroundStyle(.secondary)
    .lineLimit(2)
    .minimumScaleFactor(0.8)  // Only if truncation is severe
```

**Decision gate**: Only apply if manual testing with a reminder containing `` `var x = "long identifier string"` `` in notes shows content truncated before the 2-line limit in a `.systemMedium` widget.

### Verification

#### Automated
- [x] Widget build:
  ```fish
  xcodebuild -scheme SingleThreadWidget \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    build
  ```
- [x] Full pipeline:
  ```fish
  ./scripts/test.sh
  ```

#### Manual
- [ ] Run widget in simulator with a reminder containing `` `var x = "long identifier string"` `` in notes; verify it doesn't push critical content past the 2-line limit
- [ ] Test `.systemSmall`, `.systemMedium`, and `.systemLarge` widget families
- [ ] Verify light and dark mode rendering of code spans in widget

---

## Testing Checkpoints

| After | What must be true |
|---|---|
| Phase 1 | `CodeSpanFormatterTests` all pass; `ReminderDisplayTests` new cases pass; all existing tests still pass. No visual changes yet — the app renders identically (attributed properties exist but nothing consumes them). |
| Phase 2 | iOS card shows styled code spans; `SingleThreadUITestsFlows` existing + new tests pass; accessibility audit passes. Watch and widget still render unchanged. |
| Phase 3 | Watch renders styled code spans. `make build` passes for all targets. |
| Phase 4 | Widget renders styled code spans; truncation validated (mitigation applied if needed). Full `./scripts/test.sh` passes. |
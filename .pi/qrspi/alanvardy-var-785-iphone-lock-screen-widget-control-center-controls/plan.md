# Implementation Plan

## Overview

Add Lock Screen accessory families (`accessoryInline` / `accessoryRectangular` / `accessoryCircular`) and two Control Center `ControlWidgetButton` controls (Complete / Skip) to the existing `SingleThreadWidget` bundle, reusing the current intents and store/App Group write paths verbatim. The only new logic is a unit-tested `SingleThreadCore` presentation type; the widget and control surfaces are thin renderers over already-proven substrate.

Phase order (bottom-up): **Core presentation logic (tested) → accessory views → Control Center controls**.

---

## Phase 1: Core — `NextThingSummary` presentation/status type

### Changes

#### 1. New Core presentation type
**File**: `SingleThreadCore/Sources/SingleThreadCore/NextThingSummary.swift`
**Action**: create (SPM auto-discovers new files — no `Package.swift` edit needed)

```swift
import Foundation

/// Resolved "next thing" state fed to `NextThingSummary`. Mirrors the widget's
/// `NextThingEntry.State` so the mapping in `NextThingWidgetView` is mechanical.
/// Distinct from the widget type because this lives in `SingleThreadCore` and
/// must not depend on WidgetKit.
public enum NextThingState: Equatable, Sendable {
    case noAccess
    case empty(hasHidden: Bool)
    case allDone
    case reminder(ReminderDisplay)
}

/// Compact, family-agnostic strings + glyph consumed by the accessory views.
/// Pure formatting only — never reads EventKit / App Group itself.
public struct NextThingSummary: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case next, allDone, empty, noAccess
    }

    public let status: Status
    public let inlineText: String          // accessoryInline: "› Buy groceries" / "All Done" / …
    public let rectangularTitle: String
    public let rectangularDetail: String?  // due date / list / recurrence / alert, gated by show flags
    public let symbolName: String          // reminder priority glyph, else per-status glyph
}

extension NextThingSummary {
    public static func summarize(
        _ state: NextThingState,
        showsDate: Bool,
        showsList: Bool,
        showsRecurrence: Bool,
        showsAlarms: Bool
    ) -> NextThingSummary {
        switch state {
        case .noAccess:
            return NextThingSummary(
                status: .noAccess,
                inlineText: SharedStrings.remindersAccess,
                rectangularTitle: SharedStrings.remindersAccess,
                rectangularDetail: nil,
                symbolName: "lock.shield")
        case let .empty(hasHidden):
            let word = hasHidden ? SharedStrings.nothingDueRightNow : SharedStrings.noRemindersYet
            return NextThingSummary(
                status: .empty,
                inlineText: word,
                rectangularTitle: word,
                rectangularDetail: nil,
                symbolName: "checklist")
        case .allDone:
            return NextThingSummary(
                status: .allDone,
                inlineText: SharedStrings.allDone,
                rectangularTitle: SharedStrings.allDone,
                rectangularDetail: nil,
                symbolName: "checkmark.circle")
        case let .reminder(display):
            let title = String(display.titleAttributed.characters) // backtick-stripped plain title
            return NextThingSummary(
                status: .next,
                inlineText: "› \(title)",
                rectangularTitle: title,
                rectangularDetail: detail(
                    for: display,
                    showsDate: showsDate,
                    showsList: showsList,
                    showsRecurrence: showsRecurrence,
                    showsAlarms: showsAlarms),
                symbolName: symbol(for: display))
        }
    }

    // MARK: Private

    private static func detail(
        for display: ReminderDisplay,
        showsDate: Bool,
        showsList: Bool,
        showsRecurrence: Bool,
        showsAlarms: Bool
    ) -> String? {
        var parts: [String] = []
        if showsDate, let dueDate = display.dueDate {
            parts.append(detailDateFormat.format(dueDate))
        }
        if showsList, let listName = display.listName, !listName.isEmpty {
            parts.append(listName)
        }
        if showsRecurrence, display.hasRecurrence {
            parts.append(display.recurrenceSummary ?? SharedStrings.repeats)
        }
        if showsAlarms, display.hasAlarms {
            parts.append(SharedStrings.alert)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func symbol(for display: ReminderDisplay) -> String {
        switch ReminderPriority.level(forMarker: display.priorityMarker) {
        case .high: "exclamationmark.3"
        case .medium: "exclamationmark.2"
        case .low: "exclamationmark"
        case nil: "list.bullet"
        }
    }

    /// Date-only, locale-relative formatter. Date components are omitted so a
    /// reminder whose due date has no meaningful time renders without a
    /// spurious "12:00 AM". Unit tests assert gate behavior, not exact strings
    /// (formatting output is locale-dependent).
    private static let detailDateFormat = Date.FormatStyle(date: .abbreviated, time: .omitted)
}
```

Implementation notes:
- `ReminderDisplay` is already `public`, `Equatable`, `Sendable` in Core, so `NextThingState`/`NextThingSummary` derive both conformances.
- `String(display.titleAttributed.characters)` reuses `CodeSpanFormatter` to strip backtick fences from the plain title/notes without importing SwiftUI here.
- `SharedStrings` members (`remindersAccess`, `nothingDueRightNow`, `noRemindersYet`, `allDone`, `repeats`, `alert`) all live in `LocalizedString+Shared.swift` — no new localized strings introduced in this phase.
- `Date.FormatStyle` (`detailDateFormat`) is a `static let` of a `Sendable` value type, so the `Sendable` conformance of `NextThingSummary` is compiler-verified with no isolation annotation.

#### 2. Unit tests for the summary
**File**: `SingleThreadTests/NextThingSummaryTests.swift`
**Action**: create (Swift Testing, `@Test`; function names must NOT start with `test`/`testing` — SwiftFormat strips those prefixes)

```swift
import Foundation
import Testing
import SingleThreadCore

struct NextThingSummaryTests {
    // MARK: Helpers

    private func reminder(
        title: String = "Buy groceries",
        dueDate: Date? = Date(timeIntervalSince1970: 1_800_000_000),
        priorityMarker: String = "",
        listName: String? = nil,
        hasRecurrence: Bool = false,
        recurrenceSummary: String? = nil,
        hasAlarms: Bool = false
    ) -> ReminderDisplay {
        ReminderDisplay(
            title: title,
            dueDate: dueDate,
            priorityMarker: priorityMarker,
            listName: listName,
            hasRecurrence: hasRecurrence,
            recurrenceSummary: recurrenceSummary,
            hasAlarms: hasAlarms)
    }

    // MARK: Happy path

    @Test
    func reminderWithDateProducesInlinePrefixAndDetail() {
        let summary = NextThingSummary.summarize(
            .reminder(reminder()), showsDate: true, showsList: false,
            showsRecurrence: false, showsAlarms: false)
        #expect(summary.status == .next)
        #expect(summary.inlineText.hasPrefix("› "))
        #expect(summary.rectangularTitle == "Buy groceries")
        #expect(summary.rectangularDetail != nil) // due-date string present
    }

    @Test
    func reminderWithoutShowsDateOmitsDetail() {
        let summary = NextThingSummary.summarize(
            .reminder(reminder()), showsDate: false, showsList: false,
            showsRecurrence: false, showsAlarms: false)
        #expect(summary.rectangularDetail == nil)
    }

    // MARK: Sad / edge

    @Test
    func emptyWithHiddenMirrorsNothingDueWord() {
        let summary = NextThingSummary.summarize(
            .empty(hasHidden: true), showsDate: true, showsList: true,
            showsRecurrence: true, showsAlarms: true)
        #expect(summary.status == .empty)
        #expect(summary.rectangularTitle == SharedStrings.nothingDueRightNow)
        #expect(summary.symbolName == "checklist")
    }

    @Test
    func emptyWithoutHiddenMirrorsNoRemindersWord() {
        let summary = NextThingSummary.summarize(
            .empty(hasHidden: false), showsDate: true, showsList: true,
            showsRecurrence: true, showsAlarms: true)
        #expect(summary.rectangularTitle == SharedStrings.noRemindersYet)
    }

    @Test
    func allDoneProducesCheckmarkGlyph() {
        let summary = NextThingSummary.summarize(
            .allDone, showsDate: true, showsList: true,
            showsRecurrence: true, showsAlarms: true)
        #expect(summary.status == .allDone)
        #expect(summary.symbolName == "checkmark.circle")
        #expect(summary.rectangularTitle == SharedStrings.allDone)
    }

    @Test
    func noAccessProducesLockGlyph() {
        let summary = NextThingSummary.summarize(
            .noAccess, showsDate: true, showsList: true,
            showsRecurrence: true, showsAlarms: true)
        #expect(summary.status == .noAccess)
        #expect(summary.symbolName == "lock.shield")
        #expect(summary.rectangularTitle == SharedStrings.remindersAccess)
    }

    // MARK: Glyph mapping

    @Test
    func priorityMarkerMapsToExclamationSymbol() {
        let summary = NextThingSummary.summarize(
            .reminder(reminder(priorityMarker: "!!")), showsDate: false,
            showsList: false, showsRecurrence: false, showsAlarms: false)
        #expect(summary.symbolName == "exclamationmark.2")
    }

    @Test
    func noPriorityMapsToGenericGlyph() {
        let summary = NextThingSummary.summarize(
            .reminder(reminder(priorityMarker: "")), showsDate: false,
            showsList: false, showsRecurrence: false, showsAlarms: false)
        #expect(summary.symbolName == "list.bullet")
    }

    // MARK: Show-flag matrix

    @Test
    func listAndRecurrenceBitsAreGatedByShowFlags() {
        let base = reminder(listName: "Groceries", hasRecurrence: true, recurrenceSummary: "Weekly")
        let on = NextThingSummary.summarize(
            .reminder(base), showsDate: false, showsList: true,
            showsRecurrence: true, showsAlarms: false)
        #expect(on.rectangularDetail?.contains("Groceries") == true)
        #expect(on.rectangularDetail?.contains("Weekly") == true)

        let off = NextThingSummary.summarize(
            .reminder(base), showsDate: false, showsList: false,
            showsRecurrence: false, showsAlarms: false)
        #expect(off.rectangularDetail == nil)
    }

    @Test
    func alarmBitIsGatedByShowsAlarms() {
        let withAlarm = reminder(hasAlarms: true)
        let on = NextThingSummary.summarize(
            .reminder(withAlarm), showsDate: false, showsList: false,
            showsRecurrence: false, showsAlarms: true)
        #expect(on.rectangularDetail == SharedStrings.alert)
        let off = NextThingSummary.summarize(
            .reminder(withAlarm), showsDate: false, showsList: false,
            showsRecurrence: false, showsAlarms: false)
        #expect(off.rectangularDetail == nil)
    }
}
```

Notes:
- Tests assert **gate behavior and glyph/status mapping**, not locale-dependent date strings (the formatter is locale-relative; `catalogsHaveAllSixLanguages` already handles localization of the shared strings themselves).
- `SharedStrings.nothingDueRightNow` / `noRemindersYet` / `allDone` / `remindersAccess` / `repeats` / `alert` are referenced directly so the "word" behavior is pinned to the real shared catalog.

### Verification

#### Automated
- [x] Targeted: `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,id=<UDID>' -only-testing:SingleThreadTests/NextThingSummaryTests test` (get `<UDID>` from `xcrun simctl list devices available | grep 'iPhone 17'`; pin the destination — a name-only destination is ambiguous and hangs).
- [x] `make test` (runs `./scripts/test.sh --unit-only`; full iOS unit suite stays green).

#### Manual
None — this layer is UI-free.

---

## Phase 2: Lock Screen accessory families

### Changes

#### 1. Declare accessory families + family switch
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify

**`supportedFamilies`** (now line 128) — add the three accessory families:

```swift
.supportedFamilies([
    .systemSmall, .systemMedium, .systemLarge,
    .accessoryInline, .accessoryRectangular, .accessoryCircular,
])
```

**`NextThingWidgetView`** — add `@Environment(\.widgetFamily)` and gate the body. The existing `switch entry.state` body (currently lines 141–162) is preserved verbatim as a new `mainView` computed property; the body switches on family and only calls accessory views for accessory families:

```swift
struct NextThingWidgetView: View {
    @Environment(\.widgetFamily) private var family: WidgetFamily
    let entry: NextThingEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            accessoryInlineView
        case .accessoryRectangular:
            accessoryRectangularView
        case .accessoryCircular:
            accessoryCircularView
        default:
            mainView
        }
    }

    // Existing messageView/reminderView/actionButtons unchanged.

    private var mainView: some View {
        // Move the current `body` switch (case .noAccess/.empty/.allDone/.reminder) here
        // unchanged — home-screen rendering is untouched.
        switch entry.state {
        case .noAccess:
            messageView(
                title: SharedStrings.remindersAccess,
                systemImage: "lock.shield",
                message: String(
                    localized: "Open SingleThread to enable access.",
                    table: "Localizable",
                    bundle: .main))
        case let .empty(hasHidden):
            messageView(
                title: SharedStrings.noReminders,
                systemImage: "checklist",
                message: hasHidden ? SharedStrings.nothingDueRightNow : SharedStrings.noRemindersYet)
        case .allDone:
            messageView(
                title: SharedStrings.allDone,
                systemImage: "checkmark.circle",
                message: nil)
        case let .reminder(display):
            reminderView(display)
        }
    }

    // MARK: Accessory

    private var accessoryState: NextThingState {
        switch entry.state {
        case .noAccess: .noAccess
        case let .empty(hasHidden): .empty(hasHidden: hasHidden)
        case .allDone: .allDone
        case let .reminder(display): .reminder(display)
        }
    }

    private var summary: NextThingSummary {
        NextThingSummary.summarize(
            accessoryState,
            showsDate: entry.showsDate,
            showsList: entry.showsList,
            showsRecurrence: entry.showsRecurrence,
            showsAlarms: entry.showsAlarms)
    }

    private var accessoryInlineView: some View {
        Text(summary.inlineText)
            .accessibilityLabel(summary.inlineText)
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(summary.rectangularTitle, systemImage: summary.symbolName)
                .font(.headline)
            if let detail = summary.rectangularDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var accessoryCircularView: some View {
        Image(systemName: summary.symbolName)
    }
}
```

Implementation notes:
- No `containerBackground(for: .widget)` on any accessory view — that modifier already lives at the `StaticConfiguration` content closure and only meaningfully applies to the `.widget` rendering; accessories draw on host-provided backgrounds.
- Labels use SF Symbol names from the summary, so no new localized strings in this phase.
- These views are non-interactive (no buttons) — mitigates the accessibility hit-region / caption-size SwiftLint rules.

#### 2. Accessory `#Preview` timelines
**File**: `SingleThreadWidget/NextThingWidget.swift` (append to the existing `#Preview` block)
**Action**: modify

Add three previews (one per family, one per non-empty status):

```swift
#Preview("Accessory Inline — Reminder", as: .accessoryInline) {
    NextThingWidget()
} timeline: {
    NextThingEntry(
        date: Date(),
        state: .reminder(ReminderDisplay(title: "Buy groceries", dueDate: Date())),
        showsDate: true, showsList: true, showsRecurrence: true, showsAlarms: true)
}

#Preview("Accessory Rectangular — No Access", as: .accessoryRectangular) {
    NextThingWidget()
} timeline: {
    NextThingEntry(
        date: Date(),
        state: .noAccess,
        showsDate: true, showsList: true, showsRecurrence: true, showsAlarms: true)
}

#Preview("Accessory Circular — All Done", as: .accessoryCircular) {
    NextThingWidget()
} timeline: {
    NextThingEntry(
        date: Date(),
        state: .allDone,
        showsDate: true, showsList: true, showsRecurrence: true, showsAlarms: true)
}
```

### Verification

#### Automated
- [x] `make build` (build-for-testing compiles `SingleThreadWidget.appex`, exercising the family switch and all three accessory views).
- [x] `make lint` (`swiftformat --lint` + `swiftlint lint --strict`).
- [x] `make test` still green (no regression to unit suites).

#### Manual
- [ ] Open the Lock Screen gallery (long-press Lock Screen → Customize → Add Widget → SingleThread): the three accessory variants appear and each renders the next-reminder summary.
- [ ] For the `.allDone` / `.empty` / `.noAccess` positions, the accessory variants render the minimal glyph+word (checkmark "done", checklist, lock).

---

## Phase 3: Control Center Complete + Skip controls

### Changes

#### 1. `LocalizedStringResource` display-name accessors (no new localized strings)
**File**: `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`
**Action**: modify (append inside `SharedStrings`, next to the existing `completeAction`/`skipAction`)

`StaticControlConfiguration.displayName(_:)` only accepts a `LocalizedStringResource` (verified against the iOS 26.5 WidgetKit `.swiftinterface`, `ControlWidgetConfiguration.displayName`). `SharedStrings.completeAction`/`skipAction` return a plain `String`, so add resource-typed twins that resolve the **already-translated** "Complete"/"Skip" keys from Core's `.module` catalog — nothing new to translate, and no duplication into the widget's `.main` catalog:

```swift
public static var completeActionResource: LocalizedStringResource {
    LocalizedStringResource("Complete", table: "Localizable", bundle: .module)
}

public static var skipActionResource: LocalizedStringResource {
    LocalizedStringResource("Skip", table: "Localizable", bundle: .module)
}
```

(No `description` strings are added — a `.description` would be new user-visible text requiring all six language entries to satisfy `LocalizationTests.catalogsHaveAllSixLanguages`; the display name + button label are sufficient for the gallery. Omit `.description`.)

#### 2. The two `ControlWidget` structs
**File**: `SingleThreadWidget/ControlCenterControls.swift`
**Action**: create

```swift
import AppIntents
import SingleThreadCore
import SwiftUI
import WidgetKit

struct CompleteReminderControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "CompleteReminder") {
            ControlWidgetButton(action: CompleteReminderIntent()) {
                Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
            }
        }
        .displayName(SharedStrings.completeActionResource)
    }
}

struct SkipReminderControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SkipReminder") {
            ControlWidgetButton(action: SkipReminderIntent()) {
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
            }
        }
        .displayName(SharedStrings.skipActionResource)
    }
}
```

Implementation notes:
- Both `ControlWidget` structs have no stored properties, so the `@MainActor init()` requirement of the `ControlWidget` protocol is met by the synthesized memberwise `init()` — no explicit `@MainActor` annotation needed (the protocol and all `StaticControlConfiguration`/`ControlWidgetButton` types are `@MainActor`).
- `ControlWidgetButton(action:)` requires `action: AppIntent`; `CompleteReminderIntent`/`SkipReminderIntent` both conform (`ReminderIntents.swift`), so the intents are reused **verbatim** — `perform()`, `isDiscoverable = false`, and the store write paths (`completeCurrentReminder()` / `skipCurrentReminderImmediately()`) are unchanged.
- Stateless `ControlWidgetButton` per decision 1 (Q1=A): no toggle/value provider, no `ControlCenter.shared.reloadControls` wiring.
- `kind` strings ("CompleteReminder"/"SkipReminder") are new, unique identifiers — no clash with the widget's `kind = "NextThing"`.

#### 3. Register the controls in the bundle
**File**: `SingleThreadWidget/SingleThreadWidgetBundle.swift`
**Action**: modify

```swift
import SwiftUI
import WidgetKit

@main
struct SingleThreadWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextThingWidget()
        CompleteReminderControl()
        SkipReminderControl()
    }
}
```

Implementation notes:
- `WidgetBundleBuilder` gained a `buildExpression<Content: ControlWidget>(_ content: Content) -> some Widget` overload (iOS 18+, verified in `SwiftUI.swiftinterface`); it wraps each `ControlWidget` in an internal adaptor so it can sit beside `NextThingWidget()` in the same `body`. No new extension target, no `NSExtensionPointIdentifier` / Info.plist change — controls reuse `com.apple.widgetkit-extension` via the existing bundle.
- `widgetFamily` — no interaction here; controls are not widgets and do not flow through `NextThingWidgetView`.

### Verification

#### Automated
- [ ] `make build` (compiles `appex` with the two controls + the mixed bundle body — this is the cross-cutting seam that must compile).
- [ ] `make lint`.
- [ ] `make test` — `ReminderIntentsTests.completeIntentIsConfigured` and `skipIntentIsConfigured` stay green (they pin `isDiscoverable == false` and the `.main`-catalog title; both intents are unchanged).

#### Manual
- [ ] On a device (gallery surfacing is not reliable in the simulator): Control Center → Customize Controls (plus button) → SingleThread shows **Complete** and **Skip**.
- [ ] Tap **Complete** — the first visible reminder completes through `completeCurrentReminder()` (freemium cap 100, counter incremented).
- [ ] Tap **Skip** — the first visible reminder skips via the synchronous immediate write (`skipCurrentReminderImmediately()`), same path as the widget's existing Skip button.

---

## Cross-cutting notes

- The single cross-cutting seam — `WidgetBundle` hosting `Widget` + two `ControlWidget`s in one `body` — is validated at Phase 3's `make build`. If it unexpectedly fails to compile, isolate the controls within the existing appex (a second `WidgetBundle`-conforming struct is not allowed — only one `@main`; the fallback is a `WidgetBundleBuilder` restructure, not a new target). This fallback does not invalidate Phases 1–2.
- **No new localized strings** were introduced anywhere, so `LocalizationTests` and the `.xcstrings` catalogs are untouched. (Avoided deliberately to dodge the six-language translation requirement.)
- No schema/migration, no codegen, no new persisted keys, no new test target, no pbxproj edits (all new `.swift` files are auto-discovered).

## Testing checkpoints

- After Phase 1: `NextThingSummaryTests` + full `make test` green.
- After Phase 2: `make build` + `make lint` green (previews compile; gallery manual).
- After Phase 3: `make build` + `make lint` + `make test` (ReminderIntentsTests included) green.
- Before commit: full `./scripts/test.sh` (CI-identical: format, lint, build, watch build, Periphery, unit + UI + watch + macOS tests) green.

## Deviations from the structure outline

1. **`.description(_:)` omitted** on the controls. Structure showed `.displayName("…").description("…")` as placeholders; adding real description text would be *new* user-visible strings requiring all six language entries in Core's `Localizable.xcstrings` (enforced by `LocalizationTests.catalogsHaveAllSixLanguages`). The display name + button label are sufficient for the gallery, and this keeps the localization surface unchanged. Reused `SharedStrings` for the visible label (as structure's Stage-2 "otherwise reuse SharedStrings" instruction directs).
2. **`SharedStrings` gained two `LocalizedStringResource` twins** (`completeActionResource`/`skipActionResource`). Necessary because `StaticControlConfiguration.displayName` is `LocalizedStringResource`-only (verified in SDK), and building one from Core's `.module` catalog requires being inside Core. This is a minimal enabler consistent with design decision "reuse SharedStrings", and introduces no new localized keys.
3. Everything else follows structure phase order and file list exactly.
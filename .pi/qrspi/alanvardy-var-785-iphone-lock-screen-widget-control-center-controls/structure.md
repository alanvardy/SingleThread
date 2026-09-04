# Structure Outline

## Approach

Add Lock Screen accessory families and two Control Center controls to the existing `SingleThreadWidget` bundle, reusing the current intents and store/App Group write paths **verbatim** (design decisions 1–3). The only new logic is a unit-testable `SingleThreadCore` presentation type; the widget and control surfaces are thin renderers over already-proven substrate. Horizontal order, bottom-up: **Core presentation logic (tested) → accessory views → Control Center controls**.

---

## Stage 1: Core — `NextThingSummary` presentation/status type

The decision 4 type: turns the already-derived widget state into `accessoryInline` / `accessoryRectangular` / `accessoryCircular` strings + a glyph, with a flattened `next / allDone / empty / noAccess` status. Pure Swift, no widget/UI dependency — the disciplined, unit-tested foundation every layer above consumes. The widget keeps its own `NextThingEntry.State` (home-screen rendering untouched); the view maps into Core's state for accessory use.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/NextThingSummary.swift` (new; SPM auto-discovers)
- `SingleThreadTests/NextThingSummaryTests.swift` (new, Swift Testing, `@Test`; names must not start with `test`)

**Key changes**:
```swift
// Core (new)
enum NextThingState: Equatable {
    case noAccess, empty(hasHidden: Bool), allDone, reminder(ReminderDisplay)
}

struct NextThingSummary: Equatable {
    enum Status: Equatable { case next, allDone, empty, noAccess }
    let status: Status
    let inlineText: String        // accessoryInline: "› Buy groceries" / "Done" / …
    let rectangularTitle: String
    let rectangularDetail: String?  // due date / list, respects showsDate/showsList
    let symbolName: String        // reminder priority/glyph, else status glyph
}

extension NextThingSummary {
    static func summarize(_ state: NextThingState,
                          showsDate: Bool, showsList: Bool,
                          showsRecurrence: Bool, showsAlarms: Bool) -> NextThingSummary
}
```
The widget's `makeEntry` already resolves auth → visible-first-reminder → show-flags; `NextThingState` mirrors `NextThingEntry.State` (:10-15) so the mapping is mechanical. Core does formatting only — no EventKit/App-Group reads are duplicated.

**Tests** (`NextThingSummaryTests.swift`):
- happy: `.reminder` + `showsDate` → inline starts `"› "`, `rectangularDetail` = due-date string; `showsDate=false` → `nil` detail.
- sad/edge: `.empty(hasHidden: true)` vs `.empty(hasHidden: false)` (detail/word mirror the existing `nothingDueRightNow` vs `noRemindersYet`), `.allDone` → `Status.allDone` + checkmark glyph, `.noAccess` → `Status.noAccess` + lock glyph.
- glyph: reminder with priority → priority marker symbol; no priority → generic glyph.
- show-flag matrix: `showsList`/`showsRecurrence` off → those bits absent from `rectangularDetail`.
- `Status`/`symbolName` correctness across all four states (the contract Layers 2–3 code against).

**Verify**: targeted `xcodebuild -only-testing:SingleThreadTests/NextThingSummaryTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=<ver>' test` (pin `,OS=` per conventions §3), then `make test` (unit-only) stays green. No manual check — this layer is UI-free.

---

## Stage 2: Lock Screen accessory families

Extend the existing widget to the three accessory families behind a real `environment(\.widgetFamily)` switch (superseding the family-agnostic view, design "Do NOT follow"). Each accessory view is a thin renderer that calls `NextThingSummary.summarize(...)` from Stage 1. Home-screen `.systemSmall/.systemMedium/.systemLarge` rendering is untouched.

**Files**:
- `SingleThreadWidget/NextThingWidget.swift` (supportedFamilies :128; body switch :141-162; three accessory views; new `#Preview`s mirroring :257/:274/:286)
- `SingleThreadWidget/Resources/Localizable.xcstrings` + `SingleThreadTests/LocalizationTests.swift:171-236` — **only if** new widget-localized strings are introduced; otherwise reuse `SharedStrings` (`LocalizedString+Shared.swift:12-73`).

**Key changes**:
- `supportedFamilies = [.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryRectangular, .accessoryCircular]` — modified.
- `@Environment(\.widgetFamily) private var family: WidgetFamily` + `switch family` gate in `NextThingWidgetView.body` — modified.
- `private var accessoryInlineView / accessoryRectangularView / accessoryCircularView: some View` — new; each consumes the Stage 1 `NextThingSummary`. `accessoryCircular` shows `symbolName` glyph only (no text); inline = `inlineText`; rectangular = title + `rectangularDetail`. No `containerBackground(for: .widget)` on accessory families.
- `#Preview` timelines for `.accessoryInline` / `.accessoryRectangular` / `.accessoryCircular` (one per status: Reminder, No Access, All Done) — the only executable render check.

**Tests**: no widget test target exists (conventions §2) — no automated render test; coverage is Stage 1 unit tests + previews + (manual) Lock Screen gallery, stated explicitly in the PR. If new strings are added: extend `LocalizationTests.swift` key assertions so catalog validation is the automated gate.

**Verify**: `make build` (build-for-testing compiles the `SingleThreadWidget.appex`) + `make lint` (`swiftformat --lint` + `swiftlint lint --strict`). Manual: Lock Screen gallery shows the three variants; `.allDone`/`.empty`/`.noAccess` render the minimal glyph+word.

---

## Stage 3: Control Center Complete + Skip controls

Two stateless `ControlWidget`s (decision 1: `ControlWidgetButton`, no toggle/value provider/reload), wrapping the **unchanged** `CompleteReminderIntent` / `SkipReminderIntent` and registered in the existing bundle. Independent of Stages 1–2 (controls reuse intents, not the summary) but ordered last because the `WidgetBundle`-hosts-`ControlWidget` seam is the riskiest to verify (gallery needs a device).

**Files**:
- `SingleThreadWidget/SingleThreadWidgetBundle.swift` (:7-8) — register both controls alongside `NextThingWidget()`.
- `SingleThreadWidget/ControlCenterControls.swift` (new; or appended to the bundle file) — the two `ControlWidget` structs.
- `SingleThreadTests/ReminderIntentsTests.swift` — unchanged (existing config tests must keep passing).

**Key changes**:
```swift
struct CompleteReminderControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "CompleteReminder") {
            ControlWidgetButton(action: CompleteReminderIntent()) {
                Label("Complete", systemImage: "checkmark.circle.fill")
            }
        }
        .displayName("…").description("…")
    }
}
struct SkipReminderControl: ControlWidget { /* StaticControlConfiguration(kind: "SkipReminder") → SkipReminderIntent() */ }
// WidgetBundle.body: NextThingWidget(), CompleteReminderControl(), SkipReminderControl()
```
Reuses the two intents **verbatim** — no change to `perform()` (`ReminderIntents.swift:17-24,40-51`), no new extension target, no Info.plist/key/deployment change. `isDiscoverable = false` stays (controls surface via `.displayName`/`.description`, decision 1/5).

**Tests**: `ReminderIntentsTests.completeIntentIsConfigured` (:11) and `skipIntentIsConfigured` (:25) stay green (they pin `isDiscoverable == false` and `.main`-catalog title — both still true). No new intent tests (intents unchanged); no widget test target → no automated control test; gallery/tap behavior is a manual on-device check, stated in the PR.

**Verify**: `make build` + `make lint` + `make test` (ReminderIntentsTests green). Manual (on device): Control Center gallery shows Complete + Skip; tapping completes/skips the first visible reminder through the same `canMutate`/counter paths (cap 100) as the widget buttons.

---

## Cross-cutting note

`WidgetBundle` hosting `Widget` + `ControlWidget` in one `body` is the single cross-cutting seam, validated only at Stage 3 (design "Open Risks"). If a `ControlWidget` cannot sit beside `NextThingWidget()` in the same `WidgetBundle.body`, isolate it within the existing appex — no new target — which does not invalidate Stages 1–2. No other cross-cutting change exists; reload semantics are untouched (design decision 8).

## Testing Checkpoints

- After Stage 1: `NextThingSummaryTests` + full `make test` green.
- After Stage 2: `make build` + `make lint` green (previews compile; gallery manual).
- After Stage 3: `make build` + `make lint` + `make test` (ReminderIntentsTests included) green.
- Before commit: full `./scripts/test.sh` (CI-identical) green.
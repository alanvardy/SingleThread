# Structure Outline

## Approach

Fix iPad card stretch and oversized sheets by reusing the codebase's **one** existing
iPad-adaptation pattern — the viewport-relative width cap (`min(340, viewportWidth * 0.6)`,
`EmptyStateCard.swift:42-44`) — instead of introducing size-class/idiom branching. Add the
cap to the reminder card, remove its accidental full-width stretch sources, and content-size
the nudge + reschedule sheets via `.presentationSizing(.fitted)`. No persistence, store, or
sync logic changes; this is a pure SwiftUI view-modifier fix on an iOS-scoped surface.

This is a **view layer** task — there is no migration/store/service/transport stack. The
horizontal layers are: a pure pinnable helper (the only unit-testable logic) → the card view
layer → the sheet view layer → a cross-target regression gate. Each layer lands with its
tests green before the next begins.

---

## Stage 1: Pure width-cap helper (`CardWidth`)

Extract the one iPad-proportionate sizing formula into a shared, pinnable free function so a
Swift Testing unit test can pin `min(ceiling, fraction)` behavior without rendering. This is
the foundation the view layers consume; nothing above it can land until its tests are green.

**Files**: `SingleThread/CardWidth.swift` (new), `SingleThread/EmptyStateCard.swift`
(delegate), `SingleThreadTests/CardWidthTests.swift` (new)

**Key changes**:
- `enum CardWidth { static func maxContentWidth(viewportWidth: CGFloat) -> CGFloat }` — returns
  `min(340, viewportWidth * 0.6)`; new type.
- `EmptyStateCard.maxContentWidth(viewportWidth:)` — re-pointed to delegate to
  `CardWidth.maxContentWidth`, removing the now-duplicated formula (design forbids a second
  inline copy). Behavior-preserving; existing empty-state UI tests are the regression guard.

**Tests** (`CardWidthTests.swift`, Swift Testing):
- `maxContentWidthScalesBelowCeiling` — viewport `200` → `120` (happy)
- `maxContentWidthPinsAtCeiling` — viewport `1000` → `340` (above ceiling)
- `maxContentWidthHitsCeilingAtBoundary` — viewport `340 / 0.6` → `340` (exact boundary)
- `maxContentWidthIsNonNegativeAtZeroViewport` — viewport `0` → `0` (sad / degenerate proposal)

**Verify**: `make format` → `make lint` → `make test` (or
`xcodebuild -only-testing:SingleThreadTests`); Periphery stays clean by construction (the
helper is consumed by `EmptyStateCard` immediately).

---

## Stage 2: Card de-stretch + width cap (reminder card view layer)

Make the reminder card hug its content in every state — plain, nudge banner shown, swipe
prompt shown, long title — by (a) deleting the swipe prompt's `.frame(maxWidth: .infinity)`,
(b) giving the nudge banner an explicit content-hugging constraint so the `borderedProminent`
button stops expanding under the row's `.center` proposal on iPad, and (c) layering the
`CardWidth` cap *inside* the card, mirroring `EmptyStateCard.swift:31`, with centering staying
on the caller row (`ContentView.swift:433`) exactly as empty/all-done do.

**Files**: `SingleThread/ReminderCardView.swift`, `SingleThread/ContentView.swift`,
`SingleThreadUITests/SkipNudgeUITests.swift` (new iPad test)

**Key changes**:
- `ReminderCardView` — remove `.frame(maxWidth: .infinity)` on the swipe `prompt` (`:206-207`).
- `ReminderCardView` — nudge banner (`:143-159`): add `.fixedSize(horizontal: true, vertical: false)`.
- `ReminderCardView` — new stored property `var maxWidth: CGFloat`, applied as
  `.frame(maxWidth: maxWidth)` on the card content (mirror `EmptyStateCard.swift:31`).
- `ContentView` (`:415-427`) — pass the cap: `ReminderCardView(..., maxWidth: CardWidth.maxContentWidth(viewportWidth: geometry.size.width))`.

**Tests**:
- **New iPad UI test** `testNudgedCardDoesNotSpanRowOnIPad` — seed
  `--seed '{"reminders":[…],"skipCounts":{"Buy groceries":5}}'`, swipe → Skip to reach the 6th-skip
  nudge, then assert the `skipNudgeBanner` accessibility frame (`ReminderCardView.swift:156`)
  width ≤ row width − `80` (the `40`×2 inset, `ContentView.swift:429`). Written **red-first**
  against `origin/main` (proves it reproduces the report) before the fix, then green.
- Existing green, unchanged: `SkipNudgeUITests` (delete/reschedule/view-in-Reminders),
  `ActionMenuUITests`, swipe-prompt flows (`SingleThreadUITestsFlows` `:517-560`).

**Verify**: `make build`; `SIM` = pinned iPad destination (`platform=iOS Simulator,name=iPad (A16)` or `,id=<UDID>`)
for the new test; `SIM` = iPhone 17 for the existing suites. `make periphery` after the
`prompt` deletion to confirm no orphaned code.

---

## Stage 3: Content-sized sheets (sheet view layer)

Size the nudge sheet and the standalone reschedule sheet to their content so they no longer
render with large blank bands above/below on iPad. Both are short top-aligned `VStack`s inside
`NavigationStack`; the fix is a single `presentationSizing(.fitted)` modifier on each `.sheet`
attachment (iOS 17+ API; target is iOS 18.7). Built *after* Stage 2 because the sheet is
reached by tapping the (now-capable) banner and shares `RescheduleSheet`.

**Files**: `SingleThread/ContentView.swift` (`:302-303` reschedule, `:306-307` nudge)

**Key changes**:
- `.sheet(...)` attachments for `actionMenuRescheduleSheet` and `nudgeSheetContent` each gain
  `.presentationSizing(.fitted)` (new modifier; no type/signature change elsewhere).
- Documented fallback (design Decision 3, only if fitted misbehaves with the `ToolbarItem`
  cancel or the embedded `DatePicker`): swap to `.presentationDetents([.height(…)])` with a
  per-sheet value — do not start there, and no hardcoded device-conditional frames.

**Tests**:
- Existing green, run on iPad to exercise the new presentation: `SkipNudgeUITests` reschedule
  path (`:76-103`), `ActionMenuUITests` reschedule path (`:83-111`).
- Manual iPad-sim check: both sheets render content-sized with no blank bands.
- Optional (only if stable): a frame assertion on the sheet's content `VStack` — skip if it
  trips the local-only hit-region flakiness noted in `AGENTS.md`.

**Verify**: `make build`; `make ui-test` (full `SingleThreadUITests`) on the pinned iPad
destination, plus the manual content-size check.

---

## Stage 4: Full gate + cross-target regression (final checkpoint)

Prove the iOS-scoped changes don't shift shared card/centering behavior for the watch and
widget targets (which mirror the same centering pattern, `WatchReminderView.swift:368`,
`NextThingWidget.swift:161`) and that format/lint/periphery stay clean. Run **once**, by the
parent/this phase, after Stages 1–3 commit — workers should not re-run the full gate.

**Files**: none (verification only).

**Verify**: `./scripts/test.sh` (CI-identical: swiftformat → swiftlint `--strict` → iOS build
→ watch build → periphery → iOS unit → iOS UI → watch unit+UI → macOS unit). Confirm the
`SingleThreadWatchTests` / `SingleThreadWatchUItests` and any widget-runner assertions are green
unchanged.

---

## Testing Checkpoints

Resume can happen after any of these incremental gates; each must be green before advancing:

1. **After Stage 1**: `make format` && `make lint` && `make test` — `CardWidthTests` green.
2. **After Stage 2**: iPad-targeted `testNudgedCardDoesNotSpanRowOnIPad` green (was red on
   `origin/main`) + existing nudge/action-menu/swipe UI suites green on iPhone.
3. **After Stage 3**: `make ui-test` on iPad green + manual check that both sheets are
   content-sized.
4. **After Stage 4**: `./scripts/test.sh` fully green (all targets, periphery, lint).

## Explicitly Out of Scope (do not touch in any stage)

- Skip-count persistence, `SkipCountStore`, threshold logic, the 6th-skip interrupt, and the
  known watch-sync gap on that intercept — behaviorally correct for this ticket.
- The **two-hardcoded-6s** bug (`SkipCountStore.defaultThreshold = 6` vs the static
  `"Skipped 6 times"` label in `LocalizedString+Shared.swift:25-28`, with `skipCount(for:)`
  consumed only by tests). Flagged for a separate ticket; folding it in would expand a layout
  fix into persistence/UI-string work.
- The settings and purchase sheets (`ContentView.swift:294-299`) — intentionally full-height,
  not in scope.
- Any size-class / idiom branching (`horizontalSizeClass` / `.pad`) — the codebase has zero
  matches; viewport-relative math replaces it.
- No new test target, no new `.sheet` presentation — modifiers on existing views only.

## Open Risks (carried from design — verify at the named stage)

- **Fitted + NavigationStack/DatePicker** (Stage 3): least-proven; detent fallback is the
  documented escape hatch.
- **Cap value tuning** (Stage 1 → proven Stage 2): `min(340, 0.6)` is sized for empty states;
  the reminder card may warrant a different ceiling/fraction. Confirm with the iPad assertion,
  adjust the single constant in `CardWidth` if needed.
- **Long-title wrap regression** (Stage 2): the cap makes titles wrap earlier on iPad. Cap wins
  per design; revisit only if visually objectionable.
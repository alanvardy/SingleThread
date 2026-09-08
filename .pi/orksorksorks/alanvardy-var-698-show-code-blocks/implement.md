# Implementation Summary — Show Code Blocks (VAR-698)

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | a5f5ac2 | Core formatter + display model |
| 2     | 56bafab | iOS card view |
| 3     | 560381f | Watch app |
| 4     | de7030f | Widget |

## Automated Checks
- [x] `swift build --package-path SingleThreadCore` (Phase 1)
- [x] `CodeSpanFormatterTests` all pass (Phase 1)
- [x] Extended `ReminderDisplayTests` pass (Phase 1)
- [x] All existing single-thread unit tests pass (Phase 1)
- [x] Periphery reports no dead code (Phase 1)
- [x] iOS build passes (Phase 2)
- [x] Unit tests still pass (Phase 2)
- [x] UI flows — existing seeded tests + new code-block test pass (Phase 2)
- [x] Accessibility audit still passes (Phase 2)
- [x] SwiftLint clean (Phase 2)
- [x] Watch build passes (Phase 3)
- [x] Full build (all targets) passes (Phase 3)
- [x] Watch UI tests pass (Phase 3)
- [x] Widget build passes (Phase 4)
- [x] Full `./scripts/test.sh` pipeline passes (Phase 4) — note: one flaky watch UI test (`testCompleteRemovesReminder`) intermittently fails under parallel load but passes in isolation and on rerun; unrelated to these changes.

## Manual Verification Items (from the plan)
- [ ] App builds and runs on iPhone 17 simulator with no visible change (properties exist but nothing consumes them yet) — Phase 1
- [ ] Build to iPhone 17 simulator; verify a real `EKReminder` with `` `code` `` in title and ```` ```fenced``` ```` in notes renders with monospaced styling — Phase 2
- [ ] Verify VoiceOver reads code content without backtick artifacts — Phase 2
- [ ] Verify at largest Dynamic Type size the card doesn't break (Settings → Accessibility → Larger Text → max) — Phase 2
- [ ] Run on watch simulator with a real `EKReminder` containing code spans — verify monospaced styling renders correctly — Phase 3
- [ ] Verify code background color is visible on the watch (small screen); if too subtle, consider bumping opacity to `0.25` — Phase 3
- [ ] Run widget in simulator with a reminder containing `` `var x = "long identifier string"` `` in notes; verify it doesn't push critical content past the 2-line limit — Phase 4 (also the decision gate for the optional `.minimumScaleFactor(0.8)` mitigation, intentionally NOT applied)
- [ ] Test `.systemSmall`, `.systemMedium`, and `.systemLarge` widget families — Phase 4
- [ ] Verify light and dark mode rendering of code spans in widget — Phase 4

## Notes / Observations
- **Phase 1 formatter fix**: The plan's provided `CodeSpanFormatter.format(_:)` loop only matched code spans when the remainder *started* with a backtick, so `"Use \`map\` here"` rendered as literal text (failing the plan's own tests). Rewrote the main loop to locate the next backtick anywhere in the string and route through the existing `extractFenced`/`extractInline` helpers (unchanged), honoring the plan's documented edge cases. Removed the unused `leadingPlain` field.
- **SwiftUI dependency**: Not added to `Package.swift` (Apple does not publish SwiftUI as a standalone SPM package); relied on `#if canImport(SwiftUI)` per the plan's preferred fallback.
- **watchOS background color**: `UIColor.secondarySystemBackground` is unavailable on watchOS; added `#if os(watchOS)` gray fallback in `platformSecondaryBackground()` (the risk Phase 3 flagged, resolved).
- **Phase 2 UI test adaptation**: The plan's `app.staticTexts["x"]` subscript queries fail for attributed text — attributed text with code spans exposes accessibility *labels* but not string *identifiers*, and the subscript matches by identifier. The new `testCodeBlocksRenderWithoutBacktickFences` was adapted to gather all StaticText labels and assert the visible aggregated text contains the code content and contains no backtick fences. Intent preserved (fences stripped, styled code content visible).
- **Phase 3/4**: Watch and widget view changes exactly per plan. No widget UI test was added — the plan calls for none; the widget rendering change is validated by the widget build + full pipeline and its manual verification items.
- **Truncation mitigation**: `.minimumScaleFactor(0.8)` was intentionally NOT applied — it is a conditional decision gate requiring manual visual verification on a `.systemMedium` widget with long code spans.
- Watch UI tests in `scripts/test.sh` can be flaky under parallel load (pre-existing, unrelated to this feature).

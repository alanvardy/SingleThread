# Design Discussion — Skipped sizing (iPad card stretch + oversized sheets)

## Current State

**The reminder card is laid out by the row, not by the card.** The list holds exactly
one `ReminderCardView` row (`ContentView.swift:415-427`) under a modifier chain
(`ContentView.swift:428-435`): `.listRowBackground(.clear)`
(`ContentViewModel.swift:73-75`) → `.padding(.horizontal, 40)` (:429) →
`.frame(maxWidth: .infinity, alignment: .center)` (:433) → `.frame(minHeight: viewHeight)`
(:434). The plate itself is net-zero geometry — `cardPlate(restoresGeometry: true)` adds
+12 padding then undoes it (`CardPlateModifier.swift:23-30`), so the plate is a pure
background shape and **all** sizing lives in that row chain.

**Two known stretch sources sit inside the card.** The swipe prompt forces full row width
via `.frame(maxWidth: .infinity)` (`ReminderCardView.swift:206-207`). The nudge banner is
a `borderedProminent` `Button` (`ReminderCardView.swift:143-159`) whose author *intended*
it to hug content (doc `:138-142`), but under the row's `.center` frame proposal on iPad
it renders edge-to-edge — the reported bug. The card interior stays leading via
`VStack(alignment: .leading)` (`ReminderCardView.swift:35`), and the title `Text` wraps to
the proposed width, so unusually long titles already fill the row today.

**There is exactly one iPad-proportionate pattern in the codebase**:
`EmptyStateCard.maxContentWidth(viewportWidth:)` = `min(340, viewportWidth * 0.6)`
(`EmptyStateCard.swift:42-44`, doc `:36-41`), applied only to empty/all-done states
(`ContentView.swift:383`, `:398`). **No** size-class (`horizontalSizeClass`) or idiom
(`.pad`) check exists in any of the four targets; the reminder card participates in no
adaptation whatsoever.

**Sheets are never content-sized.** All four `.sheet`s use the SDK default full-height
presentation (`ContentView.swift:294-295` settings, `:297-299` purchase, `:302-303`
reschedule, `:306-307` nudge). No `presentationDetents`/`presentationSizing`/`preferredContentSize`
exists anywhere. The nudge sheet (`ContentView+iOS.swift:56-82`) and reschedule sheet
(`ContentView+ActionMenu.swift:175-193`) are short top-aligned `VStack`s inside
`NavigationStack`, stretched only by `.frame(maxWidth: .infinity, alignment: .leading)`
(`ContentView+iOS.swift:74`, `RescheduleSheet.swift:49`) — hence large blank space above
and below the content on iPad. The nudge sheet embeds `RescheduleSheet`
(`ContentView+iOS.swift:62`); the same shared sheet backs the action-menu Reschedule path.

(The research also surfaced a latent, *out-of-scope* bug: the nudge label is a hardcoded
`"Skipped 6 times"` (`LocalizedString+Shared.swift:25-28`) disconnected from the actual
threshold `SkipCountStore.defaultThreshold = 6` (`SkipCountStore.swift:12`); per-reminder
`skipCount(for:)` (`ReminderStore.swift:516-518`) is consumed only by tests. See
"What We're NOT Doing".)

## Desired End State

- The reminder card hugs its content in **every** state — plain, nudge banner shown,
  swipe prompt shown, long title — on **both** iPhone and iPad, never stretching
  edge-to-edge; it is capped to a viewport-relative maximum on iPad the same way the
  empty/all-done states are.
- The post-skip (nudge) sheet **and** the standalone reschedule sheet are sized to their
  content (no large blank bands) on iPad, while remaining full/sheet presentation as
  expected on iPhone.
- A pure, pinnable helper computes the card's max width (mirroring
  `EmptyStateCard.maxContentWidth`), and unit + UI tests prove the fix.

**Verification** (full gate is CI-identical `./scripts/test.sh`; targeted suites per
`conventions.md`):
- SwiftFormat + SwiftLint `--strict` clean (`make format` / `make lint`).
- New unit test for the width-cap helper (Swift Testing, `SingleThreadTests`).
- Existing nudge/reschedule UI tests still pass (`SkipNudgeUITests.swift:24-26`,
  `ActionMenuUITests.swift:21-125`), plus a new iPad-targeted UI assertion that the
  nudged card does not span the row.
- Periphery clean (`make periphery`) — no dead extraction.

## Patterns to Follow

**Good — match these:**
- Viewport-relative width cap: `EmptyStateCard.maxContentWidth` (`EmptyStateCard.swift:42-44`)
  — reuse the *shape* of this (`min(ceiling, viewportWidth * fraction)`), ideally as a
  shared free function so it is unit-pinnable. Do not inline a second copy.
- Content-hugging + centering split (Pattern B in research): keep the cap *inside* the
  card/hugging layer and the `.center` on the caller row (`ContentView.swift:433`), exactly
  as empty/all-done do (`ContentView.swift:386`, `:399` + cap at `EmptyStateCard.swift:31`).
- Sheet presentation stays `.sheet` (no new `fullScreenCover`/`popover`); only attach
  `presentationSizing`.
- `--seed` seam for deterministic UI tests (`UITestingSeed.swift:44-56`,
  `AppViewModel.swift:302-332`; skipCounts written to AppGroup defaults `:309-310`) — the
  standard way to reach the nudge state without a real `EKEventStore`.

**Bad — do NOT copy:**
- The swipe `prompt`'s `.frame(maxWidth: .infinity)` (`ReminderCardView.swift:206-207`) —
  the canonical full-width stretch source. Remove/replace it.
- Hardcoded sizing magic: the reschedule/settings sheets' divergent ad-hoc frames
  (`ContentView.swift:577-579` macOS `minWidth/minHeight`) — do not add another device-
  conditional frame; size from content.
- The disconnected hardcoded "6"s (`SkipCountStore.swift:12` vs
  `LocalizedString+Shared.swift:25-28`) — no new duplicated constant here or elsewhere.
- Do **not** introduce size-class/idiom branching (`horizontalSizeClass`/`.pad`): the
  codebase deliberately avoids it (zero matches); viewport-relative math achieves the same
  without divergence.

## Design Decisions

1. **Card width fix — cap + remove stretch sources (Q1 A):** add a viewport-relative
   `maxWidth` cap on the reminder card (mirroring `EmptyStateCard.maxContentWidth`,
   `EmptyStateCard.swift:42-44`), and remove the swipe `prompt`'s
   `.frame(maxWidth: .infinity)` (`ReminderCardView.swift:206-207`) so the prompt hugs
   too. The nudge banner gets an explicit content-hugging constraint (e.g.
   `.fixedSize(horizontal: true, vertical: false)` or removing whatever lets the
   `borderedProminent` button expand). Rationale: matches the one existing iPad adaptation
   pattern and fixes the whole card-state matrix (nudge, prompt, long title) instead of
   the two reported symptoms. iPhone render changes slightly (title wraps at a cap that it
   rarely reached before) — accepted in trade for a hard guarantee.

2. **Cap as a pure helper (Q4 A):** extract the width computation to a pinnable function
   (e.g. `CardWidth.maxContentWidth(viewportWidth:)` next to `EmptyStateCard`'s), so a
   Swift Testing unit test pins `min(ceiling, fraction)` behavior without rendering. This
   is the same shape already unit-tested for empty states.

3. **Sheet sizing — `.presentationSizing(.fitted)` (Q2 A):** attach
   `.presentationSizing(.fitted)` to the nudge and reschedule sheet presentations
   (`ContentView.swift:302-303`, `:306-307`). iOS 17+ API; deployment target is iOS 18.7
   (`project.pbxproj:765`). Content-sized by construction — no hardcoded heights to clip
   at larger Dynamic Type. If `fitted` misbehaves with the `NavigationStack` toolbar or
   the `DatePicker` (reschedule), fall back to `.presentationDetents([.height(…)])` with a
   per-sheet value — but do not start there.

4. **Sheet scope — both sheets (Q3 A):** fix the nudge sheet *and* the standalone
   reschedule sheet. Same root cause, shared `RescheduleSheet` (`ContentView+iOS.swift:62`,
   `ContentView+ActionMenu.swift:175-193`), near-zero extra cost, consistent UX. The
   settings and purchase sheets are intentionally long/`NavigationStack`-based and are
   **not** in scope.

5. **Test strategy — helper unit test + iPad UI assertion (Q4 A):** unit-test the cap
   helper (happy + boundary: fraction below ceiling, above ceiling). Add one iPad-targeted
   UI test (via the existing `--seed` nudge flow, `SkipNudgeUITests.swift:24-26`) asserting
   the nudged card's frame does not span the row width to within the horizontal inset
   (`ContentView.swift:429`). Use the accessibility/`frame` of `skipNudgeBanner`
   (`ReminderCardView.swift:156`) as the anchor, not a whole-view frame audit — avoids the
   local-only hit-region flakiness noted in `AGENTS.md`. No new test target: existing
   `SingleThreadUITests` runs on the iPad matrix job (ci.yml:22-27).

## What We're NOT Doing

- **Not** touching skip-count persistence, `SkipCountStore`, threshold logic, the 6th-skip
  interrupt (`ReminderStore.swift:384-389`), or the known watch-sync gap on that intercept
  (`research.md` cross-cutting). Those are behaviorally correct for this ticket.
- **Not** deriving the nudge label from the stored count (the two-hardcoded-6s bug,
  `SkipCountStore.swift:12` vs `LocalizedString+Shared.swift:25-28`). Flagged for a
  separate ticket; folding it in would expand a layout fix into persistence/UI-string work.
- **Not** introducing size-class/idiom branching (`horizontalSizeClass`, `.pad`) anywhere.
- **Not** resizing the settings or purchase sheets (`ContentView.swift:294-299`) — they are
  intentionally full presentations.
- **Not** changing `.padding(.horizontal, 40)` (`ContentView.swift:429`) or the
  `.frame(maxWidth: .infinity, alignment: .center)` centering mechanism beyond layering the
  cap inside it.
- **Not** adding a new target/`.sheet` presentation — purely modifiers on existing views.

## Open Risks

- **`presentationSizing(.fitted)` + `NavigationStack`/toolbar**: fitted sizing with a
  `ToolbarItem` cancel button and an embedded `DatePicker` is the least-proven part; may
  need a detent fallback (Decision 3). Verify on simulator before locking.
- **Exact iPad stretch trigger**: research flagged the nudge-button expansion as unproven
  on device (`ReminderCardView.swift:138-142` vs `:206`). The cap + hug fixes (Decisions
  1-2) cover all candidates, but the iPad UI test must actually fail against `origin/main`
  before the change to prove it reproduces the report.
- **Cap value tuning**: `min(340, viewportWidth * 0.6)` is sized for empty states; the
  reminder card may warrant a different ceiling/fraction. Reuse the constant shape but
  confirm the constant with the iPad assertion rather than guessing.
- **Long-title wrap regression**: the new cap makes titles wrap earlier on iPad than today
  (they currently fill the row). If that reads worse than the stretch, we may need to
  reconcile cap vs. intrinsic width (cap wins per Decision 1 — revisit only if visually
  objectionable).
- **Watch/widget surfaces**: the watch nudge banner and widget card are documented as
  "like the watch nudge" (`ReminderCardView.swift:138-142`) and use the same centering
  pattern (`WatchReminderView.swift:368`, `NextThingWidget.swift:161`). This ticket is
  iOS-scoped; verify the iOS changes don't shift shared `ReminderCardView` behavior for
  those targets via the existing watch/widget test suites.
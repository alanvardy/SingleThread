# Done

- **Branch / head SHA**: `alanvardy-var-1112-make-links-in-reminder-titles-and-notes-tappable` @ `afebc4a7` (pushed to origin).

## Mechanical checks

- `make format` — clean.
- `make lint` (`swiftlint lint --strict`) — **0 violations, 0 serious in 220 files**.
- Targeted unit suites:
  - `SingleThreadTests/LinkFormatterTests` — **12/12** (incl. new `requiresWordBoundaryBeforeBareWWW`).
  - `SingleThreadTests/ReminderDisplayTests` — **12/12**.
- `SingleThreadUITests/SingleThreadUITests/testLanguageSelectionChangesVisibleString` — **1/1 in isolation**.
- Full CI-identical gate `./scripts/test.sh` (three clean-lane attempts on `afebc4a7`, pinned iPhone `CDE2B125…` + watchOS-26.5 `3F69EA19…`):
  - **All branch-relevant phases PASS**: format, SwiftLint `--strict`, warning-check self-test, deployment-target check, iOS build (**no un-allowlisted compiler warnings**), watch build, Periphery (`No unused code detected`), iOS UI (4/4 on the first attempt), watch UI, watch unit.
  - The gate did not reach its final green line only because of pre-existing, branch-unrelated **flakes**, each confirmed recoverable and none in code this diff touches:
    1. `AISortCoordinatorTests/reRanksAfterSilentFallbackClearsTheDigest()` — documented timing-sensitive macOS test (20 s poll timeout), passes in isolation; branch does not touch `AISortCoordinator`.
    2. `SingleThreadUITests/testLanguageSelectionChangesVisibleString()` — UI-query timeout on the language picker; `git diff origin/main HEAD -- SingleThreadUITests/` is empty; test passes in isolation (and passed 4/4 in the first full-gate attempt on the same tip).
    3. A Periphery false positive (`showAbout`, two superfluous-ignore comments) seen once only when a stray `build-for-testing` had written to the same index store; Periphery was clean on the uncontaminated runs.
  - CI is the authority for the residual flakes.

## Review outcome

One bounded `reviewer` (fresh context) plus own diff scan. Findings and resolution:

- **Blocker (gate) — redundant `try` → `#UnnecessaryEffectMarker` warnings** in `SingleThreadTests/ReminderDisplayTests.swift`. **Fixed**: removed the two unnecessary `try`s (kept `throws` where `try #require` is genuinely used).
- **P1 — duplicate `ForEach` ids** when a URL appears in both title and notes (render-time failure risk) in `ReminderCardView`. **Fixed**: indexed identity `ForEach(Array(linkURLs.enumerated()), id: \.offset)`.
- **O1 — bare-`www.` had no start-of-token boundary** (e.g. `visitwww.example.com`). **Fixed**: `nextPrefix` now requires a word boundary before a `www.` candidate; added `requiresWordBoundaryBeforeBareWWW`.
- **O2 — `ReminderDisplayRow` had no accessibility custom actions** for its links. **Fixed**: added `@Environment(\.openURL)` + per-link `.accessibilityActions`.
- **Ignored/deferred**: reviewer's claim that `ReminderDisplayRow` links are not tappable was overstated (`Text` link runs route through the app-level `.environment(\.openURL, …)`); `applyCodeAttributes` private→internal is required for same-module reuse and is not public API.
- Verified correct by reviewer + own scan: the `openURL` recursion guard in `SingleThreadApp` (wraps the App-level captured original, non-recursive), code-span exclusion, localization coverage (all six languages), concurrency/Sendable, and widget/watch staying on the code-span-only accessors.

Fixes committed as `afebc4a7` and pushed.

## Remaining manual items

- Plan `plan.md` manual checks: tap a title link and a notes link in the running app (browser opens); bare domains/emails stay plain; backticked URLs stay code-styled and untappable; widget + watch show URLs as plain text; VoiceOver lists one "Open link to <host>" action per link; the action label changes across de/es/fr/ja/zh-Hans.
- The six manual steps in `docs/SimulatorManualVerification.md` → "Tappable links (VAR-1112)".
- Confirm CI green on the PR (local full gate had only the unrelated flakes above).

# Structure Outline

## Approach

Restructure the test runners (not the tests' logic) so the local unit loop goes native macOS
(~10× faster), the full gate drops the duplicate iOS-Sim unit pass locally (keeping it in CI),
and the 38 iOS+watch UI methods collapse to one launch-and-render a11y smoke test per platform
on an iPhone-only matrix — all with the `--seed`/`--ui-testing` seams frozen and zero native
unit tests removed.

Layers are ordered bottom-up. Each stage ships its code **and** its verification green before the
next starts; a later stage can assume the earlier one is proven and can rely on it (or seed/mock
against it). CI reconfiguration is the one layer without a local runtime gate — flagged in Stage 4.

---

## Stage 1: Smoke-Test Content — the new UI test surface (foundation)

Delivers the two surviving UI test methods before anything is deleted, so the replacement is
proven complete in isolation against the frozen seams. Green here proves: plain `--ui-testing`
launch renders the expected card and the minimal a11y audit passes on both platforms.

**Files**: `SingleThreadUITests/SingleThreadUITests.swift` (method replaced in the existing
class), `SingleThreadWatchUITests/SingleThreadWatchUITests.swift` (method replaced; the private
`launchApp()` helper is **relocated** here from the soon-deleted `SingleThreadWatchUITestsFlows.swift:298-304`)

**Key changes** (signatures only):
- `final class SingleThreadUITests: XCTestCase` — keep class name; `runsForEachTargetApplicationUIConfiguration = false`; replace
  `testAccessibilityAudit` with `func testLaunchAndRenderSmoke()`.
- `final class SingleThreadWatchUITests: XCTestCase` — replace `testAccessibilityAudit` with
  `func testLaunchAndRenderSmoke()`; add `@MainActor private func launchApp() -> XCUIApplication`
  (relocated verbatim from `SingleThreadWatchUITestsFlows.swift:298-304`).
- **Reused, not new**: iOS `SingleThreadUITestCase.launchApp(arguments:)` (`SingleThreadUITestCase.swift:13`),
  plain `--ui-testing` seam (frozen), `performAccessibilityAudit(for: [.sufficientElementDescription, .trait])`
  (the CI carve-out subset from `SingleThreadUITests.swift:53-64`).
- **Assertions (iOS)**: card renders — priority `"!!"` (`ReminderCardView.swift:90-96`), title/notes
  `notesText` (`:131-137`), action cluster complete/skip/mic (`ContentView.swift:675-676`);
  `loadsReminders:false` list (`ContentView.swift:171-174`).
- **Assertions (watch)**: card `"!!"`/title/notes (`WatchReminderView.swift:299-319`),
  `completeButton`/`skipButton` (`:139,:154`).

**Tests**: the smoke methods themselves (`testLaunchAndRenderSmoke` — one per platform). Happy path
= renders card; sad path = audit finds a `.trait`/`.sufficientElementDescription` violation (mutation-checkable).
No new unit tests — the surface they replace is already unit-mirrored per `research.md` Q4.

**Verify**:
- `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=18.7' -only-testing:SingleThreadUITests/testLaunchAndRenderSmoke`
- `xcodebuild test -scheme SingleThreadWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -only-testing:SingleThreadWatchUITests/testLaunchAndRenderSmoke`
- `make format` / `make lint` clean.

---

## Stage 2: Collapse the Superseded UI Surface

Deletes every UI test the smoke tests now cover. Builds on Stage 1's proven smoke; green here proves
the collapsed target still compiles, lints, and runs only the intended single method.

**Files** (delete):
`SingleThreadUITests/SingleThreadUITestsLaunchTests.swift`,
`SingleThreadUITests/SingleThreadUITestsAppearanceLaunchTests.swift`,
`SingleThreadUITests/SingleThreadUITestsFlows.swift`,
`SingleThreadUITests/ActionButtonsUITests.swift`,
`SingleThreadUITests/NotificationsSettingsUITests.swift`,
`SingleThreadUITests/NotificationsUITests.swift`,
`SingleThreadUITests/SkipNudgeUITests.swift`,
`SingleThreadUITests/ActionMenuUITests.swift` (empty),
`SingleThreadUITests/NotificationSchedulingUITests.swift` (empty),
`SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`,
`SingleThreadWatchUITests/SingleThreadWatchUITestsLaunchTests.swift`.
*(Exact file list reconciled in plan against `research.md` Q4's 9+2 and 3-file inventories.)*

**Key changes**:
- No new signatures. The surviving classes now expose exactly one method each:
  `testLaunchAndRenderSmoke`.
- `SingleThreadUITestCase.swift` (shared base: `launchApp`, `launchSeeded`, `assertTogglePersists`,
  `statusLabel`) is **kept** — it still serves the surviving iOS class and any future UI tests.
- `runsForEachTargetApplicationUIConfiguration = true` (the lone watch `LaunchTests.swift:6-7` + all
  implicit flow defaults) is removed from the repo along with those files.

**Tests**: no new tests; the Stage 1 smoke tests are the regression net. Coverage note: the folded
audit (`[.sufficientElementDescription, .trait]`) replaces the standalone
`testAccessibilityAudit` methods; `SkipNudgeUITests` iPad geometry and the 3 CI-blind classes
(`NotificationsSettingsUITests`, `NotificationsUITests`, `SkipNudgeUITests`) are unit-mirrored by
`SkipCountStoreTests`, `NotificationPreferenceTests`, `NotificationSchedulerTests` (design decision 5).

**Verify**:
- Same two targeted runs as Stage 1 (now the only members — must still pass, and the whole-target
  `-only-testing:SingleThreadUITests` run returns in ~1 method, not 23).
- `make lint` / `make format` clean; `make periphery` clean after `DerivedData/` wipe (catches dangling refs).

---

## Stage 3: Local Runner Reconfiguration — `scripts/test.sh` + `Makefile`

Repoints the local scripts at the new surface and the native unit loop. Independent of the deleted
methods (filters reference targets, not the deleted files), but ordered after Stage 2 so the local
full gate already runs the collapsed UI surface.

**Files**: `scripts/test.sh`, `Makefile` (textually unchanged — resolves through the script).

**Key changes** (signatures / clauses):
- `scripts/test.sh --unit-only` (`:300-317`): replace the iOS-Sim build-for-testing + test pair with the
  macOS form `CODE_SIGNING_ALLOWED=NO ... test -only-testing:SingleThreadTests -destination 'platform=macOS'`
  (mirrors phase 13 `:285-291` and `Makefile:26` `mac-test`). The ~57 iOS-only `@Test`s become CI-only locally.
- `scripts/test.sh full` (`:230-237`): **delete phase 7** (the iOS-Sim unit pass). Pipeline becomes
  iOS build → watch build → periphery → iOS UI → watch build(concrete)+dylib fix → watch UI → watch unit → macOS unit.
- `Makefile` `test` (`:78-79`) → `--unit-only` now native; `ui-test` (`:81-82`) and `check` (`:103-104`) unchanged textually.
- Not touched: pre-boot (`:22-48`), runtime cleanup (`:52-83`), deploy-target guard (`:110-192`), watch dylib fix (`:256-268`).

**Tests / Verify**:
- `make test` → must run `SingleThreadTests` **natively** and pass (annotate the 3 known pre-existing
  macOS `EntitlementStoreTests` host-state failures — `isEntitledSurvivesStoreRecreation`,
  `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`; CI-green on fresh runners, never debug).
- Same two targeted smoke runs from Stage 1 still green under `scripts/test.sh` (filters unchanged).

---

## Stage 4: CI Reconfiguration — `ci.yml`

Points CI at the single smoke method on an iPhone-only matrix and removes the now-deleted-class
references. **This is the one layer with no local runtime gate** (CI runs only on `push` to `main`,
`ci.yml:3-5`); its semantics are locally exercised by Stage 3 because the same `-only-testing` filter
names the smoke method in `scripts/test.sh`. Verification is inspection + consistency, and the PR's
CI run is the true gate.

**Files**: `.github/workflows/ci.yml`

**Key changes**:
- Merge `ui-tests-flows` (`:93-161`), `ui-tests-launch-appearance` (`:163-231`), `ui-tests-audits`
  (`:233-301`) into one `ui-tests-smoke` job: `matrix.device: ["iPhone 17"]`,
  `-only-testing:SingleThreadUITests/testLaunchAndRenderSmoke`, keeping
  `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1` +
  `-retry-tests-on-failure` + `-maximum-test-execution-time-allowance 900`.
- Drop the env-group split (`:14-16`, references the 5 now-collapsed classes).
- `watch-ui-tests` (`:405-472`): filter → `-only-testing:SingleThreadWatchUITests/testLaunchAndRenderSmoke`;
  watch unit filter (`:467-472`) untouched.
- **Untouched**: `unit-tests` (`:19-91`, retains the iOS-Sim unit pass in CI), `mac-tests` (`:303-357`),
  `lint` (`:355-411`).

**Tests / Verify**: `npx actionlint` (or yaml parse) on `ci.yml`; cross-check every `-only-testing`
name against the final file list from Stage 2; confirm matrix is iPhone-only and no reference to a
deleted class remains. Runtime confirmation is the CI run on the PR.

---

## Testing Checkpoints (resume after any context reset)

1. After **Stage 1** — the 2 smoke methods pass their targeted `xcodebuild … -only-testing:…/testLaunchAndRenderSmoke` runs and `make lint` is clean.
2. After **Stage 2** — same 2 smoke runs still green (now sole members), `make lint`/`make format`/`make periphery` clean.
3. After **Stage 3** — `make test` runs `SingleThreadTests` **natively** and passes (3 known macOS `EntitlementStoreTests` failures annotated as pre-existing).
4. After **Stage 4** — `actionlint` clean and every CI `-only-testing` name matches a surviving member.

Final integration: launch the full `./scripts/test.sh` once via the `run-gate` skill (single async
gate subagent, multi-hour timeout) — it must show the reordered pipeline with the iOS-Sim unit phase
gone and the collapsed UI phase passing. Never `nohup` it ad-hoc; never re-run it per stage.
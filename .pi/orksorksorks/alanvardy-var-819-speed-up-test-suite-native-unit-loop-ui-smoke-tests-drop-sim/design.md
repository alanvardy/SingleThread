# Design Discussion — Speed up the test suite

## Current State

The suite runs the same 520 `@Test` native unit tests **twice per full gate** at two
destinations: iOS Simulator (`scripts/test.sh:230-237`, `-parallel-testing-enabled YES`)
and native macOS (`scripts/test.sh:285-291`, `CODE_SIGNING_ALLOWED=NO`). They are one
target (`project.pbxproj:269-290`) with `SUPPORTED_PLATFORMS="iphoneos iphonesimulator
macosx"`, so the macOS pass is a ~10× faster duplicate of ~458 universal tests plus
5 macOS-only ones.

The local fast loop (`make test` → `scripts/test.sh --unit-only`, `scripts/test.sh:300-317`)
currently runs **iOS Simulator only** — never the native pass, never lint/periphery/watch.

The iOS + watch UI surface is 38 test methods (`SingleThreadUITests` 23 methods / 9 files,
`SingleThreadWatchUITests` 15 methods / 3 files) driven through `--seed` / `--ui-testing`
seams. CI runs 8 iOS legs (4 jobs × `["iPhone 17","iPad (A16)"]`, `ci.yml`) plus a watch
job; the a11y audit is the only test whose CI behavior is split from local
(`SingleThreadUITests.swift:53-64`).

Platform gating is **compile-time only**: `#if os(...)` decides membership,
`-only-testing:` decides runtime selection. No runtime skip facility exists anywhere in
the repo (no `@available`, no `.skip`/`.enabled`, no `XCTSkip`).

## Desired End State

1. **Local unit fast loop is native.** `make test` / `--unit-only` runs
   `SingleThreadTests` natively on macOS (`CODE_SIGNING_ALLOWED=NO test`), not iOS Sim.
   ~10× faster iteration, no simulator in the unit loop.

2. **Full gate drops the local iOS-Sim unit pass**, keeps the macOS-native unit pass
   (already the last phase), and keeps an iOS-Sim unit pass **in CI only**. Native unit
   coverage is unchanged (no tests removed).

3. **UI tests collapse to one launch-and-render smoke test per platform** (iOS
   `SingleThreadUITests`, watch `SingleThreadWatchUITests`), each folding in the minimal
   CI-parity a11y audit `[.sufficientElementDescription, .trait]`.

4. **CI device matrix goes iPhone-only** for the UI smoke job (watch/`mac-tests`/`lint`
   already have no matrix).

5. `--seed` / `--ui-testing` seams are **unchanged** — the smoke tests reuse the existing
   plain-`--ui-testing` launch path verbatim.

Verification (per conventions.md — targeted suites only, full gate runs once via the
`run-gate` skill):
- `xcodebuild test -scheme SingleThread -destination 'platform=macOS'
  -only-testing:SingleThreadTests` — native unit pass green (annotate the three known
  pre-existing `EntitlementStoreTests` host-state failures).
- `xcodebuild test ... -only-testing:SingleThreadUITests/<SmokeTest>` on iPhone sim.
- `xcodebuild test ... -only-testing:SingleThreadWatchUITests/<SmokeTest>` on the
  concrete watch sim.
- `make lint` / `make format` clean.

## Patterns to Follow

- **Compile-time `#if os(...)` is the ONLY platform gate** — used to exclude iOS-only
  files from the macOS build (`AppDelegateTests.swift:1`, `BackgroundCardTests.swift:8`,
  `EntitlementSyncTests.swift:1`, `RescheduleSyncTests.swift:1`,
  `SkippedReminderSyncServiceTests.swift:1`, `EnableActionButtonsSyncTests.swift:1`,
  and the inverse macOS-only `MacOSActionButtonChromeTests.swift:1`,
  `MenuBarExtraOptionsTests.swift:1`). We add **no** new skip mechanism; we extend this
  pattern if any new platform-divergent test appears.
- **`-only-testing:` is the runtime selector** (`scripts/test.sh:230-237`,
  `ci.yml:59,71`). Reused to point CI at the smoke methods after collapse.
- **`CODE_SIGNING_ALLOWED=NO` on every macOS pass** (`scripts/test.sh:291`, `Makefile:26`,
  `ci.yml:309`). The native unit loops must keep it.
- **Launch seams** (`SingleThreadUITestCase.swift:13,21`; watch
  `SingleThreadWatchUITestsFlows.swift:298-304`) are the standard way to drive UI tests
  without a real `EKEventStore`. Smoke tests call the existing helpers, not new ones.
- **Unit tests are Swift Testing** (`import Testing`, `@Test`, names must NOT start with
  `test`); UI tests are XCTest (names keep `test…`). Preserve this split in the smoke
  methods.
- **a11y carve-out** (`SingleThreadUITests.swift:53-64`): CI runs only
  `[.sufficientElementDescription, .trait]`; the `.dynamicType`/`.hitRegion` categories
  and `contrast`/`textClipped` are deliberately excluded (false positives / unit-covered
  per `:44-61`). The folded smoke audit adopts exactly the CI subset.

Patterns found that should **NOT** be followed:

- Do **not** introduce runtime skip traits (`@Test(.enabled/disabled)`, `XCTSkip`) — no
  precedent exists; the compile-time gate already covers the only need (Q3 research).
- Do **not** keep the iOS-Sim unit pass in `--unit-only`/`test.sh full` locally — that is
  precisely the ~10× duplication being removed.
- Do **not** retain `runsForEachTargetApplicationUIConfiguration` divergence for the
  smoke tests — the single smoke method should pin `false` (iOS already does this in 4
  classes `SingleThreadUITests.swift:18-19` etc.; the watch launch test is the lone `true`
  at `SingleThreadWatchUITestsLaunchTests.swift:6-7` and that whole file is going away).

## Design Decisions

1. **Local unit loop goes native macOS** (Q1 = A). `scripts/test.sh --unit-only`
   (`:300-317`) replaces its iOS-Sim build+test pair with the macOS form
   `CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests` (mirroring phase 13,
   `:285-291`, and `Makefile:26`). `Makefile:78-79` is unchanged textually but now
   resolves to native. The ~57 iOS-only `@Test`s (`AppDelegateTests`, `BackgroundCardTests`,
   and the 4 WatchConnectivity sync files) run **CI-only**.
2. **No new skip machinery** (Q2 = A). "Truly iOS-only" tests are already excluded from
   the macOS build by `#if os(...)` at compile time; EventKit tests are *not* iOS-only
   (they run on both destinations, `ReminderStoreTests.swift:1108-1115`,
   `EventKitStoringTests.swift:141`). Nothing to implement.
3. **A11y audit is folded, not dropped** (Q3 = B). Each smoke test renders the app then
   calls `performAccessibilityAudit` with `[.sufficientElementDescription, .trait]`
   (the CI subset), matching the existing carve-out rather than the local
   `.dynamicType,.hitRegion` set.
4. **iPhone-only CI matrix** (Q4 = A). The UI smoke job runs `matrix.device: ["iPhone 17"]`
   (watch/`mac-tests`/`lint` unchanged). `SkipNudgeUITests` (iPad-only geometry,
   `SkipNudgeUITests.swift:27`) is deleted; its behavior is already unit-covered by
   `SkipCountStoreTests` threshold logic.
5. **Consciously drop the 3 CI-blind classes** (Q5 = A). `NotificationsSettingsUITests`,
   `NotificationsUITests` (and the empty `ActionMenuUITests`,
   `NotificationSchedulingUITests`, `NotificationsUITests` `#if os(iOS)` files) are removed
   and documented as unit-mirrored (`NotificationPreferenceTests`,
   `NotificationSchedulerTests`, `SkipCountStoreTests`). They never ran on CI anyway
   (`ci.yml:14-16` groups reference only 5 classes).
6. **Full gate drops the iOS-Sim unit phase locally, keeps it in CI.** In
   `scripts/test.sh full`, remove phase 7 (`:230-237`) so the pipeline goes iOS build →
   watch build → periphery → iOS UI → … → watch unit → macOS unit. The pre-booted sim
   (`:22-48`) stays (still serves iOS build `:210-216` and iOS UI `:240-245`). CI's
   `unit-tests` job (`ci.yml:19-91`) is untouched — that is the retained sim pass.
7. **Smoke test content** — one XCTest method per platform, launched via the existing
   plain `--ui-testing` seam (no `--seed`): iOS asserts the rendered list
   (`ContentView.swift:171-174` loadsReminders-false card, priority `"!!"` and title/notes
   at `ReminderCardView.swift:90-96,131-137`, action cluster `ContentView.swift:675-676`),
   then the minimal audit; watch asserts the card (`WatchReminderView.swift:49-53,89-129`,
   priority/title/notes `:299-319`, `completeButton`/`skipButton` `:139,154`) and the
   minimal audit. Seams and their payloads are byte-identical to today.

## What We're NOT Doing

- **NOT** removing or renaming any native unit tests — the 520 `@Test` set is untouched;
  only *where they run locally* changes (and iOS-only ones shift to CI-only locally).
- **NOT** changing `--seed` / `--ui-testing` semantics, payloads, or
  `AppGroup.defaults` round-trips — the seams are frozen.
- **NOT** touching the `mac-tests`, `lint`, or `watch-ui-tests` CI jobs beyond the
  single-method `-only-testing` filter on the smoke method.
- **NOT** adding runtime skip traits, `@available` gating, or any new platform-conditional
  execution facility.
- **NOT** re-adding a local iOS-Sim unit path, an iPad matrix leg, separate a11y-audit
  methods, or the 3 CI-blind UI classes.
- **NOT** dropping the watch unit suite (`SingleThreadWatchTests`, 44 tests — it already
  runs only on the watch sim via `scripts/test.sh:277-282` / `ci.yml:467-472`).
- **NOT** writing UI tests for write flows (complete/delete) — the single smoke test is
  launch-and-render only; write flows stay covered by unit tests + the `--seed` seam.

## Open Risks

- **The three known pre-existing macOS `EntitlementStoreTests` failures**
  (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`,
  `hostStoreKitIsClean`) become part of the *daily* local fast loop rather than a
  once-per-gate annoyance. Mitigation: they are already documented as host-state
  (CI-green on fresh runners); gate subagent annotates, never debug.
- **If the fold-audit hangs** on virtualized runners (full-traversal hang documented at
  `SingleThreadUITests.swift:46-52`), the minimal CI subset *should* avoid it — but if
  the smoke test flakes in CI, fall back to dropping the audit call entirely (Q3=A) as a
  follow-up, since SwiftLint + unit tests retain coverage.
- **Native macOS run needs host EK store access** — real `EKEventStore()` fixtures
  (`EventKitStoringTests.swift:141,557`, `ReminderStoreTests.swift:1109,1122`) read the
  host store. Already the case for phase 13 today, so this is pre-existing, not new.
- **Exact executed-vs-source counts** (520 source `@Test` vs 564 executed at VAR-790)
  were inferred from git history, not a fresh run — final numbers confirmed during the
  gate.
- **`--unit-only` behavior reversal** — devs relying on the old sim-only `make test` get,
  instead, a native pass that excludes the 57 iOS-only tests; the sim path vanishes from
  the local loop. Worth a one-line note in the PR description so nothing looks like a
  lost regression.
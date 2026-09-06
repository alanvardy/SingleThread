# SingleThread iOS App — Agent Conventions

## Shell Environment

- The command tool runs **fish** — see `~/.pi/agent/AGENTS.md` "Shell
  environment" and the `fish-shell` skill; for bash-only constructs write
  `/tmp/x.sh` FIRST and run `bash /tmp/x.sh` (applies to the parent's own
  tool calls too).

## Build & Test

- **Simulator**: `iPhone 17` is the default locally. `iPad (A16)` is also
  supported; CI runs **both** in parallel matrix jobs. Check available devices
  with `xcrun simctl list devices available | grep -iE 'iphone|ipad'` if
  either is unavailable.
- **Destination pinning**: the name-only `iPhone 17` destination is ambiguous
  when multiple runtimes exist — a bare `name=` hangs.
  Pin `,OS=<ver>` or `,id=<UDID>` (from `xcrun simctl list devices available`).
  `scripts/test.sh`/`Makefile` accept `SIM=`.
- **One xcodebuild test process at a time** (simulator contention). On
  `Busy`/`RequestDenied` runner-launch failures: shutdown sims (`xcrun
  simctl shutdown all`) and kill orphaned `xcodebuild`/`xctest` processes.
  Watch UI tests need a paired sim: `xcrun simctl pair <watchUDID> <phoneUDID>`.
- **Build & tests via `make`**: `make build` / `make test` / `make
  ui-test` / `make periphery` / `make lint` / `make format`; pin a
  destination with `SIM=`. `make periphery` reads a stale build index after
  branch switches — clean `DerivedData/` and rerun first. For targeted suites:
  `xcodebuild -only-testing:SingleThreadTests` (Swift Testing) /
  `-only-testing:SingleThreadUITests` (XCTest, a11y audit) with the
  destination pinned per above.
- **Debug builds only**: `DEBUG_INFORMATION_FORMAT = dwarf` keeps incremental
  builds fast. Release builds switch to `dwarf-with-dsym`.
- **After code changes**, run the full CI check locally via the Before
  Committing gate below (`./scripts/test.sh` — identical to CI).

## Concurrency Model

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the iOS app and
  watch app targets (not project-wide). Async functions in those targets
  default to `@MainActor`; do not wrap in `Task { @MainActor in }` there —
  it's redundant. The `SingleThreadCore` package, widget, and test targets do
  **not** enable it — annotate `@MainActor` explicitly where needed in those.
- The compiler language mode is **Swift 6** (`SWIFT_VERSION = 6.0`).
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` is also set (the Xcode 26 default),
  which keeps concurrency diagnostics approachable.

## Persistence (EventKit + App Group)

- The app reads and writes Apple Reminders through **EventKit**, not SwiftData.
  `ReminderStore` (a `@MainActor @Observable` class in `SingleThreadCore`)
  owns the `EKEventStore` and the skipped-reminder list.
- Skipped-reminder identifiers persist in a shared App Group `UserDefaults`
  (see `AppGroup.swift`); the phone and watch sync them over WatchConnectivity.
- **Every persisted value shared with the watch must round-trip through
  `AppGroup.defaults` (the `UserDefaults(suiteName:)` suite), never
  `UserDefaults.standard`** — on simulator the suite always exists, so the
  two diverge silently. This includes `--ui-testing`/`--seed` launch-arg
  seams.
- Previews and tests inject a pre-populated `ReminderStore` (or use
  `loadsReminders: false`) instead of a real `EKEventStore`.
- `UserDefaults` (incl. `AppGroup.defaults`) is **not** `Sendable` in this
  SDK — verify concurrency claims for shared types against the compiler.

## Purchases (StoreKit)

- The premium product ID is a single source of truth:
  `EntitlementStore.unlockProductID` — never hard-code the id elsewhere,
  and keep `Products.storekit` plus the scheme's
  `StoreKitConfigurationFileReference` in sync with it.
- Real-device testing requires a sandbox tester account (App Store Connect)
  and the signed Paid Applications Agreement; otherwise the store shows
  nothing to tap.

## Project Layout

```
SingleThread/                  # git root
├── SingleThread.xcodeproj/    # Xcode project
├── SingleThread/              # iOS app sources (SingleThreadApp, ContentView, ReminderDictation)
├── SingleThreadCore/          # local SPM package — model/domain layer (ReminderStore, ReminderSkip, …)
├── SingleThreadWatch/         # watchOS app
├── SingleThreadWidget/        # widget extension
├── SingleThreadTests/         # unit tests (Swift Testing)
├── SingleThreadUITests/       # UI tests (XCTest, accessibility audit)
├── scripts/                   # CI-identical test gate; run-devices.sh = devicectl install/launch
├── .github/workflows/ci.yml   # GitHub Actions
├── AGENTS.md
├── Makefile
├── .swiftformat
├── .swiftlint.yml
├── .periphery.yml
└── .mise.toml
```

## QRSPI Workflow

- QRSPI pipeline: `/1_spec` → `/2_clarify` → `/3_design` → `/4_research` →
  `/5_plan` → `/6_implement` (see `~/.pi/agent/AGENTS.md` and `.pi/skills/qrspi/SKILL.md`).
- All QRSPI work — decompose, research, design, plan — happens directly on
  the main ticket's current branch. **No child subtasks** and **no separate
  design PR/branch**. Artifacts live under `.pi/qrspi/<current-branch>/` and
  are committed alongside the ticket's other work (each phase commits its own
  artifact before moving on).
- Plans are consumed literally: verify every snippet, file path, test name,
  and `SIM=…,OS=` destination this session (compile / `ls` / `rg` /
  `xcrun simctl list runtimes`); unproven red-first premises must be marked
  `UNVALIDATED` for the implementer to verify first.

## Adding New Files and Targets

- **New `.swift` files**: Xcode auto-discovers them (synchronized file groups,
  `objectVersion = 77`) — no pbxproj edits needed.
- **New test target** (e.g. `SingleThreadWatchUITests`): requires pbxproj
  object IDs, scheme TestAction wiring, a `-only-testing` entry in
  `scripts/test.sh`, and CI matrix entries. The QRSPI design phase should
  flag this explicitly — it is not a simple file-add.

## Lint & Format

- SwiftFormat (`.swiftformat`) enables `organizeDeclarations`,
  `blankLinesAroundMark`, and `preferSwiftTesting`, and disables
  `trailingCommas`, `trailingClosures`, and `isEmpty`. Run `make format` (or
  `swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/`) to apply.
  UI tests are excluded (`--exclude SingleThreadUITests`).
- SwiftLint runs with `--strict` in CI, so every warning is an error. Run
  `swiftlint lint --strict` before committing. The config is auto-discovered
  from the repo root (`.swiftlint.yml`).
- Variable names must be ≥ 3 characters per `identifier_name` (exceptions:
  `id`, `e`, `d`, `rt`, `to`, `gvm`).
- Unit tests use **Swift Testing** (`import Testing`, `@Test`), not XCTest.
  UI tests still use XCTest.
- **Unit-test names must not start with `test`/`testing`** — SwiftFormat
  strips those prefixes and silently renames the function under `make format`
  (phantom "file reverted" diffs). Follow the convention
  (`isEntitledFallsByDefault`). UI-test (XCTest) names keep `test…` — UI tests
  are SwiftFormat-excluded.
- Force-unwrapping is banned outside test code. Test fixtures relax this rule
  via `SingleThreadTests/.swiftlint.yml`.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide — scope per-target
  overrides in the pbxproj; never via CLI flags (`xcodebuild …=YES`
  conflicts with the SPM package's `-suppress-warnings`).

## Testing Requirements

- **Every new feature and bug must ship with a unit test** (`SingleThreadTests`,
  Swift Testing). A change is not "done" until its logic is covered —
  persistence, filtering, sorting, parsing, formatting, state transitions.
- Bug fixes must add (or fix) a unit test that reproduces the bug before the
  fix, so the fix is proven to hold. A bug-fix ticket is done only when a
  test reproduces the *reported symptom* and the plan's manual/on-device
  verification items actually ran — proving a supporting fact is not fixing
  the bug.
- **UI tests are the exception, not the default.** Use them sparingly, only
  when justified — e.g. a new end-to-end user flow whose value can't be
  captured by a unit test, or a regression that only manifests at the UI layer
  (accessibility, navigation). UI tests are slow and flaky-prone, so each one
  must earn its place; say why a UI test is added or skipped in the PR rather
  than staying silent.
- The `--seed '<json>'` launch-arg seam (backed by `InMemoryEventStore`) is the
  standard way to drive deterministic iOS UI tests for write flows (complete /
  delete) without a real `EKEventStore` or a TCC prompt. Use it for the rare
  UI tests that are justified; reuse the existing `--ui-testing` seam on
  watchOS.
- **Gate staging**: phase subagents verify with a build plus targeted
  `-only-testing:` suites only. The full `./scripts/test.sh` runs ONCE, by the
  parent (or a dedicated final phase), after phases commit — workers
  re-running the full multi-hour gate exceed run caps and orphan unverified
  changes. Plan per-phase Verification lists as targeted `-only-testing:`
  suites (never the full UI suite); launch the full gate detached
  (`nohup bash scripts/test.sh > /tmp/gate.log 2>&1 & echo $last_pid`) so it
  outlives a capped worker. After two consecutive UI-stage contention
  failures with a passing sequential rerun, stop re-running the local gate —
  CI is authoritative.
- Conflict-laden rebases are NOT resolution-edited mid-review: stop, and
  resolve (`git checkout --theirs` / manual continue) in a separate scoped
  fix commit before review resumes.

## Accessibility Testing

- UI tests include `testAccessibilityAudit()` (`performAccessibilityAudit`) +
  SwiftLint `accessibility_label_for_image` / `accessibility_trait_for_button`.
- Local audit runs extra strictness categories (`.hitRegion`, `.dynamicType`)
  beyond CI's — a local hit-region failure can be local-only, not a CI break.
- Caption-sized SwiftUI buttons need `.padding` on the label — a
  `.frame(minHeight: 44)` does not expand the accessibility label frame.

## Before Committing

- Run `make format` then `make lint` (or `./scripts/test.sh` for the full
  build + test + lint pipeline — formats, lints, builds, Periphery, unit +
  UI tests; identical to CI).
- New test suites must be added to `Makefile`'s `test` target and
  `scripts/test.sh` if they need explicit `-only-testing` filters.
- Confirm the change ships with unit-test coverage (see
  [Testing Requirements](#testing-requirements)) before marking work "done";
  UI tests only where justified per that policy.
- A test failure your diff didn't touch is likely pre-existing on
  `origin/main` — verify with git blame / CI history before debugging it, and
  fix it in a separate scoped commit. Known local-only: the two macOS
  `EntitlementStoreTests` SKTestSession tests fail on this machine (CI
  mac-tests is green) — don't debug, treat as pre-existing and annotate.
  Never `git stash` to baseline (stashes span branches) — use `git show
  origin/main:<path>` or a throwaway `git worktree add`.

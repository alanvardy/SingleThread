# SingleThread iOS App — Agent Conventions

## Shell Environment

- The command tool runs **fish** (`/opt/homebrew/bin/fish`), not bash. Use
  fish-native `for … end` loops, never `for … do / done`.
- **Never use bash heredocs** (`<<'EOF'`) — write files with the `write` tool
  and pass them via `--body-file`/paths instead.

## Build & Test

- **Simulator**: `iPhone 17` is the default locally. `iPad (A16)` is also
  supported; CI runs **both** in parallel matrix jobs. Check available devices
  with `xcrun simctl list devices available | grep -iE 'iphone|ipad'` if
  either is unavailable.
- `make` targets and `scripts/test.sh` honor a `SIM` override, e.g.
  `make test SIM='platform=iOS Simulator,name=iPad (A16)'`.
- **Build**:
  ```bash
  xcodebuild -scheme SingleThread \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -configuration Debug build
  ```
- **Unit tests** (Swift Testing, in `SingleThreadTests`):
  ```bash
  xcodebuild test -scheme SingleThread \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:SingleThreadTests
  ```
- **UI tests** (XCTest, in `SingleThreadUITests`, includes accessibility audit):
  ```bash
  xcodebuild test -scheme SingleThread \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:SingleThreadUITests
  ```
- **Debug builds only**: `DEBUG_INFORMATION_FORMAT = dwarf` keeps incremental
  builds fast. Release builds switch to `dwarf-with-dsym`.
- Or use `make` targets: `make build`, `make test`, `make ui-test`,
  `make lint`, `make format`, `make periphery`, `make clean`.
- **After code changes**, run the full CI check locally:
  ```bash
  ./scripts/test.sh
  ```
  This formats, lints, builds,
  runs Periphery dead-code detection (reusing the build's index store),
  runs unit tests, runs UI tests (including accessibility audit), and runs
  SwiftFormat + SwiftLint checks — identical to CI.

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
- Previews and tests inject a pre-populated `ReminderStore` (or use
  `loadsReminders: false`) instead of a real `EKEventStore`.

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
├── scripts/                   # CI-identical test script
├── .github/workflows/ci.yml   # GitHub Actions
├── AGENTS.md
├── Makefile
├── .swiftformat
├── .swiftlint.yml
├── .periphery.yml
└── .mise.toml
```

## QRSPI Workflow

- Complex tasks go through the QRSPI workflow: decompose → research → design
  → plan → implementation. Artifacts live in `.pi/qrspi/<branch>/`
  (`task.md`, `questions.md`, `research.md`, `design.md`, `plan.md`).
- A **design phase runs on a separate child subtask** of the main ticket
  (`linear issue create --parent <MAIN-ID>`), on its **own branch** (Linear's
  `branchName`), with artifacts under `.pi/qrspi/<design-branch>/`, forked
  from `origin/main`, and a **draft PR titled with "design"**.
- All research for the current task lives under `.pi/qrspi/<branch>/` — the
  root-level `research.md` is stale scratch from an earlier task. See the
  `.pi/skills/qrspi/SKILL.md` skill for the full convention.

## Adding New Files

The project uses Xcode's synchronized file groups (`objectVersion = 77`), so
Xcode auto-discovers `.swift` files placed in `SingleThread/`,
`SingleThreadTests/`, or `SingleThreadUITests/` — no pbxproj edits needed.

## Lint & Format

- SwiftFormat (`.swiftformat`) enables `organizeDeclarations`,
  `blankLinesAroundMark`, and `preferSwiftTesting`, and disables
  `trailingCommas`, `trailingClosures`, and `isEmpty`. Run `make format` (or
  `swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/`) to apply.
  UI tests are excluded (`--exclude SingleThreadUITests`).
- SwiftLint runs with `--strict` in CI, so every warning is an error. Run
  `swiftlint lint --strict` before committing. The config is auto-discovered
  from the repo root (`.swiftlint.yml`).
- SwiftLint includes 35 opt-in rules covering accessibility, performance,
  concurrency safety, and code modernization (see `.swiftlint.yml` for the
  full list).
- Variable names must be ≥ 3 characters per `identifier_name` (exceptions:
  `id`, `e`, `d`, `rt`, `to`, `gvm`).
- Unit tests use **Swift Testing** (`import Testing`, `@Test`), not XCTest.
  UI tests still use XCTest.
- Force-unwrapping is banned outside test code. Test fixtures relax this rule
  via `SingleThreadTests/.swiftlint.yml`.

## Testing Requirements

- **Every new feature or behavior change must ship with tests.** A change is
  not "done" until it is covered by:
  - a **unit test** (`SingleThreadTests`, Swift Testing) for any new logic —
    persistence, filtering, sorting, parsing, formatting, state transitions;
  - a **UI test** (`SingleThreadUITests` / `SingleThreadWatchUITests`, XCTest)
    for any new end-to-end user flow — e.g. view, complete, skip, delete,
    settings. This is the regression guard for the user-facing use cases.
- The `--seed '<json>'` launch-arg seam (backed by `InMemoryEventStore`) is the
  standard way to drive deterministic iOS UI tests for write flows (complete /
  delete) without a real `EKEventStore` or a TCC prompt. Use it for new iOS UI
  tests; reuse the existing `--ui-testing` seam on watchOS.
- Bug fixes must add (or fix) a test that reproduces the bug before the fix, so
  the fix is proven to hold.
- If a feature genuinely can't be UI-tested (e.g. dictation/speech, which is
  handled by unit tests only), say so explicitly in the PR rather than silently
  skipping it.

## Dead Code Detection (Periphery)

- Periphery 3.8.0 scans the compiler index store for unused declarations.
  It runs in CI (`periphery scan --strict`) and locally via
  `make periphery` or as part of `./scripts/test.sh`.
- Configuration: `.periphery.yml` (retains SwiftUI previews, excludes UI
  test boilerplate).

## Accessibility Testing

- `SingleThreadUITests` includes `testAccessibilityAudit()` using
  `XCUIApplication.performAccessibilityAudit()`, checking dynamic type,
  hit regions, element descriptions, and traits.
- Complemented by SwiftLint rules `accessibility_label_for_image` and
  `accessibility_trait_for_button`.

## Compiler Warnings

- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` is set in the project-level build
  configuration (Debug + Release), inherited by all targets. Warnings are
  hard failures everywhere — CI, local, and Xcode GUI. This was previously
  a command-line flag (to keep local iteration unblocked), but the local
  Swift Package (`SingleThreadCore`) requires scoping it to project targets
  because `xcodebuild SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` globally injects
  `-warnings-as-errors` which conflicts with the package's `-suppress-warnings`
  (a known Apple bug).

## Before Committing

- Run `make format` then `make lint` (or `./scripts/test.sh` for the full
  build + test + lint pipeline).
- New test suites must be added to `Makefile`'s `test` target and
  `scripts/test.sh` if they need explicit `-only-testing` filters.
- Confirm the feature ships with both unit and UI test coverage (see
  [Testing Requirements](#testing-requirements)) before marking work "done".

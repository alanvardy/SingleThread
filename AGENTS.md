# SingleThread iOS App — Agent Conventions

## Build & Test

- **Simulator**: `iPhone 17` is the default. Check available devices with
  `xcrun simctl list devices available | grep iPhone` if unavailable.
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
  This formats, lints, builds (with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`),
  runs Periphery dead-code detection (reusing the build's index store),
  runs unit tests, runs UI tests (including accessibility audit), and runs
  SwiftFormat + SwiftLint checks — identical to CI.

## Concurrency Model

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set at the project level.
  All async functions default to `@MainActor`. Do not wrap in
  `Task { @MainActor in }` — it's redundant.
- The compiler language mode is **Swift 6** (`SWIFT_VERSION = 6.0`).
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` is also set (the Xcode 26 default),
  which keeps concurrency diagnostics approachable while retaining the
  default `MainActor` isolation.

## SwiftData

- The app uses SwiftData. `SingleThreadApp` builds a `ModelContainer` for the
  `Item` `@Model`; `ContentView` drives it with `@Query` and
  `@Environment(\.modelContext)`.
- `@Model` classes must be `final`.
- Previews and tests that need a container use
  `.modelContainer(for: Item.self, inMemory: true)`.

## Project Layout

```
SingleThread/                  # git root
├── SingleThread.xcodeproj/    # Xcode project
├── SingleThread/              # app sources
│   ├── Assets.xcassets/
│   └── *.swift                # SingleThreadApp, ContentView, ReminderSkip
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

- `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` is passed to all `xcodebuild`
  invocations in CI, `scripts/test.sh`, and `Makefile`. Warnings in CI
  become hard failures. This is not set in the project file to avoid
  blocking local iteration.

## Before Committing

- Run `make format` then `make lint` (or `./scripts/test.sh` for the full
  build + test + lint pipeline).
- New test suites must be added to `Makefile`'s `test` target and
  `scripts/test.sh` if they need explicit `-only-testing` filters.

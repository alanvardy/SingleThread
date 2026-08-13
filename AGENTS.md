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
- **Debug builds only**: `DEBUG_INFORMATION_FORMAT = dwarf` keeps incremental
  builds fast. Release builds switch to `dwarf-with-dsym`.
- Or use `make` targets: `make build`, `make test`, `make lint`, `make format`,
  `make clean`.
- **After code changes**, run the full CI check locally:
  ```bash
  ./scripts/test.sh
  ```
  This formats the codebase, builds, runs unit tests, and runs SwiftFormat +
  SwiftLint checks — identical to CI.

## Concurrency Model

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set at the project level.
  All async functions default to `@MainActor`. Do not wrap in
  `Task { @MainActor in }` — it's redundant.
- The compiler language mode is **Swift 5** (`SWIFT_VERSION = 5.0` in the
  pbxproj), even though `.swift-version` and `.swiftformat`'s
  `--swiftversion 6.0` say otherwise. Don't rely on Swift 6-only language
  features (e.g. strict `any`/`Sendable` checking) until the mode is bumped.

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
│   └── *.swift                # SingleThreadApp, ContentView, Item
├── SingleThreadTests/         # unit tests (Swift Testing)
├── SingleThreadUITests/       # UI tests (XCTest)
├── scripts/                   # CI-identical test script
├── .github/workflows/ci.yml   # GitHub Actions
├── AGENTS.md
├── Makefile
├── .swiftformat
└── .swiftlint.yml
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
  `swiftlint lint --strict --config .swiftlint.yml` before committing.
- Variable names must be ≥ 3 characters per `identifier_name` (exceptions:
  `id`, `e`, `d`, `rt`, `to`, `gvm`).
- Unit tests use **Swift Testing** (`import Testing`, `@Test`), not XCTest.
  UI tests still use XCTest.

## Before Committing

- Run `make format` then `make lint` (or `./scripts/test.sh` for the full
  build + test + lint pipeline).
- New test suites must be added to `Makefile`'s `test` target and
  `scripts/test.sh` if they need explicit `-only-testing` filters.

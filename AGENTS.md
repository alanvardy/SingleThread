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
  SwiftLint checks — identical to CI. `make build` and `make test` are subsumed
  by this script; list them as separate verification steps only when a plan
  wants a narrower incremental gate.

## Concurrency Model

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set at the project level.
  All async functions default to `@MainActor`. Do not wrap in
  `Task { @MainActor in }` — it's redundant.
- The compiler language mode is **Swift 6** (`SWIFT_VERSION = 6.0`).
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` is also set (the Xcode 26 default),
  which keeps concurrency diagnostics approachable while retaining the
  default `MainActor` isolation.

## Reminders (EventKit)

- The app reads and writes system Reminders via EventKit — no SwiftData.
  `ReminderStore` is a `@MainActor @Observable final class` over an
  `EKEventStore`; `SingleThreadApp` owns it as `@State` and injects it with
  `.environment(reminderStore)`.
- `ReminderStore.load()` fetches incomplete reminders with
  `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)`,
  bridged to `async` with `withCheckedContinuation`.
- `ReminderAccessStatus` maps `.notDetermined` → `.notDetermined`,
  `.denied`/`.restricted`/`.writeOnly` → denied, and
  `.authorized`/`.fullAccess` → authorized.
- The calendar entitlement (`com.apple.security.personal-information.calendars`)
  is declared in `SingleThread/SingleThread.entitlements`.
- The write path (`eventStore.save(_:commit:)` in `ReminderStore.complete(_:)`)
  is synchronous on the main actor and **cannot run in CI** — verify
  save/persistence behavior manually.
- `ReminderFilter.swift` holds the pure
  `dueStatus(_:isCompleted:now:calendar:)` function (returns `.overdue`,
  `.dueToday`, or `nil`); unit tests cover it in `SingleThreadTests`.

## Project Layout

```
SingleThread/                  # git root
├── SingleThread.xcodeproj/    # Xcode project
├── SingleThread/              # app sources
│   ├── Assets.xcassets/
│   └── *.swift                # SingleThreadApp, ContentView, ReminderStore, ReminderFilter
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

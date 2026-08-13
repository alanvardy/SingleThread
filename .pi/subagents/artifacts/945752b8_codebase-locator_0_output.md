# Q7: Build & CI Pipeline — What EXISTS

## 1. Makefile (`Makefile`)

| Line | Content |
|------|---------|
| `Makefile:1` | `SIM := platform=iOS Simulator,name=iPhone 17` (shared simulator var) |
| `Makefile:3` | `.PHONY: build test clean lint format` |
| `Makefile:5-6` | `build:` → `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug build` |
| `Makefile:8-9` | `test:` → `xcodebuild test -scheme SingleThread -destination '$(SIM)' -only-testing:SingleThreadTests` |
| `Makefile:11-12` | `clean:` → `xcodebuild -scheme SingleThread -destination '$(SIM)' clean` |
| `Makefile:14-16` | `lint:` → `swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/` then `swiftlint lint --strict --config .swiftlint.yml` |
| `Makefile:18-20` | `format:` → `swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/` then `swiftlint --fix --config .swiftlint.yml` |

## 2. `scripts/test.sh`

- `scripts/test.sh:1-2` — shebang `#!/usr/bin/env bash`; `set -euo pipefail` (fail-fast).
- `scripts/test.sh:5` — `SIM="platform=iOS Simulator,name=iPhone 17"`; `:6` — `SCHEME="SingleThread"`.
- `scripts/test.sh:8` — `cd "$(dirname "$0")/.."` (repo root).
- `scripts/test.sh:10-12` — Formatting: `swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/` + `swiftlint --fix --config .swiftlint.yml`.
- `scripts/test.sh:15-16` — SwiftFormat check: `swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/`.
- `scripts/test.sh:19-20` — SwiftLint: `swiftlint lint --strict --config .swiftlint.yml`.
- `scripts/test.sh:23-26` — Build: `xcodebuild -scheme "$SCHEME" -destination "$SIM" -configuration Debug build`.
- `scripts/test.sh:29-32` — Unit tests: `xcodebuild test -scheme "$SCHEME" -destination "$SIM" -only-testing:SingleThreadTests`.
- `scripts/test.sh:35` — `echo "✅ All CI checks passed."`.

## 3. `.github/workflows/ci.yml`

- `ci.yml:1` — workflow `name: CI`.
- `ci.yml:3-7` — triggers: `push` → `branches: [main]`; `pull_request` → `branches: [main]`.
- **Job `test`** (`ci.yml:10`):
  - `ci.yml:11` — `runs-on: macos-26`.
  - `ci.yml:13` — `actions/checkout@v4`.
  - `ci.yml:15-17` — `maxim-lobanov/setup-xcode@v1` with `xcode-version: '26.6'`.
  - `ci.yml:19-20` — "Override development team": `echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV`.
  - `ci.yml:22-26` — `actions/cache@v4`, path `~/Library/Developer/Xcode/DerivedData/SingleThread-*`, key `derived-data-${{ runner.os }}-xcode26.6-${{ hashFiles('SingleThread/**/*.swift') }}`, restore-key `derived-data-${{ runner.os }}-xcode26.6-`.
  - `ci.yml:28-33` — "Build" (`timeout-minutes: 20`): `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`.
  - `ci.yml:35-40` — "Unit tests" (`timeout-minutes: 20`): `xcodebuild test ... -only-testing:SingleThreadTests`.
- **Job `lint`** (`ci.yml:42`):
  - `ci.yml:43` — `runs-on: macos-26`.
  - `ci.yml:45` — `actions/checkout@v4`.
  - `ci.yml:47-48` — "Install tools": `brew install swiftlint swiftformat`.
  - `ci.yml:50-52` — "SwiftFormat check" (`timeout-minutes: 5`): `swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/`.
  - `ci.yml:54-56` — "SwiftLint" (`timeout-minutes: 5`): `swiftlint lint --strict --config .swiftlint.yml`.

## 4. `.swiftformat` rules (apply to new code)

- `:.swiftformat:2` — `--swiftversion 6.0`.
- Indentation: `:5` `--indent 4`; `:6` `--wraparguments before-first`; `:7` `--wrapcollections before-first`; `:8` `--closingparen same-line`.
- Enabled rules: `:11` `blankLinesAroundMark`, `:12` `organizeDeclarations`, `:13` `preferSwiftTesting`.
- Disabled rules: `:14` `andOperator`, `:15` `isEmpty`, `:16` `trailingClosures`, `:17` `trailingCommas`, `:18` `wrapMultilineStatementBraces`.
- Exclusions: `:21` `--exclude SingleThreadUITests` (UI tests are NOT formatted).

## 5. `.swiftlint.yml` rules (apply to new code)

- Included paths: `:2-5` — `SingleThread`, `SingleThreadTests`, `SingleThreadUITests`.
- Disabled rules (`:8-14`): `single_test_class`, `balanced_xctest_lifecycle`, `empty_xctest_method`, `final_test_case`, `multiple_closures_with_trailing_closure`, `type_name` (XCTest-specific rules disabled because project uses Swift Testing).
- Thresholds:
  - `line_length` `:17-19` — warning 120, error 150.
  - `cyclomatic_complexity` `:21-23` — warning 12, error 15.
  - `type_body_length` `:25-27` — warning 500, error 600.
  - `file_length` `:29-31` — warning 650, error 800.
- Force unwrap/cast severity: `force_cast` `:34-35` warning; `force_try` `:36-37` warning.
- Opt-in rules (`:40-52`): `closure_spacing`, `empty_count`, `explicit_init`, `fatal_error_message`, `first_where`, `implicit_return`, `overridden_super_call`, `prohibited_super_call`, `sorted_imports`, `trailing_closure`, `unowned_variable_capture`, `vertical_parameter_alignment_on_call`.
- `identifier_name` exclusions (`:55-62`): `id`, `e`, `d`, `rt`, `to`, `gvm`.

## 6. Supporting build settings (`SingleThread.xcodeproj/project.pbxproj`)

- `project.pbxproj:6` — `objectVersion = 77` (synchronized file groups — auto-discovers new `.swift` files, no pbxproj edits needed; documented in `AGENTS.md`).
- `project.pbxproj:306` — Debug `DEBUG_INFORMATION_FORMAT = dwarf`; `:368` — Release `dwarf-with-dsym`.
- `project.pbxproj:307/369/395/439/482/508/533/558` — `DEVELOPMENT_TEAM = 6NWX2DHB9Q` (hardcoded in project; CI overrides to empty via `GITHUB_ENV`).
- `project.pbxproj:411` — `IPHONEOS_DEPLOYMENT_TARGET = 26.5`.
- `project.pbxproj:416` — `PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.SingleThread`.
- `project.pbxproj:421` — `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"` (iOS/macOS/visionOS multi-platform).
- `project.pbxproj:422` — `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- `project.pbxproj:423` — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- `project.pbxproj:426` — `SWIFT_VERSION = 6.0`.
- `project.pbxproj:427` — `TARGETED_DEVICE_FAMILY = "1,2,7"`.

These same Debug settings are repeated for the app target (`:395-427`), unit test target (`:482-496`), and UI test target (`:533-547`), and Release configs mirror them at `:439-471`, `:508-522`, `:558-572`.

## Additional context (`AGENTS.md`)

- `AGENTS.md` documents the same simulator (`iPhone 17`), build/test commands, `make` targets, `./scripts/test.sh` as CI-identical, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift 6, and the lint/format commands. It also notes unit tests use Swift Testing while UI tests use XCTest (`SingleThreadTests/SingleThreadTests.swift:7` uses `import Testing`; `SingleThreadUITests/SingleThreadUITests.swift:7` and `SingleThreadUITestsLaunchTests.swift:7` use `import XCTest`).

---
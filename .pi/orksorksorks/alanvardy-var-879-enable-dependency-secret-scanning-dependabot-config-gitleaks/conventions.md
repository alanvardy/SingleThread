# Conventions — SingleThread (VAR-879)

Shared factual appendix for Design / Structure / Plan. All `file:line` refs into
this repo unless noted. Branch `alanvardy-var-879-…`; HEAD `60ee183` = DELETEME stub only.

## Build / test / lint / format / verify commands

- **Full CI-identical gate**: `./scripts/test.sh` (full). Mode dispatch `:91–94`; aliases:
  `make test` → `scripts/test.sh --unit-only` (`Makefile:78`), `make ui-test` → `--ui-only` (`:81`), `make check` → full (`:103`).
- **Pipeline** (`test.sh:195–286`): swiftformat → swiftlint --fix → swiftformat --lint → swiftlint --strict → iOS build-for-testing → watch build → Periphery (`--skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict`, `:226`) → iOS UI → watch UI (local `lib_TestingInterop.dylib` embed `:247–255`) → watch unit → macOS native unit.
- **Per-target / fast**: `make build` (`:17`), `make watch-build` (`:20`), `make mac-build` (`:23`), `make mac-test` (`:26`), `make lint` (`:109`, swiftformat --lint 8 dirs + swiftlint --strict), `make format` (`:113`), `make periphery` (`:117`).
- **CI inlines everything** (`.github/workflows/ci.yml`) — does NOT call `scripts/test.sh` or `make`. Workflow-only edits go into `ci.yml` directly.
- **Lint order before committing**: `make format` then `make lint` (fast); `./scripts/test.sh` full gate run once by a dedicated async gate subagent in a worktree (AGENTS.md `:119–145,192–199`), never ad-hoc nohup.
- **SwiftLint runs `--strict` in CI** — every warning is an error (`ci.yml:223–225`, `test.sh:207`, `Makefile:111`). `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide.

## Tool pins & configs

- `.mise.toml:1–4`: swiftlint 0.65.0, swiftformat 0.62.1, periphery 3.8.0. `.swift-version:1` = 6.0.
- `.swiftlint.yml`: included 7 dirs (`:2–9`); line_length 120/150 (`:20`); `unused_import` analyzer (`:78`); identifier_name exceptions `id,e,d,rt,to,gvm` (`:82–89`); test-scoped relax in `SingleThreadTests/.swiftlint.yml`.
- `.swiftformat`: 4-space indent, `preferSwiftTesting`, excludes `SingleThreadUITests`.
- `.periphery.yml:12`: report_exclude `**/SingleThreadUITests/**`.

## Test-suite inventory & CI mapping

| Suite | Path | Framework | CI job (`ci.yml`) |
|---|---|---|---|
| iOS unit | `SingleThreadTests/` (~68 files) | Swift Testing | `unit-tests` (`:12–78`) |
| iOS UI (smoke) | `SingleThreadUITests/SingleThreadUITests.swift` | XCTest, 1 test `:26` | `ui-tests-smoke` (`:80–139`) |
| watchOS unit | `SingleThreadWatchTests/` (8 files) | Swift Testing | `watch-ui-tests` (`:243–309`) |
| watchOS UI (smoke) | `SingleThreadWatchUITests/SingleThreadWatchUITests.swift` | XCTest, 1 test `:11` | `watch-ui-tests` |

- Counts: 538 iOS `@Test` + 41 watch = 579; 1180 `#expect`/73 `#require`/6 `Issue.record` (`scripts/count_tests.sh:18–28`).
- **Unit tests = Swift Testing; names must NOT start with `test`/`testing`** (SwiftFormat strips the prefix; watch UI XCTest names keep `test…` and are not excluded). UI tests = XCTest (XCTest is not SwiftFormat-excluded for watch UI, is for iOS).

## Build / verify gotchas

- **Destination pinning**: name-only `iPhone 17` is ambiguous across runtimes — pin `,OS=` or `,id=`; `make`/`test.sh` take `SIM=` (default `Makefile:1`). Bare `name=` hangs.
- **One xcodebuild test process at a time** (simulator contention); on `Busy`/`RequestDenied`, `xcrun simctl shutdown all` + kill orphaned `xcodebuild`/`xctest`.
- Watch UI tests use a **standalone (unpaired)** watch sim by default; CI creates it (`ci.yml:262–272`, `simctl create "CI Watch S11"`). Pairing is only a troubleshooting step.
- **Debug-only `dwarf`** (`DEBUG_INFORMATION_FORMAT = dwarf`) for fast incremental builds; release uses `dwarf-with-dsym`.
- Known pre-existing local-only failures (macOS EntitlementStoreTests): `isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` canary — don't debug, annotate pre-existing.
- CI matrix runs **both** iPhone 17 and iPad (A16); name-only destinations in ci.yml (`ci.yml:15`). CI never resolves UDIDs (test.sh does, `:20–47`).

## Security / scanning surface (this ticket)

- `.github/` contains only `workflows/ci.yml`; **no dependabot.yml, no CODEOWNERS, no SECURITY.md**.
- Repo settings (live): vulnerability alerts **disabled**; **secret scanning + push protection already enabled** (`security_and_analysis`).
- **No `.env*` handling** in `.gitignore`/scripts; no `.env` file. No existing gitleaks/ignore markers anywhere in the tree.
- `alanvardy` is a **personal account** — org/teams endpoints 404; no GitHub teams exist → Dependabot `reviewers`/`assignees` can only be plain username `alanvardy`, never `org/team` slugs.
- Referencing org repo (private) `alanvardy/api`: gitleaks config exists (`.github/workflows/gitleaks/gitleaks.toml`, `[extend] useDefault = true` only, unused by any workflow); that repo SHA-pins CodeQL actions (`github/codeql-action@v4.37.9`) unlike SingleThread's major-tag style.

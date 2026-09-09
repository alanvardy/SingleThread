# Research Findings

Scope: repo config + security-tooling surface of SingleThread. Branch state at
research time: HEAD `60ee183` adds only a `DELETEME` stub — **no implementation,
no dependabot.yml, no gitleaks config exists yet** (Q3).

## Q1: CI workflow layout — `.github/workflows/ci.yml`

### Findings
- Single workflow in repo: `.github/workflows/ci.yml` (309 lines). Trigger `on: push` to `[main]` only (`ci.yml:3–5`); **no `pull_request` trigger**. Concurrency `ci-${{ github.ref }}`, cancel-in-progress (`ci.yml:7–9`). **No `permissions:` block** (implicit default token). **No `needs:`** — 5 jobs run independently in parallel (`ci.yml:13,81,142,194,241`).
- All 5 jobs `runs-on: macos-26`.
  1. `unit-tests` (`ci.yml:12–78`): matrix `["iPhone 17","iPad (A16)"]`; build `-only-testing:SingleThreadTests` → `test-without-building` (parallelism disabled), upload `TestResults.xcresult` on failure.
  2. `ui-tests-smoke` (`ci.yml:80–139`): iPhone 17; smoke `testLaunchAndRenderSmoke`, `-retry-tests-on-failure`.
  3. `mac-tests` (`ci.yml:141–192`): `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`, `test -only-testing:SingleThreadTests`.
  4. `lint` (`ci.yml:193–238`): brew install mise → `mise install` → SwiftFormat `--lint` (8 dirs) → SwiftLint `--strict` → watch build → Periphery.
  5. `watch-ui-tests` (`ci.yml:243–309`): creates unpaired watch sim (`simctl create "CI Watch S11"`), watch UI + unit smoke.
- Common prologue per job: `actions/checkout@v4` → `maxim-lobanov/setup-xcode@v1` (`xcode-version '26.6'`) → `echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV` → `actions/cache@v4` (DerivedData, hashFiles) → simctl pre-boot.
- **Third-party action pin style: short major tags only** (no SHA): `checkout@v4`, `setup-xcode@v1`, `cache@v4`, `upload-artifact@v4` (`ci.yml:21,23,31,75,89,…`). Sole third-party action besides the `actions/*` set is `maxim-lobanov/setup-xcode@v1`.
- **CI does not invoke `scripts/test.sh` or the Makefile** — zero matches in ci.yml; all builds/tests are inline xcodebuild commands. Lint step mirrors `make lint` (8-dir swiftformat list shared with `test.sh:181–184`/`Makefile:110`); Periphery differs (ci.yml uses `--destination`, test.sh uses `--skip-build --index-store-path`).

## Q2: Secret-like / high-entropy strings (gitleaks allowlist inputs)

### Findings
- **Only one scanner-significant artifact in the repo**: the base64 1×1 JPEG in `SingleThreadTests/BackgroundTestFixtures.swift:8–20` — `static let jpegData = Data(base64Encoded: "/9j/4AAQSkZJRg…/Z")!`, ~2,700 chars of genuine high-entropy base64 split across 12 concatenated string literals (lines 9–20). This is the fixture a scanner (gitleaks base64/entropy rule) would flag.
- Inline JSON payloads — low entropy, not credential-bearing: `TestFixtures.swift:212–214`; `BackgroundImageStoreTests.swift:225–226,452–453,460`; `BackgroundCardTests.swift:129–130`; `--seed` JSON launch args throughout `UITestingSeedTests.swift:15,30,42,54,70,81,93,104,115,127,132`.
- Hardcoded URLs, no credentials: `TestFixtures.swift:221–222` (`https://vardy.cc/unsplash`, `https://images.unsplash.com/photo-1.jpg`); `BackgroundImageStoreTests.swift:438–440`; `URLOpeningTests.swift:10,12,32,35` (custom schemes), `:18–19` (`a://1`,`a://2`). Production mirrors: `BackgroundImageStore.swift:180,183`, `ContentView+Previews.swift:18`, `AppInfo.swift:16`.
- Fake UUIDs: `ReminderDeepLinkTests.swift:20`, `ContentViewModelTests.swift:55`.
- **Absent repo-wide**: no Authorization/Bearer/Basic headers, no JWTs, no AWS keys, no GitHub/Slack/Stripe tokens, no private-key blocks, no `.env`/`.pem`/`.p8`/`.pfx`/`.key` files, no hex ≥32 chars, no payment strings. `docs/TestFlight-macOS.md:50–51,99` describe an App Store Connect API key as a "portal secret" but embed no value.
- **No existing allowlist/ignore markers anywhere**: no `.gitleaks.toml`, `.gitleaksignore`, `.secrets.baseline`, no `gitleaks:allow`/`#nosec`/`# pragma: allowlist` (only false-positive `nosec` inside `Task.sleep`). No `CODEOWNERS`, no `SECURITY.md`, no `.env` handling in `.gitignore` (Q3).
- Net: the gitleaks allowlist must cover at least the base64 JPEG (path-scoped), plus possibly the `--seed` JSON / unsplash URL fixtures depending on chosen scan scope and ruleset.

## Q3: Repo-wide config conventions & branch state

### Findings
- `.gitignore` (40 lines): Xcode/DerivedData/build/SPM/CocoaPods/Carthage/macOS/IDE/Fastlane/code-injection/`.pi-subagents`/`DerivedDataPhase4/`. **No `.env*` patterns; no `.env` file exists** — no env-handling conventions.
- `.ignore:1–2`: ignores `.pi/qrspi`, `.pi/orksorksorks` (tooling search exclusion).
- `.mise.toml:1–4` pins `swiftlint 0.65.0`, `swiftformat 0.62.1`, `periphery 3.8.0`. `.swift-version:1` = `6.0`.
- `.swiftlint.yml` (1.8 KB): included 7 dirs; line_length 120/150; `analyzer_rules: unused_import`; identifier_name exceptions (`id,e,d,rt,to,gvm`). `.swiftformat`: 4-space indent, `preferSwiftTesting`, excludes `SingleThreadUITests`. `.periphery.yml:12` excludes `**/SingleThreadUITests/**`.
- **`alanvardy` is a personal account, not an org** (org/teams endpoints 404; `gh api orgs/alanvardy/teams` → "Not Found"; owner = `Alan Vardy <alanvardy@gmail.com>`, single author). **No GitHub teams exist** → Dependabot `reviewers` can only hold plain usernames, never `org/team` slugs; reviewers must be repo collaborators, assignees need write access. See Q5.
- Repo settings (GitHub-side, checked live): **vulnerability alerts DISABLED** (`GET vulnerability-alerts` → 404 "Vulnerability alerts are disabled"); **secret scanning `enabled`; secret scanning push protection `enabled`** (`repos/alanvardy/SingleThread` → `security_and_analysis`). `.github/dependabot.yml` absent (contents API → "Not Found").
- Org convention lead: `alanvardy/api` (private) has `.github/workflows/gitleaks/gitleaks.toml` (`[extend] useDefault = true` only, no rules) — but **no workflow in that repo references gitleaks** (dormant config). `api` uses SHA-pinned CodeQL actions (`github/codeql-action@v4.37.9`) and an auto-merge workflow using `fastify/github-action-merge-dependabot@v3` (minor/patch, rebase).
- Branch state: branch == `origin/main` merge-base `9a73548` + one commit `60ee183` adding only `DELETEME`. Working tree additionally has the unstaged `DELETEME` deletion and untracked `.pi/orksorksorks/…` (gitignored). `DELETEME` is a recurring "stub commit" marker convention (added on stub commits, removed pre-review).

## Q4: Build & test gate

### Findings
- **Makefile** (`.PHONY` at `:15`): `build`=iOS Debug build-for-testing (`:17`); `watch-build` `:20`; `mac-build` `:23`; `mac-test`=macOS test `-only-testing:SingleThreadTests` `CODE_SIGNING_ALLOWED=NO` (`:26`); `coverage*` `:40–76`; `test`→`./scripts/test.sh --unit-only` `:78`; `ui-test`→`--ui-only` `:81`; `watch-ui-test`/`watch-test` direct xcodebuild `:87–102`; `check`→full test.sh `:103`; `clean` `:106`; `lint`=swiftformat --lint 8 dirs + swiftlint --strict `:109–112`; `format` `:113`; `periphery` `:117`.
- **`scripts/test.sh`** (322 lines): `set -euo pipefail`; `resolve_sim_udid`/`preboot_sim` via `xcrun simctl` (`:20–47`); stale-XCTest-runtime cleanup (`:50–75`); `verify_deployment_target` guard (18.7 iOS / 26.5 macOS+watchOS, 20 pbxproj + 3 Package.swift literals, `:108–185`) runs unconditionally. Full pipeline (`:195–286`): format→swiftlint --fix→lint strict→iOS build-for-testing→watch build→Periphery (`--skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict`)→iOS UI→watch UI (incl. local `lib_TestingInterop.dylib` embed `:247–255`)→watch unit→macOS native unit.
- **CI inlines its own commands; it does not call scripts/test.sh or make** (Q1). CI and test.sh duplicate the 8-dir swiftformat list, dest strings, and `-only-testing` selectors.
- **Test-suite inventory**:
  - iOS unit `SingleThreadTests/` (~68 Swift files) — **Swift Testing** (`import Testing` ×67, 0 XCTest). CI: `unit-tests`.
  - iOS UI `SingleThreadUITests/SingleThreadUITests.swift` — **XCTest**, one `testLaunchAndRenderSmoke` (`:26`). CI: `ui-tests-smoke`.
  - watchOS unit `SingleThreadWatchTests/` (8 files, incl. `TestFixtures.swift`) — **Swift Testing** (×7). CI: `watch-ui-tests` (`-only-testing:SingleThreadWatchTests`).
  - watchOS UI `SingleThreadWatchUITests/SingleThreadWatchUITests.swift` — **XCTest**, one `testLaunchAndRenderSmoke` (`:11`).
  - Counts (`scripts/count_tests.sh:18–28`): 538 iOS `@Test` + 41 watch = 579; 1180 `#expect`/73 `#require`/6 `Issue.record`; 1 launch per UI suite.
- `.periphery.yml:12` excludes `**/SingleThreadUITests/**`; Periphery incremental via `--skip-build --index-store-path` in test.sh, plain `--strict -destination` in CI/Makefile.
- Simulator caveats (AGENTS.md): name-only `iPhone 17` destination is ambiguous when multiple runtimes exist — pin `,OS=` or `,id=`; one xcodebuild test process at a time (`make`/test.sh take `SIM=`).

## Q5: gitleaks & Dependabot (external tools)

### Findings — gitleaks
- Project: Checkmarx-owned gitleaks; **current stable v8.30.1** (Feb 2026; v8.30.0 Nov 2025 added Looker/Airtable PAT rules). ~150–200+ default regex/entropy rules (config/gitleaks.toml embedded in binary). Covers AWS/GCP/Azure, GitHub/GitLab/Slack/Discord/Stripe/Twilio/npm/PyPI tokens + generic-api-key/generic-credential (regex+keyword+entropy). Built-in path allowlist for lockfiles/vendored deps/binaries/images/docs.
- **Exit codes: 0 clean, 1 scan error, 2 leaks found.**
- Allowlisting mechanisms (4): (a) config-file `[allowlist]` (fields: `description`, `commits[]`, `paths[]`, `regexes[]`, `stopwords[]`, `regexTarget` secret/match/line, `condition` OR/AND) + per-rule `[[rules.allowlists]]`; **custom config replaces defaults unless `[extend] useDefault = true`**; (b) inline `gitleaks:allow` comment on the secret's line (v8.10+, path-independent; disabled by `--ignore-gitleaks-allow`; unusable in JSON/YAML values); (c) `--baseline-path` (suppress pre-existing findings; proves pre-existing not benign); (d) `.gitleaksignore` (Fingerprint lines, path/line-brittle).
- Config resolution: `--config` → `GITLEAKS_CONFIG` env → `GITLEAKS_CONFIG_TOML` → `.gitleaks.toml` in scanned dir → built-in.
- **Official action `gitleaks/gitleaks-action@v2`**: supported events push/pull_request/workflow_dispatch/schedule (not `pull_request_target`); runs `detect --redact -v --exit-code=2 --report-format=sarif --report-path=results.sarif`; uploads `results.sarif` artifact; env `GITLEAKS_VERSION`, `GITLEAKS_ENABLE_UPLOAD_ARTIFACT`, `GITLEAKS_ENABLE_COMMENTS`, `GITLEAKS_LICENSE` (org-owned only). Does **not** auto-upload SARIF to code scanning — needs separate `github/codeql-action/upload-sarif@v3`. Alternate integations: `ghcr.io/gitleaks/gitleaks` docker image, binary release download, or `docker run`/direct binary in a CI step.
- Gotchas: gitleaks 8.30.x SARIF can emit `endColumn:0` (rejected by codeql upload — sanitize first); artifact-upload race if no leaks in some v2 releases.

### Findings — Dependabot
- `.github/dependabot.yml` schema: top-level `version: 2`; `updates:` array; per-ecosystem block `package-ecosystem` (e.g. `github-actions`, `swift`), `directory` (required; pubspec/`/` root), `schedule.interval` (`daily|weekly|monthly`), `schedule.day` (weekly), `schedule.time` (`HH:MM`), `schedule.timezone` (IANA), `reviewers`, `assignees`, `open-pull-requests-limit` (default 5), plus `labels`, `target-branch`, `versioning-strategy`, `groups`.
- `open-pull-requests-limit`: int, default 5 open version-update PRs per ecosystem; `0` disables version updates. Security updates exempt (own 10 cap).
- **`reviewers`/`assignees` on personal-account repos**: plain usernames only — `org/team` slugs are org-only. `reviewers` must be collaborators (else 422 "Reviews may only be requested from collaborators"); `assignees` need write access. GitHub Docs note `reviewers` being phased out in favor of CODEOWNERS.
- `swift` ecosystem is valid (SPM Package.swift; resolved via `Package.resolved`).

## Cross-Cutting Observations
- **No secret-scanner or dependabot config exists today**; `.github/` holds only `ci.yml`. This is a greenfield add — no conventions to preserve, but the repo's pin-by-major-tag style (`checkout@v4` etc.) contrasts with `alanvardy/api`'s SHA-pinned CodeQL habit.
- **Repo has essentially no real secrets by construction** (single personal account, no env files, no CI secrets beyond default token) — the practical gitleaks burden is the base64 JPEG fixture and, at wider scope, fixture JSON/URLs. The allowlist problem is narrow and path-scoped.
- **CI is the sole gate** (push-to-main only), inlined, all-main-job parallel; adding a gitleaks step means editing `ci.yml` inline (existing style), not `scripts/test.sh`/Makefile, if it's CI-only.
- Dependabot "reviewers alone" intent must resolve to the plain username `alanvardy` (personal account; no teams exist) — matches the repo's single-author reality.

## Open Areas
- Exact default-rule count / whether a default gitleaks scan of this tree fires only the base64 JPEG is unverified without running the binary (`gitleaks detect --list-rules` / a dry run). Whether inline vs config-file allowlist is preferred is a design decision, not a fact.
- `gitleaks/gitleaks-action@v2` `GITLEAKS_VERSION` default reported variously (8.24.3) vs current 8.30.1 — verify against the action README before pinning.
- Whether Dependabot `reviewers` phase-out timing affects choice is unresolved (design consideration, not a repo fact).
- `schedule.time`/`timezone` for Dependabot and exact `swift` directory value (`/` root) not yet confirmed against a live Dependabot config.

# Done

- **Branch / head SHA**: `alanvardy-var-1048-add-no-warnings-check` @ `ac8e93a0`
  (gate-verified source tip). This `done.md` is a follow-on docs-only commit.
- **Mechanical checks**:
  - `make format` — clean (no-op); `make lint` — 0 violations, 0 serious, 198 files.
  - Warning-check fixture self-test — **20/20** (added missing-log, no-caller-pipefail, and off-line-header cases).
  - Shell syntax + CI YAML parse — OK.
  - Full CI-identical gate (`./scripts/test.sh`, run twice via the `run-gate` async subagent in an isolated worktree):
    - **All warning-gate stages green** — 6× `✓ no un-allowlisted compiler warnings`, 0 real `❌ …compiler warning`; the only red lines are the self-test's deliberate negative fixtures.
    - SwiftFormat / SwiftLint / deployment-target + xcodebuild-wrapper checks / Periphery (0 findings) / iOS build / Watch build / iOS UI tests / Watch UI tests / Watch unit tests — all PASS.
    - **Only failures: the three pre-existing local-only macOS `EntitlementStoreTests`** (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`), documented in `AGENTS.md` as pre-existing on `origin/main` and green on fresh CI runners. Not debugged; CI is authoritative.
- **Review outcome**:
  - **Blockers: none.** The reviewer's sole blocker — that `queueUserInfo` returning unconditional `true` is not behavior-preserving — was **rejected with evidence**: the compiler warning being fixed was literally *"comparing non-optional value of type `WCSessionUserInfoTransfer` to `nil` always returns true"*, so the old `!= nil` already evaluated to `true` on every real call. The suggested alternative (keep `!= nil` + allowlist it) would violate the ticket's own "never silence a fixable warning" rule. Only the surrounding docs were stale, and those were corrected.
  - **Fixes applied** (`ac8e93a0`):
    1. `check-warnings.sh` — fail closed when a passed log does not exist (was a silent green scan).
    2. `check-warnings.sh` — `run_xcodebuild` sets `pipefail` locally so `tee` cannot mask a failed build when sourced without it.
    3. `check-warnings.sh` — `allowlist_match` handles an unterminated final line, removing the trailing-newline fragility noted in `implement.md`.
    4. `xcodebuild-warnings.allow` — narrowed from the whole `StoreKitTest.framework/Headers/` directory to the exact observed `SKTestTransaction.h:34` diagnostic; a new fixture proves an off-line diagnostic in the same header still fails.
    5. `.github/workflows/ci.yml` — wrapped the macOS unit-test `xcodebuild` (it compiles the test target) in the same tee + scan idiom as the other build steps.
    6. `SkippedReminderSyncService` / both `TestFixtures.swift` — corrected the `queueUserInfo` and fake-transport docs (no behavior change; refusal is a `SkipSyncSession` test-seam concept only).
  - **Optional improvements declined, with reason**: hardening `verify_xcodebuild_wrapped` beyond `^[[:space:]]*xcodebuild` would false-positive on the function's own diagnostic `echo`/`printf` strings; regex locale/CRLF hardening and de-duplicating the tee idiom between `ci.yml` and `run_xcodebuild` are out of scope.
- **Remaining manual items**:
  - The `implement.md` plan items still marked manual (on-device / red-first probes the user confirms by hand). Their *automated* counterparts all passed.
  - CI is authoritative for the PR: all jobs (iPhone + iPad matrix, mac-tests, watch jobs, lint/warning-check self-test) must be green — fix/allowlist any CI-only warning in a follow-up commit.
  - The three macOS `EntitlementStoreTests` failures will still present locally; expected and unrelated.
# Research Findings

## Q1: Swift 6 warning settings — inheritance and the warnings-as-errors lever

### Findings
- `SWIFT_TREAT_WARNINGS_AS_ERRORS` is the **only** Swift warnings-as-errors lever in the project; no `-Werror`-family, per-diagnostic, or `-Wno` flags exist anywhere (`SingleThread.xcodeproj/project.pbxproj:676,731,856,885`; grep across pbxproj finds only these four occurrences).
- **Project-level Debug/Release both set it to `YES`**: `pbxproj:676` (Debug block `51AA3EF7…`), `pbxproj:731` (Release block `51AA3EF8…`).
- **Only override: `SingleThreadTests` sets `NO`** in both Debug (`pbxproj:856`) and Release (`pbxproj:885`), with an explicit rationale comment (`pbxproj:858-860,887-889`): *StoreKitTest's headers contain an iOS-18-deprecated symbol; with warnings-as-errors the module's PCM fails to emit. SingleThreadTests is the only target importing StoreKitTest, so relax it here.*
- **Inheritance model**: the pbxproj separates project-level configs (`pbxproj:1156-1162`) from per-target config lists (`pbxproj:1164-1210`). Every target except `SingleThreadTests` omits the key, so all **inherit project-level `YES`**: `SingleThread`, `SingleThreadUITests`, `SingleThreadWatch`, `SingleThreadWidget`, `SingleThreadWatchUITests`, `SingleThreadWatchTests`. Only `SingleThreadTests` is relaxed (`NO`).
- `SWIFT_VERSION = 6.0` is repeated project-level and per-target (`pbxproj:769,818,858,887,…`); `SWIFT_APPROACHABLE_CONCURRENCY = YES` everywhere; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on app targets only.
- The `GCC_WARN_*` / `CLANG_*` settings (e.g. `pbxproj:643-666, 705-728`) are C/C++/ObjC-only (`_ERROR`/`YES_ERROR`), not Swift — irrelevant to Swift warnings.
- **The SPM `-suppress-warnings` claim is not present in the tree.** `SingleThreadCore/Package.swift` (the only `Package.swift`) contains no `-suppress-warnings`; it only declares a `Package(...)` with one `.target(name: "SingleThreadCore", resources: [.process("Resources")])` (`Package.swift:1-24`). The `-suppress-warnings` warning lives only in `AGENTS.md:145-147` as a conceptual caution: **never** toggle warnings-as-errors via CLI flags (`xcodebuild …=YES`) because it conflicts with the SPM package's `-suppress-warnings`. The package reference is `XCLocalSwiftPackageReference` (`pbxproj:1228`, product dependency `pbxproj:1230`).

### Connection
Targets inherit `YES` from the project level by omission; the `SingleThreadTests = NO` override at `pbxproj:856/885` is the established, documented precedent for scoping warnings-as-errors to a single target.

## Q2: `scripts/test.sh` xcodebuild invocations, output flow, failure propagation, and the test-one.sh capture idiom

### Findings
- **Strict mode**: `set -euo pipefail` at `scripts/test.sh:2`; any foreground command returning non-zero aborts immediately. Failure propagation is entirely via `set -e` — there are **no** per-command `$?` handlers around the xcodebuild calls. Explicit `exit 1`s exist only where `set -e` wouldn't fire: usage error (`test.sh:123`), deployment-target drift (`test.sh:224`), unresolved watch simulator (`test.sh:274`). Success ends `echo "✅ All CI checks passed."; exit 0` (`test.sh:348-349`).
- **Seven xcodebuild invocations in full mode, three command styles** (all `-derivedDataPath "$DERIVED_DATA"` with `DERIVED_DATA="DerivedData"`, `test.sh:25`):
  - **iOS `build-for-testing`** (app + test targets): `test.sh:252-256`, dest `$SIM`, `-configuration Debug`.
  - **Watch `build`** (watch app only): `test.sh:282-286`, dest `$WATCH_SIM`.
  - **iOS UI `test-without-building`**: `test.sh:294-298`, dest `$SIM`, `-only-testing:SingleThreadUITests`.
  - **Watch `build-for-testing`** (both watch test bundles): `test.sh:302-307`, dest `$WATCH_TEST_SIM`, `-only-testing:SingleThreadWatchUITests -only-testing:SingleThreadWatchTests`.
  - **Watch UI `test-without-building`**: `test.sh:324-329`, `-only-testing:SingleThreadWatchUITests`.
  - **Watch unit `test-without-building`**: `test.sh:332-336`, `-only-testing:SingleThreadWatchTests`.
  - **macOS unit `test`** (the only `test`-style build in full mode): `test.sh:340-347`, dest `$MAC_SIM`, `CODE_SIGNING_ALLOWED=NO`, `-only-testing:SingleThreadTests`.
  - Sub-modes: unit-only macOS unit `test` (`test.sh:355-360`); UI-only build-for-testing (`test.sh:369-373`) + test-without-building (`test.sh:378-382`).
- **Stdout/stderr flow — no capture**: every xcodebuild streams live to the caller's terminal in the foreground; **no build log is written or parsed anywhere in test.sh** (no `tee`, `> file`, or log argument). The only swallowed output is unrelated (`xcrun simctl boot … 2>/dev/null || true`, `test.sh:44`).
- **test-one.sh is the sole in-repo build-log capture idiom**: `LOG="$WORK/xcodebuild.log"` (`scripts/test-one.sh:30`), `xcodebuild … >"$LOG" 2>&1 &` backgrounds and merges stderr into the file (`test-one.sh:33-34`), `wait "$XCB"` → `STATUS=$?` inside `set +e`/`set -e` (`test-one.sh:47-52`), and on non-zero prints `tail -25 "$LOG"` then exits that code (`test-one.sh:54-58`). It also hard-fails on zero matching cases by parsing `xcresulttool get test-results summary` (`test-one.sh:57-67`) — the same zero-match-red trap as `-only-testing:`.
- **Build surface a warnings observation would need to cover**: iOS `build-for-testing` (`test.sh:252`), watch `build` (`test.sh:282`), watch `build-for-testing` (`test.sh:302`), macOS unit `test` (`test.sh:340`), plus the `--ui-only` build (`test.sh:369`) and unit-only mode (`test.sh:355`). Periphery runs between the builds (`test.sh:292-295`).

## Q3: Compiler-warning suppression and lint-convention mechanisms

### Findings
- **pbxproj carve-out** is the only compiler-warning suppression: `SingleThreadTests` `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO` (`pbxproj:856,885`).
- **SwiftLint suppression is narrowly scoped** (15 sites, 3 forms), never blanket:
  - File-level footer `// swiftlint:disable <rule>`: `SingleThread/ContentView.swift:8` (`file_length`), `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:8` (`file_length`), `SingleThreadTests/ReminderStoreTests.swift:8` (`file_length`).
  - Inline `// swiftlint:disable:next <rule>`: `SingleThreadCore/.../BoolPreferenceStore.swift:14` (`function_default_parameter_at_end`), `SingleThreadCore/.../ReminderDictationParser.swift:116,122,128,134,140,146,155` (all `force_try`).
  - Inline same-line `// swiftlint:disable:this <rule>`: `SingleThreadTests/ReminderStoreTests.swift:924` (`empty_count`), `SingleThreadTests/CompletionCounterStoreTests.swift:14,22,63,84,86` (all `empty_count`).
- SwiftLint runs **`--strict`** (every warning = error) in all three callers: `Makefile:131`, `scripts/test.sh:248`, `.github/workflows/ci.yml:232`.
- SwiftLint configs: root `.swiftlint.yml` (`included` = 7 source dirs incl. both UI-test dirs; `disabled_rules` for XCTest rules `single_test_class`, `balanced_xctest_lifecycle`, `empty_xctest_method`, `final_test_case`, `multiple_closures_with_trailing_closure`, `type_name`; thresholds `line_length` 120/150, `cyclomatic_complexity` 12/15, `type_body_length` 500/600, `file_length` 650/800; `force_cast`/`force_try` downgraded to `severity: warning`; 36-rule `opt_in_rules`; `analyzer_rules: [unused_import]`; `identifier_name.excluded: [id,e,d,rt,to,gvm]`) and a per-directory relax in `SingleThreadTests/.swiftlint.yml` (`disabled_rules: [force_unwrapping]`).
- SwiftFormat config `.swiftformat`: `--swiftversion 6.0`; indent 4; enables `blankLinesAroundMark`, `organizeDeclarations`, `preferSwiftTesting`; disables `trailingCommas`, `trailingClosures`, `isEmpty`, `andOperator`, `wrapMultilineStatementBraces`; `--exclude SingleThreadUITests`. Invoked as fix (`test.sh:239`, `Makefile:134`) and lint check (`test.sh:244`, `Makefile:130`).
- **No compiler-level suppression exists**: no `-Wno-*`, no `-Werror` in `Package.swift` (`Package.swift:1-24`), no `pragma`/`@_silence` in Swift sources; `suppress*` hits are unrelated prose/comments (`SingleThread/SingleThreadButtonModifier.swift:18`, `AppViewModel.swift:204,226`).

### Conventions established
Warnings-as-errors is the project-wide default; the only carve-out is `SingleThreadTests`, documented at its config site. SwiftLint suppression is per-location (`:next`/`:this`), test-only leniency goes in a per-directory `.swiftlint.yml` rather than inline comments, and format/lint are enforced identically through `Makefile`, `scripts/test.sh`, and CI (`--strict`).

## Q4: CI and Makefile vs `scripts/test.sh`

### Findings
- **Makefile delegates to the gate**: `test:` → `./scripts/test.sh --unit-only` (`Makefile:98-99`), `ui-test:` → `--ui-only` (`Makefile:101-102`), `check:` → `./scripts/test.sh` full gate (`Makefile:123-124`); `lint:` (`Makefile:129-131`), `format:` (`Makefile:133-135`), `periphery:` uses `-- -destination "$(SIM)"` (`Makefile:137-138`). Direct xcodebuild targets exist for `build`/`watch-build`/`mac-build`/`mac-test`/coverage etc. (`Makefile:37-96`). Destination resolution: explicit `SIM=` env > `.simulator_id` > default `iPhone 17` (`Makefile:1-35`).
- **CI does not call `scripts/test.sh`.** `.github/workflows/ci.yml` re-implements the phases as separate inline steps (all jobs `runs-on: macos-26`, Xcode 26.6 pinned via `maxim-lobanov/setup-xcode` `ci.yml:27,96,154,205,255`). Jobs: `unit-tests` (iOS matrix iPhone 17/iPad — build `-only-testing:SingleThreadTests` `ci.yml:52-58`, test `ci.yml:67-75`), `ui-tests-smoke` (job `ci.yml:84`, build `ci.yml:121-127`, test `ci.yml:136-141`), `mac-tests` (job `ci.yml:146`, build `ci.yml:173-179`, test `ci.yml:184-190`), `lint` (job `ci.yml:199`; swiftformat `ci.yml:228`, `swiftlint lint --strict` `ci.yml:232`, watch build `ci.yml:237-241`, periphery `ci.yml:245`), `watch-ui-tests` (job `ci.yml:247`, watch build `ci.yml:290-297`, watch UI test `ci.yml:302`, watch unit `ci.yml:313`), `secret-scan` (`ci.yml:319`). Build steps use `-showBuildTimingSummary`.
- **Build output is not retained**: each xcodebuild streams only to the CI step log. The only artifacts uploaded are `TestResults.xcresult` / `TestResults-mac.xcresult`, and only `if: failure()` (`ci.yml:78,193`). No build-log artifact, no `-resultBundlePath` on build steps. CI does **not** run `make check`/`test.sh`, so a check added only to `test.sh` would not execute in CI's current step-based path.

## Cross-Cutting Observations
- **Warnings-as-errors is already the effective default** for every target except `SingleThreadTests` (`pbxproj:676,731,856,885`). A no-compile-warnings gate that only "turns on" warnings-as-errors would already be satisfied for most targets; the relaxed `SingleThreadTests` target (`NO`) is the plausible current source of compile warnings, since that is the one target that does not already fail builds on warnings. (The task's premise that "existing warnings" must be resolved points at this target.)
- **No build-log capture exists in `scripts/test.sh`** — a warnings scan would need to add capture around the seven xcodebuild calls (`test.sh:252,282,294,302,324,332,340`); the only existing idiom is `scripts/test-one.sh:30-58` (`>LOG 2>&1` + `tail`).
- **Gate vs CI divergence**: `test.sh` runs its warning-relevant software on targeted destinations (macOS native for `SingleThreadTests`, iOS/watch sims; `test.sh:252/282/302/340`), while CI builds `SingleThreadTests` on iOS sims (`ci.yml:52-58,67-75`). A warnings check must account for which platform builds which target — a warning may surface on iOS but not macOS or vice versa.

## Open Areas
- **Current warnings inventory is not statically enumerable** — it requires running the builds and reading the Swift compiler diagnostics. The report confirmed the *configuration* (warnings-as-errors off only for `SingleThreadTests`) but not *which* warnings exist today or in which target; that is a build/spike, not a codebase fact.
- The **exact textual format** of Swift compiler warnings in xcodebuild output (for grep/counting) was not verified — only that xcodebuild streams to stdout/stderr without capture.
- The `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project default means any warning *should* already fail the build for inherited targets (if Xcode's Swift driver honors the setting for Swift diagnostics as expected) — whether deposits surface as compiler errors or are absorbed by the driver was not empirically confirmed.
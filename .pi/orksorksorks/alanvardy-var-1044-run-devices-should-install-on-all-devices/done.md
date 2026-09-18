# Done

- **Branch / head SHA**: `alanvardy-var-1044-run-devices-should-install-on-all-devices` — reviewed code tip `9b87d31d` (pushed; local == origin); this `done.md` is committed on top.
- **Merge base**: `c791ab3a` (== `origin/main` at review time).

## Mechanical checks

- `bash -n scripts/run-devices.sh` — clean.
- `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` — clean (`SC1111` is the
  pre-existing unicode-quote warning in the iOS "Trust" message, excluded per plan deviation 6).
- `shellcheck -S warning scripts/test-run-devices.sh` — clean.
- `bash scripts/test-run-devices.sh` — **16/16 checks pass** (two discovery filters against the
  synthetic fixture, wrong-shape tolerance, and 4 stubbed end-to-end control-flow scenarios).
- `make format` / `make lint` — 0 violations, 0 serious across 198 files; no Swift files touched.
- **Full CI gate** via the `run-gate` skill (async worktree subagent, workflow `1d2c4afe`, gate
  child `6e90c70e`, gated commit `9b87d31d`, log `/tmp/gate-var1044.log`):

  | Stage | Result |
  |---|---|
  | Format / SwiftLint | PASS |
  | iOS build | PASS |
  | Watch build | PASS |
  | Periphery | PASS (report-only; no findings) |
  | iOS UI tests | PASS |
  | Watch UI tests (watchOS 26.5, unpaired) | PASS |
  | Watch unit tests | PASS |
  | **macOS unit tests** | **FAIL** — pre-existing `main` break (see below) |

  Gate exit 65, driven solely by `mac-tests`.

### The `mac-tests` failure is pre-existing on `main`, not a VAR-1044 regression

`xcodebuild -scheme SingleThread -destination platform=macOS test` fails at **Build (macOS)** with
`SingleThread/AppViewModel.swift:22:23: error: cannot find type 'SkipSyncSession' in scope` (plus
downstream `@State` macro-expansion errors). Root cause: `SkipSyncSession` is declared only under
`#if os(iOS) || os(watchOS)` in
`SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`, while
`AppViewModel.swift:22` references it unconditionally, so the `SingleThread` target cannot compile
for the macOS host.

Verified independently:

1. `git diff --stat <merge-base>..HEAD -- SingleThread SingleThreadCore` is **empty** — this branch
   touches only `scripts/`, the fixture, and `.pi/orksorksorks/…` docs.
2. `origin/main` == merge-base `c791ab3a`.
3. CI run `35294352708` on `main` (`c791ab3a`) fails exactly the `mac-tests` job at the **Build
   (macOS)** step with the identical error, while every other job (`lint`, `unit-tests` iPhone+iPad,
   `ui-tests-smoke`, `watch-ui-tests`, `secret-scan`) is green.

Fixing the macOS build is out of scope for VAR-1044; it belongs in its own ticket.

- **AGENTS.md note is stale**: "CI mac-tests green on fresh runners (three local-only
  `EntitlementStoreTests`)" no longer holds for current `main` — the `mac-tests` job is red at the
  Build step, so those three tests never execute locally or in CI.

## Review outcome

One bounded `reviewer` (fresh context, diff passed inline) plus the parent's own scan. No code-level
P0 was found; failure tallies, exit codes, `set -euo pipefail` hygiene, `identifier|name` parsing,
and devicectl-4016 handling all traced correct.

**Blockers fixed**

- `DELETEME` bootstrap marker removed (`git rm DELETEME`).

**Fixes worth doing now (applied)**

- **Zero-device gate defect** (`scripts/run-devices.sh`): with `RUN_WATCH=1 RUN_MAC=0`, no
  reachable iOS device, and only an *unreachable* physical watch, the script exited early with
  "No iPhone/iPad…" and never built the watch — contradicting design decision 4 ("the watch app is
  built whenever a physical watch was discovered"). `WATCH_BUILD_NEEDED` is now computed **before**
  the gate and counts `WATCH_UNREACHABLE_COUNT`, so a discovered physical watch is always a reason
  to continue; the iOS-only fail-fast is preserved when nothing watch-related was found.
- **Regression coverage added**: `scripts/test-run-devices.sh` now replays the script end-to-end
  with stubbed `xcrun`/`xcodebuild`, asserting the unreachable-watch-only build, the
  reachable-watch-only success (exit 0), the no-device fail-fast (exit 1), and `RUN_WATCH=0`
  silence (exit 1). The bug reproduces against the pre-fix gate and is fixed by it.

**Optional improvements (applied)**

- `DEVICES_JSON_IN` invalid JSON now fails with a curated message instead of a Python traceback.
- Discovery filters tolerate valid-JSON/wrong-shape inventories (`{}`, missing `result.devices`)
  without a traceback.
- Summary `iPhone/iPad` line counts actual `devicectl` launch successes (`IOS_LAUNCHED/total`), not
  discovered devices, so a failed install is not reported as launched.
- Watch launch-form reporting no longer silently overwrites: the first successful form is kept and
  a later watch needing the other form is flagged.
- `"Apple Watch: 0 watches found"` → `"no installable watch found"` (the old wording implied
  absence when watches existed but were unpaired / Developer-Mode-off).
- Test-script robustness: explicit `<<'PY'` heredoc matcher, output-file existence checks,
  wrong-shape filter assertions.

**Optional improvements declined/deferred**: none from the reviewer's list were declined.

**Deliberate deviations from `plan.md`'s literal snippets** (introduced by the fixes above; the
remainder of the plan's code is unchanged):

- Phase-3 summary text: `"no installable watch found"` and `"iOS: N/total launched"` read
  differently from the plan for accuracy.
- `scripts/test-run-devices.sh` now covers bash control flow with stubs, not just the python
  filters (plan deviation 4 described the bash orchestration as hand-verified only).
- `WATCH_BUILD_NEEDED` moved above the zero-device gate.

## Remaining manual items (user)

- **M4 — the merge gate — still UNVALIDATED.** A direct `devicectl device install app` of the
  `SKIP_INSTALL=YES` companion-embedded watch bundle has never succeeded anywhere in this repo.
  Run `RUN_MAC=0 ./scripts/run-devices.sh` with the watch on the wrist, its paired iPhone nearby
  and unlocked, and both on this Mac's network. If it fails with an unresolvable
  provisioning/install error, stop and revisit design decision 1 (direct-to-watch install vs.
  companion relay) rather than patching around it.
- M1, M2, M3, M5, M6, M7, M8 from `plan.md` / `implement.md` remain unchecked.
- **Separate follow-up ticket**: fix the pre-existing `main` macOS build break
  (`SkipSyncSession` unavailable on macOS in `SingleThread/AppViewModel.swift:22`), which keeps the
  `mac-tests` CI job red on every branch.
- Gate-process note for later rebases: `organizeDeclarations` in SwiftFormat is load-sensitive —
  run this repo's gate serially, not concurrently with another worktree's gate.

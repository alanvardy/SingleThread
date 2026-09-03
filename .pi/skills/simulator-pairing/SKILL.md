---
name: simulator-pairing
description: Pair iPhone and watch simulators for watchOS UI tests, and read .ips runner crash dumps. Use when watch UI tests hang or fail with runner-launch errors, when `simctl pair` errors with "requires a device pair", or when a paired-sim check is the suspected failure.
---

# Simulator Pairing (SingleThread)

Watch UI tests require the watch simulator to be **paired** with a phone simulator. Without a pair, the full gate hangs in runner-launch (or fails with `lib_TestingInterop.dylib` missing) — it is not a code bug.

## Steps

1. Shut down sims: `xcrun simctl shutdown all`.
2. List devices: `xcrun simctl list devices available` → note the watch UDID and phone UDID.
3. Check/recreate the pair: `xcrun simctl list pairs`, then
   `xcrun simctl pair <watchUDID> <phoneUDID>`.
4. Re-run only the watch UI tests (`-only-testing:SingleThreadWatchUITests`) before the full gate.

## Reading runner crash dumps

On runner-launch failures, `xctest` drops `.ips` crash reports (e.g. `lib_TestingInterop.dylib` missing) under `~/Library/Logs/DiagnosticReports`. Inspect the exception info there before assuming a simulator-contention or code issue.

## Environment note (this machine)

The watchOS 26.5 simruntime lacks `lib_TestingInterop.dylib`; `scripts/test.sh` carries a bundling workaround (a no-op elsewhere via its `[[ ! -f ]]` guard). Keep env-specific breakage documented **here**, not in CI-identical gate code — if the runtime is ever repaired, remove the workaround from `scripts/test.sh` in the same change that drops this note.
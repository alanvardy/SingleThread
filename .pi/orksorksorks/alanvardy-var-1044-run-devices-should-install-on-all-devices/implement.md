# Implementation Summary

Ticket: VAR-1044 — run-devices should install on all devices (Apple Watch leg)

`scripts/run-devices.sh` gains a third platform leg — discover → build → install →
launch → summary for a physical Apple Watch — so one run covers iPhone, iPad,
macOS, and Apple Watch. No `.swift` file, no `project.pbxproj`, no
`Makefile`/CI change, no shell test target.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | 3b152f9e | walking skeleton — discover, diagnose, and build the watch app |
| 2     | 3c0962d6 | install + launch the watch app on reachable watches |
| 3     | cede9858 | per-platform summary, synthetic inventory fixture, and offline filter checks |

All three commits are pushed to `origin/alanvardy-var-1044-run-devices-should-install-on-all-devices`
(the branch histories are the post-rebase chain: commit 1 was force-with-lease
pushed after the mandated `git rebase origin/main` rewrote the 3 doc commits —
approved by the supervisor; phases 2 and 3 were plain fast-forward pushes).

## Automated Checks

- [x] Phase 1: `bash -n scripts/run-devices.sh` — clean
- [x] Phase 1: `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` —
      clean (SC1111 is the pre-existing unicode-quote warning in the iOS "Trust"
      message; per the plan it was excluded, not fixed)
- [x] Phase 1: stub control flow — 5 cases, exits 0,0,0,1,0
- [x] Phase 1: `DerivedData/Build/Products/Debug-watchos/SingleThreadWatch.app`
      exists (real build from a real `./scripts/run-devices.sh` run with this
      Mac's live inventory)
- [x] Phase 1: `codesign -dv` reports `TeamIdentifier=6NWX2DHB9Q` on that product
- [x] Phase 1: `Debug-iphoneos/SingleThread.app` intact after the watch build
      (shared-DerivedData risk checked)
- [x] Phase 2: `bash -n` + `shellcheck -S warning --exclude=SC1111` — clean save
      one transient SC2034 (`WATCH_LAUNCH_FORM` written in Phase 2, read by the
      Phase 3 summary); resolved and fully clean at Phase 3
- [x] Phase 2: stub control flow — reachable watch installs+launches once with
      the CoreDevice identifier `AAAAAAAA-0000-0000-0000-000000000002`;
      unreachable-only watch → zero install/launch attempts, exit 1; phase-2
      harness exits 0,0,0,1,0; RUN_WATCH=0 regression clean
- [x] Phase 3: `bash scripts/test-run-devices.sh` — 8/8 checks `✅`, exit 0
- [x] Phase 3: `shellcheck -S warning --exclude=SC1111` — fully clean (0
      warnings); `bash -n` clean
- [x] Phase 3: fixture has 8 devices; `Fixture iPhone` pinned at
      identifier `CCCCCCCC-0000-0000-0000-000000000007`
- [x] Phase 3: `git status --short` shows no `.pi/` file and no captured live
      inventory in the stage (only the three script files + plan.md are staged;
      `/tmp/var1044-devices.json` — the live capture with real UDIDs — is never
      committed)
- [x] Phase 3: `make format` then `make lint` — 0 violations, 0 serious, no
      Swift regressions (no Swift files touched)

## Manual Verification Items (from the plan)

The local watch's tunnel is currently down, and the unvalidated hardware merge
gate (M4) is a real-watch install that cannot complete until the watch is on the
wrist. Confirm each of these before marking the PR ready:

- [ ] **M1 — `RUN_WATCH=0`**: `RUN_WATCH=0 ./scripts/run-devices.sh` → output
      contains no line mentioning a watch, no `Debug-watchos` build, exit
      code as before this change.
- [ ] **M2 — watch discovered but tunnel down** (this Mac's state today):
      `RUN_WATCH=1 RUN_MAC=0 ./scripts/run-devices.sh` → prints
      `==> Discovering paired Apple Watches…`, names `Alan's Apple Watch` as
      unreachable with the wrist/paired-iPhone hint, and prints **no**
      `Probe Watch S9` / `LocalTest Watch` / `CI Watch S11-local` line (the
      sims are excluded); the watch build still runs (the `Debug-watchos`
      product appears); exit 1.
- [ ] **M3 — saved-inventory replay**: `xcrun devicectl list devices -j
      /tmp/var1044-devices.json` then
      `DEVICES_JSON_IN=/tmp/var1044-devices.json RUN_MAC=0 ./scripts/run-devices.sh`
      → only watch name in the output is the real one; installed/launched if the
      tunnel is up, named unreachable otherwise. Never commit
      `/tmp/var1044-devices.json` — it contains real UDIDs and serial numbers.
- [ ] **M4 — happy path, watch on the wrist** (the merge gate): watch reachable,
      paired iPhone nearby and unlocked, both on this Mac's network →
      `RUN_MAC=0 ./scripts/run-devices.sh` → watch build succeeds, watch
      installed + launched, run ends `✅ … and 1 Apple Watch(es).` exit 0.
      **UNVALIDATED:** a direct `devicectl device install app` of a
      `SKIP_INSTALL=YES` companion-embedded watch bundle has never succeeded
      anywhere in this repo (design "Open Risks" item 1). If M4 fails with an
      unresolvable provisioning/install error, **stop and revisit design
      decision 1 (direct-to-watch install vs. companion relay)** — do not patch
      around it.
- [ ] **M5 — which launch flag form worked**: run prints the
      `⚠️ --activate was rejected … retrying without it…` warning only if the
      first form failed; the summary line `Watch launch flags:` shows the form
      that exited 0. Record it in the PR — the only proof for the watchOS
      flag-support unknown.
- [ ] **M6 — sad path**: watch taken off the wrist / paired iPhone locked →
      `RUN_MAC=0 ./scripts/run-devices.sh` → watch named unreachable with the
      wrist/iPhone hint, **zero** install attempts, exit 1.
- [ ] **M7 — new build is really on the wrist**:
      `xcrun devicectl device info details --device 6EF5C1CD-A890-559B-98D5-8F7F5A5A699A`
      shows the app installed.
- [ ] **M8 — the `RUN_WATCH × RUN_MAC` matrix** (stubs or the real Mac):
      0/1 → no watch output; 1/0 yes → watch built+installed+launched ✅ exit 0;
      1/0 no → watch named unreachable, exit 1, no install attempt; 1/1 yes →
      all four platforms ✅ exit 0; 1/1 no → macOS+iOS complete, watch
      unreachable, ❌ exit 1.
- [ ] `RUN_WATCH=0` produces no `==> Discovering paired Apple Watches…` line, no
      `Apple Watch` build, and no watch contribution to `failures`.
- [ ] Every printed failure message names both a cause and a next action (read
      the captured output of the matrix, not just the exit codes).
- [ ] `RUN_WATCH=1 RUN_MAC=0 ./scripts/run-devices.sh` with the real watch named
      unreachable is the expected local outcome today (tunnel `disconnected`);
      it must exit 1 and must not print a raw devicectl 4016.

### Final gate

- [ ] One full `./scripts/test.sh` via the `run-gate` skill (async gate
      subagent, managed worktree, multi-hour timeout) — `run-devices.sh` is not
      exercised by that gate, so the expectation is no new failures.
- [ ] `git rm DELETEME` and `git status --short` clean before the PR is marked
      ready (branch bootstrap artifact; see `AGENTS.md`).

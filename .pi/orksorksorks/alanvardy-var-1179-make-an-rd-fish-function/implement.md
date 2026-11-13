# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| —     | `2c3a908c` | chore: remove DELETEME marker (bootstrap cleanup) |
| 1     | `c7e47030` | Phase 1: IOS_TARGET=duo end-to-end in run-devices.sh |

Phase 1 is on the ticket branch `alanvardy-var-1179-make-an-rd-fish-function`
(`SingleThread` repo, pushed to origin).

Phase 2 is a separate repo/commit (dotfiles allows direct commits to `main`):

| Phase | Commit | Description |
|-------|--------|-------------|
| 2     | `1ba21e5` | feat(fish): add rd for the Duo-only run-devices mode |

Phase 2 is on `~/dev/dotfiles` `main` (pushed `98b4dc2..1ba21e5`), not the
ticket branch.

## Automated Checks
- [x] `bash -n scripts/run-devices.sh` passed
- [x] `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` passed
- [x] `bash scripts/test-run-devices.sh` passed, including the new
  `duo mode emits only the physical Duo`, `duo mode excludes the regular
  physical iPhone`, `flow: IOS_TARGET=duo installs only the iPhone Duo`
  (+ sub-checks: no sim boot, no watch build, no macOS build, skipped
  watch/macOS legs both reported) and `flow: IOS_TARGET=duo with no Duo
  fails fast`
- [x] `rg -n 'test-run-devices' Makefile scripts/test.sh` still returns nothing
  (no gate wiring needed)
- [x] `fish --no-execute ~/dev/dotfiles/fish/functions/rd.fish` reported no
  syntax error
- [x] No dotfiles test targets exist (`ls ~/dev/dotfiles` shows no
  `scripts/test.sh`)

Scope note: the `duo` filter reuses the existing `mode != "device"` branch
unchanged — no Python edit was needed (Phase 1 changed only
`scripts/run-devices.sh` + `scripts/test-run-devices.sh`; Phase 2 created only
`fish/functions/rd.fish`).

## Manual Verification Items (from the plan)
- [ ] With the physical Duo paired and reachable:
  `IOS_TARGET=duo ./scripts/run-devices.sh` builds/installs/launches only the
  Duo, prints `iPhone Duo (device): 1/1 launched, 0 unreachable`, and shows no
  simulator boot, no watch build, no macOS build.
- [ ] With the Duo unpaired/unreachable, `IOS_TARGET=duo ./scripts/run-devices.sh`
  exits non-zero with `No reachable iPhone/iPad found.` (or the unreachable
  message) without touching sim/watch/macOS.
- [ ] `IOS_TARGET=duo RUN_WATCH=1 RUN_MAC=1 ./scripts/run-devices.sh` still
  allows the watch/macOS legs (the opt-back-in path).
- [ ] From a SingleThread worktree, `rd` builds/installs/launches only the Duo
  and prints the duo summary (same result as
  `IOS_TARGET=duo ./scripts/run-devices.sh`).
- [ ] `functions rd` shows the function loaded from
  `~/.config/fish/functions/rd.fish`.

## Post-plan gate (parent / review step)
- [ ] Run the full CI-identical gate via the `run-gate` skill
  (`./scripts/test.sh`: build + lint + Periphery + unit + UI) once after the
  phases commit. The change is shell-only, so this is a regression check.
- [ ] `./scripts/test-run-devices.sh` is not part of `scripts/test.sh`; run it
  directly in the gate worktree as well.
- [ ] Confirm the ticket branch has no `DELETEME` before merge (it is already
  removed by `2c3a908c`) and that the dotfiles commit is on `main` (not the
  ticket branch) — verified: dotfiles `1ba21e5` is on `main`.

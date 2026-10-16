---
name: run-gate
description: Run the full CI-identical test gate (./scripts/test.sh) as ONE dedicated async gate subagent in a managed worktree. Use when the full build + lint + Periphery + unit + UI gate must run after phases commit — never nohup it ad-hoc and never have phase subagents re-run it.
---

# Run Gate (SingleThread)

The full gate is `./scripts/test.sh` — format, lint, build, Periphery, unit +
UI tests across iPhone/iPad, plus watch. It is **multi-hour** and
single-xcodebuild-at-a-time, so it runs exactly once, as a **dedicated async
gate subagent** that the parent launches after phases commit. Do **not**
`nohup … > /tmp/gate.log 2>&1 &` it ad-hoc, and do **not** let phase subagents
re-run it (they exceed run caps and orphan unverified changes).

## Why a gate subagent, not `nohup`

- **Watchdog built in** — the subagent monitors its own run: detects a stalled
  log, kills orphaned `xcodebuild`/`xctest`, handles `Busy`/`RequestDenied`,
  and returns a structured verdict instead of leaving a silent stale log.
- **Worktree isolation** — the gate runs in a managed git worktree branched
  from the branch tip, so you can keep editing the main tree without perturbing
  the gated commit. This fixes the "tree moves under the gate" validity problem.
- **Completion notification** — the parent is told when it finishes instead of
  polling `/tmp/gate.log`.

## When to launch

- After all phases have **committed** to the current branch. The worktree
  branches from the branch tip, so **uncommitted changes are NOT gated** —
  commit first.
- **Once per merge.** If you make further commits during the run, they are NOT
  covered by that gate — either wait for it or record that it covered an
  earlier commit (`git rev-parse --short HEAD` at launch).
- Run `make format` then `make lint` in-line first (fast), so the slow gate
  doesn't burn an hour on a format/lint failure you could catch in seconds.
- A `worktree: true` lane **refuses to launch unless the source checkout is
  clean** (untracked files count; `.pi/subagents/` does not), failing with
  *"worktree isolation requires a clean git working tree"*. Commit everything
  first, including `.pi/orksorksorks/<branch>/` artifacts and the `DELETEME`
  removal.
- **When the branch is checked out in a worktree another writer has dirtied**,
  do not commit or stash their work and do not ask them to stop. Pass an
  explicit `cwd:` inside `runs.run(...)` pointing at a *clean* checkout (the
  main tree will do), and pin the commit in the meta-prompt. The lane then
  branches from **that** checkout's branch — so without the pin you silently
  gate `main` instead of the ticket branch. This has happened; see the
  meta-prompt's step 1.
- Always pass `SIM='platform=iOS Simulator,id=<UDID>'` (this worktree's
  `.simulator_id`): the leftover local `Gate iPhone 17` sim collides with the
  name-only default destination.
- Pin the watch destination too: `WATCH_TEST_SIM='platform=watchOS
  Simulator,id=<26.5-UDID>'`, with the watch **unpaired**. A name-only
  `Apple Watch Series 11 (46mm)` resolves to watchOS 27.0 when both runtimes are
  installed (the 46 mm device exists only on 26.5), and pairing to the worktree
  phone makes the XCTest runner launch on a phone clone and fail.

## How to launch (ONE top-level subagent call)

Issue a single top-level `{ workflow: <true|"./gate-<branch>.js">, async: true }`
call that launches one `runs.run('gate', …)` child with:

- `agent: "delegate"` — inherits the parent model and has `bash`/`edit`/`write`
  (it needs `bash` to run the gate and watchdog it; it should not modify source).
- `worktree: true` — managed worktree branched from the branch tip; isolates
  source and `DerivedData/` so the parent can keep working.
- `timeoutMs` — multi-hour, well above the 30m default, e.g. `21_600_000` (6h).
  A gate is the one legitimate long-timeout child.
- `output` — a `gate.md` report path so the verdict is durable.

**The launch parameter is `workflow`** — not `worktree`, not `workflowScript`.
`worktree`, `cwd`, `output` and `timeoutMs` are `runs.run(...)` options, never
top-level call parameters; passing them without `workflow` fails with
*"Execution requires either { agent, task? } for one child or workflow (true, a
script path, or a named workflow resource)"*. Two shapes:

- `workflow: true` reads the ```js block **from the same reply**, which must
also carry visible text. A tool-call-only reply silently loses the block and
fails with *"The assistant message that issued this call has no text in the
session"*.
- `workflow: "./gate-<branch>.js"` reads a script file — `write` it first.
⭐ Prefer this: it survives an empty reply, and re-running the same launch is
just re-issuing the path. Use `./` or an absolute path; a bare name resolves as
a named workflow resource.

When a launch is rejected the error names the parameter at fault — fix that one
and retry **once**. A run of variants against the same failure is the
lane-infrastructure blocker the pi-subagents skill says to stop on and report,
not to keep re-sending.

The workflow `await`s the gate child and returns its verdict. Because the whole
workflow is `async: true`, the parent turn **yields and is notified on
completion** — it does not block.

Workflow body (top-level `await`; no nested async helpers):

```js
const result = await runs.run('gate', {
  agent: 'delegate',
  worktree: true,
  timeoutMs: 21600000,
  output: 'gate.md',
  task: `…meta-prompt below…`
});
return result;
```

## Gate subagent meta-prompt (the `task`)

```
You are running the full CI-identical gate for SingleThread in this worktree.

1. cd to the repo root and confirm you are on the COMMIT UNDER TEST — this
   meta-prompt names it, and the lane may have branched from a different
   checkout than you expect. If `git rev-parse --short HEAD` is not that commit,
   run `git checkout <sha>` (detached HEAD is fine) and confirm again with
   `git rev-parse --short HEAD`. Gating the wrong base has happened before: do
   not skip this.
2. Launch the gate detached from a temp script — your command tool is fish,
   which has no `nohup` and no `$!`, so `nohup … & echo $!` is rejected.
   `write` /tmp/gate-<branch>.sh:
   #!/bin/bash
   set -uo pipefail
   export SIM='platform=iOS Simulator,id=<UDID>'
   echo $$ > /tmp/gate-<branch>.pid
   exec ./scripts/test.sh > /tmp/gate-<branch>.log 2>&1
   Then launch it detached and record the printed pid:
   bash -c 'nohup bash /tmp/gate-<branch>.sh >/dev/null 2>&1 & echo $!'
   On any `fish:` rejection, do not retry a variant — go through /tmp.
3. Watchdog with SHORT-LIVED bash calls — one `sleep 60` + `wc -c <log>` per
   turn, never a single long-open command (a 240s-open bash call trips the
   needs-attention controller and wedges the lane). If the log is stalled, kill
   orphaned xcodebuild/xctest **that belong to this lane** — check the command
   line and cwd first: another pi session may be running its own tests on a
   different simulator, and killing theirs corrupts their run. Check for a crash
   dump (.ips under ~/Library/Logs/DiagnosticReports). On Busy/RequestDenied, xcrun simctl
   shutdown all + kill stragglers, then restart the gate — **at most ONE clean
   restart**, then return FAIL with the log path. ANY Periphery finding outside
   the pre-annotated known list is report-only: never a restart trigger.
4. On completion capture the exit status and tail. Return a structured verdict:
   PASS, or FAIL with the failing suite(s) and the log path
   (/tmp/gate-<branch>.log). State explicitly whether the **Periphery** stage
   passed: it is stage-fatal and runs before every test stage, so a Periphery
   FAIL means the suite result is *unknown*, never green. List failing cases by
   name. If two UI-stage contention failures recur, stop re-running locally —
   CI is authoritative.
5. This is a read/verify lane: do not modify source files. Clean up orphaned
   processes before finishing.
```

## Triage a FAIL before you debug it

A stage-fatal FAIL — Periphery especially, which precedes every test stage — is
often **pre-existing on main** and merely *surfaced* by a rebase onto it. Check
provenance before touching any code:

```bash
git log --oneline -3 -- <file>            # whose commits introduced it
git diff --stat main -- <file>            # empty = identical to main, so not yours
git log --oneline <base>..HEAD -- <file>  # empty = none of your commits touch it
```

If the file is main's and none of the branch's commits appear in its history,
the branch did not cause it. Report it and decide explicitly: fix main's code
here, or leave it and say the gate is red for a main-origin reason. Periphery
findings also split by toolchain — Xcode 27 misses `$`-projection-only `@State`
while CI on 26.6 counts it used — so check the `periphery` skill before
concluding a finding is a regression.

## While it runs

- Do **not** run any other tests in the same window — one `xcodebuild` at a
  time still holds. Worktree isolation protects the source, not the machine;
  the simulator/DerivedData exclusion window is unchanged.
- You may keep editing the main tree; the gated commit is pinned by the
  worktree.

## Retrieving the result

- Read the run's saved output under its own `subagent-artifacts/`
  (`*_output.md` — the `output` you set), the `outputPathMapping` returned at
  launch, or `subagent({ action: 'status' })`. Never mine
  `/var/folders/.../async-subagent-runs` temp dirs.
- A failure your diff didn't touch is likely pre-existing on `origin/main` —
  verify with git blame / CI history before debugging.

## Teardown (required)

The gate is a read-only lane, so its worktree is disposable the moment the
verdict is recorded. Remove it — do not leave it behind (they accumulate to
tens of GB under `<repo-parent>/worktrees/`):

```fish
pi_worktree_clean --dry-run   # review the candidates
pi_worktree_clean             # remove clean, idle lanes
```

To remove only this run's lane: `worktree_remove <worktree-path>` (this also
deletes its `.simulator_id` simulator and closes its herdr workspace). The
`pi-worktree-cleanup` skill explains the guards — why only clean, idle,
non-cwd lanes are removed and why a branch with unique commits is kept.

## After two UI-stage contention failures

Stop re-running locally. CI is authoritative — push and let
`.github/workflows/ci.yml` decide.

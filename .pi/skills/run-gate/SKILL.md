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

## How to launch (ONE top-level subagent call)

Issue a single top-level `{ workflowScript, async: true }` call that launches
one `runs.run('gate', …)` child with:

- `agent: "delegate"` — inherits the parent model and has `bash`/`edit`/`write`
  (it needs `bash` to run the gate and watchdog it; it should not modify source).
- `worktree: true` — managed worktree branched from the branch tip; isolates
  source and `DerivedData/` so the parent can keep working.
- `timeoutMs` — multi-hour, well above the 30m default, e.g. `21_600_000` (6h).
  A gate is the one legitimate long-timeout child.
- `output` — a `gate.md` report path so the verdict is durable.

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

1. cd to the repo root and confirm you are on the branch tip
   (git rev-parse --short HEAD).
2. Run the gate in the background of YOUR OWN bash so you can watch it:
   nohup ./scripts/test.sh > /tmp/gate-<branch>.log 2>&1 & echo $!
   If the default iPhone 17 name destination is ambiguous, pin it:
   SIM='platform=iOS Simulator,id=<UDID>' ./scripts/test.sh
3. Watchdog: every ~60s confirm the log is still growing. If it is stalled,
   kill orphaned xcodebuild/xctest and check for a crash dump (.ips under
   ~/Library/Logs/DiagnosticReports). On Busy/RequestDenied, xcrun simctl
   shutdown all + kill stragglers, then restart the gate (up to 2 contention
   retries).
4. On completion capture the exit status and tail. Return a structured verdict:
   PASS, or FAIL with the failing suite(s) and the log path
   (/tmp/gate-<branch>.log). If two UI-stage contention failures recur, stop
   re-running locally — CI is authoritative.
5. This is a read/verify lane: do not modify source files. Clean up orphaned
   processes before finishing.
```

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

## After two UI-stage contention failures

Stop re-running locally. CI is authoritative — push and let
`.github/workflows/ci.yml` decide.

# Session Learning Report

**Session reviewed**: `/Users/vardy/.pi/agent/sessions/--Users-vardy-dev-alanvardy-var-643-crash-report--/2026-08-21T01-57-31-763Z_01a02209-a1f3-702b-a02f-d682b6ab379d.jsonl`
(QRSPI decompose + design setup for VAR-643 "Crash report", 99 messages, 01:57–02:22). The current working turn also tripped the legacy `subagent({tasks:[…]})` form.

---

## Wrong Turns

1. **QRSPI design-branch convention reverse-engineered over ~10 turns** (severity: high) — The decompose prompt's step 4 ("artifact directory: `.pi/qrspi/<git branch>/`") is ambiguous when a design subtask is involved. The agent first wrote `task.md`/`questions.md` under `.pi/qrspi/alanvardy-var-643-crash-report/`, then after user approval spent ~12 minutes (turns ~02:09–02:21: `git branch -a`, `git log`, `git ls-tree` across VAR-621/635/636/637/638, several `linear issue view` calls) reverse-engineering that design work belongs on a **separate child-subtask branch** (`-644-qrspi-design-crash-report`), then `mv`'d the artifacts and re-committed. Corrected only by archaeology of prior design subtasks (VAR-635→637, VAR-621→636). Nothing in `AGENTS.md` documents this.

2. **Stale root-level `research.md` + `DELETEME` misled task discovery** (severity: high): At session start (turns ~01:57:45–01:58:09) the agent twice read a root `research.md` — a 13 KB leftover "DynamicTypeSize" note from VAR-628 — and spent turns reconciling why it didn't match the `-643-crash-report` branch, plus `cat DELETEME`. Corrected only when `linear issue view "VAR-643"` surfaced the actual crash log. Task research belongs in `.pi/qrspi/<branch>/research.md`, not repo root.

3. **Repeated bash-isms in the fish shell** (severity: medium): A bash `for id in …; do …; done` loop (turns `a0da56e4`) and a `gh pr create --body "$(cat <<'EOF' …)"` heredoc (turn `c57fa92c`) both failed with fish errors, forcing re-runs. The "no heredocs / use fish `for … end`" convention lives only in the *home* `~/AGENTS.md` (lines 5–14) and the `fish-shell` skill — not in the project `AGENTS.md` the agent was reading.

4. **Subagent API guess `schedule_spawn` + legacy `{tasks:[…]}`** (severity: low): `subagent({action:"schedule_spawn"})` errored (turn `98e60faa`), and the workflow prompt's own `subagent({tasks:[…]})` example is superseded by `workflowScript` — the tool rejected it this session. Both were self-correcting via tool error messages; not repo-fixable.

---

## What Worked Well

The core technical work was clean: the agent quickly diagnosed the crash (a Swift 6 `@MainActor`-isolated `withCheckedContinuation` resumed from a non-main TCC callback queue → `_dispatch_assert_queue_fail`), read the actual crash site `SingleThread/ReminderDictation.swift`, dispatched a codebase-locator appropriately, and produced five genuinely neutral research questions. Once the VAR-636/637/638 precedent was found, setup (VAR-644 subtask → `-644-qrspi-design-…` branch → PR #83) matched it exactly, including forking from `origin/main`.

---

## AGENTS.md Audit

- **Move to skill**: lines 3–41 **"Build & Test"** → skill `build-and-test` — pure invocation reference (simulator names, `xcodebuild` incantations, `make` targets, `scripts/test.sh`); never used in this decompose/design session.
- **Move to skill**: lines 128–144 **"Dead Code Detection (Periphery)"** + **"Accessibility Testing"** → skills `periphery` / `accessibility-testing` — situation-specific, unused this session.
- **Consider trimming**: lines ~148–155 **"Compiler Warnings"** — the historical backstory ("This was previously a command-line flag … known Apple bug") could shrink to the operative fact: `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` is set project-wide.
- **Consider trimming**: lines 13–39 (the three full `xcodebuild` blocks) — largely redundant with the `make` targets and `scripts/test.sh` one-liners immediately below; keep only the simulator-name/destination notes.
- **Keep as-is**: lines 42–52 **"Concurrency Model"** — this is the section that actually supported the correct crash diagnosis.

---

## Bash Script Candidates

- None of the skills exercised this session compress cleanly into a bash script: `linear` is declarative CLI gotchas (`--limit 0` default, `create` has no `--json`, archive-only-via-GraphQL), `fish-shell` is syntax conventions, `bear` is a reference card. A thin wrapper around `linear` branch-name→`issue view` / `issue create` is possible, but the value is in the caveats, not the plumbing.

---

## Recommendations

1. **`.pi/skills/qrspi/SKILL.md`** — add a project QRSPI skill documenting the artifact layout (`.pi/qrspi/<branch>/` with `task.md` → `questions.md` → `research.md` → `design.md` → `plan.md` → `structure.md`), the decompose/research/design/plan phase flow, and the key rule that a **design phase runs as a child subtask** (e.g. `QRSPI Design: …`) created via `linear issue create --parent <PARENT>`, on its **own branch named by Linear's `branchName`**, with artifacts under the **design branch's** directory, forked from `origin/main`, and a **draft PR with "design" in the title**. (priority: high)
   - Evidence: Wrong turns #1 and #2 — ~14 minutes and a re-commit spent reverse-engineering this from git + Linear history.

2. **`AGENTS.md`, near top (Project Layout or a short "Workflow" section)** — add 2–4 lines documenting the QRSPI design-subtask/branch/PR convention, and that the current-task `research.md` lives under `.pi/qrspi/<branch>/` (so a future agent doesn't trust a stale root-level `research.md`). (priority: high)
   - Evidence: Wrong turns #1 and #2.

3. **`AGENTS.md`, top** — add a one-line note "Shell environment: this tool runs fish (not bash); no heredocs — use the `write` tool", mirroring `~/AGENTS.md` so it's co-located with the build commands. (priority: medium)
   - Evidence: Wrong turn #3 (two fish errors in this repo).

4. **Remove `research.md` and `DELETEME`** from repo root (or gitignore them) — they are stale scratch/former-task artifacts that misled task discovery. (priority: medium)
   - Evidence: Wrong turn #2.

---

## Residual Risks

- Turn numbers are approximate (messages are sequential JSONL entries; therapist-cited message IDs/timestamps are the precise anchor).
- Findings #1 and #2 share one root cause (QRSPI artifact placement ambiguity); a single `qrspi` workflow doc addresses the majority of the wasted effort.
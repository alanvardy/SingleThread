# QRSPI Task Workflow

QRSPI is the multi-phase workflow used to decompose a complex task into
research questions, research them, and produce a design + plan before
implementation. This repo runs it through the `.pi/qrspi/` directory and one
or more Linear tickets.

## Phase flow

```
decompose (1_qrspi)
  → research (2_research)
  → design (3_design / /3_plan)
  → plan (4_plan)
  → implementation (on the main ticket's branch)
```

Each phase writes a file into a `.pi/qrspi/<branch>/` directory
(`task.md`, `questions.md`, `research.md`, `design.md`, `plan.md`,
`structure.md`).

## Key rule: no subtasks, no child PRs — everything on the main ticket's branch

The full QRSPI cycle (decompose → research → design → plan → implementation)
runs on the **main ticket's branch**, in a single Linear ticket. Do **not**
create subtasks or separate child branches/PRs for the design phase.

1. Work is done on the main ticket's own branch (Linear's authoritative
   `branchName`: `linear issue view "<ID>" --json` → `.branchName`).
2. **Artifacts live in** `.pi/qrspi/<main-ticket-branch>/` — the directory is
   named after the main ticket's branch, never a design/child branch.
3. There is **one PR** for the whole task (the feature PR). The QRSPI artifacts
   are committed to that same branch and included in that PR.
4. No `--parent` subtickets and no separate "design" draft PRs.

## Decompose phase specifics

- Decompose a task into **3–7 neutral, fact-seeking research questions**.
- Write `task.md` (what's being built, brief) and `questions.md` (neutral
  questions that target different codebase areas, with a `## Context` that
  never leaks the goal).
- Present questions to the user for approval before finalizing.

## Research phase specifics (2_research)

Research answers the neutral fact-seeking questions in `questions.md` with
facts, `file:line` references, and observed patterns. It is a documentation
task: describe what exists, never propose fixes or solutions.

- **Answer small questions directly.** When a question resolves to a few small
  files (1–3 reads each, in one codebase area), read the source and cite
  `file:line` inline. Don't spawn a per-question subagent for a tractable
  codebase — reading is faster and more reliable than a fan-out.
- **Fan out only when warranted.** Spawn one subagent per question only when
  the questions span materially different codebase areas or need large
  traversal. For a change confined to one component, prefer targeted reads.
- **Dispatch fallback.** If a named agent type (`codebase-analyzer`,
  `codebase-pattern-finder`, …) is unavailable, skip the fan-out entirely and
  go straight to targeted `read`/`grep`. Do not burn turns discovering that a
  requested archetype doesn't exist.
- **Consume fan-out output.** If you do spawn agents, read their persisted
  results and synthesize from them — do not abandon the fan-out and re-derive
  the whole research from scratch.
- **Verify before finishing.** Before marking `2_research` done, grep the
  draft `research.md` for `file:` tokens and confirm each `file:line` resolves
  to real source.

## Artifact layout

The full progression for a single task:

```
.pi/qrspi/<main-ticket-branch>/
├── task.md
├── questions.md
├── research.md
├── design.md
├── plan.md
└── structure.md
```

The `2_research`, `3_design`, and `4_plan` phases each write their artifact
into this same directory. All research for the current task lives **here**,
not at the repo root — a root-level `research.md` is stale scratch from an
earlier task and should not be trusted as current-task context.
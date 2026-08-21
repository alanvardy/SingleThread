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

## Key rule: design phase runs on a SEPARATE child subtask

When the main ticket needs a design phase, it does **not** run on the main
ticket's branch. Instead:

1. **Create a child subtask** under the main ticket:
   `linear issue create --no-interactive --parent <MAIN-ID> --team VAR -p 4 -t "QRSPI Design: <slug>" -d "..."`
2. The design subtask has its **own branch**, named by submitting Linear's
   authoritative `branchName` field:
   `linear issue view "<ID>" --json` → `.branchName`.
3. **Artifacts live in a directory named after the DESIGN branch**, not the
   main ticket's branch:
   `.pi/qrspi/<design-branch>/task.md`, `…/questions.md`, …
4. The design branch forks from `origin/main` (skip the main ticket's WIP
   commits, e.g. DELETEME).
5. Open a **draft PR** targeting `main` with **"design" in the title**:
   `gh pr create -B main -H <design-branch> --title "design: …" --draft`

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

The full progression for a single task's design phase:

```
.pi/qrspi/<design-branch>/
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
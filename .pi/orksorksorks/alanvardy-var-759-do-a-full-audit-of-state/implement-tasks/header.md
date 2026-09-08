# {PHASE} Implementation Task — SingleThread State Audit (VAR-759)

You are implementing {PHASE} of the QRSPI implementation plan for the SingleThread repo at
`/Users/vardy/dev/alanvardy-var-759-do-a-full-audit-of-state` (branch
`alanvardy-var-759-do-a-full-audit-of-state`).

## Shell environment (IMPORTANT)
The command tool runs **fish** — compound commands, `VAR=$(...)`, heredocs and loops fail.
Write `/tmp/x.sh` with the write tool and run `bash /tmp/x.sh`. On a `fish:` rejection stop —
do not retry variants. Use `set VAR (cmd)` and `$status` for simple cases.

## Context
This ticket (VAR-759) is a **read-only state audit**. NO app code changes of any kind land in
this ticket. The work product is a set of audit artifacts under
`.pi/qrspi/alanvardy-var-759-do-a-full-audit-of-state/audit/` plus shell verifier scripts.
Do not modify any Swift file, project file, test target, or non-audit source. If you find an app
bug worth noting, record it in your final report — do not fix it.

## Primary documents — READ THESE FIRST
1. `.pi/qrspi/alanvardy-var-759-do-a-full-audit-of-state/plan.md` — read it FULLY. Your phase
   section is duplicated verbatim below and is your scope.
2. `.pi/qrspi/alanvardy-var-759-do-a-full-audit-of-state/research.md` — the research data source
   (Q1–Q7) you compile from. **Re-verify every line number against the actual source files at
   implementation time** — research/plan may have drifted.
3. `.pi/qrspi/alanvardy-var-759-do-a-full-audit-of-state/structure.md` and `design.md` —
   background on the audit's layer model and decisions.

## Working rules
- **Read every source file you cite before writing anything.** Never trust plan/research line
  numbers blindly — verify each `file:line` and the exact source text yourself.
- The `audit/` directory already exists with earlier phases' deliverables (Phase 1 created
  `factbase.tsv`, `verify-citations.sh`, `verify-citations-self-test.sh`; later phases add more
  files). ADD your phase's deliverables. Do not rewrite other phases' deliverable files except:
  `factbase.tsv` MAY gain NEW rows for file:line citations you newly introduce (Phases 2–5 do
  this — keep the file well-formed, tab-separated, header intact, and `verify-citations.sh`
  green). Never delete or edit existing rows' lineText.
- Do not refactor, clean up, or "improve" app code you encounter. Note anything noteworthy in
  your final report.
- **TSV byte-exactness**: `verify-citations.sh` compares `sed -n '<line>p' <file>` with your
  `lineText` using `!=`. Your `lineText` must be **byte-for-byte identical** to the source line,
  INCLUDING leading/trailing whitespace. Before using a line in a tab-separated file, check it
  for TAB characters (`sed -n '<line>p' <file> | grep -P '\t'`) — a tab in a line breaks the TSV;
  pick a different line for that row or drop it if a clean line cannot be found.
- When plan.md shows a naive code draft followed by a corrected version (e.g.
  `verify-citations.sh`, the self-test script), **implement the corrected version**.
- Order of operations: read sources → create/modify deliverables → run the phase's Automated
  verification commands → fix failures → flip the applicable `- [ ]` checkboxes in plan.md to
  `- [x]` → commit → push → report.

## Verification tooling note
The verifier scripts and greps run from the repo root; the plan writes commands like
`bash audit/verify-citations.sh` — run them as `bash
.pi/qrspi/alanvardy-var-759-do-a-full-audit-of-state/audit/verify-citations.sh` (or `cd` first
from a script). Make sure every run is from a directory where the paths resolve.

----
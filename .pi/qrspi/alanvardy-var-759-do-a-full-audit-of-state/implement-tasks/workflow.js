// VAR-759 sequential phase implementation workflow.
// Launches Phase 1..5 one at a time as `worker` subagents, each following its
// task instruction file; awaits each before starting the next.
// Stops early if a child reports structuredOutput.verdict === "blocked".
const TASK_DIR = "/Users/vardy/dev/alanvardy-var-759-do-a-full-audit-of-state/.pi/qrspi/alanvardy-var-759-do-a-full-audit-of-state/implement-tasks";

const SCHEMA = {
  type: "object",
  properties: {
    verdict: { type: "string", enum: ["ok", "blocked"] },
    phase: { type: "integer" },
    sha: { type: "string" },
    status: { type: "string" },
    note: { type: "string" },
  },
  required: ["verdict", "phase"],
  additionalProperties: true,
};

function mkTask(n) {
  return (
    "Execute every instruction in the task file " + TASK_DIR + "/P" + n +
    ".md — read it fully before acting. The command tool runs fish: compound commands, " +
    "VAR=$(...), heredocs and loops fail — write /tmp/x.sh and run bash /tmp/x.sh. " +
    "This ticket is a read-only state audit: do not modify Swift, project, or test files. " +
    "After committing and pushing, end your reply with exactly one line: " +
    "PHASE_RESULT phase=" + n + " sha=<full sha> status=<ok|issue|blocked> note=<one-line summary>. " +
    "Also emit structured output with verdict 'ok' on success, or verdict 'blocked' only if you " +
    "hit a fundamental, unresolvable mismatch between the plan and the codebase (phase, sha, " +
    "status, note fields alongside)."
  );
}

function runPhase(key, n, timeoutMs) {
  return runs.run(key, {
    agent: "worker",
    task: mkTask(n),
    context: "fresh",
    output: key + ".txt",
    timeoutMs: timeoutMs,
    outputSchema: SCHEMA,
  });
}

function isBlocked(r) {
  return !!(r && r.structuredOutput && r.structuredOutput.verdict === "blocked");
}

const r1 = await runPhase("phase1", 1, 7200000);
if (isBlocked(r1)) {
  return { stoppedAt: 1, phase1: r1.outputReference };
}

const r2 = await runPhase("phase2", 2, 5400000);
if (isBlocked(r2)) {
  return { stoppedAt: 2, phase1: r1.outputReference, phase2: r2.outputReference };
}

const r3 = await runPhase("phase3", 3, 5400000);
if (isBlocked(r3)) {
  return { stoppedAt: 3, phase1: r1.outputReference, phase2: r2.outputReference, phase3: r3.outputReference };
}

const r4 = await runPhase("phase4", 4, 5400000);
if (isBlocked(r4)) {
  return { stoppedAt: 4, phase1: r1.outputReference, phase2: r2.outputReference, phase3: r3.outputReference, phase4: r4.outputReference };
}

const r5 = await runPhase("phase5", 5, 5400000);

return {
  stoppedAt: 0,
  phase1: r1.outputReference,
  phase2: r2.outputReference,
  phase3: r3.outputReference,
  phase4: r4.outputReference,
  phase5: r5.outputReference,
};
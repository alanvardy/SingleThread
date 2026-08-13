# Task for codebase-locator

You are a codebase documentarian researching an iOS/macOS/visionOS SwiftUI + SwiftData app at the repo root. Describe what EXISTS with precise file:line references. Do NOT suggest improvements, optimizations, or solutions. Do NOT read .pi/qrspi/*/task.md or any task/ticket/design docs. Read only the actual source and config files (SingleThread/*.swift, SingleThread.xcodeproj/project.pbxproj, Makefile, scripts/test.sh, .github/workflows/ci.yml, .swiftformat, .swiftlint.yml, AGENTS.md). Q7: Describe the build and CI pipeline: Makefile targets, scripts/test.sh contents, .github/workflows/ci.yml, and the formatting/lint rules in .swiftformat and .swiftlint.yml that apply to new code. Give file:line references.

## Acceptance Contract
Acceptance level: attested
Completion is not accepted from prose alone. End with a structured acceptance report.

Criteria:
- criterion-1: Return concrete findings with file paths and severity when applicable

Required evidence: review-findings, residual-risks

Finish with a fenced JSON block tagged `acceptance-report` in this shape:
Use empty arrays when no items apply; array fields contain strings unless object entries are shown.
`criteriaSatisfied[].status` must be exactly one of: satisfied, not-satisfied, not-applicable.
`commandsRun[].result` must be exactly one of: passed, failed, not-run.
`manualNotes` and `notes` are optional strings; an empty string means no note and does not satisfy `manual-notes` evidence.
```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "specific proof"
    }
  ],
  "changedFiles": [
    "src/file.ts"
  ],
  "testsAddedOrUpdated": [
    "test/file.test.ts"
  ],
  "commandsRun": [
    {
      "command": "command",
      "result": "passed",
      "summary": "short result"
    }
  ],
  "validationOutput": [
    "validation output or concise summary"
  ],
  "residualRisks": [
    "none"
  ],
  "noStagedFiles": true,
  "diffSummary": "short description of the diff",
  "reviewFindings": [
    "blocker: file.ts:12 - issue found, or no blockers"
  ],
  "manualNotes": "anything else the parent should know"
}
```
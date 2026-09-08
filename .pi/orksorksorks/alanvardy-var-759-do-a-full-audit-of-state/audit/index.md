# SingleThread State Audit — Assembled Report

## Artifacts

1. **[Fact Base](factbase.tsv)** — citation-verified source index. One row per declaration/read/write of every state value across all four targets, pinned to `file:line` + exact source text. Verified by `verify-citations.sh`.

2. **[Inventory](inventory.md)** — per-key tables (default, encoding, read/write sites, dual-read paths, targets) and store-mirror table (which `@Observable` property mirrors which persisted key; transient vs mirrored).

3. **[Clusters & Divergence](clusters.md)** — four combinatorial cluster matrices (completion-transition, branch ordering, entitlement gate, dictation) marking every combination reachable/unreachable/contradiction, plus 11 App Group vs `.standard` divergence sites.

4. **[Enum Assessment](enums.md)** — three concrete enum sketches for the highest-value clusters (completion-transition, entitlement gate, branch ordering) with advisory pointers for the remaining bare-Bool/Int clusters.

5. **[Findings](findings.md)** — severity-ranked findings (T1–T4) with evidence citations from the fact base, plus a prioritized action list mapping to deferred tickets.

## Verification

Run `bash audit/verify-citations.sh` from the `audit/` directory. Exit 0 means every cited `file:line` still matches source.

Run `bash audit/verify-citations-self-test.sh` to confirm the verifier catches deliberate corruption.

## Scope

This is a **read-only audit**. No code changes land in this ticket. All findings, enum sketches, and the action list inform a separately-ticketed refactor.
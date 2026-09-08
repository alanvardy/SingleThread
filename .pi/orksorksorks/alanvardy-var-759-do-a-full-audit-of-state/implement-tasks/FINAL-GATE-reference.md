
Before declaring the audit complete, run the final verification suite:

- [ ] `bash audit/verify-citations.sh` exits 0 (all citations pinned to source, no drift)
- [ ] `bash audit/verify-citations-self-test.sh` exits 0 (verifier catches corruption)
- [ ] Inventory cite-check passes: all `inventory.md` file:line refs ⊆ `factbase.tsv`
- [ ] Cluster matrices fully annotated: zero bare `undefined` cells (only listed open areas)
- [ ] Three enum sketches only; `replaces` fields resolve
- [ ] Findings tier ordering monotonic: T1 before T2 before T3 before T4
- [ ] `index.md` links all five artifacts
- [ ] `./scripts/test.sh` remains green (app is untouched by design)

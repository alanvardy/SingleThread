# Task

Fix the local full gate (`./scripts/test.sh`) so the Watch UI tests stage stops hard-failing on machines with **more than one watchOS runtime installed**.

**Symptom:** `WATCH_TEST_SIM` defaults to a *name-only* destination — `platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)` (`Makefile:11`, `scripts/test.sh:13`). With two runtimes present, xcodebuild normalizes a name-only spec to `OS:latest` (= watchOS 27.0, per this machine's evidence 2026-09-15), which has no `Series 11 (46mm)` device, so the destination resolves to nothing and the stage dies before any case runs with an opaque `Unable to find a device matching the provided destination specifier` error. `SIM` doesn't have this problem because it is UDID-pinned and pre-booted (`scripts/test.sh:50-71`); the watch destination has no equivalent resolution step. Impact: three consecutive full-gate restarts burned the gate subagent's restart budget with no verdict. CI is green (pins `id=` with a deterministic UDID, `ci.yml:262-306`) — this is local-only.

**Fix (⭐ per ticket):** mirror the existing iOS `.simulator_id` mechanism for the watch —
1. Add a `resolve_watch_sim_udid`-style helper (model on `resolve_sim_udid` at `scripts/test.sh:22-31`, which anchors the device name, picks the UDID in parentheses, and falls back leaving the destination unchanged) that prefers a UDID (`id=`) when the name is ambiguous across runtimes, and use it when consuming `WATCH_TEST_SIM` (watch build-for-testing at `scripts/test.sh:272`, UI tests at `:294`, watch unit at `:302`; `Makefile:98/:106`).
2. Add a fail-fast preflight (before the watch-stage invocation) that exits with a clear, actionable "no watch simulator matches <name>" message instead of the opaque xcodebuild destination error — covering the missing/ambiguous cases.
3. Keep the `WATCH_TEST_SIM` env override working; the default stays name-based and simply resolves to a UDID at runtime (optionally pre-boot the watch sim like `preboot_sim` at `scripts/test.sh:33-37`).

**Acceptance:**
- `./scripts/test.sh` with no `WATCH_TEST_SIM` override reaches and passes the Watch UI tests stage on this machine (two watchOS runtimes installed).
- A missing/ambiguous watch simulator fails fast with an actionable message.
- Existing single-runtime behavior (and CI) unchanged.

**Note:** No unit test is meaningful here (build-script/destination resolution) — verification is a full local gate run on this multi-runtime machine. Run `make format` + `make lint` before the gate, then the full `./scripts/test.sh`.

## Why SMALL

Single module (build-script territory: `Makefile` + `scripts/test.sh`, ~2–4 files), follows an existing in-file pattern end to end (`resolve_sim_udid` / `preboot_sim` / `.simulator_id` at `scripts/test.sh:22-71`) — A and B hold (approach already prescribed as ⭐ in the ticket, 0–2 unknowns). No schema/migration (C), no new subsystem and no convention/format risk — CI pins `id=` and never reads `WATCH_TEST_SIM`, so it is provably unaffected and the `WATCH_TEST_SIM` seam keeps working (D). No design sign-off pending — the ticket selected the durable option (E). No new test infrastructure; the gate run itself is the verification (F).

## Key files

- `scripts/test.sh` — `WATCH_TEST_SIM` default `:13` (comment `:11`); pattern to mirror: `resolve_sim_udid` `:22-31`, `preboot_sim` `:33-37`, iOS resolution+pre-boot `:50-71`; watch consumers `:252`, `:272`, `:294`, `:302`.
- `Makefile` — `WATCH_TEST_SIM ?=` `:11` (comment `:9`); consume at `:98` (watch-ui-test), `:106` (watch-test); iOS `.simulator_id` wiring `:4-5` as the model.
- Optional: `scripts/simverify.sh` (`:5-7` sim vars, iOS-only boot `:14-19`) if it gains a watch path.
- Doc-only (optional): `.pi/skills/simulator-pairing/SKILL.md` if the resolution/pairing notes change.
- Context: `.github/workflows/ci.yml:262-306` already pins `id=${{ env.WATCH_UDID }}` — do not touch CI.
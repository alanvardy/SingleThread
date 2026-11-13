# Done

- **Branch / head SHA**: `alanvardy-var-1175-run-the-regular-iphone-and-ipad-legs-in` / `2631b6875afa5afc88c1ce55a42977520cab8a31` (`fix: scope ControlPlateModifier to macOS`)
- **Mechanical checks**:
  - `bash -n scripts/run-devices.sh` and `scripts/test-run-devices.sh`: pass.
  - `./scripts/test-run-devices.sh`: pass (32 checks).
  - `make lint`: pass (0 violations).
  - `make format`: pass (no changes after the fix).
  - `git diff --check`: pass.
  - Shellcheck: pass except pre-existing `SC1111` unicode-quote warning at `scripts/run-devices.sh:124` (identical on `main`).
  - Full CI-identical gate on `0d362077`: executable stages **PASS** — iOS UI 6/6, watch UI 1/1, watch unit 81/81, mac unit 862/862; warning-check 20/20; format/lint/build passed. The original gate aborted at Periphery with 2 findings in `ControlPlateModifier.swift`; the test-stage verdict was obtained via the authorized Option B continuation with Periphery skipped.
  - **Periphery false positive fixed** in `2631b687`: `SingleThread/ControlPlateModifier.swift` is now compiled only on macOS, where its `.controlPlate()` usages live. `periphery scan --strict -- -destination "platform=iOS Simulator,id=BD205AB3-B188-48F1-B45A-3EE33B972ABB"` now reports **no unused code**. The macOS build also succeeds. The full gate was **not rerun** after this fix; targeted checks cover the changed file.
- **Review outcome**: No blockers. The bounded reviewer found no merge-blocking issue. Two non-blocking P1s remain deferred to the user: (1) `devicectl list` failure still hard-aborts `IOS_TARGET=sim` before the simulator legs run; (2) a set-but-nonmatching `DUO_DEVICE_ID` silently drops the Duo with no notice. Optional P2s noted: validate `IOS_TARGET` (`sim|device`), fix the empty `SIM_WATCH` notice text, adjust summary wording for device/no-Duo cases, mirror `test.sh`'s stale `.simulator_id` warning, wire the new offline harness into CI, and remove the walking-skeleton header wording. No P1/P2 fixes were applied because the review ran without `autofix`; the user's [1]/[2] menu decision remains open.
- **Remaining manual items**:
  - Apply the P1s (and optionally P2s) if desired.
  - Run the full gate again for the new fix commit if a complete post-fix verdict is required.
  - Run `./scripts/run-devices.sh` against real hardware/simulators; the sim/Duo/watch/macOS legs were verified offline via stubs only.
  - Complete the manual verification items in `plan.md`/`implement.md`.

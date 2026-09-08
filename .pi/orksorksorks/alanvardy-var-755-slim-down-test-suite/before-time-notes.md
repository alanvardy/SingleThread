# Before-Test Timing Capture (Phase 1)

Captured for Phase 6 comparison (targeted wall-clock before/after).

- **Date**: 2026-09-01 20:51:21 -0700 → 20:53:25 -0700
- **SIM**: `platform=iOS Simulator,id=D7AC0D41-275E-47C5-B603-BC7FA08D1BB4` (iPhone 17)
- **Command**: `xcodebuild -scheme SingleThread -only-testing:SingleThreadTests -destination "$SIM" -derivedDataPath DerivedData test`
- **Build state**: cold (no `DerivedData/` existed before this run)
- **Elapsed wall time**: **124 seconds** (exit code 0, all tests green)
- **Notes**: Full build + test. For the Phase 6 after-measure to be comparable it must re-pin the same SIM id and use the identical command form; if DerivedData already contains a build at that point, the after number will be build-cached and should be noted as such.
- **Structural snapshot at this point**: see `before.json` in this directory (unit_tests 552, expectation mean 1.83, launches 35, settle_sleeps 5, forced_400ms 4, xcodebuild 14 file-wide).

# VAR-645: UI tests slow

The XCTest UI test suite (and to a lesser extent the unit test suite) can take
up to 15 minutes to run through CI and the local `scripts/test.sh` pipeline.

This ticket asks whether the UI and unit tests can be made to run faster —
specifically whether build/test artifacts from individual test runs can be
reused across runs, and whether the UI test suite can be split into parallel
parts. The goal is to reduce end-to-end test wall-clock time without weakening
coverage.
# Task — Speed up the test suite

Restructure how the local and CI test suites run to cut wall-clock time: (1) stop
the local full gate from running the 520 iOS unit tests on the iOS Simulator —
a duplicate of the native macOS pass that is ~10× slower — while keeping the
sim run in CI and making any truly iOS-only tests (EventKit etc.) skip cleanly
on macOS; (2) replace the 38 iOS+watch UI test methods with one launch-and-render
smoke test per platform, folding in or consciously dropping the a11y audit
coverage and going iPhone-only on the device matrix; (3) make the local unit
fast loop (`make test` / `--unit-only`) run natively on macOS.

Goal: ~10× faster local unit iteration and roughly 30–50 min shaved off local
and CI gate time, with zero net loss of native unit coverage and the
`--seed`/`--ui-testing` seams unchanged.
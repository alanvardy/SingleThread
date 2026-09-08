# Task — Testflight macOS (VAR-721)

SingleThread currently ships an iOS app (+ watchOS app and widget) that already
declares macOS as a supported platform and compiles for `platform=macOS` in CI,
but is not yet a runnable, distributable Mac app. This ticket gets the project
building and running for macOS locally (fixing whatever platform gaps that
uncovers), then sets up the path to distribute it via TestFlight for macOS.
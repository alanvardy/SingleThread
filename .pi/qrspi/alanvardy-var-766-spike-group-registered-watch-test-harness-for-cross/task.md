# VAR-766 — Spike: group-registered watch test harness for cross-container verification

Build a watch-side test harness that exercises the watch app with the App Group
"group suite" entitlement registered, so the cross-container read/write behavior
between the group suite and `UserDefaults.standard` can be verified for real.
Today the phone writes `completionCount` into the App Group suite
(`WatchAppViewModel.swift:186`) while the watch's `pushAll()` reads it from
`.standard` (`WatchAppViewModel.swift:161`); because `AppGroup.defaults` falls
back to `.standard` when the suite is unregistered, the divergence is
unverifiable on the current simulator setup.

This is a spike (audit follow-up, prerrequisite for T1.2 / T2.1). Acceptance is a
watch test that proves whether group-registered and `.standard` streams diverge,
with the harness reusable by successor tickets. Per AGENTS.md this requires a new
watch test target with full pbxproj object IDs, scheme TestAction wiring,
`-only-testing` entries, and Makefile/scripts/CI matrix entries — flagged
explicitly in the design phase.
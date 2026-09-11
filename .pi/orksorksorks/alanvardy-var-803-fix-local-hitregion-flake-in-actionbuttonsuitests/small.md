# Task

Fix the local-only `.hitRegion` accessibility-audit flake so the iOS UI-test suite passes on the local simulator. `ActionButtonsUITests.testActionButtonsAccessibilityAudit` fails locally with a `.hitRegion` audit failure, while CI passes because `.hitRegion` is excluded from CI's audit categories. AGENTS.md documents the pattern: "Local audit runs extra strictness categories (`.hitRegion`, `.dynamicType`) beyond CI's — a local hit-region failure can be local-only, not a CI break."

**Acceptance criteria**: the test either passes locally (fix the hit-region issue on the Complete/Skip button labels) **or** the local audit drops `.hitRegion` to match CI behavior. The test must not be a known-expected failure in local runs.

## Why SMALL

Criterion F holds: a single module (iOS UI test target), 0–2 unknowns, and the approach is already known and documented in AGENTS.md; no schema/migration; no new subsystem; no shared/persistence code; no design sign-off needed (the ticket specifies both accepted outcomes).

## Key files (from recon)

- `SingleThreadUITests/SingleThreadUITests.swift` — currently contains the sole iOS UI-test smoke (`testLaunchAndRenderSmoke`), which already restricts `performAccessibilityAudit` to `[.sufficientElementDescription, .trait]` (excluding `.hitRegion`/`.dynamicType`, with a comment noting the applied carve-out). Verify whether the flake surface still exists on this branch or was already collapsed by the earlier "Collapse the superseded UI surface" change (e46f94b0 is on `main`; `ActionButtonsUITests.swift` is gone from the tree).
- If the hit-region bug is to be fixed instead of dropped: the Complete/Skip button label rendering (per AGENTS.md, caption-sized SwiftUI buttons need `.padding` on the label — a `.frame(minHeight: 44)` doesn't expand the accessibility label)
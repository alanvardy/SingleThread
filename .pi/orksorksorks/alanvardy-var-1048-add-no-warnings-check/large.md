# Task

Add a check to `scripts/test.sh` that fails the CI gate if there are compile
warnings anywhere in the code, then resolve all existing warnings so the check
passes. This is the shared CI-identical gate every change runs through, so the
new check must be correct and green from day one.

## Why LARGE

CONVENTION_RISK + UNKNOWNS + CROSS_CUTTING: modifying the shared `scripts/test.sh` build/CI gate, plus the entirely open-ended "resolve all warnings" half whose scope (how many warnings, in which of the app/watch/widget/Core/test targets, and whether per-target pbxproj overrides are needed given `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` and the SPM package's `-suppress-warnings` conflict) is unknown and needs a recon/spike.
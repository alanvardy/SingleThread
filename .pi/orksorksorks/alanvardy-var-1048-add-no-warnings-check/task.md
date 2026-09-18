# Task

Add a check to `scripts/test.sh` that fails the CI gate if there are compile
warnings anywhere in the code, then resolve all existing warnings so the check
passes. This is the shared CI-identical gate every change runs through, so the
new check must be correct and green from day one.
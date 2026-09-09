# Research Questions

## Context

This research covers the configuration and security-tooling surface of the SingleThread iOS repository: the GitHub Actions workflow layout, test fixture data, repo-wide config conventions, the build/test gate, and external tooling conventions. Focus is on describing what exists and how it works, with file:line references, across .github/, the test suite, and root config files.

## Questions

1. Trace .github/workflows/ci.yml in detail: list every job (name, runner, matrix, needs), the full step sequence of each job with line numbers, how third-party GitHub Actions are referenced (pin style), any permissions blocks, concurrency settings, and which parts of the file duplicate or differ from scripts/test.sh and the Makefile.

2. Inventory secret-like or high-entropy string patterns across the repository that a secret scanner could flag, centering on the fixture files SingleThreadTests/TestFixtures.swift, SingleThreadTests/BackgroundTestFixtures.swift, and SingleThreadWatchTests/TestFixtures.swift, plus any other fixture or test-data files in the test suites (JSON payloads, base64 blobs, URLs with credentials, fake tokens or auth headers, payment-like strings). Report exact file:line references and the shape of each string, and whether any existing ignore/allowlist markers exist anywhere in the repository.

3. Map repo-wide configuration conventions: .gitignore contents, .mise.toml tool pins, .swiftlint.yml and .swiftformat configs, presence or absence of CODEOWNERS, SECURITY.md, .env file handling, any workflows or .github files other than ci.yml, and team or reviewer definitions referenced anywhere in the repo. Also describe the current git branch state: HEAD commit contents, the DELETEME file, and any commit history relevant to this branch.

4. Trace the build and test gate: the Makefile targets and scripts/test.sh pipeline (swiftformat, swiftlint, builds, periphery, each test suite with its invocation), how simulator destinations are pinned, and whether CI invokes these scripts or inlines commands. Produce a compact test-suite inventory: every test file path, framework used (Swift Testing vs XCTest), and platform gating or CI job that runs it.

5. Research gitleaks and Dependabot as external tools: what gitleaks default rules cover, the mechanisms for allowlisting (config file, inline comments, baseline, path scoping), the supported ways to run gitleaks in GitHub Actions (official action, docker image, binary download) and current stable version, its exit-code and SARIF behavior in CI. For Dependabot, document the dependabot.yml schema elements relevant to ecosystem, schedule, reviewer and assignee fields, open-pull-requests-limit, and how review fields behave on personal-account repositories where no org teams exist.
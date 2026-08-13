# Task

The GitHub Actions CI pipeline for SingleThread is slower than expected ("seems extra slow"). Find where time is actually spent — Xcode build, unit-test invocation, simulator boot, lint/format tool installation, and caching — and identify concrete changes that would make the CI test suite finish faster.

This is an investigation-first task: the deliverable is a clear account of the bottlenecks and a set of recommended changes, not necessarily a full implementation up front.

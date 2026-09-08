# Task — Slim down unit tests

The unit test suite (SingleThreadTests plus SingleThreadWatchTests) contains
duplicate and low-value tests that cost maintenance and run time without
proportionate coverage. Investigate where duplication and low-value tests
exist, and produce a concrete slimming plan (what to consolidate, what to
delete, what to keep) that reduces the suite while preserving meaningful
coverage. Deliver recommendations and implement the agreed slimming on the
main ticket branch.
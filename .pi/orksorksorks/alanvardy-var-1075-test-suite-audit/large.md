# Task

Audit the SingleThread codebase's test suite with parallel subagents: refactor
code to be as unit-testable as possible, find opportunities to write
additional valuable unit tests, and add them. The audit spans all modules
(SingleThread app, SingleThreadCore, watch app, widget, and the existing test
targets). Actively raise issues with the user when they are found.

## Why LARGE

CROSS_CUTTING + UNKNOWNS + CONVENTION_RISK + MULTI_MODULE. The ticket is an
open-ended codebase-wide audit rather than a localized change: the concrete
refactors and test opportunities are unknown until research discovers them,
and making shared/persistence code (ReminderStore, EventKit/AppGroup seams,
watch-sync values) more testable touches convention/ownership boundaries that
need design decisions and human sign-off. Scope and ordering must be
established before implementation.

## Key files

No pre-seeded targets — the audit determines them. Expect recon to cover
SingleThread/, SingleThreadCore/, SingleThreadWatch/, SingleThreadWidget/,
SingleThreadTests/, SingleThreadUITests/, SingleThreadWatchTests/, and the
existing test seams (AppGroup.defaults, InMemoryEventStore, `--seed`/`--ui-testing`
launch args) per AGENTS.md.
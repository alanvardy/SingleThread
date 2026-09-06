# Task — Prevent multiple test suite runs from clobbering each other

VAR-802 asks two questions: can multiple test suite runs in this repo
clobber each other, and is the risk currently serious enough to address?
The goal is to establish where and how test runs interfere (filesystem
artifacts, simulators, persisted UserDefaults state, CI caches) and, if the
risk warrants it, ship mitigation — serialization and/or state isolation
between concurrent runs for both local and CI test gates, following the
repo's existing test conventions.
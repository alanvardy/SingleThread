# Task

Investigate and fix a production Sentry "Fatal App Hang Fully Blocked" (issue
7821993169, culprit `SingleThreadApp.$main`) on SingleThread 1.4+21 / iOS 27.2.
The captured stacks contain **no SingleThread app frames on the hung main
thread** — only the Sentry ANR-detection thread (`monitorThreadCache` sleeping)
plus system and WatchConnectivity background threads — so the hang's root cause
is unidentified and must be diagnosed before a fix can be designed. The fix must
be backed by a unit test reproducing the hang condition (per repo policy for bug
fixes).

## Why LARGE

Matched triggers: **UNKNOWNS** (the hang's cause is unidentified; the crash
report has no app-code culprit frame, so a spike/repro investigation is needed
before any approach exists) and **CONVENTION_RISK** (the only in-app-adjacent
threads point at WatchConnectivity `WCContentIndex index` and file coordination
on the shared EventKit/App-Group persistence path). The decisive signal is the
missing root cause: with no known culprit and no dictated approach, neither
MEDIUM's M1 ("approach known, 0–2 unknowns") nor SMALL's A–B can hold.

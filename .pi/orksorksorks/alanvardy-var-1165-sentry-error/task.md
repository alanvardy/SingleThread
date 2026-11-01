# Task

Diagnose and fix a production Sentry "Fatal App Hang Fully Blocked" (issue
7821993169, culprit `SingleThreadApp.$main`) on SingleThread 1.4+21 / iOS 27.2.
The captured stacks contain no SingleThread app frames on the hung main thread —
only the Sentry ANR-detection thread plus system and WatchConnectivity
background threads — so the root cause is unidentified and must be established
before a fix can be designed. The fix must ship with a unit test that
reproduces the hang condition, per the repo's bug-fix test policy.

# VAR-748: Revisit ContentView file_length threshold (650→700) raised in VAR-743

ContentView.swift grew past the `file_length` warning (650) during VAR-743, so
the threshold was bumped to 700 as an out-of-scope workaround. This ticket
revisits that decision: either decompose ContentView so the threshold can be
restored to 650 (preferred), or explicitly accept 700 as the new ceiling —
with `./scripts/test.sh` green and appropriate test coverage either way.
Related symptom: ContentView's `body` modifier chain also hit a compiler
type-check timeout in VAR-743, worked around by extracting helpers
(`setBackgroundPinned`, settings-sheet write-back chain) rather than fixed.
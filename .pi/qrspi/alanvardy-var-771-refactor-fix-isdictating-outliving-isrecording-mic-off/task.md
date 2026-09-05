# Task

Fix a reachable state contradiction in the dictation flow (VAR-759 audit finding
T1.1): when dictation's transcribe phase ends, the mic is torn down
(`isRecording` → false) but `isDictating` stays true for the remaining
parse/add-reminder phases plus a ~1 s feedback sleep, so the iOS UI can render
the pulsing "Recording" indicator while the microphone is not capturing audio.
The goal is to pull `isDictating = false` into the recording-teardown path so
the UI never shows "Recording" when the mic is off, shipped with a unit test
asserting no state window where `isDictating=true ∧ isRecording=false` after
teardown, and with existing dictation-flow tests still green.
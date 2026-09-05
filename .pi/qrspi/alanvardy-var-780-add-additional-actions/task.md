# Task

The SingleThread app currently offers exactly two per-reminder actions on every
platform: complete and skip. This task adds an **"Additional actions"** toggle
to the Settings → Interface section (off by default). When enabled, the skip
button no longer acts directly — instead it presents a menu of three options:
**skip**, **reschedule**, and **delete**. The toggle must behave consistently
across iPhone, iPad, watch, and macOS. When the toggle is off, existing
behavior is unchanged.
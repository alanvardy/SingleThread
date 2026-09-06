# Task — Careful rescheduling recurring reminders (VAR-795)

Verify what happens to a recurring reminder's repeat rule when it is
rescheduled. If rescheduling erases the reminder's repeating nature, either
find a way to reschedule without erasing the repeat, or hide the reschedule
button for repeating reminders. Whichever path is chosen must ship with unit
test coverage; a UI test is only justified if the behavior manifests at the UI
layer.
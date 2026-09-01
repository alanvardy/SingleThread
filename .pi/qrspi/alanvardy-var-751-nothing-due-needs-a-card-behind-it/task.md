# Task: Nothing due needs a card behind it

The "Nothing due" empty state on the iOS reminder list is currently plain white text
on the background (unreadable in dark mode / over a photo). The goal is to give it a
card/plate behind it just like the reminder card so it stays readable, and to apply
the same treatment to the other "no more reminders" empty cases (the "All Done"
state on iOS, and the equivalent empty states on the watch and widget).

The fix is a pure UI change on the current branch (`alanvardy-var-751-nothing-due-needs-a-card-behind-it`),
following QRSPI. It must ship with unit + UI test coverage per the repo's testing
requirements.
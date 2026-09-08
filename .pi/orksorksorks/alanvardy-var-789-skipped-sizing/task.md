# Task — Skipped sizing

The reminder list has a card-presentation bug on iPad: when a reminder has been skipped enough times to show the "Skipped X times" nudge banner, the reminder card stretches to full row width instead of hugging its content — this does not happen on iPhone. Additionally, the card that appears after tapping the nudge banner (the skip-management sheet) is far larger than its content needs, with blank space above and below; it should be much smaller, comparable to the reminder card's footprint.

The fix should make the reminder card only as wide as necessary in all states, and make the post-skip sheet sized to its content. Must ship with unit and UI test coverage per repo conventions.
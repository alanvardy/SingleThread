# Task: Show code blocks (VAR-698)

Reminders in SingleThread can contain inline code (`` `code` ``) and multi-line
fenced code blocks (``` ``` ```) in both the title and the notes. Today those
backtick-delimited sequences render as literal, plainly-formatted text, making
code hard to read against surrounding prose.

Goal: format `code` (inline) and ```code blocks``` (fenced/multi-line) nicely —
distinct, readable code styling — wherever a reminder's title or notes are
displayed (iOS list, watch face, and widget).
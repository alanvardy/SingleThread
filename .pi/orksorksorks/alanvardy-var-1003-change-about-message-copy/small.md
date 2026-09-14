# Task

Change the About screen's developer credit copy in the SingleThread iOS app.
Replace the current text `Made with love by a lone developer` with the new
text `Made with ❤️ by a Canadian developer 🇨🇦`. Keep everything else
(bold/italic styling, layout, accessibility attributes on that Text) unchanged.

Update the existing unit test assertions in `AboutViewTests` that reference the
old copy so they assert the new string — the change is done only when those
tests pass (the About-view text is the reported symptom; tests must reproduce
and cover it). Run `make format` and `make lint` before committing.

## Why SMALL

Single module, exactly 2 files, trivial string-literal swap following the
existing pattern; 0 unknowns; no schema, no subsystem, no design decision;
tests needed are the existing local assertions only (A–F all hold).

## Key files

- `SingleThread/AboutView.swift` — the `Text("Made with love by a lone developer")` on line 28
- `SingleThreadTests/AboutViewTests.swift` — assertions on lines 19 and 37 (`bodyDescription` contains the old copy)
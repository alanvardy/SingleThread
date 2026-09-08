# Task: Deal with created reminders (VAR-702)

Running the test suite creates reminders in the developer's real Apple Reminders list, cluttering it up.

Goal: stop tests from polluting real reminder data. Candidate approaches from the ticket: mock out reminder usage entirely, or clean up created reminders after test runs. Any cleanup must be safe under parallel CI jobs (one suite must not delete another suite's reminders) — e.g. only delete reminders named "Test reminder" that are older than ~5 minutes.

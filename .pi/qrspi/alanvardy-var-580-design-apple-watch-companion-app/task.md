# Task

Produce a design document for adding an Apple Watch companion app to the
existing SingleThread iOS app. The design must cover how the watch app will
reuse the existing reminder logic (view the next incomplete reminder due
today-or-earlier, complete it, or skip it) and how the per-device "skipped
reminders" list — currently stored only in `UserDefaults.standard` on the
phone — will stay synchronized between iPhone and Apple Watch.

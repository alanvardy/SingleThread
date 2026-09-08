# Task

Add an Apple Watch companion app to the existing SingleThread iOS app that
exposes the same reminders functionality (view the next incomplete reminder due
today-or-earlier, complete it, or skip it). The watch app will share the
existing pure-logic components (skip-list resolution, notes formatting, date
filtering) with the iOS target and will keep the per-device "skipped reminders"
list synchronized between iPhone and Apple Watch, since that list currently
lives only in `UserDefaults.standard` on the phone.

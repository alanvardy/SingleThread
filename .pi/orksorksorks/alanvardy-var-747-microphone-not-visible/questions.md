# Research Questions

## Context

Areas of focus: the SwiftUI view chain that conditionally renders the
microphone button in the SingleThread iOS/macOS app, the speech-recognition
permission/authorization layer feeding the render gate, and the persistence
and sync of the "show microphone" user setting. The feature is implemented in
`SingleThread/ContentView.swift`, `SingleThread/DictationViewModel.swift`,
`SingleThread/ReminderDictation.swift`, and `SingleThread/SettingsBindings.swift`,
with related code in `SingleThreadCore/` and tests under `SingleThreadTests/`.

## Questions

1. What is the complete decision chain that determines whether the mic button
   renders, in what order do its conditions apply, and what UI states (error,
   feedback, recording, upgrade prompt, action-button cluster) replace or
   precede it? Trace the code in `ContentView.swift` (notably `bottomBar` and
   the `canDictate`/`showMicrophoneButton`/`canMutate`/`showsActionButtons`
   gates) and report file:line references.

2. How does the app obtain and track speech-recognition authorization status
   (`SFSpeechRecognizerAuthorizationStatus`), where is the status read, how do
   the `.denied`, `.restricted`, `.notDetermined`, and `.authorized` states
   each flow through the `canDictate` decision, and is there any UI that
   surfaces the status or an explanation when the mic is suppressed?

3. Where is the `showMicrophoneButton` setting stored and synced across
   app installs and devices? What storage suites (`UserDefaults.standard` vs
   App Group), watchOS sync payloads, launch-arg seams, and registration
   defaults exist, and could they cause the stored value or its default to
   differ between two installs on the same account?

4. What platform and configuration conditions affect whether dictation works
   at all (as opposed to whether the button renders): `SFSpeechRecognizer`
   availability, supported locales, on-device recognition requirements,
   usage-description keys in Info.plist, entitlements, and deployment
   targets? Where are these checked/not checked at render time?

5. How does the mic button's visibility differ across iOS, macOS, and watchOS
   (and the widget), and what does each platform render in place of the mic
   when the iOS-only freemium or action-button gates apply?

6. What existing tests (unit and UI) cover mic visibility, authorization-state
   transitions, and the toggle, and what states are untested? What happens
   when the app re-creates its `ReminderDictation`/`ContentViewModel` during
   body evaluation, and could that cause the render gate to read stale or
   inconsistent authorization state?
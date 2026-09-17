# Task

Add a "Language" dropdown to the Interface section of the iOS/macOS settings
screen (`InterfaceSettingsView`), letting the user pick one of the six shipped
languages (en, zh-Hans, es, ja, de, fr) and persisting that preference in the
shared App Group (phone + watch). The picked language must actually drive the
app's displayed strings and locale-sensitive rendering at runtime — a new
locale-override subsystem layered on top of the existing `String(localized:)`
+ `.xcstrings` infrastructure (today the app renders in the system locale with
no user-selectable override).

The work spans: the settings dropdown UI (~56 localized call sites + ~47
hardcoded strings exist), a new persisted preference type, and the runtime
locale-override mechanism reaching app/core targets (and possibly the watch
and widget), including SwiftUI locale-aware date rendering.
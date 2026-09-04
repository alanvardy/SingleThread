# Task

On the macOS build of the SingleThread app, the background wallpaper photo
does not appear at all — nothing shows behind the reminder card, just the
window background color. The photo fetching, persistence, and settings are
already cross-platform; it is the rendering layer that is `#if os(iOS)`-gated.
The goal is to make the wallpaper render behind the reminder card on macOS,
consistent with iOS behavior (respecting enabled/fade/pin settings), without
regressing iOS or the existing test suite.
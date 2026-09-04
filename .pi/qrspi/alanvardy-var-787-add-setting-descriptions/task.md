# Task — Add setting descriptions

The Settings screen currently shows only setting names with no explanation.
The task is to add small caption/description text under each setting section
header (e.g. Reminder → "Settings that impact how the reminder is displayed")
and under each individual setting row (e.g. Pin background → "Prevents
background from changing every X hours", where X derives from the rotation
period constant in code). Descriptions appear as small text under what they
describe, in both section headers and rows.

The change must preserve existing persistence, widget reload, and Apple Watch
sync behavior of every setting. The Settings UI is cross-platform (iOS +
macOS share the same files), so captions must respect the existing `#if
os(iOS)` gating. New description strings must be added to the localization
catalogs with all six supported languages.
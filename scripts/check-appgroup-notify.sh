#!/bin/bash
set -euo pipefail
# Guard the App Group notification invariant: AppGroup.defaults must be a
# stored (cached) instance, never a computed property. Each
# UserDefaults(suiteName:) call returns a fresh object, and
# didChangeNotification's `object` is the changing instance — so a computed
# `defaults` makes every `object:`-filtered observer silently never fire
# (AI sort rules would never re-rank). See .pi/skills/ai-sorting/SKILL.md.

FILE="SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift"

if [ ! -f "$FILE" ]; then
  echo "check-appgroup-notify: cannot find $FILE" >&2
  exit 1
fi

if ! grep -Eq 'static (let|var) defaults' "$FILE"; then
  echo "check-appgroup-notify: AppGroup.defaults not found in $FILE" >&2
  exit 1
fi

if grep -Eq 'static var defaults' "$FILE"; then
  echo "check-appgroup-notify: FAIL — AppGroup.defaults is computed (static var)." >&2
  echo "  didChangeNotification object: filters will never fire; make it a static let." >&2
  exit 1
fi

echo "check-appgroup-notify: ok (AppGroup.defaults is a cached static let)"
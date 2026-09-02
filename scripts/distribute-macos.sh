#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild archive -scheme SingleThread -destination 'generic/platform=macOS' \
  -configuration Release -archivePath build/SingleThread.xcarchive

xcodebuild -exportArchive -archivePath build/SingleThread.xcarchive \
  -exportPath build/ -exportOptionsPlist exportOptions.plist
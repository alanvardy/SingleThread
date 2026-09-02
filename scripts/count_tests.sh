#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Occurrence count of PATTERN across GLOB (summed across files).
oc() { grep -roE "$1" $2 2>/dev/null | wc -l | tr -d ' '; }

unit_ios=$(oc '@Test' 'SingleThreadTests/*.swift')        # 516
unit_watch=$(oc '@Test' 'SingleThreadWatchTests/*.swift') # 36
unit_total=$((unit_ios + unit_watch))                     # 552
expect=$(oc '#expect' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')          # 962
require=$(oc '#require' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')        # 46
issue=$(oc 'Issue\.record' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')     # 3
# Mean = (#expect + #require) / @Test  → 1008/552 = 1.83. Issue.record lives in
# guard else-branches alongside a #require/#expect, so it is excluded from the mean.
mean=$(awk "BEGIN { printf \"%.2f\", ($expect + $require) / $unit_total }")
launches_ios=$(oc '\.launch\(\)' 'SingleThreadUITests/*.swift')      # 24
launches_watch=$(oc '\.launch\(\)' 'SingleThreadWatchUITests/*.swift') # 11
settle=$(oc 'Task\.sleep\(nanoseconds: Self\.eventKitSettleDelay\)' \
  'SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift')   # 5
forced=$(oc 'Task\.sleep\(nanoseconds: 400_000_000\)' \
  'SingleThreadTests/ReminderStoreTests.swift SingleThreadTests/ReminderStoreGateTests.swift') # 4
xcodebuild=$(grep -c 'xcodebuild' scripts/test.sh)                    # 14 (file-wide: 9 full-mode + 2 unit-only + 2 ui-only + 1 comment)
# Best-effort lower bound: single-line #expect(…) with no message / sourceLocation.
unnamed=$(grep -roE '#expect\([^)]*\)' SingleThreadTests/*.swift SingleThreadWatchTests/*.swift \
  | grep -vcE ',\s*"|sourceLocation:' || true)

report() {
  echo "unit_tests:        $unit_total (iOS $unit_ios, watch $unit_watch)"
  echo "expect:            $expect"
  echo "require:           $require"
  echo "issue_record:      $issue"
  echo "assertion_mean:    $mean"
  echo "launches:          $((launches_ios + launches_watch)) (iOS $launches_ios, watch $launches_watch)"
  echo "settle_sleeps:     $settle"
  echo "forced_400ms:      $forced"
  echo "xcodebuild:        $xcodebuild"
  echo "unnamed_expect:    $unnamed (lower bound — gate is Stage 3 review)"
}

if [[ "${1:-}" == "--write" ]]; then
  cat > "$2" <<EOF
{"unit_tests":$unit_total,"unit_ios":$unit_ios,"unit_watch":$unit_watch,
 "expect":$expect,"require":$require,"issue_record":$issue,"assertion_mean":$mean,
 "launches_ios":$launches_ios,"launches_watch":$launches_watch,
 "settle_sleeps":$settle,"forced_400ms":$forced,"xcodebuild":$xcodebuild,"unnamed_expect":$unnamed}
EOF
fi
report

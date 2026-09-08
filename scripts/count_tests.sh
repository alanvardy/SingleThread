#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Occurrence count of PATTERN across GLOB (summed across files).
# Trailing `|| true` keeps this exit-0 when grep finds no matches (pipefail
# would otherwise make a zero-count metric kill the script under set -e).
oc() { grep -roE "$1" $2 2>/dev/null | wc -l | tr -d ' ' || true; }

unit_ios=$(oc '@Test' 'SingleThreadTests/*.swift')        # 521
unit_watch=$(oc '@Test' 'SingleThreadWatchTests/*.swift') # 44
unit_total=$((unit_ios + unit_watch))                     # 565
expect=$(oc '#expect' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')          # 1197
require=$(oc '#require' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')        # 73
issue=$(oc 'Issue\.record' 'SingleThreadTests/*.swift SingleThreadWatchTests/*.swift')     # 6
# Mean = (#expect + #require) / @Test  → 1270/565 = 2.25. Issue.record lives in
# guard else-branches alongside a #require/#expect, so it is excluded from the mean.
mean=$(awk "BEGIN { printf \"%.2f\", ($expect + $require) / $unit_total }")
launches_ios=$(oc '\.launch\(\)' 'SingleThreadUITests/*.swift')      # 2
launches_watch=$(oc '\.launch\(\)' 'SingleThreadWatchUITests/*.swift') # 1
# The real 200 ms settle lives at ReminderStore.swift:39 (typealias
# ReminderStoreSettle); it is injectable and tests use noopSettle /
# --ui-testing-noop-settle, so no fixed sleep-pattern metric is counted.
xcodebuild=$(grep -c 'xcodebuild' scripts/test.sh)                    # 11
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
  echo "xcodebuild:        $xcodebuild"
  echo "unnamed_expect:    $unnamed (lower bound — gate is Stage 3 review)"
}

if [[ "${1:-}" == "--write" ]]; then
  cat > "$2" <<EOF
{"unit_tests":$unit_total,"unit_ios":$unit_ios,"unit_watch":$unit_watch,
 "expect":$expect,"require":$require,"issue_record":$issue,"assertion_mean":$mean,
 "launches_ios":$launches_ios,"launches_watch":$launches_watch,
 "xcodebuild":$xcodebuild,"unnamed_expect":$unnamed}
EOF
fi
report

#!/bin/bash
# Runs the screen sweep on the iPad Pro 13-inch, one simulator at a time. Large Score
# is made for the larger iPads (people with low vision don't read music on a mini).
# --all adds the standard 11-inch iPad: before a TestFlight build only. The iPad mini
# is left out (Kris, 2026-11-25: "As usual, skip the mini"); --mini adds it on request. Screenshots land in build/sweep/<date>/, audit lines in the log.
# Crash reports from the simulators' own processes are checked after each run.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-2
OUT="build/sweep/$(date +%Y-%m-%d-%H%M)"
mkdir -p "$OUT"

fresh_simulator() { # name type
  local name="$1" type="$2" udid
  udid=$(xcrun simctl list devices | grep "LS $name (" | grep -oE '[0-9A-F-]{36}' | head -1 || true)
  if [ -z "$udid" ]; then
    udid=$(xcrun simctl create "LS $name" "$type" "$RUNTIME")
    xcrun simctl boot "$udid"; xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl shutdown "$udid" # warm-up boot: first-boot service crashes don't count
  fi
  echo "$udid"
}

check_crashes() { # udid since
  local udid="$1" since="$2" bad=0
  for f in $(find ~/Library/Logs/DiagnosticReports -name "*.ips" -newer "$since" 2>/dev/null); do
    grep -q "SimDevice.$udid" "$f" || continue
    proc=$(head -c 600 "$f" | grep -oE '"(app_name|procName)":"[^"]*"' | head -1)
    case "$proc" in
      *LargeScore*) echo "app crash: $f";;
      *PosterBoard*|*SpringBoard*) echo "simulator broken ($proc): replace it"; bad=1;;
      *) echo "runtime service crash, noted: $proc";;
    esac
  done
  return $bad
}

DEVICES=$(fresh_simulator "iPad Pro 13" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB)
if [ "${1:-}" = "--all" ]; then
  DEVICES="$DEVICES $(fresh_simulator "iPad" com.apple.CoreSimulator.SimDeviceType.iPad-A16)"
fi
if [ "${2:-}" = "--mini" ] || [ "${1:-}" = "--mini" ]; then
  DEVICES="$DEVICES $(fresh_simulator "iPad mini" com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro)"
fi
STAMP=$(mktemp); touch "$STAMP"

for UDID in $DEVICES; do
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  TEST_RUNNER_SWEEP_DIR="$PWD/$OUT" TEST_RUNNER_VOICEOVER_DIR="$PWD/docs/voiceover" xcodebuild -project LargeScore.xcodeproj -scheme LargeScore \
    -destination "id=$UDID" -derivedDataPath build/dd \
    -only-testing:LargeScoreUITests test 2>&1 | tee "$OUT/log-$UDID.txt" | grep -E "AUDIT|CONTRAST|✘|passed|failed|error:" || true
  check_crashes "$UDID" "$STAMP" || true
  xcrun simctl shutdown "$UDID"
done
echo "screenshots: $OUT"

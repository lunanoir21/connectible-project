#!/usr/bin/env bash
# T-N1 (Phase N): real-device battery measurement helper.
#
# Two-phase, not a timed sleep -- the actual wait (hours) happens in
# real life between the two calls, not inside this script:
#
#   ./tool/battery_measure.sh start baseline   # phone idle, app installed but not "Discoverable"
#   ...let the phone sit screen-off for a few hours, untouched...
#   ./tool/battery_measure.sh stop baseline
#
#   ./tool/battery_measure.sh start active     # phone paired, Discoverable on, actively syncing
#   ...same duration, same conditions otherwise...
#   ./tool/battery_measure.sh stop active
#
# Then compare results/<label>.txt for both runs. See
# docs/design/battery-measurement.md for the full protocol (what
# "same conditions" means, how to read the output, what counts as
# pass/fail).
#
# Requires: adb on PATH, exactly one device/emulator attached
# (`adb devices`), and the app already installed
# (io.connectible.mobile).
set -euo pipefail

PACKAGE="io.connectible.mobile"
RESULTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/battery-results"

usage() {
  echo "Usage: $0 start <label>   -- reset stats, record start battery level" >&2
  echo "       $0 stop <label>    -- record end battery level + save app battery breakdown" >&2
  exit 1
}

require_one_device() {
  local count
  count=$(adb devices | tail -n +2 | grep -c "device$" || true)
  if [ "$count" -ne 1 ]; then
    echo "error: expected exactly one attached device/emulator, found $count (adb devices)" >&2
    exit 1
  fi
}

battery_level() {
  adb shell dumpsys battery | grep -oP 'level:\s*\K[0-9]+'
}

app_version() {
  adb shell dumpsys package "$PACKAGE" | grep -oP 'versionName=\K\S+' | head -1
}

cmd="${1:-}"
label="${2:-}"
[ -n "$cmd" ] && [ -n "$label" ] || usage

require_one_device
mkdir -p "$RESULTS_DIR"
out="$RESULTS_DIR/$label.txt"

case "$cmd" in
  start)
    echo "Resetting battery stats and starting run '$label'..."
    adb shell dumpsys batterystats --reset > /dev/null
    {
      echo "label: $label"
      echo "app_version: $(app_version)"
      echo "start_time: $(date -Iseconds)"
      echo "start_level_pct: $(battery_level)"
    } > "$out"
    echo "Recorded start state to $out"
    echo "Now let the phone sit screen-off, untouched, for the agreed duration."
    echo "Run '$0 stop $label' when done."
    ;;
  stop)
    if [ ! -f "$out" ]; then
      echo "error: no start record for '$label' -- run '$0 start $label' first" >&2
      exit 1
    fi
    {
      echo "end_time: $(date -Iseconds)"
      echo "end_level_pct: $(battery_level)"
    } >> "$out"
    echo "Saving full per-app battery breakdown (this can take a few seconds)..."
    adb shell dumpsys batterystats "$PACKAGE" > "$RESULTS_DIR/$label-batterystats-raw.txt" 2>&1 || true
    echo "Done. Summary for '$label':"
    grep -E "^(label|app_version|start_time|start_level_pct|end_time|end_level_pct):" "$out"
    start_pct=$(grep "start_level_pct:" "$out" | cut -d' ' -f2)
    end_pct=$(grep "end_level_pct:" "$out" | cut -d' ' -f2)
    echo "battery_drop_pct: $((start_pct - end_pct))"
    echo "Full per-app breakdown saved to $RESULTS_DIR/$label-batterystats-raw.txt"
    ;;
  *)
    usage
    ;;
esac

#!/usr/bin/env bash
# Measures tully's idle CPU and memory in three states, using throwaway settings.
# Usage: ./scripts/perf.sh [seconds per state]   (default 30). Needs dist/tully.app (scripts/build.sh).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/tully.app"
SECONDS_PER_STATE=${1:-30}
SAMPLES=$((SECONDS_PER_STATE / 2))

measure() { # $1 = label, rest = launch flags
  local label=$1; shift
  pkill -f "$APP/Contents/MacOS/tully" 2>/dev/null; sleep 1
  "$APP/Contents/MacOS/tully" --isolated-defaults "$@" >/dev/null 2>&1 &
  local pid=$!
  sleep 8 # settle: first samples, window creation
  local cpu
  cpu=$(top -l $((SAMPLES + 1)) -s 2 -pid $pid -stats cpu | awk 'NR>1 && $1 ~ /^[0-9.]+$/ {n++; if (n>1) {s+=$1; c++}} END {printf "%.2f", s/c}')
  local mem
  mem=$(footprint -p $pid 2>/dev/null | awk '/phys_footprint:/ {print $2, $3; exit}')
  printf "%-28s CPU %6s %%   memory %s\n" "$label" "$cpu" "${mem:-n/a}"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
}

measure "popover closed"
measure "popover open" --open-popover-window
measure "system monitor open" --open-system-monitor

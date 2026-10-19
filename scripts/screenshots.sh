#!/usr/bin/env bash
# Regenerates screenshot/*.png with sample data (no real processes or files are shown).
# Needs Screen Recording permission for the terminal (screencapture of tully's own windows).
# Usage: ./scripts/screenshots.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/screenshot"
TMP="$(mktemp -d)"
"$ROOT/scripts/build.sh" Release >/dev/null
BIN="$ROOT/dist/tully.app/Contents/MacOS/tully"
swiftc -O "$ROOT/scripts/tools/winid.swift" -o "$TMP/winid"
mkdir -p "$OUT"
rm -f "$OUT"/*.png

# Offscreen renders: converter wheels, forms, editors, HUD
"$BIN" --render-screenshots="$OUT"

# capture NAME FLAGS... : launches tully with demo data and captures each window it opens
capture() {
  local name=$1; shift
  pkill -f "$BIN" 2>/dev/null || true; sleep 1
  "$BIN" --demo-data "$@" >/dev/null 2>&1 &
  local pid=$!
  sleep 5
  local ids
  ids=$("$TMP/winid" tully | awk '{print $1}')
  local i=0
  for id in $ids; do
    local suffix=""; [ $i -gt 0 ] && suffix="-$i"
    screencapture -o -l "$id" "$OUT/$name$suffix.png"
    i=$((i + 1))
  done
  kill $pid 2>/dev/null || true
}

for tab in System Disk Windows Switcher Convert; do
  capture "popover-$(echo $tab | tr '[:upper:]' '[:lower:]')" --open-popover-window=$tab
done
capture "system-monitor" --open-system-monitor
capture "disk-clean" --open-disk-clean
capture "about" --open-about
for pane in general menuBar windowManager windowRing fileConverter diskClean power; do
  capture "settings-$pane" --open-settings=$pane
done
for scene in window-ring auto-layout keyboard-cleaning; do
  capture "$scene" --show-scene=$scene
done
rm -rf "$TMP"
ls "$OUT"

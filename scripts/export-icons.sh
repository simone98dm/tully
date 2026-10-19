#!/usr/bin/env bash
# Regenerates the app icon PNGs and the menu bar template PDF from design/icon/IconKit.swift.
# Usage: ./scripts/export-icons.sh [ring|tiles|pulse]   (default: ring, the chosen direction)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
swiftc -O "$ROOT/design/icon/IconKit.swift" -o "$TMP/iconkit"
"$TMP/iconkit" export "${1:-ring}" "$TMP/out"
cp "$TMP"/out/icon_*.png "$ROOT/tully/Assets.xcassets/AppIcon.appiconset/"
cp "$TMP/out/menuicon-18.pdf" "$ROOT/tully/Assets.xcassets/MenuIcon.imageset/menuicon.pdf"
"$TMP/iconkit" sheet "$ROOT/design/icon/directions.png"
rm -rf "$TMP"
echo "Icons exported."

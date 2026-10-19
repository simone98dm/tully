#!/usr/bin/env bash
# Build tully and place the app in dist/tully.app
# Usage: ./scripts/build.sh [Release|Debug]  (default: Release)
set -euo pipefail

CONFIG=${1:-Release}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build"
DIST="$ROOT/dist"

cd "$ROOT"
echo "Building tully ($CONFIG)..."
if ! xcodebuild \
  -project tully.xcodeproj \
  -scheme tully \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  build > "$DERIVED.log" 2>&1; then
  grep -E "error:" "$DERIVED.log" || tail -20 "$DERIVED.log"
  echo "Build failed. Full log: $DERIVED.log"
  exit 1
fi

mkdir -p "$DIST"
rm -rf "$DIST/tully.app"
ditto "$DERIVED/Build/Products/$CONFIG/tully.app" "$DIST/tully.app"
echo "Built: $DIST/tully.app ($(du -sh "$DIST/tully.app" | cut -f1))"

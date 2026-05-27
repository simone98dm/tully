#!/usr/bin/env bash
# Local release script: build → package → tag
# Usage: ./scripts/release.sh [patch|minor|major]  (default: patch)
set -euo pipefail

BUMP=${1:-patch}
REPO="simone98dm/tully"

# ── Read current version ───────────────────────────────────────────────────────
PBXPROJ="tully.xcodeproj/project.pbxproj"
CURRENT_VER=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | awk -F' = ' '{print $2}' | tr -d ';')
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | awk -F' = ' '{print $2}' | tr -d ';')

IFS='.' read -r major minor patch <<< "$CURRENT_VER"
minor=${minor:-0}; patch=${patch:-0}

case "$BUMP" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  *) echo "Unknown bump type: $BUMP (use major|minor|patch)"; exit 1 ;;
esac

NEW_VER="$major.$minor.$patch"
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "Releasing v$NEW_VER (build $NEW_BUILD)..."

# ── Bump version in pbxproj ───────────────────────────────────────────────────
sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $NEW_VER;/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"

# ── Build ─────────────────────────────────────────────────────────────────────
echo "Building..."
xcodebuild \
  -project tully.xcodeproj \
  -scheme tully \
  -configuration Release \
  build \
  2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

# ── Package ───────────────────────────────────────────────────────────────────
APP=$(find ~/Library/Developer/Xcode/DerivedData/tully-*/Build/Products/Release \
  -name "tully.app" -maxdepth 1 | head -1)
ZIP="tully-v${NEW_VER}.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Packaged: $(du -sh "$ZIP" | cut -f1)"

# ── Tag ───────────────────────────────────────────────────────────────────────
git add "$PBXPROJ"
git commit -m "chore: bump version to $NEW_VER"
git tag "v$NEW_VER"

echo ""
echo "Done. v$NEW_VER tagged locally."
echo "Push with:  git push origin main --follow-tags"
echo "Upload $ZIP to: https://github.com/$REPO/releases/tag/v$NEW_VER"

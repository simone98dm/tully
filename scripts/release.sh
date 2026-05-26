#!/usr/bin/env bash
# Local release script: build → sign → update appcast → tag
# Usage: ./scripts/release.sh [patch|minor|major]  (default: patch)
set -euo pipefail

BUMP=${1:-patch}
REPO="simone98dm/tully"

SPARKLE_SIGN=$(find ~/Library/Developer/Xcode/DerivedData/tully-*/SourcePackages/checkouts/Sparkle \
  -path "*artifacts/sparkle/Sparkle/bin/sign_update" 2>/dev/null | head -1)

if [ -z "$SPARKLE_SIGN" ]; then
  echo "sign_update not found — resolve packages first (open in Xcode or xcodebuild -resolvePackageDependencies)"
  exit 1
fi

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
ditto -c -k --keepParent "$APP" tully.zip
echo "Packaged: $(du -sh tully.zip | cut -f1)"

# ── Sign ──────────────────────────────────────────────────────────────────────
echo "Signing..."
OUTPUT=$("$SPARKLE_SIGN" tully.zip)   # reads private key from Keychain
ED_SIG=$(echo "$OUTPUT" | grep -oE 'sparkle:edSignature="[^"]+"' | cut -d'"' -f2)
LENGTH=$(stat -f%z tully.zip)

if [ -z "$ED_SIG" ]; then
  echo "Signing failed — check that generate_keys was run and private key is in Keychain"
  exit 1
fi

echo "Signature: $ED_SIG"

# ── Update appcast ────────────────────────────────────────────────────────────
python3 scripts/update_appcast.py \
  --version "$NEW_VER" \
  --build   "$NEW_BUILD" \
  --sig     "$ED_SIG" \
  --length  "$LENGTH" \
  --repo    "$REPO"

# ── Commit + tag ──────────────────────────────────────────────────────────────
git add "$PBXPROJ" docs/appcast.xml
git commit -m "chore: bump version to $NEW_VER"
git tag "v$NEW_VER"

echo ""
echo "Done. v$NEW_VER tagged locally."
echo "Push with: git push origin main --follow-tags"
echo "Upload tully.zip to: https://github.com/$REPO/releases/tag/v$NEW_VER"

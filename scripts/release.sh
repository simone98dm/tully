#!/usr/bin/env bash
# Release: bump version → build once → verify → commit → annotated tag → push → GitHub release.
# The zip, dist/tully.app and the tag all come from the same build, and the script refuses to
# tag if the built app's version doesn't match.
#
# Usage: ./scripts/release.sh [patch|minor|major] [--notes-file FILE] [--no-publish]
set -euo pipefail

BUMP=patch
NOTES_FILE=""
PUBLISH=1
while [ $# -gt 0 ]; do
  case "$1" in
    patch|minor|major) BUMP=$1 ;;
    --notes-file) NOTES_FILE=$2; shift ;;
    --no-publish) PUBLISH=0 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PBXPROJ="tully.xcodeproj/project.pbxproj"

# ── Preconditions ─────────────────────────────────────────────────────────────
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "Release from main only."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Working tree not clean; commit or stash first."; exit 1; }
git pull --ff-only

# ── Bump version ──────────────────────────────────────────────────────────────
CURRENT_VER=$("$ROOT/scripts/version.sh")
CURRENT_BUILD=$("$ROOT/scripts/version.sh" --build)
IFS='.' read -r major minor patch <<< "$CURRENT_VER"
minor=${minor:-0}; patch=${patch:-0}
case "$BUMP" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
esac
NEW_VER="$major.$minor.$patch"
NEW_BUILD=$((CURRENT_BUILD + 1))
TAG="v$NEW_VER"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "Tag $TAG already exists."; exit 1; }

echo "Releasing $TAG (build $NEW_BUILD)..."
sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $NEW_VER;/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"

# ── Build once, verify, package ───────────────────────────────────────────────
"$ROOT/scripts/build.sh" Release
"$ROOT/scripts/version.sh" --check-app dist/tully.app "$NEW_VER" "$NEW_BUILD"
ZIP="tully-$TAG.zip"
rm -f "$ZIP"
ditto -c -k --keepParent dist/tully.app "$ZIP"
echo "Packaged $ZIP ($(du -sh "$ZIP" | cut -f1))"

# ── Commit, tag, push ─────────────────────────────────────────────────────────
git add "$PBXPROJ"
git commit -m "chore: bump version to $NEW_VER"
git tag -a "$TAG" -m "tully $NEW_VER (build $NEW_BUILD)"
"$ROOT/scripts/version.sh" --check-tag "$TAG"

if [ "$PUBLISH" = 0 ]; then
  echo "Tagged $TAG locally. Publish with: git push origin main $TAG"
  exit 0
fi
git push origin main "$TAG"

# ── GitHub release ────────────────────────────────────────────────────────────
NOTES_ARGS=(--generate-notes)
[ -n "$NOTES_FILE" ] && NOTES_ARGS=(--notes-file "$NOTES_FILE")
# a GITHUB_TOKEN env var with narrow scopes would override the stored gh login
env -u GITHUB_TOKEN gh release create "$TAG" "$ZIP" --title "tully $NEW_VER" --latest "${NOTES_ARGS[@]}"
echo "Released $TAG."

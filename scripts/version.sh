#!/usr/bin/env bash
# Single source of truth for tully's version: MARKETING_VERSION / CURRENT_PROJECT_VERSION in the project.
#   version.sh                         → prints the version (e.g. 2.0.0)
#   version.sh --build                 → prints the build number
#   version.sh --check-tag vX.Y.Z      → fails unless the tag matches the project version
#   version.sh --check-app APP V B     → fails unless the built app reports version V and build B
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/tully.xcodeproj/project.pbxproj"

project_value() { # $1 = setting name; all targets must agree
  local values
  values=$(grep -E "^\s*$1 = " "$PBXPROJ" | sed -E "s/.*= (.*);/\1/" | sort -u)
  if [ "$(echo "$values" | wc -l | tr -d ' ')" != "1" ]; then
    echo "Targets disagree on $1: $(echo $values)" >&2
    exit 1
  fi
  echo "$values"
}

case "${1:-}" in
  "") project_value MARKETING_VERSION ;;
  --build) project_value CURRENT_PROJECT_VERSION ;;
  --check-tag)
    tag=${2:?tag required}
    version=$(project_value MARKETING_VERSION)
    if [ "$tag" != "v$version" ]; then
      echo "✖ Tag $tag doesn't match the app version $version (expected v$version)." >&2
      exit 1
    fi
    echo "✓ Tag $tag matches the app version $version."
    ;;
  --check-app)
    app=${2:?app required}; want_version=${3:?version required}; want_build=${4:?build required}
    plist="$app/Contents/Info.plist"
    got_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$plist")
    got_build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist")
    if [ "$got_version" != "$want_version" ] || [ "$got_build" != "$want_build" ]; then
      echo "✖ $app is $got_version ($got_build), expected $want_version ($want_build)." >&2
      exit 1
    fi
    echo "✓ $app is $got_version ($got_build)."
    ;;
  *) echo "usage: $0 [--build | --check-tag TAG | --check-app APP VERSION BUILD]" >&2; exit 2 ;;
esac

#!/usr/bin/env bash
# Builds the Release configuration signed with the personal identity from Local.xcconfig and installs it
# as /Applications/Weitblick Remote.app. A stable identity keeps macOS privacy grants (Accessibility,
# microphone) and Keychain access across updates; ad-hoc builds lose them with every new build.
# Does not launch the app.
#
#   scripts/install-local.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP_NAME="Weitblick Remote"
TARGET="/Applications/$APP_NAME.app"

[[ -f Local.xcconfig ]] || {
  echo "Local.xcconfig missing: it sets the signing identity (see docs/RELEASING.md)" >&2; exit 1; }

# Parallel agents share this checkout: one build at a time (same lock as build.sh).
if [[ -z "${WEITBLICK_BUILD_LOCKED:-}" ]]; then
  export WEITBLICK_BUILD_LOCKED=1
  exec lockf -t 1800 /tmp/weitblick-build.lock "$0" "$@"
fi

if pgrep -xq "$APP_NAME"; then
  echo "$APP_NAME is running; quit it first" >&2; exit 1
fi

"$ROOT/scripts/build-freerdp.sh"
xcodegen generate --quiet
xcodebuild -project WeitblickRemote.xcodeproj -scheme WeitblickRemote -configuration Release \
  -destination generic/platform=macOS -derivedDataPath build/DerivedData -quiet build

BUILT="build/DerivedData/Build/Products/Release/$APP_NAME.app"
codesign --verify --strict --deep "$BUILT"
IDENTITY=$(codesign --display --verbose=2 "$BUILT" 2>&1 | sed -n 's/^Authority=//p' | head -1)
[[ -n "$IDENTITY" ]] || { echo "the build is not signed with an identity (ad-hoc?); check Local.xcconfig" >&2; exit 1; }

rm -rf "$TARGET"
ditto "$BUILT" "$TARGET"
codesign --verify --strict --deep "$TARGET"
echo "installed $TARGET ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist"), signed by $IDENTITY)"

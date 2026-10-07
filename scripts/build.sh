#!/usr/bin/env bash
# Builds FreeRDP if needed, generates the Xcode project and builds the app, the smoke test
# and the E2E test (Debug by default) into build/.
#
#   scripts/build.sh [Debug|Release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-Debug}"
cd "$ROOT"

# Parallel agents share this checkout: one build at a time.
if [[ -z "${WEITBLICK_BUILD_LOCKED:-}" ]]; then
  export WEITBLICK_BUILD_LOCKED=1
  exec lockf -t 1800 /tmp/weitblick-build.lock "$0" "$@"
fi

"$ROOT/scripts/build-freerdp.sh"
xcodegen generate --quiet

for scheme in WeitblickRemote weitblick-smoke weitblick-e2e; do
  xcodebuild -project WeitblickRemote.xcodeproj -scheme "$scheme" -configuration "$CONFIGURATION" \
    -derivedDataPath build/DerivedData -quiet build
done

PRODUCTS="build/DerivedData/Build/Products/$CONFIGURATION"
rm -rf "build/Weitblick Remote.app"
cp -R "$PRODUCTS/Weitblick Remote.app" "build/Weitblick Remote.app"
cp "$PRODUCTS/weitblick-smoke" build/weitblick-smoke
cp "$PRODUCTS/weitblick-e2e" build/weitblick-e2e
echo "built build/Weitblick Remote.app, build/weitblick-smoke and build/weitblick-e2e ($CONFIGURATION)"

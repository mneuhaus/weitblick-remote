#!/usr/bin/env bash
# Builds FreeRDP if needed, generates the Xcode project and builds the app, the smoke test
# and the E2E test (Debug by default) into build/.
#
#   scripts/build.sh [Debug|Release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-Debug}"
cd "$ROOT"

"$ROOT/scripts/build-freerdp.sh"
xcodegen generate --quiet

for scheme in Sprung sprung-smoke sprung-e2e; do
  xcodebuild -project Sprung.xcodeproj -scheme "$scheme" -configuration "$CONFIGURATION" \
    -derivedDataPath build/DerivedData -quiet build
done

PRODUCTS="build/DerivedData/Build/Products/$CONFIGURATION"
rm -rf build/Sprung.app
cp -R "$PRODUCTS/Sprung.app" build/Sprung.app
cp "$PRODUCTS/sprung-smoke" build/sprung-smoke
cp "$PRODUCTS/sprung-e2e" build/sprung-e2e
echo "built build/Sprung.app, build/sprung-smoke and build/sprung-e2e ($CONFIGURATION)"

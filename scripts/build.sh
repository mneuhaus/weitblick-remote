#!/usr/bin/env bash
# Builds FreeRDP if needed, generates the Xcode project and builds the app and the smoke
# tool (Debug by default) into build/.
#
#   scripts/build.sh [Debug|Release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-Debug}"
cd "$ROOT"

"$ROOT/scripts/build-freerdp.sh"
xcodegen generate --quiet

for scheme in Sprung sprung-smoke; do
  xcodebuild -project Sprung.xcodeproj -scheme "$scheme" -configuration "$CONFIGURATION" \
    -derivedDataPath build/DerivedData -quiet build
done

PRODUCTS="build/DerivedData/Build/Products/$CONFIGURATION"
rm -rf build/Sprung.app
cp -R "$PRODUCTS/Sprung.app" build/Sprung.app
cp "$PRODUCTS/sprung-smoke" build/sprung-smoke
echo "built build/Sprung.app and build/sprung-smoke ($CONFIGURATION)"

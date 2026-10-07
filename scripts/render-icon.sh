#!/usr/bin/env bash
# Renders the app icon PNGs from the SVG sources in design/icon (needs rsvg-convert and ImageMagick):
#   - the asset catalog AppIcon (all macOS sizes; 16 and 32 px from the pixel-grid variants),
#   - website exports in design/icon/export (icon-*.png, favicons, apple-touch-icon).
# The PNGs are committed, so building the app does not need these tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON="$ROOT/design/icon"
SET="$ROOT/Sources/WeitblickRemote/Support/Assets.xcassets/AppIcon.appiconset"
EXPORT="$ICON/export"
mkdir -p "$SET" "$EXPORT"

render() { # <svg> <pixels> <output>
  rsvg-convert --width "$2" --height "$2" "$1" --output "$3"
}

# name:pixels:source (the 16 and 32 px variants are drawn on their own pixel grid)
for entry in 16x16:16:app-icon-16 16x16@2x:32:app-icon-32 32x32:32:app-icon-32 32x32@2x:64:app-icon \
  128x128:128:app-icon 128x128@2x:256:app-icon 256x256:256:app-icon 256x256@2x:512:app-icon \
  512x512:512:app-icon 512x512@2x:1024:app-icon; do
  IFS=: read -r name pixels source <<<"$entry"
  render "$ICON/$source.svg" "$pixels" "$SET/icon_$name.png"
done

for pixels in 1024 512 256 128; do
  render "$ICON/app-icon.svg" "$pixels" "$EXPORT/icon-$pixels.png"
done
render "$ICON/app-icon-16.svg" 16 "$EXPORT/favicon-16.png"
render "$ICON/app-icon-32.svg" 32 "$EXPORT/favicon-32.png"
render "$ICON/app-icon.svg" 48 "$EXPORT/favicon-48.png"
magick "$EXPORT/favicon-16.png" "$EXPORT/favicon-32.png" "$EXPORT/favicon-48.png" "$EXPORT/favicon.ico"
cp "$ICON/app-icon-32.svg" "$EXPORT/favicon.svg"
# iOS masks touch icons itself and fills transparency with black: use the full-bleed original.
render "$ICON/weitblick-titlebar-color.svg" 180 "$EXPORT/apple-touch-icon.png"
echo "rendered $SET and $EXPORT"

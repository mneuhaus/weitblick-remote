#!/usr/bin/env bash
# Builds FreeRDP 3 + WinPR as static arm64 libraries into vendor/install.
# Idempotent: skips the build when the submodule commit and flag set are unchanged.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/vendor/FreeRDP"
BUILD="$ROOT/vendor/build/freerdp"
PREFIX="$ROOT/vendor/install"
OPENSSL_ROOT="${OPENSSL_ROOT:-$(brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

if [[ ! -f "$SRC/CMakeLists.txt" ]]; then
  git -C "$ROOT" submodule update --init vendor/FreeRDP
fi
for lib in libssl.a libcrypto.a; do
  [[ -f "$OPENSSL_ROOT/lib/$lib" ]] || { echo "missing $OPENSSL_ROOT/lib/$lib (brew install openssl@3)" >&2; exit 1; }
done

# Channels we ship. Everything else is switched off explicitly so Homebrew
# libraries found on the build machine can never leak into the app.
KEEP_CHANNELS=(drdynvc rdpgfx disp cliprdr rdpsnd audin rdpdr drive printer)
DROP_CHANNELS=(ainput echo encomsp geometry gfxredir location parallel rail
  rdp2tcp rdpear rdpecam rdpei rdpemsc rdpewa remdesk serial smartcard sshagent telemetry
  tsmf urbdrc video)

FLAGS=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
  -DCMAKE_VERBOSE_MAKEFILE=OFF
  -DBUILD_SHARED_LIBS=OFF
  -DBUILD_TESTING=OFF
  -DWITH_CCACHE=OFF
  -DWITH_CLANG_FORMAT=OFF
  -DWITH_MANPAGES=OFF
  -DWITH_SAMPLE=OFF
  -DWITH_CLIENT_COMMON=ON
  -DWITH_CLIENT=OFF
  -DWITH_CLIENT_SDL=OFF
  -DWITH_CLIENT_MAC=OFF
  -DWITH_CLIENT_CHANNELS=ON
  -DWITH_CHANNELS=ON
  -DWITH_SERVER=OFF
  -DWITH_SERVER_CHANNELS=OFF
  -DWITH_SHADOW=OFF
  -DWITH_PROXY=OFF
  -DWITH_PLATFORM_SERVER=OFF
  -DWITH_WINPR_TOOLS=OFF
  -DWITH_X11=OFF
  -DWITH_WAYLAND=OFF
  -DWITH_FFMPEG=OFF
  -DWITH_DSP_FFMPEG=OFF
  -DWITH_VIDEO_FFMPEG=OFF
  -DWITH_SWSCALE=OFF
  -DWITH_CAIRO=OFF
  -DWITH_OPENH264=OFF
  -DWITH_JPEG=OFF
  -DWITH_OPUS=OFF
  -DWITH_SOXR=OFF
  -DWITH_LAME=OFF
  -DWITH_FAAD2=OFF
  -DWITH_FAAC=OFF
  -DWITH_GSM=OFF
  -DWITH_AOM=OFF
  -DWITH_DAV1D=OFF
  -DWITH_YUV=OFF
  -DWITH_PCSC=OFF
  -DWITH_SMARTCARD_EMULATE=OFF
  -DWITH_PKCS11=OFF
  -DWITH_FUSE=OFF
  # Printers through the system CUPS (SDK headers; the app links libcups).
  -DWITH_CUPS=ON
  -DCUPS_INCLUDE_DIR="$SDK/usr/include"
  -DCUPS_LIBRARIES="$SDK/usr/lib/libcups.tbd"
  -DWITH_KRB5=OFF
  -DWITH_URIPARSER=OFF
  -DWITH_JSON_DISABLED=ON
  -DWITH_AAD=OFF
  -DWITH_MBEDTLS=OFF
  -DWITH_LIBRESSL=OFF
  -DWITH_MACAUDIO=ON
  -DWITH_SIMD=ON
  # NTLM needs MD4/RC4; OpenSSL 3 keeps them in the legacy provider, which is a
  # dlopen'ed module that a static build cannot carry. Use FreeRDP's own copies.
  -DWITH_INTERNAL_RC4=ON
  -DWITH_INTERNAL_MD4=ON
  -DOPENSSL_ROOT_DIR="$OPENSSL_ROOT"
  -DOPENSSL_USE_STATIC_LIBS=ON
)
for c in "${KEEP_CHANNELS[@]}"; do
  up=$(echo "$c" | tr '[:lower:]' '[:upper:]')
  FLAGS+=("-DCHANNEL_${up}=ON" "-DCHANNEL_${up}_CLIENT=ON")
done
for c in "${DROP_CHANNELS[@]}"; do
  up=$(echo "$c" | tr '[:lower:]' '[:upper:]')
  FLAGS+=("-DCHANNEL_${up}=OFF")
done

COMMIT=$(git -C "$SRC" rev-parse HEAD)
STAMP_VALUE=$( (echo "$COMMIT"; printf '%s\n' "${FLAGS[@]}"; cat "$0") | shasum -a 256 | cut -d' ' -f1)
STAMP="$PREFIX/.weitblick-build-stamp"

if [[ "${1:-}" != "--force" && -f "$STAMP" && "$(cat "$STAMP")" == "$STAMP_VALUE" ]]; then
  echo "FreeRDP up to date ($PREFIX)"
  exit 0
fi

cmake -S "$SRC" -B "$BUILD" "${FLAGS[@]}"
cmake --build "$BUILD" --parallel "$(sysctl -n hw.ncpu)"
rm -rf "$PREFIX"
cmake --install "$BUILD" >/dev/null
# The app links everything from vendor/install/lib; with only the .a files there the linker
# cannot pick Homebrew's OpenSSL dylibs by accident.
cp "$OPENSSL_ROOT/lib/libssl.a" "$OPENSSL_ROOT/lib/libcrypto.a" "$PREFIX/lib/"

# Fail loudly if a required channel did not make it into the static addin table.
TABLES="$BUILD/channels/client/tables.c"
for c in "${KEEP_CHANNELS[@]}"; do
  grep -q "\"$c\"" "$TABLES" || { echo "channel $c missing from $TABLES" >&2; exit 1; }
done
for entry in mac_freerdp_rdpsnd_client_subsystem_entry mac_freerdp_audin_client_subsystem_entry \
  cups_freerdp_printer_client_subsystem_entry; do
  grep -q "$entry" "$TABLES" || { echo "backend $entry missing from $TABLES" >&2; exit 1; }
done

echo "$STAMP_VALUE" > "$STAMP"
echo "FreeRDP installed to $PREFIX"

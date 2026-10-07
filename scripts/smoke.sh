#!/usr/bin/env bash
# Headless end-to-end test against the test VM (credentials in .testvm.env).
#
#   scripts/smoke.sh [--takeover] [--no-build] [--cycles N] [--soak SECONDS]
#
# --takeover disconnects another user's VM console session first (see scripts/testvm.sh).
# --no-build uses the existing build/weitblick-smoke.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/testvm.sh"
hold_vm_lock "$0" "$@"
ARGS=()
TAKEOVER=0
BUILD=1
for arg in "$@"; do
  case "$arg" in
    --takeover) TAKEOVER=1 ;;
    --no-build) BUILD=0 ;;
    *) ARGS+=("$arg") ;;
  esac
done

[[ -f "$ROOT/.testvm.env" ]] || { echo "SMOKE FAIL: $ROOT/.testvm.env missing" >&2; exit 1; }
mkdir -p "$ROOT/build"
require_free_console "$TAKEOVER" SMOKE

if [[ "$BUILD" == 1 ]]; then
  "$ROOT/scripts/build.sh" >"$ROOT/build/build.log" 2>&1 || { echo "SMOKE FAIL: build failed, see build/build.log" >&2; exit 1; }
fi

cd "$ROOT"
# Run a private copy: a parallel build.sh overwrites build/weitblick-smoke in place, and macOS kills a
# process whose executable pages change (SIGKILL, code signature invalid).
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/weitblick-smoke.XXXXXX")"
trap 'rm -rf "$RUN_DIR"' EXIT
cp "$ROOT/build/weitblick-smoke" "$RUN_DIR/weitblick-smoke"
"$RUN_DIR/weitblick-smoke" --env "$ROOT/.testvm.env" --out "$ROOT/build" "${ARGS[@]+"${ARGS[@]}"}"

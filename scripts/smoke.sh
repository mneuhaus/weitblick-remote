#!/usr/bin/env bash
# Headless end-to-end test against the test VM (credentials in .testvm.env).
#
#   scripts/smoke.sh [--takeover] [--cycles N] [--soak SECONDS]
#
# --takeover disconnects another user's VM console session first (see scripts/testvm.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/testvm.sh"
hold_vm_lock "$0" "$@"
ARGS=()
TAKEOVER=0
for arg in "$@"; do
  if [[ "$arg" == "--takeover" ]]; then TAKEOVER=1; else ARGS+=("$arg"); fi
done

[[ -f "$ROOT/.testvm.env" ]] || { echo "SMOKE FAIL: $ROOT/.testvm.env missing" >&2; exit 1; }
mkdir -p "$ROOT/build"
require_free_console "$TAKEOVER" SMOKE

"$ROOT/scripts/build.sh" >"$ROOT/build/build.log" 2>&1 || { echo "SMOKE FAIL: build failed, see build/build.log" >&2; exit 1; }

cd "$ROOT"
exec "$ROOT/build/sprung-smoke" --env "$ROOT/.testvm.env" --out "$ROOT/build" "${ARGS[@]+"${ARGS[@]}"}"

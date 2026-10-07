#!/usr/bin/env bash
# Headless end-to-end test against the test VM (credentials in .testvm.env).
#
#   scripts/smoke.sh [--cycles N]
#
# Windows 11 Pro allows one active session: if another user is active on the VM console,
# the login would stop at "Ein anderer Benutzer ist angemeldet". Pass --takeover to
# disconnect that console session first (tsdiscon: the session keeps running).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VM_NAME="Windows 11"
ARGS=()
TAKEOVER=0
for arg in "$@"; do
  if [[ "$arg" == "--takeover" ]]; then TAKEOVER=1; else ARGS+=("$arg"); fi
done

[[ -f "$ROOT/.testvm.env" ]] || { echo "SMOKE FAIL: $ROOT/.testvm.env missing" >&2; exit 1; }
mkdir -p "$ROOT/build"

if command -v prlctl >/dev/null; then
  console=$(prlctl exec "$VM_NAME" powershell -NoProfile -Command "query session console" 2>/dev/null \
    | awk 'NR>1 && $1 ~ /console/ && $2 !~ /^[0-9]+$/ {print $2}' || true)
  if [[ -n "$console" ]]; then
    if [[ $TAKEOVER == 1 ]]; then
      echo "disconnecting console session of '$console' in the VM (it keeps running)"
      prlctl exec "$VM_NAME" powershell -NoProfile -Command "tsdiscon console" >/dev/null
    else
      echo "SMOKE FAIL: '$console' is active on the VM console; rerun with --takeover" >&2
      exit 1
    fi
  fi
fi

"$ROOT/scripts/build.sh" >"$ROOT/build/build.log" 2>&1 || { echo "SMOKE FAIL: build failed, see build/build.log" >&2; exit 1; }

cd "$ROOT"
exec "$ROOT/build/sprung-smoke" --env "$ROOT/.testvm.env" --out "$ROOT/build" "${ARGS[@]+"${ARGS[@]}"}"

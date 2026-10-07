#!/usr/bin/env bash
# End-to-end test against the test VM (credentials in .testvm.env).
#
#   scripts/e2e.sh [--takeover] [--no-build] [--runs N]     (default: 3 runs)
#
# Types through the KeyboardEngine (German layout) into Notepad, checks shortcut translations, moves
# text, images, HTML, RTF and files through the clipboard channel in both directions (private
# pasteboard), checks drive redirection (build/e2e-work/share as \\tsclient\sprung-e2e), printers
# and audio, and reconnects after unplugging the VM's network adapter. Evidence (log, FreeRDP log,
# screenshots, transferred files, os_log) goes to build/evidence/m5-e2e-<time>/.
# --takeover: see scripts/testvm.sh. --no-build uses the existing build/sprung-e2e.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/testvm.sh"
hold_vm_lock "$0" "$@"
TAKEOVER=0
BUILD=1
RUNS=3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --takeover) TAKEOVER=1 ;;
    --no-build) BUILD=0 ;;
    --runs) RUNS="$2"; shift ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

[[ -f "$ROOT/.testvm.env" ]] || { echo "E2E FAIL: $ROOT/.testvm.env missing" >&2; exit 1; }
EVIDENCE="$ROOT/build/evidence/m5-e2e-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE"
require_free_console "$TAKEOVER" E2E
# The reconnect check unplugs the VM's network adapter; whatever happens, plug it back in.
trap reconnect_vm_network EXIT

if [[ "$BUILD" == 1 ]]; then
  "$ROOT/scripts/build.sh" >"$ROOT/build/build.log" 2>&1 || { echo "E2E FAIL: build failed, see build/build.log" >&2; exit 1; }
fi

cd "$ROOT"
# Run a private copy: a parallel build.sh overwrites build/sprung-e2e in place, and macOS kills a
# process whose executable pages change (SIGKILL, code signature invalid).
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sprung-e2e.XXXXXX")"
trap 'reconnect_vm_network; rm -rf "$RUN_DIR"' EXIT
cp "$ROOT/build/sprung-e2e" "$RUN_DIR/sprung-e2e"
START="$(date '+%Y-%m-%d %H:%M:%S')"
set +e
"$RUN_DIR/sprung-e2e" --env "$ROOT/.testvm.env" --out "$EVIDENCE" --runs "$RUNS" 2>&1 | tee "$EVIDENCE/e2e.log"
STATUS=${PIPESTATUS[0]}
set -e
log show --start "$START" --predicate 'subsystem == "nrw.neuhaus.sprung"' --info --style compact \
  >"$EVIDENCE/oslog.txt" 2>/dev/null || true
echo "evidence: $EVIDENCE"
exit "$STATUS"

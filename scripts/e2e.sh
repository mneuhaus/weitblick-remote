#!/usr/bin/env bash
# Keyboard and clipboard end-to-end test against the test VM (credentials in .testvm.env).
#
#   scripts/e2e.sh [--takeover] [--runs N]     (default: 3 runs)
#
# Types through the KeyboardEngine (German layout) into Notepad, checks shortcut translations and
# moves text, images, HTML and RTF through the clipboard channel in both directions, using a
# private pasteboard. Evidence (log, screenshots, transferred files, os_log) goes to
# build/evidence/m3-e2e-<time>/. --takeover: see scripts/testvm.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/testvm.sh"
TAKEOVER=0
RUNS=3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --takeover) TAKEOVER=1 ;;
    --runs) RUNS="$2"; shift ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

[[ -f "$ROOT/.testvm.env" ]] || { echo "E2E FAIL: $ROOT/.testvm.env missing" >&2; exit 1; }
EVIDENCE="$ROOT/build/evidence/m3-e2e-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE"
require_free_console "$TAKEOVER" E2E

"$ROOT/scripts/build.sh" >"$ROOT/build/build.log" 2>&1 || { echo "E2E FAIL: build failed, see build/build.log" >&2; exit 1; }

cd "$ROOT"
START="$(date '+%Y-%m-%d %H:%M:%S')"
set +e
"$ROOT/build/sprung-e2e" --env "$ROOT/.testvm.env" --out "$EVIDENCE" --runs "$RUNS" 2>&1 | tee "$EVIDENCE/e2e.log"
STATUS=${PIPESTATUS[0]}
set -e
log show --start "$START" --predicate 'subsystem == "nrw.neuhaus.sprung"' --info --style compact \
  >"$EVIDENCE/oslog.txt" 2>/dev/null || true
echo "evidence: $EVIDENCE"
exit "$STATUS"

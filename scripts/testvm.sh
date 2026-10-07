# Shared by smoke.sh and e2e.sh (source it). Windows 11 Pro allows one active session: if another
# user is active on the VM console, an RDP logon stops at "Ein anderer Benutzer ist angemeldet".
#
#   require_free_console <takeover 0|1> <label>
#
# With takeover=1 the console session is disconnected first (tsdiscon: its programs keep running).
VM_NAME="Windows 11"

require_free_console() {
  local takeover="$1" label="$2" console
  command -v prlctl >/dev/null || return 0
  console=$(prlctl exec "$VM_NAME" powershell -NoProfile -Command "query session console" 2>/dev/null \
    | awk 'NR>1 && $1 ~ /console/ && $2 !~ /^[0-9]+$/ {print $2}' || true)
  [[ -z "$console" ]] && return 0
  if [[ "$takeover" == 1 ]]; then
    echo "disconnecting console session of '$console' in the VM (it keeps running)"
    prlctl exec "$VM_NAME" powershell -NoProfile -Command "tsdiscon console" >/dev/null
  else
    echo "$label FAIL: '$console' is active on the VM console; rerun with --takeover" >&2
    exit 1
  fi
}

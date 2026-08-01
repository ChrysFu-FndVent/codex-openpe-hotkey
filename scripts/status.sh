#!/bin/bash
set -u

failed=0
user_domain="gui/$(id -u)"

check_job() {
  local label="$1"
  if output="$(/bin/launchctl print "$user_domain/$label" 2>/dev/null)"; then
    state="$(printf '%s\n' "$output" | awk -F'= ' '/^[[:space:]]*state =/{print $2; exit}')"
    pid="$(printf '%s\n' "$output" | awk -F'= ' '/^[[:space:]]*pid =/{print $2; exit}')"
    echo "$label: state=${state:-unknown} pid=${pid:-none}"
  else
    echo "$label: not loaded"
    failed=1
  fi
}

check_job com.openpe.promptenhancer.server
check_job com.openpe.promptenhancer.hotkey

if health="$(/usr/bin/curl --fail --silent --show-error --max-time 5 http://127.0.0.1:18980/healthz 2>/dev/null)"; then
  echo "openpe-server health: $health"
else
  echo "openpe-server health: unavailable"
  failed=1
fi

app="${OPENPE_APP_DIR:-$HOME/Applications}/OpenPE Hotkey.app"
if [ -d "$app" ]; then
  if /usr/bin/codesign --verify --deep --strict "$app" 2>/dev/null; then
    echo "app signature: valid"
  else
    echo "app signature: invalid"
    failed=1
  fi
  ui_element="$(/usr/bin/plutil -extract LSUIElement raw "$app/Contents/Info.plist" 2>/dev/null || true)"
  echo "hidden UI agent: ${ui_element:-unknown}"
else
  echo "app bundle: missing at $app"
  failed=1
fi

hotkey_plist="$HOME/Library/LaunchAgents/com.openpe.promptenhancer.hotkey.plist"
configured_hotkey="$(/usr/bin/plutil -extract EnvironmentVariables.OPENPE_HOTKEY raw "$hotkey_plist" 2>/dev/null || true)"
echo "configured hotkey: ${configured_hotkey:-Option+Q (legacy default)}"

log_file="$HOME/Library/Logs/openpe-hotkey-error.log"
if [ -f "$log_file" ]; then
  echo "recent hotkey diagnostics:"
  tail -n 5 "$log_file"
fi

exit "$failed"

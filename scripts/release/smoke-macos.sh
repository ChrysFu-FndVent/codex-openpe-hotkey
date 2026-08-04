#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/../.." && pwd)"
version="$(tr -d '[:space:]' < "$project_root/release/version.txt")"
dmg="${1:-$project_root/dist/Codex-OpenPE-Hotkey-$version-macOS-universal.dmg}"
checksum="$dmg.sha256"

if [ ! -f "$dmg" ] || [ ! -f "$checksum" ]; then
  echo "DMG or checksum is missing: $dmg" >&2
  exit 1
fi
(cd "$(dirname "$dmg")" && shasum -a 256 -c "$(basename "$checksum")")

temporary_root="$(mktemp -d)"
mount_point="$temporary_root/mount"
installed_app="$temporary_root/Applications/OpenPE Hotkey.app"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then kill "$server_pid" >/dev/null 2>&1 || true; fi
  hdiutil detach -quiet "$mount_point" >/dev/null 2>&1 || true
  rm -rf "$temporary_root"
}
trap cleanup EXIT
mkdir -p "$mount_point" "$(dirname "$installed_app")"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_point" "$dmg"
cp -R "$mount_point/OpenPE Hotkey.app" "$installed_app"
hdiutil detach -quiet "$mount_point"

helper="$installed_app/Contents/MacOS/OpenPEHotkey"
server="$installed_app/Contents/Resources/openpe-server"
plugin_root="$installed_app/Contents/Resources/CodexPlugin"
codesign --verify --deep --strict "$installed_app"
[[ "$(lipo -archs "$helper")" == *arm64* && "$(lipo -archs "$helper")" == *x86_64* ]]
[[ "$(lipo -archs "$server")" == *arm64* && "$(lipo -archs "$server")" == *x86_64* ]]
test -f "$plugin_root/.agents/plugins/marketplace.json"
test -f "$plugin_root/skills/codex-openpe-hotkey/SKILL.md"

OPENPE_API_KEY="ci-placeholder-key" \
OPENPE_SERVER_TOKEN="ci-server-token" \
OPENPE_BASE_URL="http://127.0.0.1:9/v1" \
OPENPE_MODEL="ci-placeholder-model" \
OPENPE_LANGUAGE="en" \
OPENPE_TIMEOUT="5s" \
  "$server" --listen 127.0.0.1:28980 >"$temporary_root/server.log" 2>&1 &
server_pid="$!"
healthy=false
for _ in $(seq 1 40); do
  if curl --fail --silent --max-time 2 http://127.0.0.1:28980/healthz >/dev/null; then
    healthy=true
    break
  fi
  if ! kill -0 "$server_pid" >/dev/null 2>&1; then
    cat "$temporary_root/server.log" >&2
    echo "openPE server exited during smoke test" >&2
    exit 1
  fi
  sleep 0.25
done
if [ "$healthy" != true ]; then
  cat "$temporary_root/server.log" >&2
  echo "openPE health check timed out" >&2
  exit 1
fi

kill "$server_pid"
wait "$server_pid" 2>/dev/null || true
server_pid=""
HOME="$temporary_root/home" OPENPE_APP_DIR="$temporary_root/Applications" \
  /bin/bash "$installed_app/Contents/Resources/uninstall.sh"
test ! -e "$installed_app"
echo "macOS DMG install, startup, health, and uninstall smoke test passed"

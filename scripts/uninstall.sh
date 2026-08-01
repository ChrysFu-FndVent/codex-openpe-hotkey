#!/bin/bash
set -euo pipefail

purge_secrets=false
case "${1:-}" in
  --purge-secrets)
    purge_secrets=true
    ;;
  -h|--help)
    echo "Usage: $0 [--purge-secrets]"
    exit 0
    ;;
  "") ;;
  *)
    echo "Usage: $0 [--purge-secrets]" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [--purge-secrets]" >&2
  exit 2
fi

user_domain="gui/$(id -u)"
for label in com.openpe.promptenhancer.hotkey com.openpe.promptenhancer.server; do
  /bin/launchctl bootout "$user_domain/$label" >/dev/null 2>&1 || true
done

trash_dir="$HOME/.Trash/CodexOpenPEHotkey-uninstall-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$trash_dir"

move_if_present() {
  local path="$1"
  if [ -e "$path" ]; then
    mv "$path" "$trash_dir/"
  fi
}

move_if_present "${OPENPE_APP_DIR:-$HOME/Applications}/OpenPE Hotkey.app"
move_if_present "$HOME/Library/Application Support/CodexOpenPEHotkey"
move_if_present "$HOME/Library/LaunchAgents/com.openpe.promptenhancer.server.plist"
move_if_present "$HOME/Library/LaunchAgents/com.openpe.promptenhancer.hotkey.plist"

if [ "$purge_secrets" = true ]; then
  account="$(id -un)"
  /usr/bin/security delete-generic-password -a "$account" -s com.openpe.promptenhancer.api-key >/dev/null 2>&1 || true
  /usr/bin/security delete-generic-password -a "$account" -s com.openpe.promptenhancer.server-token >/dev/null 2>&1 || true
  echo "OpenPE Keychain items were removed."
fi

echo "Installed files moved to $trash_dir and can be recovered from Trash."
echo "Shared OpenPE configuration at $HOME/.config/openpe was preserved."

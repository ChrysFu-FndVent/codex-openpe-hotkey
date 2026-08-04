#!/bin/bash
set -euo pipefail

purge_secrets=false
remove_plugin=false
for argument in "$@"; do
  case "$argument" in
    --purge-secrets) purge_secrets=true ;;
    --remove-plugin) remove_plugin=true ;;
    -h|--help)
      echo "Usage: $0 [--purge-secrets] [--remove-plugin]"
      exit 0
      ;;
    *)
      echo "Usage: $0 [--purge-secrets] [--remove-plugin]" >&2
      exit 2
      ;;
  esac
done

user_domain="gui/$(id -u)"
for label in com.openpe.promptenhancer.hotkey com.openpe.promptenhancer.server; do
  /bin/launchctl bootout "$user_domain/$label" >/dev/null 2>&1 || true
done

if [ "$remove_plugin" = true ]; then
  codex_cli=""
  for candidate in \
    "/Applications/Codex.app/Contents/Resources/codex" \
    "/Applications/ChatGPT.app/Contents/Resources/codex" \
    "$HOME/Applications/Codex.app/Contents/Resources/codex" \
    "$HOME/Applications/ChatGPT.app/Contents/Resources/codex"; do
    if [ -x "$candidate" ]; then codex_cli="$candidate"; break; fi
  done
  if [ -z "$codex_cli" ]; then codex_cli="$(command -v codex 2>/dev/null || true)"; fi
  if [ -n "$codex_cli" ]; then
    "$codex_cli" plugin remove codex-openpe-hotkey@codex-openpe-hotkey --json >/dev/null 2>&1 || true
    "$codex_cli" plugin marketplace remove codex-openpe-hotkey --json >/dev/null 2>&1 || true
    echo "Codex OpenPE Plugin and Marketplace entries were removed."
  else
    echo "Codex CLI was not found; Plugin removal was skipped." >&2
  fi
fi

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

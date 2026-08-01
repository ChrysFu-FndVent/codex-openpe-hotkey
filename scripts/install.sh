#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_parent="${OPENPE_APP_DIR:-$HOME/Applications}"
config_dir="${OPENPE_CONFIG_DIR:-$HOME/.config/openpe}"
config_file="$config_dir/.env"
openpe_server_bin="${OPENPE_SERVER_BIN:-}"
codesign_identity="${CODESIGN_IDENTITY:--}"
open_settings=true
hotkey=""

usage() {
  echo "Usage: $0 [--openpe-server PATH] [--app-dir PATH] [--hotkey SHORTCUT] [--no-open-settings]"
}

require_value() {
  if [ "$#" -lt 2 ] || [ -z "$2" ]; then
    echo "Missing value for $1" >&2
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --openpe-server)
      require_value "$@"
      openpe_server_bin="$2"
      shift 2
      ;;
    --app-dir)
      require_value "$@"
      app_parent="$2"
      shift 2
      ;;
    --hotkey)
      require_value "$@"
      hotkey="$2"
      shift 2
      ;;
    --no-open-settings)
      open_settings=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

validate_hotkey() {
  local shortcut="$1"
  local normalized
  local modifier_count=0
  local key_count=0
  local part
  local canonical_part
  local seen=","
  local -a parts
  normalized="$(printf '%s' "$shortcut" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  IFS='+' read -r -a parts <<< "$normalized"
  if [ "${#parts[@]}" -lt 2 ]; then
    return 1
  fi
  for part in "${parts[@]}"; do
    case "$part" in
      cmd|command) canonical_part="command" ;;
      ctrl|control) canonical_part="control" ;;
      alt|opt|option) canonical_part="option" ;;
      shift) canonical_part="shift" ;;
      [a-z]|[0-9]|f[1-9]|f1[0-2]) canonical_part="$part" ;;
      *) return 1 ;;
    esac
    case "$seen" in
      *",$canonical_part,"*) return 1 ;;
    esac
    seen="${seen}${canonical_part},"
    case "$canonical_part" in
      command|control|option|shift)
        modifier_count=$((modifier_count + 1))
        ;;
      [a-z]|[0-9]|f[1-9]|f1[0-2])
        key_count=$((key_count + 1))
        ;;
    esac
  done
  [ "$modifier_count" -ge 1 ] && [ "$key_count" -eq 1 ]
}

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This hotkey helper requires macOS" >&2
  exit 1
fi

for command_name in swift codesign launchctl plutil security curl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

if [ -z "$hotkey" ]; then
  existing_hotkey_plist="$HOME/Library/LaunchAgents/com.openpe.promptenhancer.hotkey.plist"
  hotkey="$(/usr/bin/plutil -extract EnvironmentVariables.OPENPE_HOTKEY raw "$existing_hotkey_plist" 2>/dev/null || true)"
  hotkey="${hotkey:-option+q}"
fi
if ! validate_hotkey "$hotkey"; then
  echo "Invalid hotkey: $hotkey" >&2
  echo "Use at least one of Command/Control/Option/Shift plus A-Z, 0-9, or F1-F12." >&2
  exit 2
fi

if [ -z "$openpe_server_bin" ]; then
  openpe_server_bin="$(command -v openpe-server 2>/dev/null || true)"
fi
if [ -z "$openpe_server_bin" ] && [ -x "$HOME/go/bin/openpe-server" ]; then
  openpe_server_bin="$HOME/go/bin/openpe-server"
fi
if [ -z "$openpe_server_bin" ] || [ ! -x "$openpe_server_bin" ]; then
  echo "openpe-server was not found. Install it from https://github.com/AoManoh/openpe" >&2
  echo "Then rerun with --openpe-server /absolute/path/to/openpe-server" >&2
  exit 1
fi
openpe_server_bin="$(cd "$(dirname "$openpe_server_bin")" && pwd)/$(basename "$openpe_server_bin")"

account="$(id -un)"
for service in com.openpe.promptenhancer.api-key com.openpe.promptenhancer.server-token; do
  if ! /usr/bin/security find-generic-password -a "$account" -s "$service" >/dev/null 2>&1; then
    echo "Missing Keychain item: $service" >&2
    echo "Run $project_root/scripts/configure.sh before installation." >&2
    exit 1
  fi
done

if [ ! -f "$config_file" ]; then
  echo "Missing OpenPE configuration: $config_file" >&2
  echo "Run $project_root/scripts/configure.sh before installation." >&2
  exit 1
fi

swift build -c release --package-path "$project_root"
binary_dir="$(swift build -c release --show-bin-path --package-path "$project_root")"
source_binary="$binary_dir/OpenPEHotkey"
if [ ! -x "$source_binary" ]; then
  echo "Build succeeded but OpenPEHotkey was not found at $source_binary" >&2
  exit 1
fi

bundle="$app_parent/OpenPE Hotkey.app"
staging_root="$(mktemp -d)"
trap 'rm -rf "$staging_root"' EXIT
staged_bundle="$staging_root/OpenPE Hotkey.app"
mkdir -p "$staged_bundle/Contents/MacOS"
cp "$source_binary" "$staged_bundle/Contents/MacOS/OpenPEHotkey"
cp "$project_root/config/Info.plist" "$staged_bundle/Contents/Info.plist"
chmod 755 "$staged_bundle/Contents/MacOS/OpenPEHotkey"
/usr/bin/codesign --force --deep --sign "$codesign_identity" "$staged_bundle"
/usr/bin/codesign --verify --deep --strict "$staged_bundle"

mkdir -p "$app_parent"
if [ -e "$bundle" ]; then
  backup="$HOME/.Trash/OpenPE-Hotkey-before-update-$(date +%Y%m%d-%H%M%S).app"
  mv "$bundle" "$backup"
  echo "Previous app moved to $backup"
fi
mv "$staged_bundle" "$bundle"
trap - EXIT
rm -rf "$staging_root"

support_dir="$HOME/Library/Application Support/CodexOpenPEHotkey"
logs_dir="$HOME/Library/Logs"
launch_agents_dir="$HOME/Library/LaunchAgents"
mkdir -p "$support_dir" "$logs_dir" "$launch_agents_dir"
cp "$project_root/scripts/openpe-server-launcher.sh" "$support_dir/openpe-server-launcher"
chmod 755 "$support_dir/openpe-server-launcher"
printf 'OPENPE_SERVER_BIN=%q\nOPENPE_ENV_FILE=%q\nOPENPE_LISTEN_ADDR=%q\n' \
  "$openpe_server_bin" \
  "$config_file" \
  "127.0.0.1:18980" > "$support_dir/runtime.env"
chmod 600 "$support_dir/runtime.env"

server_plist="$launch_agents_dir/com.openpe.promptenhancer.server.plist"
hotkey_plist="$launch_agents_dir/com.openpe.promptenhancer.hotkey.plist"
cp "$project_root/launchd/com.openpe.promptenhancer.server.plist" "$server_plist"
cp "$project_root/launchd/com.openpe.promptenhancer.hotkey.plist" "$hotkey_plist"

/usr/bin/plutil -replace ProgramArguments.0 -string "$support_dir/openpe-server-launcher" "$server_plist"
/usr/bin/plutil -replace StandardOutPath -string "$logs_dir/openpe-server.log" "$server_plist"
/usr/bin/plutil -replace StandardErrorPath -string "$logs_dir/openpe-server-error.log" "$server_plist"
/usr/bin/plutil -replace ProgramArguments.0 -string "$bundle/Contents/MacOS/OpenPEHotkey" "$hotkey_plist"
/usr/bin/plutil -replace EnvironmentVariables.OPENPE_HOTKEY -string "$hotkey" "$hotkey_plist"
/usr/bin/plutil -replace StandardOutPath -string "$logs_dir/openpe-hotkey.log" "$hotkey_plist"
/usr/bin/plutil -replace StandardErrorPath -string "$logs_dir/openpe-hotkey-error.log" "$hotkey_plist"
/usr/bin/plutil -lint "$server_plist" "$hotkey_plist" >/dev/null

user_domain="gui/$(id -u)"
/bin/launchctl bootout "$user_domain/com.openpe.promptenhancer.hotkey" >/dev/null 2>&1 || true
/bin/launchctl bootout "$user_domain/com.openpe.promptenhancer.server" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "$user_domain" "$server_plist"
/bin/launchctl bootstrap "$user_domain" "$hotkey_plist"

if [ "$codesign_identity" = "-" ]; then
  echo "The app uses an ad-hoc signature. macOS may require Accessibility approval after updates."
fi
if [ "$open_settings" = true ]; then
  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
fi

echo "Installed $bundle"
echo "Configured hotkey: $hotkey"
echo "Enable OpenPE Hotkey in Privacy & Security > Accessibility, then run scripts/status.sh."

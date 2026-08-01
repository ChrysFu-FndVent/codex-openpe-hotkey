#!/bin/zsh
set -euo pipefail

runtime_file="${OPENPE_HOTKEY_RUNTIME_FILE:-$HOME/Library/Application Support/CodexOpenPEHotkey/runtime.env}"
if [[ ! -f "$runtime_file" ]]; then
  print -u2 "Missing runtime configuration: $runtime_file"
  exit 1
fi

source "$runtime_file"

account="${OPENPE_KEYCHAIN_ACCOUNT:-$(id -un)}"
api_key_service="${OPENPE_API_KEY_SERVICE:-com.openpe.promptenhancer.api-key}"
server_token_service="${OPENPE_SERVER_TOKEN_SERVICE:-com.openpe.promptenhancer.server-token}"

openpe_api_key=$(/usr/bin/security find-generic-password -a "$account" -s "$api_key_service" -w)
openpe_server_token=$(/usr/bin/security find-generic-password -a "$account" -s "$server_token_service" -w)

export OPENPE_API_KEY="$openpe_api_key"
export OPENPE_SERVER_TOKEN="$openpe_server_token"
export OPENPE_ENV_FILE="${OPENPE_ENV_FILE:-$HOME/.config/openpe/.env}"

exec "$OPENPE_SERVER_BIN" --listen "${OPENPE_LISTEN_ADDR:-127.0.0.1:18980}"

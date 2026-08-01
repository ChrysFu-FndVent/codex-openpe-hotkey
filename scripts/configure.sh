#!/bin/bash
set -euo pipefail

base_url="https://api.openai.com/v1"
model="gpt-5.4-mini"
language="zh"
timeout="60s"
system_prompt="Rewrite the user request as a concise, actionable instruction for a coding agent. Preserve intent, facts, constraints, and language. Do not invent requirements. Output only the rewritten instruction."
api_key_stdin=false
reuse_api_key=false

usage() {
  echo "Usage: $0 [--base-url URL] [--model NAME] [--language CODE] [--timeout DURATION]"
  echo "          [--system-prompt TEXT] [--api-key-stdin | --reuse-api-key]"
}

require_value() {
  if [ "$#" -lt 2 ] || [ -z "$2" ]; then
    echo "Missing value for $1" >&2
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-url)
      require_value "$@"
      base_url="$2"
      shift 2
      ;;
    --model)
      require_value "$@"
      model="$2"
      shift 2
      ;;
    --language)
      require_value "$@"
      language="$2"
      shift 2
      ;;
    --timeout)
      require_value "$@"
      timeout="$2"
      shift 2
      ;;
    --system-prompt)
      require_value "$@"
      system_prompt="$2"
      shift 2
      ;;
    --api-key-stdin)
      api_key_stdin=true
      shift
      ;;
    --reuse-api-key)
      reuse_api_key=true
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

if [ "$api_key_stdin" = true ] && [ "$reuse_api_key" = true ]; then
  echo "--api-key-stdin and --reuse-api-key cannot be used together" >&2
  exit 2
fi

for value in "$base_url" "$model" "$language" "$timeout" "$system_prompt"; do
  case "$value" in
    *$'\n'*|*$'\r'*)
      echo "Configuration values must not contain newlines" >&2
      exit 2
      ;;
  esac
done

case "$base_url" in
  http://*|https://*) ;;
  *)
    echo "Base URL must start with http:// or https://" >&2
    exit 2
    ;;
esac

account="$(id -un)"
api_key_service="com.openpe.promptenhancer.api-key"
server_token_service="com.openpe.promptenhancer.server-token"

if [ "$reuse_api_key" = true ]; then
  if ! /usr/bin/security find-generic-password -a "$account" -s "$api_key_service" >/dev/null 2>&1; then
    echo "No existing OpenPE API key was found in Keychain" >&2
    exit 1
  fi
else
  if [ "$api_key_stdin" = true ]; then
    IFS= read -r api_key
  elif [ -t 0 ]; then
    printf "OpenAI-compatible API key (stored in Keychain): "
    IFS= read -r -s api_key
    printf "\n"
  else
    echo "Use --api-key-stdin for non-interactive configuration" >&2
    exit 2
  fi
  if [ -z "${api_key:-}" ]; then
    echo "API key must not be empty" >&2
    exit 2
  fi
  /usr/bin/security add-generic-password \
    -a "$account" \
    -s "$api_key_service" \
    -w "$api_key" \
    -U >/dev/null
  unset api_key
fi

if ! /usr/bin/security find-generic-password -a "$account" -s "$server_token_service" >/dev/null 2>&1; then
  server_token="$(/usr/bin/openssl rand -hex 32)"
  /usr/bin/security add-generic-password \
    -a "$account" \
    -s "$server_token_service" \
    -w "$server_token" \
    -U >/dev/null
  unset server_token
fi

escape_double_quoted() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

config_dir="${OPENPE_CONFIG_DIR:-$HOME/.config/openpe}"
config_file="$config_dir/.env"
mkdir -p "$config_dir"
chmod 700 "$config_dir"
umask 077
temporary_file="$(mktemp "$config_dir/.env.XXXXXX")"
trap 'rm -f "$temporary_file"' EXIT

{
  printf 'OPENPE_BASE_URL=%s\n' "$base_url"
  printf 'OPENPE_MODEL=%s\n' "$model"
  printf 'OPENPE_LANGUAGE=%s\n' "$language"
  printf 'OPENPE_TIMEOUT=%s\n' "$timeout"
  printf 'OPENPE_SYSTEM_PROMPT="%s"\n' "$(escape_double_quoted "$system_prompt")"
} > "$temporary_file"

mv "$temporary_file" "$config_file"
chmod 600 "$config_file"
trap - EXIT

echo "OpenPE configuration written to $config_file"
echo "API key and local server token are stored in macOS Keychain."

#!/bin/bash
set -euo pipefail

support_dir="${OPENPE_SIGNING_DIR:-$HOME/Library/Application Support/CodexOpenPEHotkey/signing}"
keychain="$support_dir/OpenPEHotkey.keychain-db"
password_file="$support_dir/keychain-password"
environment_file="$support_dir/local-signing.env"
identity="${OPENPE_CODESIGN_IDENTITY:-OpenPE Hotkey Local Code Signing}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Local code-signing setup requires macOS" >&2
  exit 1
fi

for command_name in openssl security; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

identity_is_valid() {
  [ -f "$keychain" ] &&
    [ -f "$password_file" ] &&
    [ -f "$environment_file" ] &&
    /usr/bin/security find-identity -p codesigning -v "$keychain" 2>/dev/null |
      /usr/bin/grep -Fq "\"$identity\""
}

add_to_user_search_list() {
  local line
  local path
  local found=false
  local -a keychains

  while IFS= read -r line; do
    path="${line#*\"}"
    path="${path%\"*}"
    [ -n "$path" ] || continue
    keychains+=("$path")
    if [ "$path" = "$keychain" ]; then
      found=true
    fi
  done < <(/usr/bin/security list-keychains -d user)

  if [ "$found" = false ]; then
    /usr/bin/security list-keychains -d user -s "${keychains[@]}" "$keychain"
  fi
}

if identity_is_valid; then
  add_to_user_search_list
  echo "Stable local signing identity is ready: $identity"
  echo "Configuration: $environment_file"
  exit 0
fi

if [ -e "$keychain" ] || [ -e "$password_file" ] || [ -e "$environment_file" ]; then
  echo "Incomplete local-signing state exists in $support_dir" >&2
  echo "Move that directory aside, then rerun this script." >&2
  exit 1
fi

mkdir -p "$support_dir"
chmod 700 "$support_dir"

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
private_key="$temporary_dir/private-key.pem"
certificate="$temporary_dir/certificate.pem"
archive="$temporary_dir/identity.p12"
p12_password_file="$temporary_dir/p12-password"

umask 077
/usr/bin/openssl rand -hex 32 > "$password_file"
/usr/bin/openssl rand -hex 32 > "$p12_password_file"
chmod 600 "$password_file" "$p12_password_file"

/usr/bin/openssl req \
  -newkey rsa:2048 \
  -nodes \
  -x509 \
  -sha256 \
  -days 3650 \
  -subj "/CN=$identity/O=Local Development" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -keyout "$private_key" \
  -out "$certificate" >/dev/null 2>&1

/usr/bin/openssl pkcs12 \
  -export \
  -inkey "$private_key" \
  -in "$certificate" \
  -name "$identity" \
  -passout "file:$p12_password_file" \
  -out "$archive"

IFS= read -r keychain_password < "$password_file"
IFS= read -r p12_password < "$p12_password_file"
/usr/bin/security create-keychain -p "$keychain_password" "$keychain"
/usr/bin/security set-keychain-settings -lut 21600 "$keychain"
/usr/bin/security unlock-keychain -p "$keychain_password" "$keychain"
/usr/bin/security import "$archive" \
  -k "$keychain" \
  -P "$p12_password" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null
/usr/bin/security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "$keychain_password" \
  "$keychain" >/dev/null
/usr/bin/security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$keychain" \
  "$certificate"
unset keychain_password p12_password

add_to_user_search_list

{
  printf 'OPENPE_CODESIGN_IDENTITY=%q\n' "$identity"
  printf 'OPENPE_CODESIGN_KEYCHAIN=%q\n' "$keychain"
  printf 'OPENPE_CODESIGN_PASSWORD_FILE=%q\n' "$password_file"
} > "$environment_file"
chmod 600 "$environment_file"

if ! identity_is_valid; then
  echo "The local signing identity was created but could not be validated" >&2
  exit 1
fi

echo "Created stable local signing identity: $identity"
echo "Configuration: $environment_file"
echo "The private key remains only in the dedicated local keychain."

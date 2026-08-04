#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/../.." && pwd)"
version="$(tr -d '[:space:]' < "$project_root/release/version.txt")"
dist_dir="${DIST_DIR:-$project_root/dist}"
server_binary="${OPENPE_SERVER_BINARY:-$dist_dir/openpe-server}"
product_name="Codex-OpenPE-Hotkey-$version-macOS-universal"
output_dmg="$dist_dir/$product_name.dmg"

for command_name in swift lipo codesign hdiutil plutil jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid release version: $version" >&2
  exit 1
fi
if [ ! -x "$server_binary" ]; then
  echo "Missing universal openPE server: $server_binary" >&2
  echo "Run scripts/release/build-openpe.sh first." >&2
  exit 1
fi

plugin_version="$(jq -r '.version' "$project_root/.codex-plugin/plugin.json")"
plist_version="$(plutil -extract CFBundleShortVersionString raw "$project_root/config/Info.plist")"
if [ "$plugin_version" != "$version" ] || [ "$plist_version" != "$version" ]; then
  echo "Version mismatch: release=$version plugin=$plugin_version plist=$plist_version" >&2
  exit 1
fi

arm64_build="$project_root/.build/release-arm64"
x86_64_build="$project_root/.build/release-x86_64"
swift build -c release --arch arm64 --scratch-path "$arm64_build" --package-path "$project_root"
swift build -c release --arch x86_64 --scratch-path "$x86_64_build" --package-path "$project_root"
arm64_binary_dir="$(swift build -c release --arch arm64 --scratch-path "$arm64_build" \
  --show-bin-path --package-path "$project_root")"
x86_64_binary_dir="$(swift build -c release --arch x86_64 --scratch-path "$x86_64_build" \
  --show-bin-path --package-path "$project_root")"
for binary in "$arm64_binary_dir/OpenPEHotkey" "$x86_64_binary_dir/OpenPEHotkey"; do
  if [ ! -x "$binary" ]; then
    echo "Missing release helper binary: $binary" >&2
    exit 1
  fi
done
for binary in "$server_binary"; do
  architectures="$(lipo -archs "$binary")"
  if [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
    echo "Expected arm64 and x86_64 in $binary, got: $architectures" >&2
    exit 1
  fi
done

staging_root="$(mktemp -d)"
trap 'rm -rf "$staging_root"' EXIT
volume_root="$staging_root/volume"
bundle="$volume_root/OpenPE Hotkey.app"
resources="$bundle/Contents/Resources"
mkdir -p "$bundle/Contents/MacOS" "$resources/CodexPlugin"

lipo -create "$arm64_binary_dir/OpenPEHotkey" "$x86_64_binary_dir/OpenPEHotkey" \
  -output "$bundle/Contents/MacOS/OpenPEHotkey"
cp "$project_root/config/Info.plist" "$bundle/Contents/Info.plist"
cp "$server_binary" "$resources/openpe-server"
cp "$project_root/scripts/openpe-server-launcher.sh" "$resources/openpe-server-launcher.sh"
cp "$project_root/scripts/uninstall.sh" "$resources/uninstall.sh"
cp "$project_root/LICENSE" "$resources/LICENSE"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$resources/THIRD_PARTY_NOTICES.md"
cp -R "$project_root/.codex-plugin" "$resources/CodexPlugin/.codex-plugin"
cp -R "$project_root/.agents" "$resources/CodexPlugin/.agents"
cp -R "$project_root/skills" "$resources/CodexPlugin/skills"
chmod 755 "$bundle/Contents/MacOS/OpenPEHotkey" "$resources/openpe-server" \
  "$resources/openpe-server-launcher.sh" "$resources/uninstall.sh"
ln -s /Applications "$volume_root/Applications"

# Ad-hoc signing gives the nested executables and app a consistent local identity.
codesign --force --sign - "$resources/openpe-server"
codesign --force --sign - "$bundle/Contents/MacOS/OpenPEHotkey"
codesign --force --deep --sign - "$bundle"
codesign --verify --deep --strict --verbose=2 "$bundle"

rm -f "$output_dmg"
mkdir -p "$dist_dir"
hdiutil create -quiet -volname "Codex OpenPE Hotkey $version" \
  -srcfolder "$volume_root" -ov -format UDZO "$output_dmg"
hdiutil verify "$output_dmg" >/dev/null

mount_point="$staging_root/mount"
mkdir -p "$mount_point"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_point" "$output_dmg"
mounted_bundle="$mount_point/OpenPE Hotkey.app"
trap 'hdiutil detach -quiet "$mount_point" >/dev/null 2>&1 || true; rm -rf "$staging_root"' EXIT
codesign --verify --deep --strict --verbose=2 "$mounted_bundle"
gatekeeper_result="$staging_root/gatekeeper.txt"
if spctl -a -vv --type execute "$mounted_bundle" 2>"$gatekeeper_result"; then
  echo "Expected unsigned/ad-hoc release to require explicit user approval." >&2
  cat "$gatekeeper_result" >&2
  exit 1
fi
if ! grep -qi "rejected" "$gatekeeper_result"; then
  echo "Gatekeeper did not return the expected rejected classification." >&2
  cat "$gatekeeper_result" >&2
  exit 1
fi
test -x "$mounted_bundle/Contents/Resources/openpe-server"
test -x "$mounted_bundle/Contents/Resources/uninstall.sh"
test -f "$mounted_bundle/Contents/Resources/CodexPlugin/.agents/plugins/marketplace.json"
test -f "$mounted_bundle/Contents/Resources/CodexPlugin/skills/codex-openpe-hotkey/SKILL.md"
lipo -archs "$mounted_bundle/Contents/MacOS/OpenPEHotkey"
lipo -archs "$mounted_bundle/Contents/Resources/openpe-server"
hdiutil detach -quiet "$mount_point"
trap 'rm -rf "$staging_root"' EXIT

(cd "$dist_dir" && shasum -a 256 "$(basename "$output_dmg")" > "$(basename "$output_dmg").sha256")
echo "Created $output_dmg"
echo "Created $output_dmg.sha256"

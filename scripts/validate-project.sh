#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

swift build
swift run CoreSelfTests

for script in scripts/*.sh scripts/release/*.sh; do
  /bin/bash -n "$script"
done

/usr/bin/plutil -lint config/Info.plist launchd/*.plist
/usr/bin/jq -e '.name == "codex-openpe-hotkey" and .skills == "./skills/"' \
  .codex-plugin/plugin.json >/dev/null
/usr/bin/jq -e '
  .name == "codex-openpe-hotkey" and
  (.plugins | length) == 1 and
  .plugins[0].name == "codex-openpe-hotkey" and
  .plugins[0].source.source == "local" and
  .plugins[0].source.path == "./"
' .agents/plugins/marketplace.json >/dev/null

for windows_file in \
  windows/OpenPEHotkey.Windows.cs \
  windows/CodexOpenPEHotkey.Windows.csproj \
  windows/SetupWizard.cs \
  windows/CodexOpenPEHotkey.Setup.csproj \
  windows/Directory.Build.props \
  installer/windows/CodexOpenPEHotkey.iss \
  scripts/windows/install.ps1 \
  scripts/windows/configure.ps1 \
  scripts/windows/start.ps1 \
  scripts/windows/status.ps1 \
  scripts/windows/uninstall.ps1 \
  scripts/windows/validate.ps1 \
  scripts/windows/installer-uninstall.ps1 \
  scripts/release/build-openpe.ps1 \
  scripts/release/package-windows.ps1 \
  scripts/release/smoke-windows.ps1; do
  if [ ! -f "$windows_file" ]; then
    echo "Missing Windows component: $windows_file" >&2
    exit 1
  fi
done

release_version="$(tr -d '[:space:]' < release/version.txt)"
plugin_version="$(/usr/bin/jq -r '.version' .codex-plugin/plugin.json)"
plist_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw config/Info.plist)"
if [ "$release_version" != "$plugin_version" ] || [ "$release_version" != "$plist_version" ]; then
  echo "Release version mismatch: release=$release_version plugin=$plugin_version plist=$plist_version" >&2
  exit 1
fi
for versioned_file in \
  Sources/CodexOpenPEHotkey/ReleaseInstaller.swift \
  windows/CodexOpenPEHotkey.Windows.csproj \
  windows/CodexOpenPEHotkey.Setup.csproj \
  windows/OpenPEHotkey.Windows.cs \
  installer/windows/CodexOpenPEHotkey.iss; do
  if ! /usr/bin/grep -Fq "$release_version" "$versioned_file"; then
    echo "Release version $release_version is missing from $versioned_file" >&2
    exit 1
  fi
done

openai_key_pattern='s''k-[A-Za-z0-9_-]{20,}'
hardcoded_api_key_pattern="OPENPE_API_KEY[[:space:]]*=[[:space:]]*['\"]?[A-Za-z0-9_-]{20,}"

if rg -n --hidden -g '!.build/**' -g '!.git/**' -g '!scripts/validate-project.sh' \
  "($openai_key_pattern|$hardcoded_api_key_pattern)" .; then
  echo "Potential secret found" >&2
  exit 1
fi

if rg -n --hidden -g '!.build/**' -g '!.git/**' -g '!scripts/validate-project.sh' '\[TODO:' .; then
  echo "Placeholder TODO markers remain" >&2
  exit 1
fi

echo "Project validation passed"

#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

swift build
swift run CoreSelfTests

for script in scripts/*.sh; do
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
  scripts/windows/install.ps1 \
  scripts/windows/configure.ps1 \
  scripts/windows/start.ps1 \
  scripts/windows/status.ps1 \
  scripts/windows/uninstall.ps1 \
  scripts/windows/validate.ps1; do
  if [ ! -f "$windows_file" ]; then
    echo "Missing Windows component: $windows_file" >&2
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

---
name: codex-openpe-hotkey
description: Install, configure, verify, diagnose, or uninstall the Codex OpenPE prompt-enhancement hotkey helper on macOS or Windows. Use when a user asks for Option+Q, Alt+Q, a custom prompt-enhancement shortcut inside the Codex desktop composer, inline generation progress, OpenPE local-server setup, hotkey troubleshooting, macOS Accessibility permission checks, Windows startup checks, or removal of this integration.
---

# Codex OpenPE Hotkey

## Overview

Operate the plugin's local desktop helper without exposing secrets or modifying unrelated Codex settings. The helper only handles selected text in allowed applications. It defaults to `com.openai.codex` on macOS and the `Codex` or `ChatGPT` process on Windows.

## Resolve Paths

Treat the directory two levels above this file as the plugin root. Use scripts from `<plugin-root>/scripts/`; do not copy script bodies into shell commands.

## Select Platform

- On macOS, use the root `scripts/*.sh` tools. The default is `Option+Q`; pass `--hotkey <shortcut>` to `install.sh` to customize it.
- On Windows, use `scripts/windows/*.ps1`. The default is `Alt+Q`; pass `-HotKey <shortcut>` to `install.ps1` or `configure.ps1` to customize it.
- Stop with an unsupported-platform explanation on Linux. Do not try to run the desktop helper under WSL.

## Install

1. Read the root `README.md` before changing the installation.
2. Confirm the platform prerequisites and an executable `openpe-server` are available.
3. Preserve existing OpenPE and hotkey configuration unless the user explicitly requests reconfiguration. Do not reset a custom shortcut to its platform default during maintenance.
4. Never print, read back, log, or place API keys or bearer tokens on a command line.
5. On macOS, run `scripts/configure.sh` when needed, then `scripts/install.sh`. Ask the user to enable `OpenPE Hotkey` in Privacy & Security > Accessibility if macOS prompts.
6. On Windows, run `scripts/windows/install.ps1`; it prompts for the API key, stores credentials in Windows Credential Manager, and creates a per-user Startup shortcut. Do not request administrator elevation.
7. Run the platform status script and require the helper process, local `/healthz`, and hidden-background configuration to pass.
8. Have the user select a harmless prompt in Codex, press the platform hotkey, keep Codex focused, and confirm inline progress is replaced by an enhanced prompt.

Do not claim completion before the real Codex composer test succeeds.

## Diagnose

Run `scripts/status.sh` on macOS or `scripts/windows/status.ps1` on Windows. Inspect only the platform's relevant OpenPE logs.

- `~/Library/Logs/openpe-hotkey-error.log`
- `~/Library/Logs/openpe-server-error.log`

Interpret common results as follows:

- `accessibility permission unavailable`: refresh the app entry in Accessibility settings and restart the hotkey LaunchAgent.
- `frontmost application is not allowed`: keep Codex focused or adjust `OPENPE_ALLOWED_BUNDLE_IDS` intentionally.
- `inline selection changed`: the user moved the selection; the result is copied instead of applied.
- `enhancement request failed`: verify local server health, gateway model availability, and the configured timeout.
- Repeated permission loss after rebuild: sign with a stable `CODESIGN_IDENTITY`; ad-hoc signatures may require renewed approval.
- Windows helper not running: check the per-user Startup shortcut and `%LOCALAPPDATA%\CodexOpenPEHotkey\hotkey-error.log`.
- Windows foreground application rejected: verify the actual executable name and update `AllowedProcessNames` intentionally with `configure.ps1`.
- Hotkey registration failure: the combination is invalid or already owned. Configure at least one supported modifier plus `A-Z`, `0-9`, or `F1-F12`, restart, and rerun the status check.

Never inspect or configure other agent applications unless the user explicitly includes them.

## Uninstall

Run `scripts/uninstall.sh` on macOS or `scripts/windows/uninstall.ps1` on Windows. Preserve shared OpenPE configuration and stored credentials by default. Use the platform purge-secrets option only when the user explicitly asks to remove credentials.

## Develop

After source changes, run `scripts/validate-project.sh`, `scripts/windows/validate.ps1` on Windows, the Codex plugin validator, and the Skill quick validator. Rebuild before repeating the real composer test. Do not alter a live installation merely to validate source code.

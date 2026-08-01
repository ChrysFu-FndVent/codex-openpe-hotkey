#requires -version 5.1

[CmdletBinding()]
param([switch]$PurgeSecrets)

. (Join-Path $PSScriptRoot "common.ps1")
Assert-WindowsPlatform

$installDirectory = Get-OpenPEInstallDirectory
$dataDirectory = Get-OpenPEDataDirectory

Stop-InstalledOpenPEProcesses
$shortcut = Get-OpenPEStartupShortcut
Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue

if ($PurgeSecrets) {
    Remove-OpenPECredentials
}

Remove-Item -LiteralPath $installDirectory -Recurse -Force -ErrorAction SilentlyContinue
if ($PurgeSecrets) {
    Remove-Item -LiteralPath $dataDirectory -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed the helper, integration configuration, logs, and OpenPE credentials."
}
else {
    Remove-Item -LiteralPath (Join-Path $dataDirectory "hotkey.pid") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $dataDirectory "server.pid") -Force -ErrorAction SilentlyContinue
    Write-Host "Removed the helper and Startup shortcut. Configuration and credentials were preserved."
}

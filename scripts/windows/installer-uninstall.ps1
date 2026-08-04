#requires -version 5.1

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot "common.ps1")
Assert-WindowsPlatform

Stop-InstalledOpenPEProcesses
Remove-Item -LiteralPath (Get-OpenPEStartupShortcut) -Force -ErrorAction SilentlyContinue

$localPrograms = Join-Path $env:LOCALAPPDATA "Programs"
$codexCandidates = @(
    (Join-Path $localPrograms "Codex\resources\codex.exe"),
    (Join-Path $localPrograms "Codex\Resources\codex.exe"),
    (Join-Path $localPrograms "ChatGPT\resources\codex.exe"),
    (Join-Path $env:ProgramFiles "Codex\resources\codex.exe")
)
$pathCommand = Get-Command codex.exe -ErrorAction SilentlyContinue
if ($null -ne $pathCommand) { $codexCandidates += $pathCommand.Source }
$codexCli = $codexCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if ($null -ne $codexCli) {
    & $codexCli plugin remove codex-openpe-hotkey@codex-openpe-hotkey --json 2>$null | Out-Null
    & $codexCli plugin marketplace remove codex-openpe-hotkey --json 2>$null | Out-Null
}

Remove-OpenPECredentials
Remove-Item -LiteralPath (Get-OpenPEDataDirectory) -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Removed Codex OpenPE Hotkey processes, Plugin, startup entry, configuration, logs, and credentials."

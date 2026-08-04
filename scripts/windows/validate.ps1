#requires -version 5.1

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot "common.ps1")
Assert-WindowsPlatform

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$parseFailed = $false
$scriptDirectories = @($PSScriptRoot, (Join-Path $projectRoot "scripts\release"))
Get-ChildItem -LiteralPath $scriptDirectories -Filter "*.ps1" | ForEach-Object {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $parseFailed = $true
        $errors | ForEach-Object { Write-Error "$($_.Extent.File):$($_.Extent.StartLineNumber): $($_.Message)" }
    }
}
if ($parseFailed) { throw "PowerShell syntax validation failed." }

$source = Join-Path $projectRoot "windows\OpenPEHotkey.Windows.cs"
Add-Type `
    -Path $source `
    -ReferencedAssemblies (Get-HelperReferences)
[CodexOpenPEHotkey.Windows.SelfTests]::Run()

$marketplacePath = Join-Path $projectRoot ".agents\plugins\marketplace.json"
$marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
if ($marketplace.name -ne "codex-openpe-hotkey" -or
    $marketplace.plugins.Count -ne 1 -or
    $marketplace.plugins[0].name -ne "codex-openpe-hotkey") {
    throw "Marketplace metadata is invalid."
}

Write-Host "Windows validation passed"

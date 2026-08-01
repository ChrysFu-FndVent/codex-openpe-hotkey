#requires -version 5.1

[CmdletBinding()]
param(
    [string]$OpenPEServer,
    [string]$BaseUrl,
    [string]$Model,
    [ValidateSet("zh", "en")][string]$Language,
    [string]$Timeout,
    [ValidateSet("zh", "en")][string]$ProgressLanguage,
    [string]$AllowedProcessNames,
    [string]$HotKey,
    [switch]$ReplaceApiKey,
    [switch]$RotateServerToken,
    [switch]$NoRestart
)

. (Join-Path $PSScriptRoot "common.ps1")
Assert-WindowsPlatform

$installDirectory = Get-OpenPEInstallDirectory
$assembly = Join-Path $installDirectory "CodexOpenPEHotkey.Windows.dll"
$configFile = Join-Path (Get-OpenPEDataDirectory) "config.json"
if (-not (Test-Path -LiteralPath $assembly) -or -not (Test-Path -LiteralPath $configFile)) {
    throw "The Windows helper is not installed. Run install.ps1 first."
}
Add-Type -Path $assembly
$configuration = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
if ($configuration.PSObject.Properties.Name -notcontains "HotKey") {
    $configuration | Add-Member -NotePropertyName "HotKey" -NotePropertyValue "Alt+Q"
}

if (-not [string]::IsNullOrWhiteSpace($OpenPEServer)) {
    if (-not (Test-Path -LiteralPath $OpenPEServer -PathType Leaf)) {
        throw "openpe-server.exe was not found: $OpenPEServer"
    }
    $configuration.OpenPEServerPath = (Resolve-Path -LiteralPath $OpenPEServer).Path
}
if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) { $configuration.BaseUrl = $BaseUrl }
if (-not [string]::IsNullOrWhiteSpace($Model)) { $configuration.Model = $Model }
if (-not [string]::IsNullOrWhiteSpace($Language)) { $configuration.Language = $Language }
if (-not [string]::IsNullOrWhiteSpace($Timeout)) { $configuration.OpenPETimeout = $Timeout }
if (-not [string]::IsNullOrWhiteSpace($ProgressLanguage)) { $configuration.ProgressLanguage = $ProgressLanguage }
if (-not [string]::IsNullOrWhiteSpace($AllowedProcessNames)) { $configuration.AllowedProcessNames = $AllowedProcessNames }
if (-not [string]::IsNullOrWhiteSpace($HotKey)) { $configuration.HotKey = $HotKey }

foreach ($name in @("BaseUrl", "Model", "Language", "OpenPETimeout", "ProgressLanguage", "AllowedProcessNames", "HotKey")) {
    $value = [string]$configuration.$name
    if ([string]::IsNullOrWhiteSpace($value) -or $value.Contains("`r") -or $value.Contains("`n")) {
        throw "$name must be non-empty and must not contain newlines."
    }
}
$hotKeyBinding = [CodexOpenPEHotkey.Windows.HotKeyBinding]::Parse([string]$configuration.HotKey)
$configuration.HotKey = $hotKeyBinding.DisplayName
$parsedBaseUrl = $null
if (-not [Uri]::TryCreate([string]$configuration.BaseUrl, [UriKind]::Absolute, [ref]$parsedBaseUrl) -or
    $parsedBaseUrl.Scheme -notin @("http", "https")) {
    throw "BaseUrl must be an absolute HTTP or HTTPS URL."
}

if ($ReplaceApiKey) {
    $secureApiKey = Read-Host "New OpenAI-compatible API key" -AsSecureString
    $plainApiKey = Convert-SecureStringToPlainText -SecureValue $secureApiKey
    try {
        if ([string]::IsNullOrEmpty($plainApiKey)) { throw "API key must not be empty." }
        [CodexOpenPEHotkey.Windows.CredentialStore]::Write(
            [CodexOpenPEHotkey.Windows.CredentialStore]::ApiKeyTarget,
            $plainApiKey)
    }
    finally {
        $plainApiKey = $null
        $secureApiKey.Dispose()
    }
}
if ($RotateServerToken) {
    $serverToken = [CodexOpenPEHotkey.Windows.CredentialStore]::GenerateServerToken()
    try {
        [CodexOpenPEHotkey.Windows.CredentialStore]::Write(
            [CodexOpenPEHotkey.Windows.CredentialStore]::ServerTokenTarget,
            $serverToken)
    }
    finally {
        $serverToken = $null
    }
}

Write-Utf8Json -Value $configuration -Path $configFile
if (-not $NoRestart) {
    Stop-InstalledOpenPEProcesses
    Start-InstalledOpenPEHotkey
    Start-Sleep -Seconds 2
}
Write-Host "Updated Windows configuration at $configFile"
Write-Host "Configured hotkey: $($hotKeyBinding.DisplayName)"

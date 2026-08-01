#requires -version 5.1

[CmdletBinding()]
param(
    [string]$OpenPEServer,
    [string]$BaseUrl = "https://api.openai.com/v1",
    [string]$Model = "gpt-5.4-mini",
    [ValidateSet("zh", "en")][string]$Language = "zh",
    [string]$Timeout = "60s",
    [ValidateSet("zh", "en")][string]$ProgressLanguage = "zh",
    [string]$AllowedProcessNames = "Codex,ChatGPT",
    [string]$HotKey,
    [switch]$ReuseApiKey,
    [switch]$NoStart
)

. (Join-Path $PSScriptRoot "common.ps1")
Assert-WindowsPlatform

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$existingConfigFile = Join-Path (Get-OpenPEDataDirectory) "config.json"
if ([string]::IsNullOrWhiteSpace($HotKey)) {
    if (Test-Path -LiteralPath $existingConfigFile) {
        $existingConfiguration = Get-Content -LiteralPath $existingConfigFile -Raw | ConvertFrom-Json
        if ($existingConfiguration.PSObject.Properties.Name -contains "HotKey" -and
            -not [string]::IsNullOrWhiteSpace([string]$existingConfiguration.HotKey)) {
            $HotKey = [string]$existingConfiguration.HotKey
        }
    }
    if ([string]::IsNullOrWhiteSpace($HotKey)) { $HotKey = "Alt+Q" }
}
Assert-WindowsHotKey -HotKey $HotKey
if ([string]::IsNullOrWhiteSpace($OpenPEServer)) {
    $command = Get-Command "openpe-server.exe" -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $OpenPEServer = $command.Source
    }
    else {
        $goBinary = Join-Path $env:USERPROFILE "go\bin\openpe-server.exe"
        if (Test-Path -LiteralPath $goBinary) {
            $OpenPEServer = $goBinary
        }
    }
}
if ([string]::IsNullOrWhiteSpace($OpenPEServer) -or -not (Test-Path -LiteralPath $OpenPEServer -PathType Leaf)) {
    throw "openpe-server.exe was not found. Build openPE with Go 1.25+, then pass -OpenPEServer with its full path."
}
$OpenPEServer = (Resolve-Path -LiteralPath $OpenPEServer).Path

foreach ($value in @($BaseUrl, $Model, $Language, $Timeout, $ProgressLanguage, $AllowedProcessNames, $HotKey)) {
    if ([string]::IsNullOrWhiteSpace($value) -or $value.Contains("`r") -or $value.Contains("`n")) {
        throw "Configuration values must be non-empty and must not contain newlines."
    }
}
$parsedBaseUrl = $null
if (-not [Uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$parsedBaseUrl) -or
    $parsedBaseUrl.Scheme -notin @("http", "https")) {
    throw "BaseUrl must be an absolute HTTP or HTTPS URL."
}

$installDirectory = Get-OpenPEInstallDirectory
$dataDirectory = Get-OpenPEDataDirectory
$assembly = Join-Path $installDirectory "CodexOpenPEHotkey.Windows.dll"
$source = Join-Path $projectRoot "windows\OpenPEHotkey.Windows.cs"

Stop-InstalledOpenPEProcesses
New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "start.ps1") -Destination $installDirectory -Force
Copy-Item -LiteralPath $source -Destination $installDirectory -Force
Build-WindowsHelper -SourcePath $source -OutputAssembly $assembly
[CodexOpenPEHotkey.Windows.SelfTests]::Run()
$hotKeyBinding = [CodexOpenPEHotkey.Windows.HotKeyBinding]::Parse($HotKey)

if ($ReuseApiKey) {
    $existingApiKey = [CodexOpenPEHotkey.Windows.CredentialStore]::Read(
        [CodexOpenPEHotkey.Windows.CredentialStore]::ApiKeyTarget)
    if ([string]::IsNullOrEmpty($existingApiKey)) {
        throw "No existing OpenPE API key was found in Windows Credential Manager."
    }
    $existingApiKey = $null
}
else {
    $secureApiKey = Read-Host "OpenAI-compatible API key (stored in Windows Credential Manager)" -AsSecureString
    $plainApiKey = Convert-SecureStringToPlainText -SecureValue $secureApiKey
    try {
        if ([string]::IsNullOrEmpty($plainApiKey)) {
            throw "API key must not be empty."
        }
        [CodexOpenPEHotkey.Windows.CredentialStore]::Write(
            [CodexOpenPEHotkey.Windows.CredentialStore]::ApiKeyTarget,
            $plainApiKey)
    }
    finally {
        $plainApiKey = $null
        $secureApiKey.Dispose()
    }
}

$serverToken = [CodexOpenPEHotkey.Windows.CredentialStore]::GenerateServerToken()
try {
    [CodexOpenPEHotkey.Windows.CredentialStore]::Write(
        [CodexOpenPEHotkey.Windows.CredentialStore]::ServerTokenTarget,
        $serverToken)
}
finally {
    $serverToken = $null
}

$configuration = [ordered]@{
    Endpoint = "http://127.0.0.1:18980/v1/prompt-enhance"
    RequestTimeoutSeconds = 75
    AllowedProcessNames = $AllowedProcessNames
    ProgressLanguage = $ProgressLanguage
    OpenPEServerPath = $OpenPEServer
    ListenAddress = "127.0.0.1:18980"
    BaseUrl = $BaseUrl
    Model = $Model
    Language = $Language
    OpenPETimeout = $Timeout
    SystemPrompt = "Rewrite the user request as a concise, actionable instruction for a coding agent. Preserve intent, facts, constraints, and language. Do not invent requirements. Output only the rewritten instruction."
    HotKey = $hotKeyBinding.DisplayName
}
$configFile = Join-Path $dataDirectory "config.json"
Write-Utf8Json -Value $configuration -Path $configFile

$shortcutPath = Get-OpenPEStartupShortcut
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$shortcut.Arguments = '-NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $installDirectory "start.ps1")
$shortcut.WorkingDirectory = $installDirectory
$shortcut.WindowStyle = 7
$shortcut.Description = "Codex OpenPE $($hotKeyBinding.DisplayName) prompt enhancement"
$shortcut.Save()

if (-not $NoStart) {
    Start-InstalledOpenPEHotkey
    Start-Sleep -Seconds 2
}

Write-Host "Installed Windows helper at $installDirectory"
Write-Host "Stored configuration at $configFile"
Write-Host "Registered per-user Startup shortcut at $shortcutPath"
Write-Host "Configured hotkey: $($hotKeyBinding.DisplayName)"
Write-Host "Select a prompt in Codex and press $($hotKeyBinding.DisplayName)."

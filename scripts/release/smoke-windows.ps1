#requires -version 5.1

[CmdletBinding()]
param([string]$Installer)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$version = (Get-Content -LiteralPath (Join-Path $projectRoot "release\version.txt") -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($Installer)) {
    $Installer = Join-Path $projectRoot "dist\Codex-OpenPE-Hotkey-$version-Windows-x64-Setup.exe"
}
$checksum = "$Installer.sha256"
if (-not (Test-Path -LiteralPath $Installer) -or -not (Test-Path -LiteralPath $checksum)) {
    throw "Installer or checksum is missing: $Installer"
}
$expectedHash = ((Get-Content -LiteralPath $checksum -Raw).Trim() -split '\s+')[0]
$actualHash = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant()
if ($expectedHash -ne $actualHash) { throw "Windows installer SHA-256 mismatch." }

$installDirectory = Join-Path $env:LOCALAPPDATA "Programs\CodexOpenPEHotkey"
$dataDirectory = Join-Path $env:LOCALAPPDATA "CodexOpenPEHotkey"
$startupShortcut = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Startup) `
    "Codex OpenPE Hotkey.lnk"

& $Installer /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
if ($LASTEXITCODE -ne 0) { throw "Silent installer failed with exit code $LASTEXITCODE." }
foreach ($required in @(
    "CodexOpenPEHotkey.Windows.dll",
    "CodexOpenPEHotkey.Setup.exe",
    "openpe-server.exe",
    "start.ps1",
    "CodexPlugin\.agents\plugins\marketplace.json",
    "CodexPlugin\skills\codex-openpe-hotkey\SKILL.md"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $installDirectory $required))) {
        throw "Installed file is missing: $required"
    }
}
if (-not (Test-Path -LiteralPath $startupShortcut)) { throw "Startup shortcut is missing." }

$assembly = Join-Path $installDirectory "CodexOpenPEHotkey.Windows.dll"
Add-Type -Path $assembly
[CodexOpenPEHotkey.Windows.SelfTests]::Run()
[CodexOpenPEHotkey.Windows.CredentialStore]::Write(
    [CodexOpenPEHotkey.Windows.CredentialStore]::ApiKeyTarget,
    "ci-placeholder-key")
[CodexOpenPEHotkey.Windows.CredentialStore]::Write(
    [CodexOpenPEHotkey.Windows.CredentialStore]::ServerTokenTarget,
    "ci-server-token")
New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
$configuration = [ordered]@{
    Endpoint = "http://127.0.0.1:18980/v1/prompt-enhance"
    RequestTimeoutSeconds = 5
    AllowedProcessNames = "Codex,ChatGPT"
    ProgressLanguage = "en"
    OpenPEServerPath = (Join-Path $installDirectory "openpe-server.exe")
    ListenAddress = "127.0.0.1:18980"
    BaseUrl = "http://127.0.0.1:9/v1"
    Model = "ci-placeholder-model"
    Language = "en"
    OpenPETimeout = "5s"
    SystemPrompt = "CI smoke test"
    HotKey = "Alt+Q"
}
. (Join-Path $installDirectory "common.ps1")
Write-Utf8Json -Value $configuration -Path (Join-Path $dataDirectory "config.json")

Start-InstalledOpenPEHotkey
$healthy = $false
for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:18980/healthz" `
            -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -eq 200) { $healthy = $true; break }
    }
    catch {}
    Start-Sleep -Milliseconds 250
}
if (-not $healthy) { throw "Installed openPE server did not pass its health check." }
& (Join-Path $installDirectory "status.ps1")
if ($LASTEXITCODE -ne 0) { throw "Installed status check failed." }

$uninstaller = Join-Path $installDirectory "unins000.exe"
& $uninstaller /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
if ($LASTEXITCODE -ne 0) { throw "Silent uninstall failed with exit code $LASTEXITCODE." }
for ($attempt = 0; $attempt -lt 20 -and (Test-Path -LiteralPath $installDirectory); $attempt++) {
    Start-Sleep -Milliseconds 250
}
if (Test-Path -LiteralPath $installDirectory) { throw "Install directory remains after uninstall." }
if (Test-Path -LiteralPath $dataDirectory) { throw "Data directory remains after uninstall." }
if (Test-Path -LiteralPath $startupShortcut) { throw "Startup shortcut remains after uninstall." }
Write-Host "Windows installer install, startup, health, and uninstall smoke test passed"

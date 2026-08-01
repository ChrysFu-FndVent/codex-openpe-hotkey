#requires -version 5.1

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot "common.ps1")
Assert-WindowsPlatform

$failed = $false
$dataDirectory = Get-OpenPEDataDirectory
$configFile = Join-Path $dataDirectory "config.json"
$shortcut = Get-OpenPEStartupShortcut

if (Test-Path -LiteralPath $configFile) {
    Write-Host "configuration: present at $configFile"
    $configuration = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
    $expectedServerPath = [string]$configuration.OpenPEServerPath
    $configuredHotKey = if ($configuration.PSObject.Properties.Name -contains "HotKey") {
        [string]$configuration.HotKey
    } else {
        "Alt+Q (legacy default)"
    }
    Write-Host "configured hotkey: $configuredHotKey"
}
else {
    Write-Host "configuration: missing at $configFile"
    $failed = $true
    $expectedServerPath = $null
}

foreach ($entry in @(
    @{
        Name = "hotkey helper"
        File = (Join-Path $dataDirectory "hotkey.pid")
        Command = (Join-Path (Get-OpenPEInstallDirectory) "start.ps1")
        Executable = $null
    },
    @{
        Name = "openpe-server"
        File = (Join-Path $dataDirectory "server.pid")
        Command = $null
        Executable = $expectedServerPath
    }
)) {
    $running = Test-ProcessFromPidFile `
        -PidFile $entry.File `
        -ExpectedCommandFragment $entry.Command `
        -ExpectedExecutablePath $entry.Executable
    if (-not $running) {
        Write-Host "$($entry.Name): not running or PID identity does not match this installation"
        if ($entry.Name -eq "hotkey helper") { $failed = $true }
    }
    else {
        $storedPid = (Get-Content -LiteralPath $entry.File -Raw).Trim()
        Write-Host "$($entry.Name): running pid=$storedPid (identity verified)"
    }
}

try {
    $health = Invoke-WebRequest `
        -Uri "http://127.0.0.1:18980/healthz" `
        -UseBasicParsing `
        -TimeoutSec 5
    Write-Host "openpe-server health: HTTP $($health.StatusCode) $($health.Content)"

    $assembly = Join-Path (Get-OpenPEInstallDirectory) "CodexOpenPEHotkey.Windows.dll"
    if (-not (Test-Path -LiteralPath $assembly)) { throw "Windows helper assembly is missing." }
    Add-Type -Path $assembly
    $serverToken = [CodexOpenPEHotkey.Windows.CredentialStore]::Read(
        [CodexOpenPEHotkey.Windows.CredentialStore]::ServerTokenTarget)
    if ([string]::IsNullOrEmpty($serverToken)) { throw "OpenPE server token is missing." }
    try {
        $info = Invoke-WebRequest `
            -Uri "http://127.0.0.1:18980/v1/info" `
            -Headers @{ Authorization = "Bearer $serverToken" } `
            -UseBasicParsing `
            -TimeoutSec 5
        Write-Host "openpe-server authenticated info: HTTP $($info.StatusCode)"
    }
    finally {
        $serverToken = $null
    }
}
catch {
    Write-Host "openpe-server health: unavailable"
    $failed = $true
}

if (Test-Path -LiteralPath $shortcut) {
    Write-Host "Startup shortcut: present"
}
else {
    Write-Host "Startup shortcut: missing"
    $failed = $true
}

$logFile = Join-Path $dataDirectory "hotkey-error.log"
if (Test-Path -LiteralPath $logFile) {
    Write-Host "Recent diagnostics:"
    Get-Content -LiteralPath $logFile -Tail 5
}

if ($failed) { exit 1 }

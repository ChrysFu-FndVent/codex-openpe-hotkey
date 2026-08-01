#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-WindowsPlatform {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw "This script must run in Windows PowerShell on Windows. Do not run it under WSL."
    }
    if ($PSVersionTable.PSEdition -ne "Desktop") {
        throw "Use Windows PowerShell 5.1 (powershell.exe), not PowerShell 7 (pwsh.exe)."
    }
}

function Assert-WindowsHotKey {
    param([Parameter(Mandatory = $true)][string]$HotKey)

    if ([string]::IsNullOrWhiteSpace($HotKey) -or $HotKey.Contains("`r") -or $HotKey.Contains("`n")) {
        throw "HotKey must be a non-empty single-line shortcut."
    }
    $parts = $HotKey.Split("+")
    if ($parts.Count -lt 2) { throw "HotKey must include at least one modifier and one key." }
    $modifiers = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $keyCount = 0
    foreach ($rawPart in $parts) {
        $part = $rawPart.Trim().ToLowerInvariant()
        $canonical = switch ($part) {
            "ctrl" { "ctrl" }
            "control" { "ctrl" }
            "alt" { "alt" }
            "option" { "alt" }
            "shift" { "shift" }
            "win" { "win" }
            "windows" { "win" }
            default { $null }
        }
        if ($null -ne $canonical) {
            if (-not $modifiers.Add($canonical)) { throw "HotKey contains a duplicate modifier." }
            continue
        }
        if ($part -notmatch '^(?:[a-z0-9]|f(?:[1-9]|1[0-2]))$') {
            throw "HotKey supports only A-Z, 0-9, or F1-F12 as the ordinary key."
        }
        $keyCount++
    }
    if ($modifiers.Count -lt 1 -or $keyCount -ne 1) {
        throw "HotKey must include at least one modifier and exactly one ordinary key."
    }
}

function Get-OpenPEInstallDirectory {
    return Join-Path $env:LOCALAPPDATA "Programs\CodexOpenPEHotkey"
}

function Get-OpenPEDataDirectory {
    return Join-Path $env:LOCALAPPDATA "CodexOpenPEHotkey"
}

function Get-OpenPEStartupShortcut {
    $startup = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
    return Join-Path $startup "Codex OpenPE Hotkey.lnk"
}

function Get-HelperReferences {
    $referenceDirectories = @(
        [Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
    )
    foreach ($programFilesDirectory in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not [string]::IsNullOrWhiteSpace($programFilesDirectory)) {
            $referenceDirectories += Join-Path `
                $programFilesDirectory `
                "Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8"
        }
    }

    $referenceNames = @(
        "System.dll",
        "System.Core.dll",
        "System.Net.Http.dll",
        "System.Web.Extensions.dll",
        "System.Windows.Forms.dll",
        "UIAutomationClient.dll",
        "UIAutomationTypes.dll"
    )
    foreach ($referenceName in $referenceNames) {
        $resolvedReference = $null
        foreach ($referenceDirectory in $referenceDirectories) {
            $candidate = Join-Path $referenceDirectory $referenceName
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $resolvedReference = (Resolve-Path -LiteralPath $candidate).Path
                break
            }
        }
        if ($null -eq $resolvedReference) {
            throw "Required .NET Framework reference was not found: $referenceName"
        }
        $resolvedReference
    }
}

function Build-WindowsHelper {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$OutputAssembly
    )

    $outputParent = Split-Path -Parent $OutputAssembly
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    if (Test-Path -LiteralPath $OutputAssembly) {
        Remove-Item -LiteralPath $OutputAssembly -Force
    }
    Add-Type `
        -Path $SourcePath `
        -ReferencedAssemblies (Get-HelperReferences) `
        -OutputAssembly $OutputAssembly `
        -OutputType Library
}

function Stop-ProcessFromPidFile {
    param(
        [Parameter(Mandatory = $true)][string]$PidFile,
        [string]$ExpectedCommandFragment,
        [string]$ExpectedExecutablePath
    )

    if (-not (Test-Path -LiteralPath $PidFile)) {
        return
    }
    $storedPid = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    $parsedPid = 0
    if ([int]::TryParse($storedPid, [ref]$parsedPid)) {
        $nativeProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $parsedPid" -ErrorAction SilentlyContinue
        if ($null -ne $nativeProcess) {
            $confirmed = $false
            if (-not [string]::IsNullOrWhiteSpace($ExpectedCommandFragment) -and
                -not [string]::IsNullOrWhiteSpace([string]$nativeProcess.CommandLine) -and
                ([string]$nativeProcess.CommandLine).IndexOf(
                    $ExpectedCommandFragment,
                    [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $confirmed = $true
            }
            if (-not [string]::IsNullOrWhiteSpace($ExpectedExecutablePath) -and
                -not [string]::IsNullOrWhiteSpace([string]$nativeProcess.ExecutablePath) -and
                [string]::Equals(
                    [IO.Path]::GetFullPath([string]$nativeProcess.ExecutablePath),
                    [IO.Path]::GetFullPath($ExpectedExecutablePath),
                    [StringComparison]::OrdinalIgnoreCase)) {
                $confirmed = $true
            }
            if (-not $confirmed) {
                throw "Refusing to stop PID $parsedPid because its identity does not match $PidFile."
            }
            Stop-Process -Id $parsedPid -Force
        }
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

function Test-ProcessFromPidFile {
    param(
        [Parameter(Mandatory = $true)][string]$PidFile,
        [string]$ExpectedCommandFragment,
        [string]$ExpectedExecutablePath
    )

    if (-not (Test-Path -LiteralPath $PidFile)) {
        return $false
    }
    $storedPid = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    $parsedPid = 0
    if (-not [int]::TryParse($storedPid, [ref]$parsedPid)) {
        return $false
    }
    $nativeProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $parsedPid" -ErrorAction SilentlyContinue
    if ($null -eq $nativeProcess) {
        return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCommandFragment) -and
        -not [string]::IsNullOrWhiteSpace([string]$nativeProcess.CommandLine) -and
        ([string]$nativeProcess.CommandLine).IndexOf(
            $ExpectedCommandFragment,
            [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        return $true
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedExecutablePath) -and
        -not [string]::IsNullOrWhiteSpace([string]$nativeProcess.ExecutablePath) -and
        [string]::Equals(
            [IO.Path]::GetFullPath([string]$nativeProcess.ExecutablePath),
            [IO.Path]::GetFullPath($ExpectedExecutablePath),
            [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $false
}

function Stop-InstalledOpenPEProcesses {
    $dataDirectory = Get-OpenPEDataDirectory
    $installDirectory = Get-OpenPEInstallDirectory
    Stop-ProcessFromPidFile `
        -PidFile (Join-Path $dataDirectory "hotkey.pid") `
        -ExpectedCommandFragment (Join-Path $installDirectory "start.ps1")

    $expectedServerPath = $null
    $configFile = Join-Path $dataDirectory "config.json"
    if (Test-Path -LiteralPath $configFile) {
        $installedConfiguration = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
        $expectedServerPath = [string]$installedConfiguration.OpenPEServerPath
    }
    Stop-ProcessFromPidFile `
        -PidFile (Join-Path $dataDirectory "server.pid") `
        -ExpectedExecutablePath $expectedServerPath
}

function Convert-SecureStringToPlainText {
    param([Parameter(Mandatory = $true)][Security.SecureString]$SecureValue)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Remove-OpenPECredentials {
    $cleanerType = "CodexOpenPEHotkey.PowerShellCredentialCleaner" -as [type]
    if ($null -eq $cleanerType) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace CodexOpenPEHotkey
{
    public static class PowerShellCredentialCleaner
    {
        private const uint CredentialTypeGeneric = 1;

        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDelete(string target, uint type, uint flags);

        public static int Delete(string target)
        {
            return CredDelete(target, CredentialTypeGeneric, 0) ? 0 : Marshal.GetLastWin32Error();
        }
    }
}
"@
    }

    foreach ($target in @(
        "com.openpe.promptenhancer.api-key",
        "com.openpe.promptenhancer.server-token"
    )) {
        $result = [CodexOpenPEHotkey.PowerShellCredentialCleaner]::Delete($target)
        if ($result -ne 0 -and $result -ne 1168) {
            throw "Could not delete Windows credential '$target' (Win32 error $result)."
        }
    }
}

function Write-Utf8Json {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $json = $Value | ConvertTo-Json -Depth 5
    $utf8WithoutBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $json, $utf8WithoutBom)
}

function Start-InstalledOpenPEHotkey {
    $installDirectory = Get-OpenPEInstallDirectory
    $launcher = Join-Path $installDirectory "start.ps1"
    if (-not (Test-Path -LiteralPath $launcher)) {
        throw "Installed Windows launcher was not found: $launcher"
    }
    Start-Process `
        -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList @(
            "-NoProfile",
            "-Sta",
            "-ExecutionPolicy", "Bypass",
            "-WindowStyle", "Hidden",
            "-File", ('"{0}"' -f $launcher)
        ) `
        -WindowStyle Hidden | Out-Null
}

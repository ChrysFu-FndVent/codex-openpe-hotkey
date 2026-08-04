#requires -version 5.1

[CmdletBinding()]
param([string]$IsccPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$version = (Get-Content -LiteralPath (Join-Path $projectRoot "release\version.txt") -Raw).Trim()
$distDirectory = Join-Path $projectRoot "dist"
$artifactDirectory = Join-Path $projectRoot "artifacts\windows"

if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid release version: $version" }
$plugin = Get-Content -LiteralPath (Join-Path $projectRoot ".codex-plugin\plugin.json") -Raw |
    ConvertFrom-Json
if ([string]$plugin.version -ne $version) { throw "Plugin version does not match release/version.txt." }

& (Join-Path $PSScriptRoot "build-openpe.ps1") -Output (Join-Path $distDirectory "openpe-server.exe")
if ($LASTEXITCODE -ne 0) { throw "openPE build failed." }

& dotnet build (Join-Path $projectRoot "windows\CodexOpenPEHotkey.Windows.csproj") -c Release
if ($LASTEXITCODE -ne 0) { throw "Windows helper build failed." }
& dotnet build (Join-Path $projectRoot "windows\CodexOpenPEHotkey.Setup.csproj") -c Release
if ($LASTEXITCODE -ne 0) { throw "Windows setup wizard build failed." }

New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot "windows\bin\Release\net48\CodexOpenPEHotkey.Windows.dll") `
    -Destination $artifactDirectory -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "windows\bin\Release\net48\CodexOpenPEHotkey.Setup.exe") `
    -Destination $artifactDirectory -Force

if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
    )
    $IsccPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($IsccPath) -or -not (Test-Path -LiteralPath $IsccPath)) {
    throw "Inno Setup 6 compiler (ISCC.exe) was not found."
}

& $IsccPath (Join-Path $projectRoot "installer\windows\CodexOpenPEHotkey.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup build failed." }

$installer = Join-Path $distDirectory "Codex-OpenPE-Hotkey-$version-Windows-x64-Setup.exe"
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw "Installer was not produced: $installer" }
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$installer.sha256", "$hash  $([IO.Path]::GetFileName($installer))`n", [Text.Encoding]::ASCII)
Write-Host "Created $installer"
Write-Host "Created $installer.sha256"

#requires -version 5.1

[CmdletBinding()]
param(
    [string]$Output,
    [ValidateSet("windows-x64")][string]$Target = "windows-x64"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$lock = Get-Content -LiteralPath (Join-Path $projectRoot "release\openpe.lock.json") -Raw |
    ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $projectRoot "dist\openpe-server.exe"
}
if ([string]$lock.commit -notmatch '^[0-9a-f]{40}$') {
    throw "release/openpe.lock.json contains an invalid commit."
}
foreach ($command in @("git", "go")) {
    if ($null -eq (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $command"
    }
}

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ("openpe-build-" + [Guid]::NewGuid())
$sourceDirectory = Join-Path $temporaryDirectory "openpe"
try {
    New-Item -ItemType Directory -Path $sourceDirectory -Force | Out-Null
    & git -C $sourceDirectory init -q
    & git -C $sourceDirectory remote add origin ([string]$lock.repository)
    & git -C $sourceDirectory fetch -q --depth 1 origin ([string]$lock.commit)
    & git -C $sourceDirectory checkout -q --detach FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "Could not check out the pinned openPE commit." }

    $actualCommit = (& git -C $sourceDirectory rev-parse HEAD).Trim()
    if ($actualCommit -ne [string]$lock.commit) {
        throw "openPE commit mismatch: expected $($lock.commit), got $actualCommit"
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Output) -Force | Out-Null
    $oldCgo = $env:CGO_ENABLED
    $oldGoos = $env:GOOS
    $oldGoarch = $env:GOARCH
    try {
        $env:CGO_ENABLED = "0"
        $env:GOOS = "windows"
        $env:GOARCH = "amd64"
        Push-Location $sourceDirectory
        try {
            & go build -trimpath -buildvcs=false -ldflags "-s -w" -o $Output .\cmd\openpe-server
            if ($LASTEXITCODE -ne 0) { throw "openPE Windows build failed." }
        }
        finally {
            Pop-Location
        }
    }
    finally {
        $env:CGO_ENABLED = $oldCgo
        $env:GOOS = $oldGoos
        $env:GOARCH = $oldGoarch
    }
    Write-Host "Built openpe-server from $($lock.commit) at $Output"
}
finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

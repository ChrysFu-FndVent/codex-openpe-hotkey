#requires -version 5.1

$ErrorActionPreference = "Stop"
$installDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$assembly = Join-Path $installDirectory "CodexOpenPEHotkey.Windows.dll"
$dataDirectory = Join-Path $env:LOCALAPPDATA "CodexOpenPEHotkey"
$logFile = Join-Path $dataDirectory "hotkey-error.log"

try {
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::STA) {
        throw "The Windows helper must run in an STA PowerShell process. Start it through the installed shortcut."
    }
    Add-Type -Path $assembly
    [CodexOpenPEHotkey.Windows.WindowsHost]::Run()
}
catch {
    New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
    $line = "{0:o} launcher failed: {1}{2}" -f [DateTimeOffset]::Now, $_, [Environment]::NewLine
    [IO.File]::AppendAllText($logFile, $line, [Text.Encoding]::UTF8)
    exit 1
}

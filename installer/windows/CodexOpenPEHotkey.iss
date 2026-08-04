#define MyAppName "Codex OpenPE Hotkey"
#define MyAppVersion "0.4.0"
#define MyAppPublisher "Codex OpenPE Hotkey Contributors"
#define MyAppURL "https://github.com/ChrysFu-FndVent/codex-openpe-hotkey"
#define MyAppExeName "CodexOpenPEHotkey.Setup.exe"

[Setup]
AppId={{F47156D0-AF3A-4FB0-B22F-D3C5F91A51D1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={localappdata}\Programs\CodexOpenPEHotkey
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=Codex-OpenPE-Hotkey-{#MyAppVersion}-Windows-x64-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#MyAppName}
VersionInfoVersion=0.4.0.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} per-user installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
SetupLogging=yes

[Files]
Source: "..\..\artifacts\windows\CodexOpenPEHotkey.Windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\artifacts\windows\CodexOpenPEHotkey.Setup.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\dist\openpe-server.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\scripts\windows\start.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\scripts\windows\common.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\scripts\windows\configure.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\scripts\windows\status.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\scripts\windows\installer-uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\.codex-plugin\*"; DestDir: "{app}\CodexPlugin\.codex-plugin"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\.agents\*"; DestDir: "{app}\CodexPlugin\.agents"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\skills\*"; DestDir: "{app}\CodexPlugin\skills"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userstartup}\Codex OpenPE Hotkey"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\start.ps1"""; WorkingDir: "{app}"; Flags: runminimized
Name: "{group}\Configure Codex OpenPE Hotkey"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall Codex OpenPE Hotkey"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Configure Codex OpenPE Hotkey"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer-uninstall.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "OpenPECleanup"

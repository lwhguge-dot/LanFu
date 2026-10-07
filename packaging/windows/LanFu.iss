#define MyAppName "LanFu"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "LanFu"
#define MyAppExeName "lanfu.cmd"

[Setup]
AppId={{A8AC4C6A-4F14-4F51-AF73-83FBD2D32F01}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\LanFu
DefaultGroupName=LanFu
OutputBaseFilename=LanFu-Setup-x64
OutputDir=.
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
UninstallDisplayName=LanFu

[Files]
Source: "release-root\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\LanFu"; Filename: "{app}\lanfu.cmd"; Parameters: "gateway --port 18789"; WorkingDir: "{app}"
Name: "{commondesktop}\LanFu"; Filename: "{app}\lanfu.cmd"; Parameters: "gateway --port 18789"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File "{app}\post-install.ps1""; Flags: runhidden waituntilterminated

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File "{app}\uninstall.ps1""; Flags: runhidden waituntilterminated

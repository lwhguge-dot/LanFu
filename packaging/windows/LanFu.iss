; LanFu Windows installer (Inno Setup 6).
#define MyAppName "LanFu"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "LanFu"

[Setup]
AppId={{A8AC4C6A-4F14-4F51-AF73-83FBD2D32F01}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\LanFu
DefaultGroupName=LanFu
DisableProgramGroupPage=yes
OutputBaseFilename=LanFu-Setup-x64
OutputDir=D:\lb\out
SetupIconFile=D:\lb\lanfu.ico
UninstallDisplayIcon={app}\lanfu.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName=LanFu

[Files]
Source: "app\*"; DestDir: "{app}\app"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "runtime\*"; DestDir: "{app}\runtime"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "lanfu.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "post-install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "lanfu.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\LanFu"; Filename: "{app}\lanfu.cmd"; Parameters: "gateway --port 18789"; WorkingDir: "{app}"; IconFilename: "{app}\lanfu.ico"
Name: "{userdesktop}\LanFu"; Filename: "{app}\lanfu.cmd"; Parameters: "gateway --port 18789"; WorkingDir: "{app}"; IconFilename: "{app}\lanfu.ico"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"; Flags: checkedonce

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\post-install.ps1"""; Flags: runhidden waituntilterminated; StatusMsg: "正在配置 LanFu..."

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall.ps1"""; Flags: runhidden waituntilterminated

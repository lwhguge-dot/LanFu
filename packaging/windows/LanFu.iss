; LanFu unified installer: gateway runtime + desktop shell in one package.
;
; Layout (assembled by .github/workflows/lanfu-release.yml):
;   app/                        gateway runtime tree (node + dist + node_modules)
;   runtime/                    bundled Node.js
;   lanfu.cmd, post-install.ps1, uninstall.ps1
;   LanFu-Hub-Setup-x64.exe     the branded desktop shell installer

#define MyAppName "LanFu"
#define MyAppVersion "0.0.0"
#define MyAppPublisher "LanFu Edu"

[Setup]
AppId={{8F2B1D64-3A75-4C9E-B2A1-LANFU00000001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\LanFu
DefaultGroupName=LanFu
DisableProgramGroupPage=yes
DisableReadyPage=yes
OutputBaseFilename=LanFu-Setup-x64
OutputDir=out
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName=LanFu
UninstallDisplayIcon={app}\lanfu.ico
SetupIconFile=lanfu.ico
CloseApplications=no


[Files]
; Gateway runtime (validated by the CI smoke test)
Source: "app\*"; DestDir: "{app}\app"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "runtime\*"; DestDir: "{app}\runtime"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "lanfu.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "post-install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "lanfu.ico"; DestDir: "{app}"; Flags: ignoreversion
; Desktop shell installer, run silently below so employees install once
Source: "LanFu-Hub-Setup-x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Run]
; 1. the desktop shell (tray + native window). Tasks are unchecked by default;
;    enable both so the shell is on the desktop and starts at logon.
Filename: "{tmp}\LanFu-Hub-Setup-x64.exe"; Parameters: "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL /TASKS=""desktopicon,startupicon"""; StatusMsg: "正在安装 LanFu 桌面端..."; Flags: waituntilterminated
; 2. gateway config, autostart, desktop-shell wiring and first pairing approval
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\post-install.ps1"""; Flags: runhidden waituntilterminated; StatusMsg: "正在配置 LanFu（首次启动约需 1 分钟）..."

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "LanFuCleanup"

[UninstallDelete]
; The uninstaller must remove the whole app tree, including files written at runtime
Type: filesandordirs; Name: "{app}"


; LanFu 一体化安装程序：本地网关运行时 + 桌面端，一次安装完成。
;
; 发布根目录结构（由 .github/workflows/lanfu-release.yml 组装）：
;   app/          网关运行时（node_modules 已剔除开发文件）
;   runtime/      随包 Node.js
;   hub/          桌面端程序（.NET 自包含发布产物，直接内嵌）
;   lanfu.cmd / post-install.ps1 / uninstall.ps1 / lanfu.ico
;
; 设计要点：桌面端载荷直接内嵌，不再串联"桌面端安装器"——省掉一次完整的
; 122MB 解压 + 二次解压，安装快一倍。

#define MyAppName "LanFu"
; CI 传 /DMyAppVersion=<版本>；脚本内的 #define 会覆盖命令行值（Inno 后定义
; 生效），必须用 #ifndef 兜底，否则窗口标题、控制面板卸载项全部显示 0.0.0
; （0.2.0～0.4.1 的正式发布全部中过这个招）。
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#define MyAppPublisher "LanFu Edu"
#define MyAumid "LanFu.Desktop"

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
; 载荷以大量小文件为主：solid 在这里解压更快、包体更小（实测非 solid 反而更慢更大）。
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName=LanFu
UninstallDisplayIcon={app}\lanfu.ico
SetupIconFile=lanfu.ico
CloseApplications=no

[Languages]
; 产品只面向中文员工，向导全程简体中文。Inno Setup 不自带中文语言文件，
; 因此随包放在脚本旁边，发布流水线会一并 stage。
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Messages]
WelcomeLabel2=即将在你的电脑上安装 [name/ver]。%n%n安装完成后会自动打开 LanFu。%n%n安装过程需要几分钟，请勿关闭窗口。

[Files]
; 网关运行时（已剔除与运行无关的开发文件，安装更快）
Source: "app\*"; DestDir: "{app}\app"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "runtime\*"; DestDir: "{app}\runtime"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "lanfu.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "post-install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "ensure-gateway.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "approve-pairing.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "lanfu.ico"; DestDir: "{app}"; Flags: ignoreversion
; 桌面端：直接内嵌，不再串联独立安装器
Source: "hub\*"; DestDir: "{localappdata}\LanFu"; Flags: recursesubdirs createallsubdirs ignoreversion

[InstallDelete]
; 升级安装前清掉上一版的 dist 缓存。
; 构建产物文件名带 hash，Inno 覆盖安装只新增/覆盖文件、不会删除旧文件，
; 多次更新后 app\dist 会积累大量孤儿 chunk（0.4.20 实测 707MB dist 里约 424MB 是旧 chunk）。
; dist 完全由本次安装包重建，删除是安全的；放在 [InstallDelete] 可以保证每次升级后只剩当前版本的文件。
Type: filesandordirs; Name: "{app}\app\dist"

[Icons]
; 桌面快捷方式 + 开始菜单（员工从桌面图标启动）
Name: "{autodesktop}\LanFu"; Filename: "{localappdata}\LanFu\LanFu.exe"; AppUserModelID: "{#MyAumid}"
Name: "{group}\LanFu"; Filename: "{localappdata}\LanFu\LanFu.exe"; AppUserModelID: "{#MyAumid}"
Name: "{group}\LanFu 对话"; Filename: "{localappdata}\LanFu\LanFu.exe"; Parameters: "lanfu://chat"; AppUserModelID: "{#MyAumid}"
Name: "{group}\LanFu 设置"; Filename: "{localappdata}\LanFu\LanFu.exe"; Parameters: "lanfu://commandcenter"; AppUserModelID: "{#MyAumid}"
Name: "{group}\卸载 LanFu"; Filename: "{uninstallexe}"
; 登录自启：桌面端常驻托盘（网关的自启由 post-install.ps1 注册）
Name: "{userstartup}\LanFu"; Filename: "{localappdata}\LanFu\LanFu.exe"; Parameters: "--background"; AppUserModelID: "{#MyAumid}"

[Registry]
; lanfu:// 深链协议（与桌面端 AppIdentity.ProtocolScheme 一致）
Root: HKCU; Subkey: "Software\Classes\lanfu"; ValueType: string; ValueName: ""; ValueData: "URL:LanFu Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\lanfu"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\lanfu\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{localappdata}\LanFu\LanFu.exe"",0"
Root: HKCU; Subkey: "Software\Classes\lanfu\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{localappdata}\LanFu\LanFu.exe"" ""%1"""

[Run]
; 安装后收尾：预置连接（生成令牌+写连接记录）、补依赖自链接、注册网关自启、
; 拉起网关、打开 LanFu 界面、后台批准桌面端配对。
; 不写任何模型/渠道配置——AI 提供商由员工装好后在应用内自己连接。
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\post-install.ps1"""; Flags: runhidden waituntilterminated; StatusMsg: "正在完成安装并启动 LanFu…"

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "LanFuCleanup"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
; 桌面端程序目录（用户数据在 %APPDATA%\LanFu 与 ~/.lanfu，按设计保留）
Type: filesandordirs; Name: "{localappdata}\LanFu"

[Code]
// 覆盖安装时旧版界面、网关、守护脚本会锁住要替换的文件，导致安装失败。
//
// 为什么不靠 RestartManager（[Setup] CloseApplications）：实测它去关正在运行的
// node 网关时关不掉，随后弹"无法自动关闭所有应用程序"并**直接中止安装**（退出码 5）。
// 这里改成在解压前自己精准结束这几个进程：只结束可执行文件路径含 LanFu 的 node，
// 不会误杀员工自己的 node 程序。
function StopOldProcesses(): Boolean;
var
  ResultCode: Integer;
  Script: String;
  ScriptPath: String;
begin
  Result := True;

  // 界面进程
  Exec('taskkill.exe', '/F /IM LanFu.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

  // 网关 node 进程与守护脚本：用 WMI 精确定位，避免误杀
  Script :=
    'Get-CimInstance Win32_Process -Filter "Name = ''node.exe''" | ' + #13#10 +
    '  Where-Object { $_.ExecutablePath -like ''*LanFu*'' } | ' + #13#10 +
    '  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }' + #13#10 +
    'Get-CimInstance Win32_Process -Filter "Name = ''powershell.exe''" | ' + #13#10 +
    '  Where-Object { $_.CommandLine -like ''*ensure-gateway*'' } | ' + #13#10 +
    '  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }' + #13#10;
  ScriptPath := ExpandConstant('{tmp}\lanfu-stop-old.ps1');
  if SaveStringToFile(ScriptPath, Script, False) then
    Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"', '',
         SW_HIDE, ewWaitUntilTerminated, ResultCode);

  Sleep(1500);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  StopOldProcesses();
end;

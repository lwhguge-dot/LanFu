param(
  [switch]$SkipLaunch
)
# LanFu 安装后配置。
#
# 设计原则（按产品决定）：安装器**不写任何网关配置**、不预先绑定连接、不代替员工批准配对。
# 连接方式由员工在 LanFu 界面里自己确认。
#
# 本脚本只做三件事：
#   1. 补一个 Inno Setup 无法保留的目录联接（网关插件解析需要）
#   2. 注册本地网关的登录自启（走带重试的守护脚本）
#   3. 把守护脚本在后台拉起（**不等待**，安装不因此变慢），然后打开 LanFu 界面
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$appDir = Join-Path $root "app"
$watchdog = Join-Path $root "ensure-gateway.ps1"
$logPath = Join-Path $env:TEMP "lanfu-post-install.log"

function Say($text) {
  $line = "[LanFu] " + $text
  Write-Output $line
  Add-Content -Path $logPath -Value ((Get-Date -Format "HH:mm:ss") + " " + $line) -ErrorAction SilentlyContinue
}
"=== LanFu 安装后配置 $(Get-Date -Format o) ===" | Set-Content -Path $logPath -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 1. 目录联接
# 网关插件用 "openclaw/plugin-sdk/*" 自引用解析，需要 app\node_modules\openclaw 指回 app。
# Inno Setup 打包会把联接实体化，7-Zip 也不建符号链接，因此安装后补建。
Say "正在补齐依赖自链接…"
try {
  $selfLink = Join-Path $appDir "node_modules\openclaw"
  if (Test-Path $selfLink) {
    Say "  已存在，跳过"
  } else {
    New-Item -ItemType Junction -Path $selfLink -Target $appDir -ErrorAction Stop | Out-Null
    Say "  已创建 node_modules\openclaw -> app"
  }
} catch { Say ("  创建失败：" + $_.Exception.Message) }

# ---------------------------------------------------------------- 2. 登录自启
# 指向带重试的守护脚本：网关首次启动可能瞬时失败，守护脚本会自动重试。
Say "正在注册本地网关的登录自启…"
try {
  Unregister-ScheduledTask -TaskName "LanFu Gateway" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  New-Item -Path $runKey -Force | Out-Null
  $cmd = '"' + (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") + '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $watchdog + '"'
  Set-ItemProperty -Path $runKey -Name "LanFuGateway" -Value $cmd
  Say "  已写入 HKCU Run\LanFuGateway（指向守护脚本）"
} catch { Say ("  自启注册失败：" + $_.Exception.Message) }

# ---------------------------------------------------------------- 3. 后台拉起守护脚本
# 不等待：安装速度不受网关启动影响；守护脚本会在后台把网关拉起来。
Say "正在后台启动本地网关…"
try {
  Start-Process -FilePath (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") -ArgumentList @("-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", $watchdog) -WindowStyle Hidden | Out-Null
  Say "  守护脚本已在后台运行"
} catch { Say ("  启动失败：" + $_.Exception.Message) }

# ---------------------------------------------------------------- 4. 打开界面
if ($SkipLaunch) { Say "已跳过启动界面"; exit 0 }

$hubExe = Join-Path $env:LOCALAPPDATA "LanFu\LanFu.exe"
if (-not (Test-Path $hubExe)) { Say "未找到桌面端，跳过启动"; exit 0 }

Say "正在打开 LanFu 主界面…"
try {
  Start-Process -FilePath $hubExe -WorkingDirectory (Split-Path $hubExe) | Out-Null
  Say "  已启动"
} catch { Say ("  启动失败：" + $_.Exception.Message) }
Say "完成。"

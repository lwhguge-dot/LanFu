param(
  [switch]$SkipLaunch
)
# LanFu 安装后配置。
#
# 设计原则（按产品决定）：安装器**不写任何网关配置**、不预先绑定连接、不代替员工批准配对。
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$appDir = Join-Path $root "app"
$watchdog = Join-Path $root "ensure-gateway.ps1"
$logPath = Join-Path $env:TEMP "lanfu-post-install.log"
$psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

function Say($text) {
  $line = "[LanFu] " + $text
  Write-Output $line
  Add-Content -Path $logPath -Value ((Get-Date -Format "HH:mm:ss") + " " + $line) -ErrorAction SilentlyContinue
}
"=== LanFu 安装后配置 $(Get-Date -Format o) ===" | Set-Content -Path $logPath -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 0. 诊断转储
# 网关在安装器进程链里启动时会失败，在普通 shell 里正常，因此把安装时的上下文记下来。
try {
  $diag = Join-Path $env:TEMP "lanfu-install-context.txt"
  $lines = @()
  $lines += "cwd=" + (Get-Location).Path
  $lines += "cwd-exists=" + (Test-Path (Get-Location).Path)
  $lines += "TEMP=" + $env:TEMP + "  exists=" + (Test-Path $env:TEMP)
  $lines += "TMP=" + $env:TMP
  $lines += "NODE_OPTIONS=[" + $env:NODE_OPTIONS + "]"
  $lines += "NODE_PATH=[" + $env:NODE_PATH + "]"
  $lines += "PATH=" + $env:PATH
  $lines += "--- all env ---"
  Get-ChildItem Env: | Sort-Object Name | ForEach-Object { $lines += ($_.Name + "=" + $_.Value) }
  $lines | Set-Content -Path $diag -Encoding UTF8
  Say ("已转储安装上下文到 " + $diag)
} catch { Say ("转储失败：" + $_.Exception.Message) }

# ---------------------------------------------------------------- 1. 目录联接
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
Say "正在注册本地网关的登录自启…"
try {
  Unregister-ScheduledTask -TaskName "LanFu Gateway" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  New-Item -Path $runKey -Force | Out-Null
  $cmd = '"' + $psExe + '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $watchdog + '"'
  Set-ItemProperty -Path $runKey -Name "LanFuGateway" -Value $cmd
  Say "  已写入 HKCU Run\LanFuGateway（指向守护脚本）"
} catch { Say ("  自启注册失败：" + $_.Exception.Message) }

# ---------------------------------------------------------------- 3. 后台拉起守护脚本
# 安装器进程链里启动的网关会因环境问题必然失败，因此这里用**全新环境**（不含安装器
# 注入的变量）启动守护脚本，让它像员工正常登录时那样工作。
Say "正在后台启动本地网关…"
# 注意：不要用 -UseNewEnvironment。实测它会构造出缺少必要变量的环境块，守护脚本
# 起不来（日志为空、网关始终未启动）；继承环境则正常。
try {
  Start-Process -FilePath $psExe -ArgumentList @("-NoProfile","-WindowStyle","Hidden","-ExecutionPolicy","Bypass","-File",$watchdog) -WorkingDirectory $root -WindowStyle Hidden | Out-Null
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

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
# 关键：必须脱离安装器进程树，并且由一个**员工日常上下文**的进程来启动。
#
# 实测证据（同一台机器、同一份文件、同一时刻）：
#   安装器进程树里的守护脚本 -> 17 次重试、45 分钟全部失败
#   我在同一时刻手动启动        -> 15 秒就绪
#   shell 经 WMI 启动守护脚本  -> 20 秒就绪
#   post-install 经 WMI 启动   -> 依然失败
# 也就是说：只要是安装器派生出来的进程，它拉起的网关就必然失败；换任何其它上下文都正常。
# 因此这里把启动动作交给 explorer.exe（资源管理器的进程上下文），它是员工日常的
# 上下文，不带安装器的血统。
Say "正在后台启动本地网关…"
$launcher = Join-Path $env:LOCALAPPDATA "LanFu\start-gateway.cmd"
try {
  New-Item -ItemType Directory -Force -Path (Split-Path $launcher) | Out-Null
  $cmdText = '@echo off' + "
" + 'start "" /b "' + $psExe + '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $watchdog + '"' + "
"
  Set-Content -Path $launcher -Value $cmdText -Encoding ASCII
  Start-Process -FilePath (Join-Path $env:SystemRoot "explorer.exe") -ArgumentList ('"' + $launcher + '"') | Out-Null
  Say "  已通过 explorer 在员工上下文里启动守护脚本"
} catch { Say ("  启动失败：" + $_.Exception.Message) }

# 兜底：万一 explorer 那条路没生效，再直接起一个（这一路在安装器血统下必定失败，
# 但不会造成损害，且登录自启会在下次登录时用干净上下文把网关拉起来）。
try {
  Start-Sleep -Seconds 20
  $ready = $false
  try { $r = Invoke-WebRequest "http://127.0.0.1:18789/" -UseBasicParsing -TimeoutSec 4; $ready = ($r.StatusCode -eq 200) } catch { }
  if (-not $ready) {
    $already = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -like "*ensure-gateway*" }
    if (-not $already) {
      Start-Process -FilePath $psExe -ArgumentList @("-NoProfile","-WindowStyle","Hidden","-ExecutionPolicy","Bypass","-File",$watchdog) -WorkingDirectory $root -WindowStyle Hidden | Out-Null
      Say "  explorer 未生效，已直接启动守护脚本（兜底）"
    } else {
      Say "  守护脚本已在运行"
    }
  } else {
    Say "  网关已就绪"
  }
} catch { Say ("  兜底检查失败：" + $_.Exception.Message) }

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

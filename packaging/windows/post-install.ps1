param(
  [switch]$SkipLaunch
)
# LanFu 安装后配置。
#
# 设计原则（2026-10-12 决策：最小接线）：安装器只打通"物理上不可能由员工完成"的
# 两步——生成网关令牌、批准桌面端的设备配对；不写任何模型/渠道配置，AI 提供商
# 由员工装好后在应用内自己连接。
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$appDir = Join-Path $root "app"
$watchdog = Join-Path $root "ensure-gateway.ps1"
$approver = Join-Path $root "approve-pairing.ps1"
$logPath = Join-Path $env:TEMP "lanfu-post-install.log"
$psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

function Say($text) {
  $line = "[LanFu] " + $text
  Write-Output $line
  Add-Content -Path $logPath -Value ((Get-Date -Format "HH:mm:ss") + " " + $line) -ErrorAction SilentlyContinue
}
"=== LanFu 安装后配置 $(Get-Date -Format o) ===" | Set-Content -Path $logPath -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 1. 连接预置
# 全新网关没有任何令牌，而桌面端/网页端都拒绝匿名连接；员工也没有 CLI 能自己生成。
# 因此安装器代为生成（仅在缺失时），并把连接记录交给桌面端，让它跳过向导直接连接。
# 注意：绝不能在这里写模型/渠道等业务配置——那是员工自己的事。
Say "正在预置网关连接…"
$shellToken = $null
try {
  $cfgPath = Join-Path $env:USERPROFILE ".lanfu\openclaw.json"
  $cfg = $null
  if (Test-Path $cfgPath) {
    try { $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $cfg = $null }
    if ($cfg -and $cfg.gateway -and $cfg.gateway.auth -and $cfg.gateway.auth.token) {
      $shellToken = [string]$cfg.gateway.auth.token
      Say "  网关令牌已存在，沿用"
    }
  }
  if (-not $shellToken) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 24
    $rng.GetBytes($bytes)
    $rng.Dispose()
    $shellToken = ([System.BitConverter]::ToString($bytes)).Replace("-", "").ToLowerInvariant()
    if (-not (Test-Path (Split-Path $cfgPath))) { New-Item -ItemType Directory -Force -Path (Split-Path $cfgPath) | Out-Null }
    if ($cfg) {
      # 已有配置但缺令牌（少见）：只补 gateway.auth.token，不动其余内容
      if (-not $cfg.gateway) { Add-Member -MemberType NoteProperty -Name gateway -Value (New-Object PSObject) -InputObject $cfg }
      if (-not $cfg.gateway.auth) { Add-Member -MemberType NoteProperty -Name auth -Value (New-Object PSObject) -InputObject $cfg.gateway }
      Add-Member -MemberType NoteProperty -Name token -Value $shellToken -InputObject $cfg.gateway.auth -Force
      $cfg | ConvertTo-Json -Depth 32 | Set-Content -Path $cfgPath -Encoding UTF8
    } else {
      @{ gateway = @{ auth = @{ token = $shellToken } } } | ConvertTo-Json -Depth 8 | Set-Content -Path $cfgPath -Encoding UTF8
    }
    Say "  已生成网关令牌"
  }
} catch { Say ("  令牌处理失败：" + $_.Exception.Message) }

if ($shellToken) {
  try {
    $shellDir = Join-Path $env:APPDATA "LanFu"
    $gwPath = Join-Path $shellDir "gateways.json"
    if (Test-Path $gwPath) {
      Say "  桌面端连接记录已存在，跳过（不覆盖员工自己的配置）"
    } else {
      New-Item -ItemType Directory -Force -Path $shellDir | Out-Null
      $gwId = [guid]::NewGuid().ToString()
      # isLocal 必须为 false：true 会让外壳走设备签名（v2）路径，仅凭共享令牌不会发起连接
      @{ gateways = @(@{
           id = $gwId
           url = "ws://127.0.0.1:18789"
           friendlyName = "LanFu"
           sharedGatewayToken = $shellToken
           isLocal = $false
         })
         activeId = $gwId
      } | ConvertTo-Json -Depth 8 | Set-Content -Path $gwPath -Encoding UTF8
      Say "  已写入桌面端连接记录（isLocal=false）"
    }
  } catch { Say ("  连接记录写入失败：" + $_.Exception.Message) }
}

# ---------------------------------------------------------------- 2. 目录联接
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

# ---------------------------------------------------------------- 3. 登录自启
Say "正在注册本地网关的登录自启…"
try {
  Unregister-ScheduledTask -TaskName "LanFu Gateway" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  New-Item -Path $runKey -Force | Out-Null
  $cmd = '"' + $psExe + '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $watchdog + '"'
  Set-ItemProperty -Path $runKey -Name "LanFuGateway" -Value $cmd
  Say "  已写入 HKCU Run\LanFuGateway（指向守护脚本）"
} catch { Say ("  自启注册失败：" + $_.Exception.Message) }

# ---------------------------------------------------------------- 4. 后台拉起守护脚本
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

# ---------------------------------------------------------------- 5. 打开界面
if ($SkipLaunch) { Say "已跳过启动界面"; exit 0 }
$hubExe = Join-Path $env:LOCALAPPDATA "LanFu\LanFu.exe"
if (-not (Test-Path $hubExe)) { Say "未找到桌面端，跳过启动"; exit 0 }
Say "正在打开 LanFu 主界面…"
try {
  Start-Process -FilePath $hubExe -WorkingDirectory (Split-Path $hubExe) | Out-Null
  Say "  已启动"
} catch { Say ("  启动失败：" + $_.Exception.Message) }

# ---------------------------------------------------------------- 6. 自动批准桌面端配对
# 外壳以设备签名身份申请 operator，网关按策略要求批准；员工没有批准入口。
# 后台分离执行，不拖住安装器：外壳自己会重连，批准落地后下一次重连即成功。
try {
  Start-Process -FilePath $psExe -ArgumentList @("-NoProfile","-WindowStyle","Hidden","-ExecutionPolicy","Bypass","-File",$approver) -WindowStyle Hidden | Out-Null
  Say "  已在后台批准桌面端配对"
} catch { Say ("  配对批准启动失败：" + $_.Exception.Message) }
Say "完成。"

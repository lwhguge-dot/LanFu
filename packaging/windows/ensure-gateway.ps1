# 确保本地网关在运行。
#
# 为什么需要这个脚本：
#   网关首次启动会做状态迁移检测，其中插件侧车会 import "openclaw/plugin-sdk/*"。
#   刚安装完时这次导入可能失败（实测在安装后的若干分钟内会失败，之后自行恢复），
#   而网关把"迁移未干净完成"视为拒绝就绪（exit 78）——这是上游有意设计，用于避免
#   在遗留状态未知时贸然运行。
#
#   因此这里做两件事，且都不改变上游语义：
#     1. 每次重试前确认依赖自链接存在，缺失就补建（首次启动最常见的失败原因）
#     2. 在较长时间窗口内反复重试，直到网关真正就绪
param(
  [int]$TimeoutSeconds = 1200
)
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$appDir = Join-Path $root "app"
$node = Join-Path $root "runtime\node.exe"
$entry = Join-Path $appDir "openclaw.mjs"
$selfLink = Join-Path $appDir "node_modules\openclaw"
$logPath = Join-Path $env:TEMP "lanfu-gateway-watchdog.log"

function Note($text) {
  Add-Content -Path $logPath -Value ((Get-Date -Format "HH:mm:ss") + " " + $text) -ErrorAction SilentlyContinue
}

function Test-Ready {
  try { $r = Invoke-WebRequest "http://127.0.0.1:18789/" -UseBasicParsing -TimeoutSec 4; return ($r.StatusCode -eq 200) } catch { return $false }
}

# 网关的插件用 "openclaw/plugin-sdk/*" 自引用解析，依赖这个目录联接。
# Inno Setup 无法保留联接，安装时已补建；这里再兜一层，缺失就补。
function Ensure-SelfLink {
  if (Test-Path $selfLink) { return $true }
  try {
    New-Item -ItemType Junction -Path $selfLink -Target $appDir -ErrorAction Stop | Out-Null
    Note "  已补建依赖自链接"
    return $true
  } catch {
    Note ("  补建自链接失败：" + $_.Exception.Message)
    return $false
  }
}

Ensure-SelfLink | Out-Null
if (Test-Ready) { Note "网关已在运行"; exit 0 }

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$attempt = 0
while ((Get-Date) -lt $deadline) {
  $attempt++
  Ensure-SelfLink | Out-Null
  Note ("第 " + $attempt + " 次启动网关")
  try {
    $proc = Start-Process -FilePath $node -ArgumentList @($entry, "gateway", "--port", "18789", "--allow-unconfigured") -WorkingDirectory $appDir -WindowStyle Hidden -PassThru
  } catch {
    Note ("  启动失败：" + $_.Exception.Message)
    Start-Sleep -Seconds 15
    continue
  }
  for ($i = 0; $i -lt 9; $i++) {
    Start-Sleep -Seconds 5
    if (Test-Ready) { Note ("  就绪（第 " + $attempt + " 次尝试）"); exit 0 }
    if ($proc -and $proc.HasExited) { break }
  }
  if (-not (Test-Ready)) {
    if ($proc -and -not $proc.HasExited) { try { Stop-Process -Id $proc.Id -Force } catch { } }
    Get-Process -Name node -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $node } | ForEach-Object { try { Stop-Process -Id $_.Id -Force } catch { } }
    # 早期失败很密（导入尚未可用），间隔逐步拉长，减少无谓重启
    $pause = [Math]::Min(60, 10 + ($attempt * 5))
    Note ("  未就绪，" + $pause + " 秒后重试")
    Start-Sleep -Seconds $pause
  }
}

Note "超时仍未就绪；登录时会自动再试"
exit 1

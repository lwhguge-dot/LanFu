param(
  [string]$ModelBaseUrl = "http://100.116.120.40:8000/v1",
  [string]$DefaultModel = "vllm/qwen38",
  [switch]$SkipDesktop,
  [switch]$SkipPairing
)
# Every step is best-effort: a failure in one must not stop the others, so a partial
# environment still leaves the employee with a usable product.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateDir = Join-Path $env:USERPROFILE ".lanfu"
$configPath = Join-Path $stateDir "openclaw.json"
$logPath = Join-Path $env:TEMP "lanfu-post-install.log"

function Say($text) {
  $line = "[LanFu] " + $text
  Write-Output $line
  Add-Content -Path $logPath -Value ((Get-Date -Format "HH:mm:ss") + " " + $line) -ErrorAction SilentlyContinue
}
"=== LanFu post-install $(Get-Date -Format o) ===" | Set-Content -Path $logPath -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 1. 首次运行配置
Say "configuring the gateway..."
try {
  if (-not (Test-Path $configPath)) {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $token = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
    $config = [ordered]@{
      gateway = [ordered]@{ mode = "local"; bind = "loopback"; auth = [ordered]@{ mode = "token"; token = $token } }
      models = [ordered]@{ mode = "merge"; providers = [ordered]@{ vllm = [ordered]@{ baseUrl = $ModelBaseUrl; api = "openai-completions"; apiKey = "sk-local" } } }
      agents = [ordered]@{ defaults = [ordered]@{ model = $DefaultModel } }
      update = [ordered]@{ auto = [ordered]@{ enabled = $false } }
    }
    $config | ConvertTo-Json -Depth 8 | Set-Content -Path $configPath -Encoding UTF8
    Say "  seeded $configPath"
  } else { Say "  existing config kept" }
} catch { Say ("  config step failed: " + $_.Exception.Message) }

# ---------------------------------------------------------------- 2. 登录自启（免管理员）
$node = Join-Path $root "runtime\node.exe"
$entry = Join-Path $root "app\openclaw.mjs"
$appDir = Join-Path $root "app"
Say "registering autostart (per-user, no admin required)..."
try {
  # 旧的计划任务方案需要管理员权限，这里改用 HKCU Run（同样在登录时启动）
  Unregister-ScheduledTask -TaskName "LanFu Gateway" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  New-Item -Path $runKey -Force | Out-Null
  Set-ItemProperty -Path $runKey -Name "LanFuGateway" -Value ('"' + $node + '" "' + $entry + '" gateway --port 18789')
  Say "  HKCU Run\LanFuGateway set"
} catch { Say ("  autostart step failed: " + $_.Exception.Message) }

# ---------------------------------------------------------------- 3. 立即启动网关
Say "starting the gateway..."
try {
  $running = $false
  try { $r = Invoke-WebRequest "http://127.0.0.1:18789/" -UseBasicParsing -TimeoutSec 3; if ($r.StatusCode -eq 200) { $running = $true } } catch { }
  if (-not $running) {
    Start-Process -FilePath $node -ArgumentList @($entry, "gateway", "--port", "18789") -WorkingDirectory $appDir -WindowStyle Hidden | Out-Null
    Say "  launched"
  } else { Say "  already running" }
} catch { Say ("  start failed: " + $_.Exception.Message) }

Say "waiting for the gateway to answer..."
$ready = $false
for ($i = 0; $i -lt 40; $i++) {
  Start-Sleep -Seconds 3
  try { $r = Invoke-WebRequest "http://127.0.0.1:18789/" -UseBasicParsing -TimeoutSec 4; if ($r.StatusCode -eq 200) { $ready = $true; break } } catch { }
}
Say ("  gateway ready: " + $ready)

# ---------------------------------------------------------------- 4. 桌面端连接
if ($SkipDesktop) { Say "desktop wiring skipped"; exit 0 }

$hubExe = Join-Path $env:LOCALAPPDATA "LanFu\LanFu.exe"
if (-not (Test-Path $hubExe)) { Say ("desktop shell not found at " + $hubExe + " - skipping"); exit 0 }

Say "wiring the desktop shell to the local gateway..."
$token = $null
try { $token = (Get-Content $configPath -Raw | ConvertFrom-Json).gateway.auth.token } catch { }
if (-not $token) { Say "  WARNING: no gateway token found" }

$hubData = Join-Path $env:APPDATA "LanFu"
try {
  New-Item -ItemType Directory -Force -Path $hubData | Out-Null
  $gatewayId = [guid]::NewGuid().ToString()
  # isLocal MUST stay false: a local record switches the shell to device-signature
  # auth, which cannot complete with only a shared token.
  $registry = [ordered]@{
    gateways = @([ordered]@{
      id = $gatewayId
      url = "ws://127.0.0.1:18789"
      friendlyName = "LanFu"
      sharedGatewayToken = $token
      isLocal = $false
    })
    activeId = $gatewayId
  }
  $registry | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $hubData "gateways.json") -Encoding UTF8
  Say "  wrote gateways.json"
} catch { Say ("  registry step failed: " + $_.Exception.Message) }

# ---------------------------------------------------------------- 5. 首次配对自动批准
if ($SkipPairing) { Say "pairing skipped"; exit 0 }
if (-not $ready) { Say "gateway not ready - skipping the pairing step"; exit 0 }

$lanfuCli = Join-Path $root "lanfu.cmd"
Say "starting the desktop shell once so it can register with the gateway..."
try { Start-Process -FilePath $hubExe -WorkingDirectory (Split-Path $hubExe) | Out-Null } catch { Say ("  launch failed: " + $_.Exception.Message) }

$approved = 0
for ($i = 0; $i -lt 25; $i++) {
  Start-Sleep -Seconds 3
  try {
    $raw = & $lanfuCli devices list --json 2>$null | Out-String
    $start = $raw.IndexOf("{")
    if ($start -lt 0) { continue }
    $data = $raw.Substring($start) | ConvertFrom-Json
    foreach ($p in @($data.pending)) {
      if (-not $p) { continue }
      $requestId = if ($p.requestId) { $p.requestId } else { $p.id }
      if (-not $requestId) { continue }
      $name = if ($p.displayName) { $p.displayName } else { "device" }
      Say ("  approving " + $requestId + " (" + $name + ")")
      & $lanfuCli devices approve $requestId 2>&1 | Out-Null
      $approved++
    }
    if ($approved -gt 0) { break }
  } catch { Say ("  poll error: " + $_.Exception.Message) }
}

if ($approved -gt 0) { Say ("  approved " + $approved + " pairing request(s)") }
else { Say "  no pairing request appeared (already paired, or the shell has not started yet)" }
Say "done."

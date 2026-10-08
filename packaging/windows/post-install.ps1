param(
  [string]$ModelBaseUrl = "http://100.116.120.40:8000/v1",
  [string]$DefaultModel = "vllm/qwen38",
  [switch]$SkipDesktop,
  [switch]$SkipPairing
)
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateDir = Join-Path $env:USERPROFILE ".lanfu"
$configPath = Join-Path $stateDir "openclaw.json"
$logPath = Join-Path $env:TEMP "lanfu-post-install.log"

# Employees are Chinese-speaking: every user-visible message in this script is
# Simplified Chinese, and the seeded config pins the Control UI locale to zh-CN.
function Say($text) {
  $line = "[LanFu] " + $text
  Write-Output $line
  Add-Content -Path $logPath -Value ((Get-Date -Format "HH:mm:ss") + " " + $line) -ErrorAction SilentlyContinue
}
"=== LanFu 安装后配置 $(Get-Date -Format o) ===" | Set-Content -Path $logPath -ErrorAction SilentlyContinue

# Runs the LanFu CLI with a hard timeout. Two details matter:
#   * lanfu.cmd is a batch file, so it must run through cmd.exe
#   * stdin is closed immediately, because a console-less process that waits for
#     input would block forever and hang the installer that waits on this script
function Invoke-LanfuCli([string]$cliArguments, [int]$timeoutMs) {
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot "System32\cmd.exe"
    $psi.Arguments = '/c ""' + $lanfuCli + '" ' + $cliArguments + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Close()
    $out = $proc.StandardOutput.ReadToEnd()
    if (-not $proc.WaitForExit($timeoutMs)) { try { $proc.Kill() } catch { }; return "" }
    return $out
  } catch { return "" }
}

# ---------------------------------------------------------------- 1. 首次运行配置
Say "正在生成网关配置…"
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
      ui = [ordered]@{ prefs = [ordered]@{ locale = "zh-CN" } }
      update = [ordered]@{ auto = [ordered]@{ enabled = $false } }
    }
    $config | ConvertTo-Json -Depth 8 | Set-Content -Path $configPath -Encoding UTF8
    Say "  已写入初始配置"
  } else { Say "  已有配置，保留不动" }
} catch { Say ("  配置步骤失败：" + $_.Exception.Message) }

# ---------------------------------------------------------------- 1b. 界面语言（含升级场景）
# Existing installs keep their config, so the locale is merged in separately and
# idempotently: an upgrade must also end up with a Simplified Chinese interface.
# NOTE: the installer runs this through Windows PowerShell 5.1, which has no
# ConvertFrom-Json -AsHashtable, so the object is edited with Add-Member instead.
try {
  if (Test-Path $configPath) {
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($null -eq $cfg.ui) {
      $cfg | Add-Member -NotePropertyName ui -NotePropertyValue (New-Object psobject) -Force
    }
    if ($null -eq $cfg.ui.prefs) {
      $cfg.ui | Add-Member -NotePropertyName prefs -NotePropertyValue (New-Object psobject) -Force
    }
    if ($cfg.ui.prefs.locale -ne "zh-CN") {
      $cfg.ui.prefs | Add-Member -NotePropertyName locale -NotePropertyValue "zh-CN" -Force
      $cfg | ConvertTo-Json -Depth 12 | Set-Content -Path $configPath -Encoding UTF8
      Say "  界面语言已设为简体中文"
    } else { Say "  界面语言已是简体中文" }
  }
} catch { Say ("  语言设置步骤失败：" + $_.Exception.Message) }

# ---------------------------------------------------------------- 2. 登录自启（免管理员）
$node = Join-Path $root "runtime\node.exe"
$entry = Join-Path $root "app\openclaw.mjs"
$appDir = Join-Path $root "app"
Say "正在注册开机自启（用户级，无需管理员权限）…"
try {
  Unregister-ScheduledTask -TaskName "LanFu Gateway" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  New-Item -Path $runKey -Force | Out-Null
  Set-ItemProperty -Path $runKey -Name "LanFuGateway" -Value ('"' + $node + '" "' + $entry + '" gateway --port 18789')
  Say "  已写入 HKCU Run\LanFuGateway"
} catch { Say ("  自启注册失败：" + $_.Exception.Message) }

# ---------------------------------------------------------------- 3. 立即启动网关
Say "正在启动网关…"
try {
  $running = $false
  try { $r = Invoke-WebRequest "http://127.0.0.1:18789/" -UseBasicParsing -TimeoutSec 3; if ($r.StatusCode -eq 200) { $running = $true } } catch { }
  if (-not $running) {
    Start-Process -FilePath $node -ArgumentList @($entry, "gateway", "--port", "18789") -WorkingDirectory $appDir -WindowStyle Hidden | Out-Null
    Say "  已启动"
  } else { Say "  网关已在运行" }
} catch { Say ("  启动失败：" + $_.Exception.Message) }

Say "正在等待网关响应（最多 5 分钟）…"
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
  Start-Sleep -Seconds 5
  try { $r = Invoke-WebRequest "http://127.0.0.1:18789/" -UseBasicParsing -TimeoutSec 4; if ($r.StatusCode -eq 200) { $ready = $true; break } } catch { }
}
Say ("  网关就绪：" + $ready)

# ---------------------------------------------------------------- 4. 桌面端连接
if ($SkipDesktop) { Say "已跳过桌面端接线"; exit 0 }

$hubExe = Join-Path $env:LOCALAPPDATA "LanFu\LanFu.exe"
if (-not (Test-Path $hubExe)) { Say "桌面端未安装，跳过"; exit 0 }

Say "正在把桌面端连接到本地网关…"
$token = $null
try { $token = (Get-Content $configPath -Raw | ConvertFrom-Json).gateway.auth.token } catch { }
if (-not $token) { Say "  警告：未找到网关令牌" }

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
  Say "  已写入 gateways.json"
} catch { Say ("  桌面端注册信息写入失败：" + $_.Exception.Message) }

# ---------------------------------------------------------------- 5. 首次配对自动批准
if ($SkipPairing) { Say "已跳过配对"; exit 0 }
if (-not $ready) { Say "网关未就绪，跳过配对"; exit 0 }

$lanfuCli = Join-Path $root "lanfu.cmd"
Say "正在启动一次桌面端，让它向网关注册…"
try { Start-Process -FilePath $hubExe -WorkingDirectory (Split-Path $hubExe) | Out-Null } catch { Say ("  启动失败：" + $_.Exception.Message) }

$approved = 0
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Seconds 4
  $raw = Invoke-LanfuCli "devices list --json --timeout 8000" 15000
  if (-not $raw) { continue }
  $start = $raw.IndexOf("{")
  if ($start -lt 0) { continue }
  try { $data = $raw.Substring($start) | ConvertFrom-Json } catch { continue }
  foreach ($p in @($data.pending)) {
    if (-not $p) { continue }
    $requestId = if ($p.requestId) { $p.requestId } else { $p.id }
    if (-not $requestId) { continue }
    $name = if ($p.displayName) { $p.displayName } else { "设备" }
    Say ("  正在批准 " + $requestId + "（" + $name + "）")
    Invoke-LanfuCli ("devices approve " + $requestId + " --timeout 8000") 12000 | Out-Null
    $approved++
  }
  if ($approved -gt 0) { break }
}

if ($approved -gt 0) { Say ("  已批准 " + $approved + " 个配对请求") }
else { Say "  未出现配对请求（可能已配对，或桌面端尚未启动）" }
Say "完成。"

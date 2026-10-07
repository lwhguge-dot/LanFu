param(
  [string]$ModelBaseUrl = "http://100.116.120.40:8000/v1",
  [string]$DefaultModel = "vllm/qwen38"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateDir = Join-Path $env:USERPROFILE ".lanfu"
$configPath = Join-Path $stateDir "openclaw.json"

# 1. seed a first-run config so the gateway starts without an interactive wizard.
if (-not (Test-Path $configPath)) {
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  $bytes = New-Object byte[] 24
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $token = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
  $config = [ordered]@{
    gateway = [ordered]@{ mode = "local"; bind = "loopback"; auth = [ordered]@{ mode = "token"; token = $token } }
    models = [ordered]@{ mode = "merge"; providers = [ordered]@{ vllm = [ordered]@{ baseUrl = $ModelBaseUrl; api = "openai-completions"; apiKey = "lanfu" } } }
    agents = [ordered]@{ defaults = [ordered]@{ model = $DefaultModel } }
    update = [ordered]@{ auto = [ordered]@{ enabled = $false } }
  }
  $config | ConvertTo-Json -Depth 8 | Set-Content -Path $configPath -Encoding UTF8
  Write-Output "Seeded first-run config at $configPath"
} else {
  Write-Output "Existing config kept at $configPath"
}

# 2. register the gateway as a logon task so LanFu is always available.
$taskName = "LanFu Gateway"
$node = Join-Path $root "runtime\node.exe"
$entry = Join-Path $root "app\openclaw.mjs"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
$action = New-ScheduledTaskAction -Execute $node -Argument ('"' + $entry + '" gateway --port 18789') -WorkingDirectory (Join-Path $root "app")
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "LanFu Gateway" -Force | Out-Null
Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

# 3. open the control UI once.
Start-Sleep -Seconds 12
try {
  $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
  $token = $cfg.gateway.auth.token
  Start-Process ("http://127.0.0.1:18789/?token=" + $token)
} catch {
  Start-Process "http://127.0.0.1:18789/"
}
Write-Output "LanFu installed."

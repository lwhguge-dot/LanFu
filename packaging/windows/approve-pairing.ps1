# 安装收尾：批准桌面端配对 + 预置助手身份（均在网关就绪后执行）。
#
# 配对：桌面外壳以设备签名（Ed25519/v3）身份申请 operator 角色，网关按上游策略要求
# 人工批准这一路径（网页端的令牌直连会被自动批准，但设备签名不会）；而员工没有
# 任何批准入口——批准需要 CLI 或网页管理页。因此安装器替员工批准本机桌面端这一台设备。
#
# 身份：出厂默认助手=小蓝（蓝凫教育工作助手）。幂等：仅在没有任何身份、或身份仍是
# 小蓝（可安全刷新）时写入；员工改过名字/头像则绝不覆盖。头像直接用网关自供的
# 品牌标志 URL，无需往工作区复制文件。
param(
  [int]$TimeoutSeconds = 300
)
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cli = Join-Path $root "lanfu.cmd"
$node = Join-Path $root "runtime\node.exe"
$entry = Join-Path $root "app\openclaw.mjs"
$cmdExe = Join-Path $env:SystemRoot "System32\cmd.exe"
$logPath = Join-Path $env:TEMP "lanfu-pairing.log"
$identityName = "小蓝"

function Note($text) {
  # UTF-8：日志含中文/Emoji，默认 ANSI 编码会把它们写成乱码
  Add-Content -Path $logPath -Value ((Get-Date -Format "HH:mm:ss") + " " + $text) -Encoding UTF8 -ErrorAction SilentlyContinue
}

# CLI 的输出前可能带有非 JSON 的提示行（例如检测到 legacy 目录时的警告），从第一个
# '{' 开始截取；网关未就绪时命令失败，返回 null 由外层重试。
function Invoke-CliJson($arguments) {
  try {
    $out = (& $cmdExe /c ('"' + $cli + '" ' + $arguments)) 2>$null | Out-String
    $idx = $out.IndexOf("{")
    if ($idx -lt 0) { return $null }
    return ($out.Substring($idx) | ConvertFrom-Json)
  } catch { return $null }
}

# 直接经 node 调 CLI（绕开 cmd 的编码层），参数含中文/Emoji 时更稳
function Invoke-CliRaw($arguments) {
  try {
    return (& $node $entry @($arguments)) 2>$null | Out-String
  } catch { return $null }
}

function Ensure-Identity {
  # 幂等检查：读 main 智能体当前身份
  $list = Invoke-CliJson "agents list --json"
  if ($list) {
    $agents = @($list.agents)
    $main = $agents | Where-Object { $_.id -eq "main" } | Select-Object -First 1
    if (-not $main) { $main = $agents | Select-Object -First 1 }
    $name = $main.identity.name
    if ($name -and $name -ne $identityName) {
      Note ("身份已由用户自定为 " + $name + "，不覆盖")
      return
    }
  }
  $out = Invoke-CliRaw @("agents", "set-identity", "--agent", "main",
    "--name", $identityName,
    "--theme", "务实、简洁、有主见",
    "--emoji", "🦆",
    "--avatar", "http://127.0.0.1:18789/lanfu-mark.png",
    "--json")
  if ($out -match '"ok"\s*:\s*true') {
    Note "助手身份已预置为小蓝（蓝凫标志头像）"
  } else {
    Note ("身份预置返回：" + ($out -replace "\s+", " ").Substring(0, [Math]::Min(160, $out.Length)))
  }
}

"=== LanFu 配对批准与身份预置 $(Get-Date -Format o) ===" | Set-Content -Path $logPath -Encoding UTF8 -ErrorAction SilentlyContinue
Note ("CLI: " + $cli)
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$identityDone = $false
while ((Get-Date) -lt $deadline) {
  $d = Invoke-CliJson "devices list --json"
  if ($d) {
    # 网关已可达：先做身份预置（与配对独立，且只需一次）
    if (-not $identityDone) { Ensure-Identity; $identityDone = $true }

    $paired = @($d.paired | Where-Object { $_.displayName -eq "LanFu" })
    if ($paired.Count -gt 0) { Note "桌面端已在配对列表，无需处理"; exit 0 }
    $pending = @($d.pending)
    if ($pending.Count -gt 0) {
      foreach ($p in $pending) {
        Note ("发现待批准请求 " + $p.requestId + "（" + $p.displayName + "）")
        if ($p.displayName -ne "LanFu") { Note "  非桌面端请求，跳过（不越权批准其它设备）"; continue }
        (& $cmdExe /c ('"' + $cli + '" devices approve ' + $p.requestId)) 2>$null | Out-Null
        Note "  已执行批准"
      }
      Start-Sleep -Seconds 3
      $d2 = Invoke-CliJson "devices list --json"
      if ($d2) {
        $paired2 = @($d2.paired | Where-Object { $_.displayName -eq "LanFu" })
        if ($paired2.Count -gt 0) { Note "桌面端配对完成"; exit 0 }
      }
    }
  }
  Start-Sleep -Seconds 3
}
Note "超时退出。桌面端会持续重连；若仍未配对，可在网页端（http://127.0.0.1:18789）手动批准"
exit 1

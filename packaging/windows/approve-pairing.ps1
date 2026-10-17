# 安装收尾：批准桌面端配对 + 预置助手身份（均在网关就绪后执行）。
#
# 配对：桌面外壳以设备签名（Ed25519/v3）身份申请 operator 角色，网关按上游策略要求
# 人工批准这一路径（网页端的令牌直连会被自动批准，但设备签名不会）；而员工没有
# 任何批准入口——批准需要 CLI 或网页管理页。因此安装器替员工批准本机桌面端这一台设备。
#
# 身份：出厂默认助手=小蓝（蓝凫教育工作助手）。幂等：仅在没有任何身份、或身份仍是
# 小蓝（可安全刷新）时写入；员工改过名字则绝不覆盖。头像用网关自供的同源品牌标志
# 路径（/lanfu-mark.png，网页端可直接渲染），不再设置 emoji——0.4.8 曾预置鸭子 emoji
# 和绝对 URL 头像，这里检测到旧残留时自动刷新为新预设。
param(
  [int]$TimeoutSeconds = 1800
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

# 网关就绪探测：只用 HTTP 请求（不启动 CLI）。网关尚未就绪时反复调用 CLI 会派生
# node 子进程并与其争抢状态目录，实测会拖慢甚至阻塞网关启动，所以先等 HTTP 200。
function Test-GatewayReady {
  try {
    $r = Invoke-WebRequest "http://127.0.0.1:18789/" -UseBasicParsing -TimeoutSec 4
    return ($r.StatusCode -eq 200)
  } catch { return $false }
}

# CLI 的输出前可能带有非 JSON 的提示行（例如检测到 legacy 目录时的警告）。从每个
# 以 '{' 或 '[' 开头的行尝试解析：agents list 的根是数组，devices list 的根是对象，
# 只从 '{' 截取会把数组截断成非法 JSON。网关未就绪时命令失败，返回 null 由外层重试。
function Invoke-CliJson($arguments) {
  try {
    $out = (& $cmdExe /c ('"' + $cli + '" ' + $arguments)) 2>$null | Out-String
    $lines = $out -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $head = $lines[$i].TrimStart()
      if (-not ($head.StartsWith("{") -or $head.StartsWith("["))) { continue }
      $candidate = ($lines[$i..($lines.Count - 1)] -join "`n")
      try { return ($candidate | ConvertFrom-Json) } catch { }
    }
    return $null
  } catch { return $null }
}

# 直接经 node 调 CLI（绕开 cmd 的编码层），参数含中文/Emoji 时更稳
function Invoke-CliRaw($arguments) {
  try {
    return (& $node $entry @($arguments)) 2>$null | Out-String
  } catch { return $null }
}

# 0.4.8 的工作区模板 IDENTITY.md 带着"Emoji：🦆"行，助手会在聊天里自述为鸭子；
# 身份仍是小蓝预设时同步清掉这一行。用户改过身份的文件绝不触碰。
function Repair-WorkspaceIdentityFile {
  try {
    $agents = @(Get-AgentRows)
    if (-not $agents) { return }
    $main = $agents | Where-Object { $_.id -eq "main" } | Select-Object -First 1
    if (-not $main) { $main = $agents | Select-Object -First 1 }
    if (-not $main -or -not $main.workspace) { return }
    $file = Join-Path $main.workspace "IDENTITY.md"
    if (-not (Test-Path $file)) { return }
    $text = [System.IO.File]::ReadAllText($file)
    if ($text -notmatch "小蓝") { return }
    $new = $text -replace "(?m)^- \*\*Emoji：\*\* 🦆\r?\n", ""
    if ($new -ne $text) {
      [System.IO.File]::WriteAllText($file, $new, (New-Object System.Text.UTF8Encoding($false)))
      Note "已清理工作区 IDENTITY.md 的旧 Emoji 行"
    }
  } catch {
    Note ("清理 IDENTITY.md 失败：" + $_.Exception.Message)
  }
}

# agents list --json 的根是数组，ConvertFrom-Json 可能把它展开成单个对象；兼容
# 单行对象、对象数组和旧的 { agents: [...] } 三种形状。调用点用 @() 包裹，
# 因为单元素数组经函数返回会被 PowerShell 展开成对象。
function Get-AgentRows {
  $list = Invoke-CliJson "agents list --json"
  if (-not $list) { return @() }
  if ($list.PSObject.Properties.Name -contains "agents") { return @($list.agents) }
  return @($list)
}

function Ensure-Identity {
  # 幂等检查：读 main 智能体当前身份（agents list 的身份字段在顶层：
  # identityName / identityEmoji / identityAvatarUrl / identitySource）
  $agents = @(Get-AgentRows)
  if ($agents.Count -gt 0) {
    $main = $agents | Where-Object { $_.id -eq "main" } | Select-Object -First 1
    if (-not $main) { $main = $agents | Select-Object -First 1 }
    $name = $main.identityName
    $emoji = $main.identityEmoji
    $avatar = $main.identityAvatarUrl
    if ($name -and $name -ne $identityName) {
      Note ("身份已由用户自定为 " + $name + "，不覆盖")
      return
    }
    if ($emoji -eq "🦆" -or $avatar -eq "http://127.0.0.1:18789/lanfu-mark.png") {
      Note "检测到 0.4.8 旧预设残留（鸭子 emoji / 绝对 URL 头像），刷新为新预设"
    } elseif (-not $emoji -and $avatar -eq "/lanfu-mark.png" -and $name -eq $identityName) {
      Repair-WorkspaceIdentityFile
      Note "身份已是当前预设，跳过"
      return
    }
    Repair-WorkspaceIdentityFile
  }
  # --clear-emoji：显式清除 0.4.8 预置的鸭子 emoji（省略只会保留旧值）。
  # 不用 --emoji ""：PowerShell 5.1 调用原生程序时会丢弃空字符串参数。
  $out = Invoke-CliRaw @("agents", "set-identity", "--agent", "main",
    "--name", $identityName,
    "--theme", "务实、简洁、有主见",
    "--clear-emoji",
    "--avatar", "/lanfu-mark.png",
    "--json")
  if ($out -match '"ok"\s*:\s*true') {
    Note "助手身份已预置为小蓝（蓝凫品牌矢量头像）"
  } else {
    $text = ($out -replace "\s+", " ")
    if ($text.Length -gt 160) { $text = $text.Substring(0, 160) }
    Note ("身份预置返回：" + $text)
  }
}

"=== LanFu 配对批准与身份预置 $(Get-Date -Format o) ===" | Set-Content -Path $logPath -Encoding UTF8 -ErrorAction SilentlyContinue
Note ("CLI: " + $cli)
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$identityDone = $false
while ((Get-Date) -lt $deadline) {
  # 网关未就绪时不要启动 CLI：CLI 会派生 node 进程并争抢网关状态目录，
  # 0.4.9 在本机实测把首启拖到 5 分钟以上，approver 的 300 秒窗口因此到期，
  # 身份自愈没能在安装时执行。先等网关 HTTP 就绪，再调 CLI。
  if (-not (Test-GatewayReady)) { Start-Sleep -Seconds 5; continue }
  $d = Invoke-CliJson "devices list --json"
  if ($d) {
    # 网关已可达：先做身份预置（与配对独立，且只需一次）
    if (-not $identityDone) { Ensure-Identity; $identityDone = $true }

    $paired = @($d.paired | Where-Object { $_.displayName -eq "LanFu" })
    if ($paired.Count -gt 0) { Note "桌面端已在配对列表，无需处理"; exit 0 }
    $pending = @($d.pending | Where-Object { $_ -and $_.requestId })
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

param(
  [switch]$SkipLaunch
)
# LanFu 安装后配置。
#
# 设计原则（2026-10-12 决策：最小接线 + 0.4.3 补全）：
#   1) 员工物理上无法自己完成的事，安装器代办：迁移旧数据、生成网关令牌、
#      预置公司模型、写桌面端连接记录、批准桌面端配对；
#   2) 除此之外不越权：已有的令牌/模型/渠道配置一律保留，绝不覆盖员工自己的选择。
#
# 顺序至关重要：网关自带的 .openclaw→.lanfu 迁移只在 .lanfu 不存在时执行，
# 所以必须先迁移、后铸令牌（0.4.2 曾因顺序颠倒把迁移挡死）。
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$appDir = Join-Path $root "app"
$watchdog = Join-Path $root "ensure-gateway.ps1"
$approver = Join-Path $root "approve-pairing.ps1"
$cli = Join-Path $root "lanfu.cmd"
$logPath = Join-Path $env:TEMP "lanfu-post-install.log"
$psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$cmdExe = Join-Path $env:SystemRoot "System32\cmd.exe"

function Say($text) {
  $line = "[LanFu] " + $text
  Write-Output $line
  Add-Content -Path $logPath -Value ((Get-Date -Format "HH:mm:ss") + " " + $line) -ErrorAction SilentlyContinue
}
"=== LanFu 安装后配置 $(Get-Date -Format o) ===" | Set-Content -Path $logPath -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 1. 旧数据搬运与预置
$stateDir = Join-Path $env:USERPROFILE ".lanfu"
$legacyWinDir = Join-Path $env:USERPROFILE ".openclaw"

# ---- 1a. WSL 旧数据搬运（仅当 Windows 侧什么都没有时；绝不覆盖）----
try {
  $winHasState = (Test-Path $stateDir) -or (Test-Path $legacyWinDir)
  if (-not $winHasState) {
    Say "Windows 侧无历史状态，扫描 WSL 发行版…"
    $distros = @()
    try {
      $raw = (& $cmdExe /c "wsl.exe --list --quiet") 2>$null | Out-String
      # wsl.exe 输出为 UTF-16LE，经 cmd 转手后可能夹杂 NUL 字符，清掉再按行拆
      $clean = ($raw -replace "`0", "")
      $distros = @($clean -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch "没有|not installed|WSL" } | ForEach-Object { $_.Trim() })
    } catch { Say ("  WSL 列举失败：" + $_.Exception.Message) }
    $source = $null
    foreach ($d in $distros) {
      foreach ($share in @("wsl.localhost", "wsl$")) {
      foreach ($home in @("home", "root")) {
        $homeRoot = "\\$share\$d\$home"
          if (-not (Test-Path $homeRoot)) { continue }
          # /root 情况下状态目录直接挂在 \\...\root\.lanfu；普通用户在 \\...\home\<用户>\
          $candidates = @()
          if ($home -eq "root") {
            $candidates = @(Join-Path $homeRoot ".lanfu"), (Join-Path $homeRoot ".openclaw")
          } else {
            $candidates = Get-ChildItem $homeRoot -Directory -ErrorAction SilentlyContinue |
              ForEach-Object { Join-Path $_.FullName ".lanfu" } , { Join-Path $_.FullName ".openclaw" }
          }
          foreach ($c in $candidates) {
            if ($c -and (Test-Path $c)) {
              # 优先 .lanfu（更新的产品状态）；多个时取最后修改时间最新的
              if (-not $source -or $c -like "*\.lanfu" -or ($source -notlike "*\.lanfu" -and (Get-Item $c).LastWriteTime -gt (Get-Item $source).LastWriteTime)) {
                $source = $c
              }
            }
          }
        }
      }
    }
    if ($source) {
      Say ("  发现 WSL 旧状态：" + $source)
      $dest = if ($source -like "*\.lanfu") { $stateDir } else { $legacyWinDir }
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
      & robocopy $source $dest /E /NFL /NDL /NJH /NJS /NP /MT:8 | Out-Null
      if ($LASTEXITCODE -ge 8) {
        Say ("  WSL 数据复制失败（robocopy 退出码 $LASTEXITCODE），跳过搬运")
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
      } else {
        Say ("  已搬运到 " + $dest + "（robocopy 退出码 $LASTEXITCODE，<8 为成功）")
      }
    } else { Say "  WSL 内未发现旧状态，跳过" }
  } else { Say "Windows 侧已有状态（或旧版 .openclaw），跳过 WSL 搬运" }
} catch { Say ("  WSL 搬运失败（不影响安装）：" + $_.Exception.Message) }

# ---- 1b. 触发网关自带的 .openclaw → .lanfu 迁移（必须在铸令牌之前！）----
try {
  if ((-not (Test-Path $stateDir)) -and (Test-Path $legacyWinDir)) {
    Say "检测到 Windows 原生 .openclaw，触发网关自带迁移…"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # 实测只有 `doctor` 一定走本地启动引导（其余命令在网关可达时直接 RPC 短路，
    # 不会执行迁移）；doctor 自身只做检查不修改。命令的退出码不重要，只看 .lanfu。
    (& $cmdExe /c ('"' + $cli + '" doctor')) 2>$null | Out-Null
    $sw.Stop()
    if (Test-Path $stateDir) {
      Say ("  迁移完成（耗时 " + [int]$sw.Elapsed.TotalSeconds + " 秒），旧目录保留在原处")
    } else {
      Say "  迁移未生效（.lanfu 未出现），继续安装流程"
    }
  }
} catch { Say ("  迁移触发失败：" + $_.Exception.Message) }

# ---- 1c. 网关令牌（仅缺失时生成）----
Say "正在预置网关连接…"
$shellToken = $null
try {
  $cfgPath = Join-Path $stateDir "openclaw.json"
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
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force -Path $stateDir | Out-Null }
    if ($cfg) {
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

# ---- 1d. 公司模型预置（仅缺失时；密钥为公司 vLLM 接受的占位值，非真实凭据）----
try {
  $cfgPath = Join-Path $stateDir "openclaw.json"
  if (Test-Path $cfgPath) {
    $cfg = $null
    try { $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $cfg = $null }
    $changed = $false
    if ($cfg) {
      if (-not $cfg.models) { Add-Member -MemberType NoteProperty -Name models -Value (New-Object PSObject) -InputObject $cfg; $changed = $true }
      if (-not $cfg.models.providers) { Add-Member -MemberType NoteProperty -Name providers -Value (New-Object PSObject) -InputObject $cfg.models; $changed = $true }
      if (-not $cfg.models.providers.vllm) {
        $vllm = @'
{
  "baseUrl": "http://100.116.120.40:8000/v1",
  "apiKey": "sk-local",
  "api": "openai-completions",
  "models": [
    {
      "id": "qwen38",
      "name": "Qwen3.8-27B",
      "input": ["text", "image"],
      "maxTokens": 32768,
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
      "api": "openai-completions",
      "contextWindow": 262144,
      "reasoning": true,
      "compat": { "thinkingFormat": "qwen-chat-template" }
    },
    {
      "id": "qwen38-think",
      "name": "Qwen3.8-27B (思考模式)",
      "input": ["text", "image"],
      "maxTokens": 65536,
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
      "api": "openai-completions",
      "contextWindow": 262144,
      "reasoning": true,
      "compat": { "thinkingFormat": "qwen-chat-template" }
    }
  ]
}
'@ | ConvertFrom-Json
        Add-Member -MemberType NoteProperty -Name vllm -Value $vllm -InputObject $cfg.models.providers
        $changed = $true
        Say "  已预置公司模型（qwen38 / qwen38-think）"
      } else { Say "  已存在 vllm 提供商配置，保留员工的" }
      if (-not $cfg.agents) { Add-Member -MemberType NoteProperty -Name agents -Value (New-Object PSObject) -InputObject $cfg; $changed = $true }
      if (-not $cfg.agents.defaults) { Add-Member -MemberType NoteProperty -Name defaults -Value (New-Object PSObject) -InputObject $cfg.agents; $changed = $true }
      if (-not $cfg.agents.defaults.model) {
        Add-Member -MemberType NoteProperty -Name model -Value "vllm/qwen38" -InputObject $cfg.agents.defaults
        $changed = $true
        Say "  已设置默认模型 vllm/qwen38"
      }
      if (-not $cfg.update) {
        # 注意：PS 5.1 不能把 hashtable 直接管道给 ConvertFrom-Json，必须走 JSON 文本
        $updateBlock = '{"auto":{"enabled":false}}' | ConvertFrom-Json
        Add-Member -MemberType NoteProperty -Name update -Value $updateBlock -InputObject $cfg
        $changed = $true
        Say "  已关闭网关自动更新（避免连到上游官方通道）"
      }
      if ($changed) { $cfg | ConvertTo-Json -Depth 32 | Set-Content -Path $cfgPath -Encoding UTF8 }
    }
  }
} catch { Say ("  模型预置失败：" + $_.Exception.Message) }

# ---- 1e. 桌面端连接记录（仅缺失时；isLocal 必须为 false，否则外壳走设备签名路径不会连接）----
if ($shellToken) {
  try {
    $shellDir = Join-Path $env:APPDATA "LanFu"
    $gwPath = Join-Path $shellDir "gateways.json"
    if (Test-Path $gwPath) {
      Say "  桌面端连接记录已存在，跳过（不覆盖员工自己的配置）"
    } else {
      New-Item -ItemType Directory -Force -Path $shellDir | Out-Null
      $gwId = [guid]::NewGuid().ToString()
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
